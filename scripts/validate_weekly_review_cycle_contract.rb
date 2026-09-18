#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-323（EMEM-09）切片 4：Weekly Grill closeout loop —— 把切片 1～3
# 串成真正可執行的迴圈。
#
# review_period_id 是本片的核心 identity：同一個排定週期的每一次 closeout
# 嘗試（準時／catch-up／retry）都必須共用同一個 review_period_id，否則
# 「週五 → 補做 → retry」只能靠日期字串猜是不是同一週，最後一定長出
# 重複 closeout／重複 Promotion。
#
# 不重述切片 1／2／3：item_dispositions 的分類詞彙直接讀
# `historical_comparison.categories` + `NEEDS_ORG_FOLLOWUP`，不自己另立
# 一套；receipt 的 forbidden_fields 重用切片 1 的 FORBIDDEN_LIFECYCLE_
# FIELDS 概念。
#
# 機器可查訊號 vs 判斷型訊號：本片沒有需要人類判斷的維度（不像切片 2）；
# 全部斷言都是「同一個 review_period_id 底下，跨多次 closeout 嘗試的內部
# 一致性」——這也是為什麼本片的驗證單位是一整段 closeout 歷史（陣列），
# 不是單筆 receipt：重複 closeout／drift 的 idempotency key 這類問題，
# 只在比對多筆記錄時才看得出來，單筆檢查本質上看不到。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/weekly-review-cycle-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

EXPECTED_NEGATIVE_LABELS = [
  "review_period_id that is not an omos URN",
  "closeouts that is not a non-empty array",
  "a closeout entry missing a required field",
  "a closeout entry carrying a forbidden field",
  "a closeout entry whose review_period_id does not match the run",
  "an invalid attempt_kind",
  "an invalid final_status",
  "more than one SCHEDULED attempt",
  "closeout attempts disagreeing on scheduled_review_period_start",
  "SKIPPED asserted before catch_up_deadline_passed is true",
  "selected_item_refs and item_dispositions not matching",
  "an item_dispositions entry that is not a map",
  "an item_dispositions entry naming an unrecognised category",
  "a NEEDS_ORG_FOLLOWUP entry carrying record_ref or promotion_ref",
  "more than one terminal-status closeout in the history",
  "a closeout attempt following a terminal-status closeout",
  "the same item's promotion_idempotency_key drifting across retries"
].freeze

REQUIRED_FIELDS = %w[
  review_period_id scheduled_review_period_start scheduled_anchor_at
  actual_closeout_at attempt_kind final_status catch_up_deadline_passed
  selected_item_refs item_dispositions
].freeze

FORBIDDEN_FIELDS = %w[
  full_personal_store_ref weekly_work_summary personal_store_snapshot
  candidate_status record_status verification_status acceptance_status
  conflict_resolution_status
].freeze

ATTEMPT_KINDS = %w[SCHEDULED CATCH_UP RETRY].freeze
CLOSEOUT_STATUSES = %w[COMPLETE FAILED SKIPPED NO_PROMOTION].freeze
TERMINAL_STATUSES = %w[COMPLETE SKIPPED NO_PROMOTION].freeze

# --- 結構驗證（fail-closed）------------------------------------------------

def weekly_review_cycle_failure(run, categories)
  review_period_id = run["review_period_id"]
  return "WRC_REVIEW_PERIOD_ID_NOT_URN" unless urn?(review_period_id)

  closeouts = run["closeouts"]
  return "WRC_CLOSEOUTS_NOT_ARRAY" unless closeouts.is_a?(Array) && !closeouts.empty?

  scheduled_count = 0
  period_starts = Set.new
  terminal_indices = []
  idempotency_by_item = {}

  closeouts.each_with_index do |entry, index|
    return "WRC_REQUIRED_FIELD_MISSING" unless REQUIRED_FIELDS.all? { |f| entry.key?(f) }
    return "WRC_FORBIDDEN_FIELD_PRESENT" if FORBIDDEN_FIELDS.any? { |f| entry.key?(f) }
    return "WRC_REVIEW_PERIOD_ID_MISMATCH" unless entry["review_period_id"] == review_period_id
    return "WRC_INVALID_ATTEMPT_KIND" unless ATTEMPT_KINDS.include?(entry["attempt_kind"])
    return "WRC_INVALID_FINAL_STATUS" unless CLOSEOUT_STATUSES.include?(entry["final_status"])

    scheduled_count += 1 if entry["attempt_kind"] == "SCHEDULED"
    period_starts << entry["scheduled_review_period_start"]
    terminal_indices << index if TERMINAL_STATUSES.include?(entry["final_status"])

    if entry["final_status"] == "SKIPPED"
      return "WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED" unless entry["catch_up_deadline_passed"] == true
    end

    selected = entry["selected_item_refs"]
    dispositions = entry["item_dispositions"]
    return "WRC_ITEM_DISPOSITION_INCOMPLETE" unless selected.is_a?(Array) && dispositions.is_a?(Hash) &&
                                                     selected.to_set == dispositions.keys.to_set

    dispositions.each do |item_ref, disposition|
      return "WRC_ITEM_DISPOSITION_NOT_MAP" unless disposition.is_a?(Hash)

      category = disposition["category"]
      return "WRC_UNKNOWN_DISPOSITION_CATEGORY" unless categories.include?(category)

      if category == "NEEDS_ORG_FOLLOWUP" && (disposition["record_ref"] || disposition["promotion_ref"])
        return "WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_PROMOTION_REF"
      end

      key = disposition["promotion_idempotency_key"]
      next unless key

      prior = idempotency_by_item[item_ref]
      return "WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT" if prior && prior != key

      idempotency_by_item[item_ref] = key
    end
  end

  return "WRC_MULTIPLE_SCHEDULED_ATTEMPTS" if scheduled_count > 1
  return "WRC_PERIOD_START_INCONSISTENT" if period_starts.size > 1
  return "WRC_DUPLICATE_TERMINAL_CLOSEOUT" if terminal_indices.size > 1
  return "WRC_CLOSEOUT_AFTER_TERMINAL" if terminal_indices.any? && terminal_indices.first != closeouts.size - 1

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
wrc = spec.fetch("weekly_review_cycle")

assert(sorted_set(wrc.fetch("closeout_statuses", [])) == sorted_set(CLOSEOUT_STATUSES),
       "weekly_review_cycle.closeout_statuses 必須剛好是 #{CLOSEOUT_STATUSES.inspect}", failures)
assert(sorted_set(wrc.fetch("terminal_statuses", [])) == sorted_set(TERMINAL_STATUSES),
       "weekly_review_cycle.terminal_statuses 必須剛好是 #{TERMINAL_STATUSES.inspect}", failures)
assert(sorted_set(wrc.fetch("attempt_kinds", [])) == sorted_set(ATTEMPT_KINDS),
       "weekly_review_cycle.attempt_kinds 必須剛好是 #{ATTEMPT_KINDS.inspect}", failures)

receipt = wrc.fetch("closeout_receipt", {})
assert(sorted_set(receipt.fetch("required_fields", [])) == sorted_set(REQUIRED_FIELDS),
       "weekly_review_cycle.closeout_receipt.required_fields 與鎖定清單不符", failures)
assert(sorted_set(receipt.fetch("forbidden_fields", [])) == sorted_set(FORBIDDEN_FIELDS),
       "weekly_review_cycle.closeout_receipt.forbidden_fields 與鎖定清單不符", failures)

# item_dispositions 的分類詞彙不重述——直接讀切片 1 的 categories，加上
# 切片 2 的 NEEDS_ORG_FOLLOWUP。這同時是本片自己不新造分類詞彙的機器證明。
hc_categories = spec.dig("historical_comparison", "categories") || []
assert(hc_categories.any?, "historical_comparison.categories 必須存在（本片綁定它，不重述）", failures)
disposition_categories = (hc_categories + ["NEEDS_ORG_FOLLOWUP"]).to_set

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = weekly_review_cycle_failure(run, disposition_categories)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = weekly_review_cycle_failure(run, disposition_categories)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
ERROR_CONTRACT = {
  "WRC_REVIEW_PERIOD_ID_NOT_URN" => "weekly_review_cycle.error.review_period_id_not_urn",
  "WRC_CLOSEOUTS_NOT_ARRAY" => "weekly_review_cycle.error.closeouts_not_array",
  "WRC_REQUIRED_FIELD_MISSING" => "weekly_review_cycle.error.required_field_missing",
  "WRC_FORBIDDEN_FIELD_PRESENT" => "weekly_review_cycle.error.forbidden_field_present",
  "WRC_REVIEW_PERIOD_ID_MISMATCH" => "weekly_review_cycle.error.review_period_id_mismatch",
  "WRC_INVALID_ATTEMPT_KIND" => "weekly_review_cycle.error.invalid_attempt_kind",
  "WRC_INVALID_FINAL_STATUS" => "weekly_review_cycle.error.invalid_final_status",
  "WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED" => "weekly_review_cycle.error.skipped_before_catch_up_exhausted",
  "WRC_ITEM_DISPOSITION_INCOMPLETE" => "weekly_review_cycle.error.item_disposition_incomplete",
  "WRC_ITEM_DISPOSITION_NOT_MAP" => "weekly_review_cycle.error.item_disposition_not_map",
  "WRC_UNKNOWN_DISPOSITION_CATEGORY" => "weekly_review_cycle.error.unknown_disposition_category",
  "WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_PROMOTION_REF" => "weekly_review_cycle.error.needs_followup_with_record_or_promotion_ref",
  "WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT" => "weekly_review_cycle.error.promotion_idempotency_key_drift",
  "WRC_MULTIPLE_SCHEDULED_ATTEMPTS" => "weekly_review_cycle.error.multiple_scheduled_attempts",
  "WRC_PERIOD_START_INCONSISTENT" => "weekly_review_cycle.error.period_start_inconsistent",
  "WRC_DUPLICATE_TERMINAL_CLOSEOUT" => "weekly_review_cycle.error.duplicate_terminal_closeout",
  "WRC_CLOSEOUT_AFTER_TERMINAL" => "weekly_review_cycle.error.closeout_after_terminal"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "weekly_review_cycle_failure")
assert(violations.empty?, "weekly_review_cycle_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "weekly_review_cycle_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS weekly review cycle contract validation (statuses=#{CLOSEOUT_STATUSES.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
