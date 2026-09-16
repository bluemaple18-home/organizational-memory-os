#!/usr/bin/env ruby
# frozen_string_literal: true
#
# repo #4：Permission / Retention / Deletion 契約 validator。
#
# 實作 Owner 於 2026-09-16 簽定的五個凍結點
# （.work/CARD-PERMISSION-RETENTION-DELETION-SPEC-FREEZE-20260916.md）：
#
#   FP-1-A  retention 轉移：線性推進 ＋ legal hold 可加可解；
#           TOMBSTONED／PURGED 為終態。解除 hold 必須回到原階段。
#   FP-2-A  刪除保留 identity、只清 payload；必須附 deletion_confirmation_ref。
#   FP-3-A  legal hold 無條件擋刪除，無覆蓋路徑。
#   FP-4-A  ACL 變更後 decision 標記 stale，下次取用前必須重做，
#           沿用舊 decision 一律 fail-closed。
#   FP-5-A  刪除必須附 projection_cleanup_receipt_ref（可驗），但不做
#           orchestration。
#
# 五個 retention 值**不在本檔重新宣告**：直接綁定 STD-01
# （raw-evidence-envelope.schema.json）的 payload_retention_state enum。
# 契約裡的 allowed_retention_transitions 若出現 STD-01 沒有的值，或漏掉
# STD-01 有的值，都會被擋下——避免兩份清單各自演化。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/permission-retention-deletion.yaml")
STD01_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/permission-retention-deletion-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/permission-retention-deletion-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

EXPECTED_NEGATIVE_LABELS = [
  "a from_state that is not a declared retention state",
  "a to_state that is not a declared retention state",
  "a transition not present in allowed_retention_transitions",
  "a departure from a terminal state",
  "a deletion attempted while legal_hold_active",
  "a hold release without pre_hold_state",
  "a hold release whose target does not equal pre_hold_state",
  "a deletion without deletion_confirmation_ref",
  "a deletion without projection_cleanup_receipt_ref",
  "a deletion that does not preserve identity fields",
  "a tombstone that still carries inline payload",
  "a retrieval honouring a stale permission decision",
  "a retrieval without any permission decision"
].freeze

def blank?(value)
  !value.is_a?(String) || value.strip.empty?
end

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

# --- retention 轉移（FP-1-A / FP-3-A）------------------------------------

def retention_transition_failure(spec, run)
  transitions = spec.fetch("allowed_retention_transitions")
  terminal = spec.fetch("terminal_states")
  states = transitions.keys

  from_state = run["from_state"]
  to_state = run["to_state"]

  return "PRD_UNKNOWN_RETENTION_STATE" unless states.include?(from_state)
  return "PRD_UNKNOWN_RETENTION_STATE" unless states.include?(to_state)

  # FP-3-A：宣告了 legal hold 還想刪，一律擋——不看 from_state 怎麼寫。
  # 這一層刻意獨立於轉移表，讓「無覆蓋路徑」有兩道保證。
  return "PRD_LEGAL_HOLD_BLOCKS_DELETION" if run["legal_hold_active"] == true &&
                                             %w[TOMBSTONED PURGED].include?(to_state)

  return "PRD_TERMINAL_STATE_DEPARTURE" if terminal.include?(from_state)
  return "PRD_ILLEGAL_RETENTION_TRANSITION" unless transitions.fetch(from_state).include?(to_state)

  # FP-1-A：解除 hold 必須回到原階段，不能藉機倒退重置保留期。
  if from_state == "LEGAL_HOLD"
    pre_hold_state = run["pre_hold_state"]
    return "PRD_HOLD_RELEASE_MISSING_PRE_STATE" unless states.include?(pre_hold_state)
    return "PRD_HOLD_RELEASE_STATE_MISMATCH" unless pre_hold_state == to_state
  end

  nil
end

# --- 刪除要求（FP-2-A / FP-5-A）------------------------------------------

def deletion_requirements_failure(spec, run)
  return nil unless %w[TOMBSTONED PURGED].include?(run["to_state"])

  return "PRD_MISSING_DELETION_CONFIRMATION" unless urn?(run["deletion_confirmation_ref"])
  return "PRD_MISSING_CLEANUP_RECEIPT" unless urn?(run["projection_cleanup_receipt_ref"])

  required = spec.dig("deletion_contract", "preserved_fields")
  preserved = run["preserved_identity_fields"]
  return "PRD_IDENTITY_NOT_PRESERVED" unless preserved.is_a?(Array) &&
                                             required.all? { |field| preserved.include?(field) }

  return "PRD_TOMBSTONE_RETAINS_PAYLOAD" if run["inline_payload_present"] == true

  nil
end

# --- permission decision 時效（FP-4-A）------------------------------------

def permission_staleness_failure(_spec, run)
  return "PRD_MISSING_PERMISSION_DECISION" if blank?(run["permission_decision_ref"])
  return "PRD_STALE_DECISION_HONOURED" if run["permission_decision_stale"] == true &&
                                          run["access_granted"] == true

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
std01 = read_json(STD01_SCHEMA_PATH)

assert(spec.dig("purpose", "no_second_workflow_authority") == true,
       "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec.dig("authority", "grants_acceptance") == false, "authority.grants_acceptance 必須為 false", failures)
assert(spec.dig("authority", "grants_permission") == false, "authority.grants_permission 必須為 false", failures)
assert(spec.dig("authority", "grants_canonical_writer") == false,
       "authority.grants_canonical_writer 必須為 false", failures)
assert(spec.dig("authority", "error_behavior") == "FAIL_LOUD", "authority.error_behavior 必須為 FAIL_LOUD", failures)

# 綁定 STD-01：轉移表的狀態集合必須與 payload_retention_state 的 enum 完全相同。
std01_states = std01.dig("properties", "payload_retention_state", "enum")
assert(std01_states.is_a?(Array) && !std01_states.empty?,
       "在 STD-01 找不到 payload_retention_state 的 enum（結構已改變？）", failures)
declared_states = spec.fetch("allowed_retention_transitions").keys
assert(sorted_set(declared_states) == sorted_set(std01_states.to_a),
       "allowed_retention_transitions 的狀態集合必須與 STD-01 的 payload_retention_state enum 相同：" \
       "契約=#{declared_states.sort} STD-01=#{std01_states.to_a.sort}", failures)

# 轉移目標也必須都是合法狀態。
spec.fetch("allowed_retention_transitions").each do |from_state, targets|
  targets.each do |target|
    assert(std01_states.include?(target),
           "allowed_retention_transitions.#{from_state} 的目標 #{target} 不是 STD-01 的合法狀態", failures)
  end
end

# 終態不得有出邊。
spec.fetch("terminal_states").each do |state|
  assert(spec.fetch("allowed_retention_transitions").fetch(state, []).empty?,
         "終態 #{state} 不得有出邊", failures)
end

# FP-3-A：LEGAL_HOLD 不得直接通往任何刪除狀態。
hold_targets = spec.fetch("allowed_retention_transitions").fetch("LEGAL_HOLD", [])
assert((hold_targets & %w[TOMBSTONED PURGED]).empty?,
       "FP-3-A：LEGAL_HOLD 不得有通往 TOMBSTONED／PURGED 的邊", failures)

assert(spec.dig("legal_hold_contract", "blocks_deletion") == true,
       "legal_hold_contract.blocks_deletion 必須為 true", failures)
assert(spec.dig("legal_hold_contract", "override_path") == "none",
       "legal_hold_contract.override_path 必須為 none", failures)
assert(spec.dig("permission_decision_contract", "recompute_strategy") == "ON_NEXT_ACCESS",
       "permission_decision_contract.recompute_strategy 必須為 ON_NEXT_ACCESS", failures)
assert(spec.dig("projection_cleanup_contract", "verifiable") == true,
       "projection_cleanup_contract.verifiable 必須為 true", failures)

# --- error_contract 與 evaluator 實際可達 code 綁定 ------------------------

EVALUATORS = %w[retention_transition_failure deletion_requirements_failure
                permission_staleness_failure].freeze

declared_codes = spec.fetch("error_contract").keys
EVALUATORS.each do |evaluator_name|
  violations = LoopReturnContract.exit_shape_violations(__FILE__, evaluator_name)
  assert(violations.empty?, "#{evaluator_name} 有不合契約的 return 形式：#{violations.inspect}", failures)
end
reachable = EVALUATORS.flat_map { |name| LoopReturnContract.reachable_codes(__FILE__, name) }.uniq
missing = reachable - declared_codes
unreachable = declared_codes - reachable
assert(missing.empty?, "evaluator 會回傳但 error_contract 未宣告的 code：#{missing.sort.inspect}", failures)
assert(unreachable.empty?, "error_contract 宣告但 evaluator 不可能回傳的 code：#{unreachable.sort.inspect}", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

def evaluate(spec, test_case)
  case test_case.fetch("evaluator")
  when "retention" then retention_transition_failure(spec, test_case.fetch("run")) ||
                        deletion_requirements_failure(spec, test_case.fetch("run"))
  when "retrieval" then permission_staleness_failure(spec, test_case.fetch("run"))
  else raise "未知的 evaluator：#{test_case.fetch('evaluator')}"
  end
end

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)
  actual = evaluate(spec, test_case)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code),
         "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = evaluate(spec, test_case)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

if failures.empty?
  puts "PASS permission retention deletion contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
