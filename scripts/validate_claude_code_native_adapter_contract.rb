#!/usr/bin/env ruby
#
# AIWR-10 / SSP-308：Claude Code Native Adapter 契約 validator。
#
# 把 Claude Code 自己公開文件裡記載的 hook 事件名稱（封閉集合，非即時掃描）
# 分類成兩種之一：對應到既有 Hook 契約接受的一個 lifecycle_events 項目，或
# 明確列為「非生命週期事件」。任何觀察到但兩邊都沒列的事件類型一律 fail loud，
# 不猜。與 codex-native-adapter.yaml 是同一套治理形狀的手足，不是重新發明。
#
# 本輪範圍縮減（Owner 2026-09-14 選定）：不做即時 runtime probe，完整性改為
# 對照公開文件的封閉事件集合驗證，而非真實 session 語料掃描——因為這裡要分類
# 的是事件「名稱」，那是文件化且穩定的，不像 Codex 原生事件集合沒有公開規格。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/claude-code-native-adapter.yaml")
HOOK_EVENTS_SNAPSHOT_PATH = File.join(ROOT, "規格/v0.1/fixtures/claude-code-hook-events-doc-snapshot.json")
TASK_CARD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/claude-code-native-adapter-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/claude-code-native-adapter-negative-fixtures.json")

EXPECTED_OUTCOMES = %w[MAPPED NOT_LIFECYCLE DISABLED].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a native event type not in lifecycle_event_map or non_lifecycle_event_types",
  "outcome MAPPED with adapter_output_ref not a URN",
  "outcome MAPPED with a native_event_type that has no lifecycle_event_map entry",
  "a MAPPED run whose mapped_to does not equal the declared map entry",
  "outcome MAPPED with a blank or absent task_ref",
  "outcome DISABLED with adapter_output_ref still present",
  "outcome NOT_LIFECYCLE with adapter_output_ref present",
  "outcome not in the declared outcomes enum",
  "a NOT_LIFECYCLE run whose native_event_type is not in non_lifecycle_event_types",
  "a run declaring adapter_required true",
  "a run declaring requires_all_users_install true",
  "a rollback side effect record missing a required field",
  "a rollback side effect record with an unspecified failure_state",
  "a run carries a forbidden authority field",
  "error but the run still claims success"
].freeze

URN_PATTERN = /\Aurn:omos:/.freeze
EXPECTED_FORBIDDEN_RUN_FIELDS = %w[
  personal_acceptance_ref verification_receipt_ref accepted_for_record
  canonical_write_receipt_ref permission_decision_ref
].freeze

# 回傳 nil 代表 mapping run 合法；否則回傳精確的 machine failure code。
# lifecycle_event_map / non_lifecycle_event_types 皆從契約執行期讀取，不重述於此。
def claude_code_mapping_failure(spec, run)
  lifecycle_map = spec.dig("lifecycle_event_map", "map")
  non_lifecycle = spec.dig("non_lifecycle_event_types", "events")

  # 1. authority（不取得 acceptance / permission / canonical writer）
  return "CLAUDE_CODE_EXCEEDS_AUTHORITY" if run["grants_acceptance"] == true
  return "CLAUDE_CODE_EXCEEDS_AUTHORITY" if run["grants_permission"] == true
  return "CLAUDE_CODE_EXCEEDS_AUTHORITY" if run["grants_canonical_writer"] == true
  return "CLAUDE_CODE_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_RUN_FIELDS.any? { |field| run.key?(field) }

  # 2. fail-loud
  return "FAIL_SILENT" if present?(run["error"]) && run["ok"] != false

  # 3. Adapter 為可選依賴
  return "CLAUDE_CODE_ADAPTER_MANDATORY" if run["adapter_required"] == true
  return "CLAUDE_CODE_ADAPTER_MANDATORY" if run["core_flow_blocked_without_adapter"] == true

  # 4. 非全員安裝
  return "CLAUDE_CODE_ORG_WIDE_INSTALL" if run["requires_all_users_install"] == true

  outcome = run["outcome"]
  return "CLAUDE_CODE_INVALID_OUTCOME" unless EXPECTED_OUTCOMES.include?(outcome)

  native_event = run["native_event_type"]
  output_ref = run["adapter_output_ref"]

  if outcome == "DISABLED"
    return "CLAUDE_CODE_DISABLED_STILL_MAPPING" if present?(output_ref)
    return nil
  end

  if outcome == "NOT_LIFECYCLE"
    return "CLAUDE_CODE_NOT_LIFECYCLE_STILL_MAPPING" if present?(output_ref)
    return "CLAUDE_CODE_UNCLASSIFIED_NATIVE_EVENT" unless non_lifecycle.include?(native_event)

    return nil
  end

  # outcome == "MAPPED"
  return "CLAUDE_CODE_OUTPUT_NOT_REF" unless output_ref.is_a?(String) && URN_PATTERN.match?(output_ref)
  # POST_MERGE_FIX_01：task_ref 是下游 Hook 用來把事件歸屬到哪一張卡的
  # 關聯鍵（ai-work-record-hook.yaml 的 event_envelope_fields.task_ref）。
  # 批次組裝（去重、排序、transition 合法性）是在 task_ref 範圍內做的，
  # 不是整個 host session 一批——這正是 UserPromptSubmit/Stop 為何過去
  # 被判定「不安全」的真正根因：不是映射本身錯，是呼叫端沒有欄位可以
  # 告訴 Hook 這個事件屬於哪個 task_ref。本檔不驗證 task_ref 的值是否等於
  # 真實 prompt_id（mapping_run 是抽象化後的分類紀錄，不是原始 hook 輸入），
  # 只要求呼叫端必須供應一個非空字串。
  return "CLAUDE_CODE_MISSING_TASK_REF" unless run["task_ref"].is_a?(String) && !run["task_ref"].strip.empty?
  return "CLAUDE_CODE_UNCLASSIFIED_NATIVE_EVENT" unless lifecycle_map.key?(native_event)

  declared_target = lifecycle_map.fetch(native_event)
  return "CLAUDE_CODE_MAPPING_TARGET_MISMATCH" unless run["mapped_to"] == declared_target

  nil
end

# rollback 契約 evaluator。純函式。回傳 nil 或精確 machine failure code。
def claude_code_rollback_failure(rollback)
  return "CLAUDE_CODE_ROLLBACK_MISSING_FIELD" unless rollback.is_a?(Hash)
  return "CLAUDE_CODE_ROLLBACK_MISSING_FIELD" unless rollback["disable_switch"] == true
  return "CLAUDE_CODE_ROLLBACK_MISSING_FIELD" unless rollback["fallback"] == "CORE_FLOW_DIRECT"

  side_effects = rollback["side_effects"]
  return "CLAUDE_CODE_ROLLBACK_MISSING_FIELD" unless side_effects.is_a?(Array) && !side_effects.empty?

  side_effects.each do |effect|
    unless effect.is_a?(Hash) && %w[name teardown failure_state].all? { |field| present?(effect[field]) }
      return "CLAUDE_CODE_ROLLBACK_MISSING_FIELD"
    end
    return "CLAUDE_CODE_ROLLBACK_SIDE_EFFECT_UNSPECIFIED" if effect["failure_state"].to_s.strip.length < 8
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
task_card_spec = read_yaml(TASK_CARD_SPEC_PATH)
target_lifecycle_keys = task_card_spec.fetch("lifecycle_event_to_status").keys

# --- 契約結構斷言 ---------------------------------------------------------

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec.dig("authority", "grants_acceptance") == false, "authority.grants_acceptance 必須為 false", failures)
assert(spec.dig("authority", "grants_permission") == false, "authority.grants_permission 必須為 false", failures)
assert(spec.dig("authority", "grants_canonical_writer") == false, "authority.grants_canonical_writer 必須為 false", failures)
assert(spec.dig("authority", "error_behavior") == "FAIL_LOUD", "authority.error_behavior 必須為 FAIL_LOUD", failures)
assert(sorted_set(spec.dig("mapping_run", "outcomes")) == sorted_set(EXPECTED_OUTCOMES), "mapping_run.outcomes 必須剛好是 MAPPED／NOT_LIFECYCLE／DISABLED", failures)

lifecycle_map = spec.dig("lifecycle_event_map", "map") || {}
non_lifecycle = spec.dig("non_lifecycle_event_types", "events") || []
# POST_MERGE_FIX_01：lifecycle_map 重新有條目（task_ref 讓
# UserPromptSubmit／Stop 的映射重新安全），恢復非空斷言。
assert(!lifecycle_map.empty?, "lifecycle_event_map 不得為空", failures)
lifecycle_map.each do |native_event, target|
  assert(target_lifecycle_keys.include?(target),
         "lifecycle_event_map.#{native_event} 的目標 #{target} 必須是 ai-task-card-record.lifecycle_event_to_status 的 key",
         failures)
end
overlap = lifecycle_map.keys & non_lifecycle
assert(overlap.empty?, "lifecycle_event_map 與 non_lifecycle_event_types 不得重疊：#{overlap.join(", ")}", failures)

# --- 完整性：分類必須涵蓋凍結的公開文件事件快照 -----------------------------
#
# SSP308-F-03（repair-01）：v0.1 是拿同一份 YAML 裡兩張手寫清單互比，
# 證明不了跟真實文件的關係。改成對照 HOOK_EVENTS_SNAPSHOT_PATH——
# 一份帶 source_url／captured_at 出處的獨立凍結檔，不是這份契約自己寫的。

hook_events_snapshot = read_json(HOOK_EVENTS_SNAPSHOT_PATH)
documented_hook_events = hook_events_snapshot.fetch("hook_events")
assert(present?(hook_events_snapshot["source_url"]), "hook events snapshot 必須記錄 source_url 出處", failures)
assert(present?(hook_events_snapshot["captured_at"]), "hook events snapshot 必須記錄 captured_at", failures)
classified = lifecycle_map.keys + non_lifecycle
assert(
  sorted_set(documented_hook_events) == sorted_set(classified),
  "凍結的 hook events 快照必須與 lifecycle_event_map + non_lifecycle_event_types 的聯集逐字相符：" \
  "快照 #{sorted_set(documented_hook_events).to_a.sort.inspect} vs 分類 #{sorted_set(classified).to_a.sort.inspect}",
  failures
)

# --- error_contract 完整性：沿用 SSP-302／SSP-307 已建立的 AST 模組 --------

EVALUATORS = %w[claude_code_mapping_failure claude_code_rollback_failure].freeze

EVALUATORS.each do |evaluator_name|
  violations = LoopReturnContract.exit_shape_violations(__FILE__, evaluator_name)
  assert(violations.empty?, "#{evaluator_name} 出口形狀違反凍結規格：#{violations.join(" ／ ")}", failures)
end

reachable_by_evaluator = EVALUATORS.each_with_object({}) do |name, acc|
  acc[name] = LoopReturnContract.reachable_codes(__FILE__, name)
end
declared_codes = spec.fetch("error_contract", {}).keys
all_reachable = reachable_by_evaluator.values.flatten
assert(!all_reachable.empty?, "無法從任一 evaluator 原始碼掃出可回傳 code，掃描失效", failures)
assert(
  sorted_set(declared_codes) == sorted_set(all_reachable),
  "error_contract 必須逐字等於兩個 evaluator 實際可回傳的 code 聯集：" \
  "僅宣告 #{(sorted_set(declared_codes) - sorted_set(all_reachable)).to_a.join(", ")}；" \
  "僅可回傳 #{(sorted_set(all_reachable) - sorted_set(declared_codes)).to_a.join(", ")}",
  failures
)
mapping_run_reachable = reachable_by_evaluator.fetch("claude_code_mapping_failure")

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定負例清單不符",
  failures
)

# --- disable/rollback side effects -----------------------------------------

rollback = spec.fetch("disable_and_rollback", {})
assert(claude_code_rollback_failure(rollback).nil?, "disable_and_rollback 本體必須是 contract-valid rollback 契約", failures)

# --- fixture 驗證 ------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)
positive_cases = positive_fixtures.fetch("mapping_cases")
negative_cases = negative_fixtures.fetch("mapping_negative_cases")

assert(!positive_cases.empty?, "mapping_cases 不得為空", failures)
positive_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} positive fixture 必須預期 allow", failures)
  actual = claude_code_mapping_failure(spec, test_case.fetch("run"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

covered_mapped = sorted_set(positive_cases.select { |c| c.dig("run", "outcome") == "MAPPED" }.map { |c| c.dig("run", "native_event_type") })
assert(covered_mapped == sorted_set(lifecycle_map.keys), "positive fixtures 必須覆蓋 lifecycle_event_map 的每一個原生事件", failures)
covered_not_lifecycle = sorted_set(positive_cases.select { |c| c.dig("run", "outcome") == "NOT_LIFECYCLE" }.map { |c| c.dig("run", "native_event_type") })
assert(covered_not_lifecycle == sorted_set(non_lifecycle), "positive fixtures 必須覆蓋 non_lifecycle_event_types 的每一項", failures)

negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code), "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = claude_code_mapping_failure(spec, test_case.fetch("run"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

positive_fixtures.fetch("rollback_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} rollback positive 必須預期 allow", failures)
  actual = claude_code_rollback_failure(test_case.fetch("rollback"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

rollback_negative_cases = negative_fixtures.fetch("rollback_negative_cases")
rollback_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} rollback negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code), "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = claude_code_rollback_failure(test_case.fetch("rollback"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end
negative_cases = negative_cases + rollback_negative_cases

covered_labels = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(", ")}", failures)

reachable_codes = mapping_run_reachable
covered_codes = sorted_set(negative_cases.map { |c| c.fetch("expected_failure_code") } & reachable_codes)
uncovered_codes = sorted_set(reachable_codes) - covered_codes
assert(uncovered_codes.empty?, "以下 mapping-run failure code 沒有任何負例覆蓋：#{uncovered_codes.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS claude code native adapter contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
