#!/usr/bin/env ruby
#
# AIWR-09 / SSP-307：Codex Native Adapter 契約 validator。
#
# 把 Codex 自己真實會發出的 session 事件類型（event_msg.payload.type，取自本機
# ~/.codex/sessions 的完整掃描，非人工樣本）分類成兩種之一：對應到既有 Hook 契約
# 接受的一個 lifecycle_events 項目，或明確列為「非生命週期事件」。任何觀察到但
# 兩邊都沒列的事件類型一律 fail loud，不猜。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/codex-native-adapter.yaml")
TASK_CARD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
RUNTIME_SAMPLE_PATH = File.join(ROOT, "規格/v0.1/fixtures/codex-native-adapter-runtime-sample.json")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/codex-native-adapter-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/codex-native-adapter-negative-fixtures.json")

EXPECTED_OUTCOMES = %w[MAPPED NOT_LIFECYCLE DISABLED].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a native event type not in lifecycle_event_map or non_lifecycle_event_types",
  "outcome MAPPED with adapter_output_ref not a URN",
  "outcome DISABLED with adapter_output_ref still present",
  "outcome NOT_LIFECYCLE with adapter_output_ref present",
  "outcome not in the declared outcomes enum",
  "outcome MAPPED with a native_event_type that has no lifecycle_event_map entry",
  "a MAPPED run whose mapped_to does not equal the declared map entry",
  "outcome MAPPED with a blank or absent task_ref",
  "a NOT_LIFECYCLE run whose native_event_type is not in non_lifecycle_event_types",
  "a run declaring adapter_required true",
  "a run declaring requires_all_users_install true",
  "a runtime sample event type absent from both classification lists",
  "a rollback side effect record missing a required field",
  "a rollback side effect record with an unspecified failure_state",
  "a run carries a forbidden authority field",
  "error but the run still claims success",
  "a classification list contains an event type never observed in the runtime sample"
].freeze

URN_PATTERN = /\Aurn:omos:/.freeze

EXPECTED_FORBIDDEN_RUN_FIELDS = %w[
  personal_acceptance_ref verification_receipt_ref accepted_for_record
  canonical_write_receipt_ref permission_decision_ref
].freeze

# 回傳 nil 代表 mapping run 合法；否則回傳精確的 machine failure code。
# lifecycle_event_map / non_lifecycle_event_types 皆從契約執行期讀取，不重述於此。
# run 是自足 fixture 物件：native_event_type, outcome, mapped_to, adapter_output_ref,
# adapter_required, requires_all_users_install, grants_acceptance/permission/canonical_writer,
# error, ok（與 Hermes Adapter 的 run 形狀一致，同一組治理欄位）。
def codex_mapping_failure(spec, run)
  lifecycle_map = spec.dig("lifecycle_event_map", "map")
  non_lifecycle = spec.dig("non_lifecycle_event_types", "events")

  # 1. authority（不取得 acceptance / permission / canonical writer）
  return "CODEX_EXCEEDS_AUTHORITY" if run["grants_acceptance"] == true
  return "CODEX_EXCEEDS_AUTHORITY" if run["grants_permission"] == true
  return "CODEX_EXCEEDS_AUTHORITY" if run["grants_canonical_writer"] == true
  return "CODEX_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_RUN_FIELDS.any? { |field| run.key?(field) }

  # 2. fail-loud
  return "FAIL_SILENT" if present?(run["error"]) && run["ok"] != false

  # 3. Adapter 為可選依賴
  return "CODEX_ADAPTER_MANDATORY" if run["adapter_required"] == true
  return "CODEX_ADAPTER_MANDATORY" if run["core_flow_blocked_without_adapter"] == true

  # 4. 非全員安裝
  return "CODEX_ORG_WIDE_INSTALL" if run["requires_all_users_install"] == true

  outcome = run["outcome"]
  return "CODEX_INVALID_OUTCOME" unless EXPECTED_OUTCOMES.include?(outcome)

  native_event = run["native_event_type"]
  output_ref = run["adapter_output_ref"]

  if outcome == "DISABLED"
    return "CODEX_DISABLED_STILL_MAPPING" if present?(output_ref)
    return nil
  end

  if outcome == "NOT_LIFECYCLE"
    return "CODEX_NOT_LIFECYCLE_STILL_MAPPING" if present?(output_ref)
    return "CODEX_UNCLASSIFIED_NATIVE_EVENT" unless non_lifecycle.include?(native_event)

    return nil
  end

  # outcome == "MAPPED"
  return "CODEX_OUTPUT_NOT_REF" unless output_ref.is_a?(String) && URN_PATTERN.match?(output_ref)
  # POST_MERGE_FIX_02：task_ref 是下游 Hook 用來把事件歸屬到哪一張卡的
  # 關聯鍵（ai-work-record-hook.yaml 的 event_envelope_fields.task_ref）。
  # 批次組裝（去重、排序、transition 合法性）是在 task_ref 範圍內做的，
  # 不是整個 host session 一批——這正是 task_started/task_complete 為何
  # 過去被判定「不安全」的真正根因：不是映射本身錯，是呼叫端沒有欄位可以
  # 告訴 Hook 這個事件屬於哪個 task_ref。本檔不驗證 task_ref 的值是否等於
  # 真實 turn_id（mapping_run 是抽象化後的分類紀錄，不是原始 payload），
  # 只要求呼叫端必須供應一個非空字串。
  return "CODEX_MISSING_TASK_REF" unless run["task_ref"].is_a?(String) && !run["task_ref"].strip.empty?
  return "CODEX_UNCLASSIFIED_NATIVE_EVENT" unless lifecycle_map.key?(native_event)

  declared_target = lifecycle_map.fetch(native_event)
  return "CODEX_MAPPING_TARGET_MISMATCH" unless run["mapped_to"] == declared_target

  nil
end

# rollback 契約 evaluator。純函式。回傳 nil 或精確 machine failure code。
def codex_rollback_failure(rollback)
  return "CODEX_ROLLBACK_MISSING_FIELD" unless rollback.is_a?(Hash)
  return "CODEX_ROLLBACK_MISSING_FIELD" unless rollback["disable_switch"] == true
  return "CODEX_ROLLBACK_MISSING_FIELD" unless rollback["fallback"] == "CORE_FLOW_DIRECT"

  side_effects = rollback["side_effects"]
  return "CODEX_ROLLBACK_MISSING_FIELD" unless side_effects.is_a?(Array) && !side_effects.empty?

  side_effects.each do |effect|
    unless effect.is_a?(Hash) && %w[name teardown failure_state].all? { |field| present?(effect[field]) }
      return "CODEX_ROLLBACK_MISSING_FIELD"
    end
    return "CODEX_ROLLBACK_SIDE_EFFECT_UNSPECIFIED" if effect["failure_state"].to_s.strip.length < 8
  end

  nil
end

# runtime sample 完整性 evaluator。純函式。回傳 nil 或精確 machine failure code。
# SSP307-F-04（repair-01）：原本只驗 observed - classified（有觀測到但沒分類
# 的事件）。Acceptance #1 要求「合起來剛好等於」，是雙向相等，不是單向涵蓋——
# 加一個從未觀測過的事件到 non_lifecycle_event_types、再補一個 positive
# fixture，原本的單向檢查完全抓不到，gate 仍然綠。
def codex_runtime_sample_failure(observed_event_types, lifecycle_map, non_lifecycle)
  classified = lifecycle_map + non_lifecycle
  return "CODEX_RUNTIME_SAMPLE_UNCLASSIFIED" unless sorted_set(observed_event_types) == sorted_set(classified)

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
task_card_spec = read_yaml(TASK_CARD_SPEC_PATH)
target_lifecycle_keys = task_card_spec.fetch("lifecycle_event_to_status").keys
spec["cross_reference"] ||= {}
spec["cross_reference"]["target_lifecycle_keys"] = target_lifecycle_keys

# --- 契約結構斷言 ---------------------------------------------------------

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec.dig("authority", "grants_acceptance") == false, "authority.grants_acceptance 必須為 false", failures)
assert(spec.dig("authority", "grants_permission") == false, "authority.grants_permission 必須為 false", failures)
assert(spec.dig("authority", "grants_canonical_writer") == false, "authority.grants_canonical_writer 必須為 false", failures)
assert(spec.dig("authority", "error_behavior") == "FAIL_LOUD", "authority.error_behavior 必須為 FAIL_LOUD", failures)
assert(sorted_set(spec.dig("mapping_run", "outcomes")) == sorted_set(EXPECTED_OUTCOMES), "mapping_run.outcomes 必須剛好是 MAPPED／NOT_LIFECYCLE／DISABLED", failures)

lifecycle_map = spec.dig("lifecycle_event_map", "map") || {}
non_lifecycle = spec.dig("non_lifecycle_event_types", "events") || []
# POST_MERGE_FIX_02：lifecycle_map 重新有條目（task_ref 讓 task_started／
# task_complete 的映射重新安全），恢復非空斷言。
assert(!lifecycle_map.empty?, "lifecycle_event_map 不得為空", failures)
lifecycle_map.each do |native_event, target|
  assert(target_lifecycle_keys.include?(target),
         "lifecycle_event_map.#{native_event} 的目標 #{target} 必須是 ai-task-card-record.lifecycle_event_to_status 的 key",
         failures)
end
overlap = lifecycle_map.keys & non_lifecycle
assert(overlap.empty?, "lifecycle_event_map 與 non_lifecycle_event_types 不得重疊：#{overlap.join(", ")}", failures)

# --- runtime probe：契約分類必須涵蓋真實觀測到的全部事件類型 ---------------

runtime_sample = read_json(RUNTIME_SAMPLE_PATH)
observed_types = runtime_sample.fetch("event_type_counts").keys
assert(
  codex_runtime_sample_failure(observed_types, lifecycle_map.keys, non_lifecycle).nil?,
  "runtime sample 觀測到但契約未分類的原生事件類型存在（CODEX_RUNTIME_SAMPLE_UNCLASSIFIED）",
  failures
)
declared_observed = spec.dig("measured_native_vocabulary", "observed_event_types")
sample_counts = runtime_sample.fetch("event_type_counts")
assert(
  sorted_set(declared_observed.keys) == sorted_set(observed_types),
  "契約 measured_native_vocabulary.observed_event_types 必須與 runtime sample 逐字相符",
  failures
)
# SSP307-F-04（repair-02）：上一輪只比對兩邊的 key 集合，count 值與
# sampled_sessions 完全沒有機器綁定——contract 的 counts 可以整批漂移，或
# sampled_sessions 可以憑空改成不同數字，gate 不會有反應。兩份「凍結 evidence」
# 若彼此對不上，其中至少一份就不是真的凍結，而是可以被悄悄改掉的裝飾文字。
assert(
  declared_observed == sample_counts,
  "契約 measured_native_vocabulary.observed_event_types 的數值必須與 runtime sample 的 event_type_counts 逐字相符（非只比對 key）：" \
  "契約 #{declared_observed.inspect} vs sample #{sample_counts.inspect}",
  failures
)
declared_sampled_sessions = spec.dig("measured_native_vocabulary", "sampled_sessions")
sample_sampled_sessions = runtime_sample.fetch("sampled_sessions")
assert(sample_sampled_sessions.to_i > 0, "runtime sample 必須來自至少一個 session", failures)
assert(
  declared_sampled_sessions == sample_sampled_sessions,
  "契約 measured_native_vocabulary.sampled_sessions（#{declared_sampled_sessions.inspect}）" \
  "必須與 runtime sample 的 sampled_sessions（#{sample_sampled_sessions.inspect}）逐字相符",
  failures
)

# --- error_contract 完整性 ---------------------------------------------------
#
# SSP307-F-03（repair-01）：這裡原本是三張手寫的 Ruby 常數陣列，跟 YAML
# error_contract 的 keys 互比 —— 兩邊都是我自己寫的，互比只證明「我抄對了」，
# 不證明 evaluator 實際可回傳什麼。新增一個 return branch、忘記同步這三張
# 清單，binding 本身完全抓不到。SSP-302 已經證明過這個模式必然出問題（regex
# 版；這裡連 regex 都沒有，是手寫清單，問題更直接）。
#
# 修法：沿用 SSP-302 已建立、參數化過的 AST/Ripper 機制
# （scripts/lib/loop_return_contract.rb），不新增第二套判斷方式。三個
# evaluator 各自求 reachable codes，並同時驗出口形狀（bodystmt 無
# rescue/else/ensure、最後一句必須是 nil 字面量）——只驗 reachable codes、
# 不驗出口形狀的話，會重新引入 SSP-302 closeout 已經修過的隱式回傳繞過缺口。
EVALUATORS = {
  "codex_mapping_failure" => nil,
  "codex_rollback_failure" => nil,
  "codex_runtime_sample_failure" => nil,
}.freeze

EVALUATORS.each_key do |evaluator_name|
  violations = LoopReturnContract.exit_shape_violations(__FILE__, evaluator_name)
  assert(violations.empty?, "#{evaluator_name} 出口形狀違反凍結規格：#{violations.join(" ／ ")}", failures)
end

reachable_by_evaluator = EVALUATORS.keys.each_with_object({}) do |name, acc|
  acc[name] = LoopReturnContract.reachable_codes(__FILE__, name)
end
declared_codes = spec.fetch("error_contract", {}).keys
all_reachable = reachable_by_evaluator.values.flatten
assert(!all_reachable.empty?, "無法從任一 evaluator 原始碼掃出可回傳 code，掃描失效", failures)
assert(
  sorted_set(declared_codes) == sorted_set(all_reachable),
  "error_contract 必須逐字等於三個 evaluator 實際可回傳的 code 聯集：" \
  "僅宣告 #{(sorted_set(declared_codes) - sorted_set(all_reachable)).to_a.join(", ")}；" \
  "僅可回傳 #{(sorted_set(all_reachable) - sorted_set(declared_codes)).to_a.join(", ")}",
  failures
)
mapping_run_reachable = reachable_by_evaluator.fetch("codex_mapping_failure")

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定負例清單不符",
  failures
)

# --- disable/rollback side effects -----------------------------------------

rollback = spec.fetch("disable_and_rollback", {})
assert(codex_rollback_failure(rollback).nil?, "disable_and_rollback 本體必須是 contract-valid rollback 契約", failures)

# --- fixture 驗證 ------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)
positive_cases = positive_fixtures.fetch("mapping_cases")
negative_cases = negative_fixtures.fetch("mapping_negative_cases")

assert(!positive_cases.empty?, "mapping_cases 不得為空", failures)
positive_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} positive fixture 必須預期 allow", failures)
  actual = codex_mapping_failure(spec, test_case.fetch("run"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

# 正例必須覆蓋每一個 lifecycle_event_map 條目，且每個 non_lifecycle 事件至少一例。
covered_mapped = sorted_set(positive_cases.select { |c| c.dig("run", "outcome") == "MAPPED" }.map { |c| c.dig("run", "native_event_type") })
assert(covered_mapped == sorted_set(lifecycle_map.keys), "positive fixtures 必須覆蓋 lifecycle_event_map 的每一個原生事件", failures)
covered_not_lifecycle = sorted_set(positive_cases.select { |c| c.dig("run", "outcome") == "NOT_LIFECYCLE" }.map { |c| c.dig("run", "native_event_type") })
assert(covered_not_lifecycle == sorted_set(non_lifecycle), "positive fixtures 必須覆蓋 non_lifecycle_event_types 的每一項", failures)

negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code), "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = codex_mapping_failure(spec, test_case.fetch("run"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

positive_fixtures.fetch("rollback_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} rollback positive 必須預期 allow", failures)
  actual = codex_rollback_failure(test_case.fetch("rollback"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

rollback_negative_cases = negative_fixtures.fetch("rollback_negative_cases")
rollback_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} rollback negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code), "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = codex_rollback_failure(test_case.fetch("rollback"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end
negative_cases = negative_cases + rollback_negative_cases

reachable_codes = mapping_run_reachable
covered_codes = sorted_set(negative_cases.map { |c| c.fetch("expected_failure_code") } & reachable_codes)
uncovered_codes = sorted_set(reachable_codes) - covered_codes
assert(uncovered_codes.empty?, "以下 mapping-run failure code 沒有任何負例覆蓋：#{uncovered_codes.to_a.join(", ")}", failures)

positive_fixtures.fetch("runtime_sample_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} runtime sample positive 必須預期 allow", failures)
  actual = codex_runtime_sample_failure(test_case.fetch("observed_event_types"), test_case.fetch("classified_lifecycle_keys"), test_case.fetch("classified_non_lifecycle_types"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

runtime_sample_negative_cases = negative_fixtures.fetch("runtime_sample_negative_cases")
runtime_sample_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} runtime sample negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code), "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = codex_runtime_sample_failure(test_case.fetch("observed_event_types"), test_case.fetch("classified_lifecycle_keys"), test_case.fetch("classified_non_lifecycle_types"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end
negative_cases = negative_cases + runtime_sample_negative_cases

covered_labels = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS codex native adapter contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
