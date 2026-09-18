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
  "a closeout entry that is not a map",
  "a closeout entry missing a required field",
  "a closeout entry carrying a forbidden field",
  "a cadence field present but blank or non-string",
  "a closeout entry whose review_period_id does not match the run",
  "an invalid attempt_kind",
  "an invalid final_status",
  "more than one SCHEDULED attempt",
  "closeout attempts disagreeing on scheduled_review_period_start",
  "SKIPPED asserted before catch_up_deadline_passed is true",
  "selected_item_refs and item_dispositions not matching",
  "an item ref that is not a PersonalMemoryCandidate identity",
  "an item_dispositions entry that is not a map",
  "an item_dispositions entry carrying a field outside the allowlist",
  "an item_dispositions entry naming an unrecognised category",
  "a NEEDS_ORG_FOLLOWUP entry carrying record_ref or promotion_ref",
  "a promotion_ref present without a promotion_idempotency_key",
  "more than one terminal-status closeout in the history",
  "a closeout attempt following a terminal-status closeout",
  "the same item's promotion identity (ref or key) drifting across retries"
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

CADENCE_STRING_FIELDS = %w[scheduled_review_period_start scheduled_anchor_at actual_closeout_at].freeze
ALLOWED_DISPOSITION_FIELDS = %w[category record_ref promotion_ref promotion_idempotency_key].freeze

def blank?(value)
  !value.is_a?(String) || value.strip.empty?
end

# --- 結構驗證（fail-closed）------------------------------------------------

def weekly_review_cycle_failure(run, categories, candidate_ref_prefix)
  review_period_id = run["review_period_id"]
  return "WRC_REVIEW_PERIOD_ID_NOT_URN" unless urn?(review_period_id)

  closeouts = run["closeouts"]
  return "WRC_CLOSEOUTS_NOT_ARRAY" unless closeouts.is_a?(Array) && !closeouts.empty?

  scheduled_count = 0
  period_starts = Set.new
  terminal_indices = []
  # repair-01 F-02：追蹤 (promotion_ref, promotion_idempotency_key) 這一整
  # 組，不是只追蹤 key——reviewer 指出只比對 key 時，retry 換掉
  # promotion_ref 但沿用同一個 key 仍會放行。
  promotion_identity_by_item = {}

  closeouts.each_with_index do |entry, index|
    # repair-01 F-03：先確認 entry 本身是 Hash，才呼叫 entry.key?——修正前
    # 一個非 Hash 的 entry（例如純字串）會直接讓 evaluator 拋
    # NoMethodError 當掉，不是 fail-closed 拒絕。
    return "WRC_CLOSEOUT_ENTRY_NOT_MAP" unless entry.is_a?(Hash)
    return "WRC_REQUIRED_FIELD_MISSING" unless REQUIRED_FIELDS.all? { |f| entry.key?(f) }
    return "WRC_FORBIDDEN_FIELD_PRESENT" if FORBIDDEN_FIELDS.any? { |f| entry.key?(f) }
    # repair-01 P2：cadence 欄位原本只驗 key 存在、值可以是 nil——
    # 「catch-up 沿用原排定週期」這句話沒有一個可驗的值可以比對。
    return "WRC_CADENCE_FIELD_NOT_STRING" unless CADENCE_STRING_FIELDS.all? { |f| !blank?(entry[f]) }
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
      # repair-01 F-01：item ref 必須真的是 PersonalMemoryCandidate 的
      # identity（讀既有 personal_memory_resource_contracts 的
      # id_templates，不自己另立字串規則）——修正前 selected_item_refs／
      # item_dispositions 的 key 可以是任意字串，包括 PersonalMemoryRecord
      # 的 URN，直接打穿「只能引用 Candidate」的契約宣稱。
      return "WRC_ITEM_REF_NOT_CANDIDATE" unless item_ref.start_with?(candidate_ref_prefix)
      return "WRC_ITEM_DISPOSITION_NOT_MAP" unless disposition.is_a?(Hash)
      # repair-01 F-01：disposition 只能帶這四個欄位——修正前沒有
      # allowlist，`candidate_status`／`weekly_work_summary` 這類欄位可以
      # 直接夾帶進來，直接打穿 receipt「bounded refs + enum、不能 inline
      # content／lifecycle state」的宣稱。
      return "WRC_ITEM_DISPOSITION_UNKNOWN_FIELD" unless (disposition.keys - ALLOWED_DISPOSITION_FIELDS).empty?

      category = disposition["category"]
      return "WRC_UNKNOWN_DISPOSITION_CATEGORY" unless categories.include?(category)

      record_ref = disposition["record_ref"]
      promotion_ref = disposition["promotion_ref"]
      promotion_key = disposition["promotion_idempotency_key"]

      return "WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_PROMOTION_REF" if category == "NEEDS_ORG_FOLLOWUP" && (record_ref || promotion_ref)

      # repair-01 F-02：promotion_ref 出現時，promotion_idempotency_key
      # 不得省略——修正前這整個 idempotency 檢查是 `next unless key`，
      # retry 只要把 key 刪掉就完全繞過本卡對「不重複 Promotion」的核心
      # 承諾。
      return "WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY" if promotion_ref && !promotion_key

      next unless promotion_key

      prior = promotion_identity_by_item[item_ref]
      if prior && (prior[:key] != promotion_key || prior[:ref] != promotion_ref)
        return "WRC_PROMOTION_IDENTITY_DRIFT"
      end

      promotion_identity_by_item[item_ref] = { key: promotion_key, ref: promotion_ref }
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

# repair-01 F-01：item ref 必須是 PersonalMemoryCandidate 的 identity——
# 直接讀既有 id_templates 取前綴，不自己另立一套字串規則。
candidate_id_template = spec.dig("personal_memory_resource_contracts", "shared_constraints", "id_templates",
                                  "PersonalMemoryCandidate")
assert(candidate_id_template.is_a?(String) && candidate_id_template.include?("{"),
       "personal_memory_resource_contracts...id_templates.PersonalMemoryCandidate 必須存在（本片綁定它，不重述）", failures)
candidate_ref_prefix = candidate_id_template.to_s.split("{").first

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = weekly_review_cycle_failure(run, disposition_categories, candidate_ref_prefix)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = weekly_review_cycle_failure(run, disposition_categories, candidate_ref_prefix)
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
  "WRC_CLOSEOUT_ENTRY_NOT_MAP" => "weekly_review_cycle.error.closeout_entry_not_map",
  "WRC_REQUIRED_FIELD_MISSING" => "weekly_review_cycle.error.required_field_missing",
  "WRC_FORBIDDEN_FIELD_PRESENT" => "weekly_review_cycle.error.forbidden_field_present",
  "WRC_CADENCE_FIELD_NOT_STRING" => "weekly_review_cycle.error.cadence_field_not_string",
  "WRC_REVIEW_PERIOD_ID_MISMATCH" => "weekly_review_cycle.error.review_period_id_mismatch",
  "WRC_INVALID_ATTEMPT_KIND" => "weekly_review_cycle.error.invalid_attempt_kind",
  "WRC_INVALID_FINAL_STATUS" => "weekly_review_cycle.error.invalid_final_status",
  "WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED" => "weekly_review_cycle.error.skipped_before_catch_up_exhausted",
  "WRC_ITEM_DISPOSITION_INCOMPLETE" => "weekly_review_cycle.error.item_disposition_incomplete",
  "WRC_ITEM_REF_NOT_CANDIDATE" => "weekly_review_cycle.error.item_ref_not_candidate",
  "WRC_ITEM_DISPOSITION_NOT_MAP" => "weekly_review_cycle.error.item_disposition_not_map",
  "WRC_ITEM_DISPOSITION_UNKNOWN_FIELD" => "weekly_review_cycle.error.item_disposition_unknown_field",
  "WRC_UNKNOWN_DISPOSITION_CATEGORY" => "weekly_review_cycle.error.unknown_disposition_category",
  "WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_PROMOTION_REF" => "weekly_review_cycle.error.needs_followup_with_record_or_promotion_ref",
  "WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY" => "weekly_review_cycle.error.promotion_ref_without_idempotency_key",
  "WRC_PROMOTION_IDENTITY_DRIFT" => "weekly_review_cycle.error.promotion_identity_drift",
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
