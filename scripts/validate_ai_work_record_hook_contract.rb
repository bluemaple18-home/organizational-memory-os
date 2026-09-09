#!/usr/bin/env ruby

# SSP-301 / AIWR-04：工作紀錄 Hook 契約 validator。
# 薄判斷：結構斷言 + 兩個純函式 evaluator——
#   hook_capture_failure  : 事件擷取 -> 合規 Skill 輸入批次（allowed events、reference-only、
#                           冪等去重、ordering/transition、authority、fail-silent、停用發空）。
#   hook_rollback_failure : disable switch / disabled behavior / fallback / 逐副作用 side_effects。
# 交叉讀 ai-work-record-boundary.yaml、ai-task-card-record.yaml、ai-work-record-skill.yaml
# （pointer binding）。沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-hook.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
CARD_RECORD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
SKILL_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-skill.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-hook-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-hook-negative-fixtures.json")

EXPECTED_ALLOWED_EVENTS = %w[start block unblock submit_review complete cancel].freeze
EXPECTED_ENVELOPE_FIELDS = %w[task_ref event occurred_at event_key evidence_refs].freeze
EXPECTED_EMITTED_FIELDS = %w[lifecycle_events batch].freeze
EXPECTED_ISOLATION_FORBIDDEN = %w[PROPAGATE RAISE_INTO_HOST BLOCK_HOST_TASK].freeze
EXPECTED_FORBIDDEN_BATCH_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  canonical_write_receipt_ref
].freeze
OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze
# fail-closed:host_task_impact 只允許「缺值」（key 不存在 => nil）或契約明定的唯一安全值。
# 其餘任何字串（BLOCKED / FAILED / CANCELLED / MUTATED …）都代表 capture failure 改變了
# 宿主任務結果,違反 failure_isolation.on_error = ISOLATE_FROM_HOST_TASK。
EXPECTED_HOST_TASK_IMPACT_ALLOWED = [nil, "UNAFFECTED"].freeze

EXPECTED_HOOK_NEGATIVE_LABELS = [
  "event not in the allowed set",
  "event envelope carries inline content",
  "duplicate event handled non-idempotently",
  "duplicate event_key with a conflicting event",
  "emitted batch does not start with start",
  "emitted batch contains an illegal transition",
  "capture failure propagates into the host task",
  "capture reports a non-isolated host task impact",
  "emitted batch carries a memory acceptance field",
  "hook disabled but batch carries an authority field",
  "emitted batch is not a valid skill input",
  "hook disabled but still emitting events",
  "error but capture still claims success",
  "rollback contract missing disable switch",
  "rollback side effect missing a field"
].freeze

def read_json(path)
  JSON.parse(File.read(path), object_class: StrictJsonObject)
end

def read_yaml(path)
  text = File.read(path)
  assert_unique_yaml_mapping_keys(Psych.parse_stream(text))
  YAML.safe_load(text, permitted_classes: [], aliases: false)
end

def assert(condition, message, failures)
  failures << message unless condition
end

def sorted_set(values)
  values.to_a.sort
end

def urn?(value, pattern)
  value.is_a?(String) && pattern.match?(value)
end

# 逐步 replay 去重後的事件序列;回傳 nil 或非法 transition 的 failure code。
def replay_transition_failure(events, card_record_spec)
  event_map = card_record_spec.fetch("lifecycle_event_to_status", {})
  transitions = card_record_spec.fetch("allowed_status_transitions", {})
  status = event_map.fetch(events.first)
  events.drop(1).each do |event|
    target = event_map.fetch(event)
    return "HOOK_ILLEGAL_TRANSITION" unless transitions.fetch(status, []).include?(target)

    status = target
  end
  nil
end

# 事件擷取 evaluator。純函式。回傳 nil 或精確 machine failure code。
# capture 是自足 fixture 物件:
#   raw_events[]（envelope）, disabled(bool), emitted{lifecycle_events[], batch[]},
#   host_task_impact, performs_memory_acceptance, writes_company_knowledge, error, ok。
def hook_capture_failure(capture, card_record_spec, allowed_events)
  event_map = card_record_spec.fetch("lifecycle_event_to_status", {})

  raw = capture["raw_events"]
  emitted = capture["emitted"]
  return "HOOK_MISSING_FIELD" unless raw.is_a?(Array) && emitted.is_a?(Hash)

  emitted_events = emitted["lifecycle_events"]
  return "HOOK_MISSING_FIELD" unless emitted_events.is_a?(Array) && emitted.key?("batch")

  # 擷取失敗必須與宿主任務隔離(fail-closed:只允許缺值或 UNAFFECTED)。
  return "HOOK_FAILURE_BLOCKS_HOST_TASK" unless EXPECTED_HOST_TASK_IMPACT_ALLOWED.include?(capture["host_task_impact"])

  # envelope 結構 + reference-only
  raw.each do |envelope|
    return "HOOK_MISSING_FIELD" unless envelope.is_a?(Hash) && EXPECTED_ENVELOPE_FIELDS.all? { |field| envelope.key?(field) }
    return "HOOK_EVENT_INLINE_CONTENT" unless urn?(envelope["task_ref"], OMOS_URN)
    return "HOOK_EVENT_INLINE_CONTENT" unless envelope["evidence_refs"].is_a?(Array) &&
                                              envelope["evidence_refs"].all? { |ref| urn?(ref, OMOS_URN) }
    return "HOOK_EVENT_INLINE_CONTENT" if present?(envelope["inline_content"]) || present?(envelope["task_body"])
  end

  # 只擷取允許的 lifecycle events
  return "HOOK_EVENT_NOT_ALLOWED" if raw.any? { |envelope| !allowed_events.include?(envelope["event"]) }
  return "HOOK_EVENT_NOT_ALLOWED" if raw.any? { |envelope| !event_map.key?(envelope["event"]) }

  # 同一 event_key 若帶不同 event = 矛盾的 duplicate,fail closed(不得靜默 first-wins)。
  seen_event_by_key = {}
  raw.each do |envelope|
    key = envelope["event_key"]
    return "HOOK_DUPLICATE_CONFLICT" if seen_event_by_key.key?(key) && seen_event_by_key[key] != envelope["event"]

    seen_event_by_key[key] = envelope["event"]
  end

  # authority:停用與否都適用 —— 批次不得帶 acceptance / canonical 欄位或宣稱越權。
  return "HOOK_EXCEEDS_AUTHORITY" if capture["performs_memory_acceptance"] == true
  return "HOOK_EXCEEDS_AUTHORITY" if capture["writes_company_knowledge"] == true
  return "HOOK_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_BATCH_FIELDS.any? { |field| emitted.key?(field) }

  # fail-loud:停用與否都適用 —— 有 error 但仍宣稱成功。
  return "FAIL_SILENT" if present?(capture["error"]) && capture["ok"] != false

  # 停用狀態:對任何事件流都必須發空批次
  if capture["disabled"] == true
    return "HOOK_DISABLED_STILL_EMITTING" unless emitted_events.empty? && emitted.fetch("batch", []).to_a.empty?

    return nil
  end

  # 冪等:以 event_key 去重,emitted 必須等於去重後序列
  deduped = raw.uniq { |envelope| envelope["event_key"] }
  return "HOOK_DUPLICATE_NOT_IDEMPOTENT" if emitted_events != deduped.map { |envelope| envelope["event"] }

  # emitted 批次必須是 contract-valid 的 skill input lifecycle_events
  return "HOOK_OUTPUT_NOT_SKILL_INPUT" if emitted_events.empty?
  return "HOOK_BATCH_MUST_START" if emitted_events.first != "start"

  transition_code = replay_transition_failure(emitted_events, card_record_spec)
  return transition_code if transition_code

  nil
end

# disable / rollback 契約 evaluator。純函式。回傳 nil 或精確 machine failure code。
def hook_rollback_failure(rollback)
  return "HOOK_ROLLBACK_MISSING_FIELD" unless rollback.is_a?(Hash)
  return "HOOK_ROLLBACK_MISSING_FIELD" unless rollback["disable_switch"] == true
  return "HOOK_ROLLBACK_MISSING_FIELD" unless rollback["disabled_behavior"] == "EMIT_NOTHING"
  return "HOOK_ROLLBACK_MISSING_FIELD" unless rollback["fallback"] == "MANUAL_SKILL_INVOCATION"

  side_effects = rollback["side_effects"]
  return "HOOK_ROLLBACK_MISSING_FIELD" unless side_effects.is_a?(Array) && !side_effects.empty?

  side_effects.each do |side_effect|
    unless side_effect.is_a?(Hash) && %w[name teardown failure_state].all? { |key| present?(side_effect[key]) }
      return "HOOK_ROLLBACK_SIDE_EFFECT_UNSPECIFIED"
    end
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)
card_record_spec = read_yaml(CARD_RECORD_SPEC_PATH)
skill_spec = read_yaml(SKILL_SPEC_PATH)

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-hook:0.1.0", "schema_id 必須是 ai-work-record-hook:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-04"), "schema.traces_to 必須包含 AIWR-04", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)

capture_contract = spec.fetch("capture_contract", {})
assert(capture_contract.fetch("allowed_events", []) == EXPECTED_ALLOWED_EVENTS, "capture_contract.allowed_events 與鎖定清單不符", failures)
assert(capture_contract.fetch("event_envelope_fields", []) == EXPECTED_ENVELOPE_FIELDS, "capture_contract.event_envelope_fields 與鎖定清單不符", failures)
assert(capture_contract["reference_only"] == true, "capture_contract.reference_only 必須為 true", failures)
assert(capture_contract.dig("idempotency", "dedupe_by") == "event_key", "capture_contract.idempotency.dedupe_by 必須是 event_key", failures)

# allowed_events 必須 ⊆ ai-task-card-record.lifecycle_event_to_status 的 key
card_events = card_record_spec.fetch("lifecycle_event_to_status", {}).keys
assert((EXPECTED_ALLOWED_EVENTS - card_events).empty?, "allowed_events 必須是 ai-task-card-record lifecycle_event_to_status 的子集", failures)

isolation = spec.fetch("failure_isolation", {})
assert(isolation["on_error"] == "ISOLATE_FROM_HOST_TASK", "failure_isolation.on_error 必須是 ISOLATE_FROM_HOST_TASK", failures)
assert(
  sorted_set(isolation.fetch("forbidden", [])) == sorted_set(EXPECTED_ISOLATION_FORBIDDEN),
  "failure_isolation.forbidden 與鎖定清單不符",
  failures
)
assert(
  isolation.fetch("host_task_impact_allowed", []) == EXPECTED_HOST_TASK_IMPACT_ALLOWED.compact,
  "failure_isolation.host_task_impact_allowed 必須剛好是 [UNAFFECTED]（缺值另計）",
  failures
)

authority = spec.fetch("authority", {})
assert(authority["reads_task_content"] == false, "authority.reads_task_content 必須是 false", failures)
assert(authority["performs_memory_acceptance"] == false, "authority.performs_memory_acceptance 必須是 false", failures)
assert(authority["writes_company_knowledge"] == false, "authority.writes_company_knowledge 必須是 false", failures)
assert(authority["error_behavior"] == "FAIL_LOUD", "authority.error_behavior 必須是 FAIL_LOUD", failures)
assert(
  sorted_set(authority.fetch("forbidden_batch_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_BATCH_FIELDS),
  "authority.forbidden_batch_fields 與鎖定清單不符",
  failures
)
boundary_error_enum = boundary.dig("automated_step_contract", "error_behavior_enum").to_a
assert(boundary_error_enum == %w[FAIL_LOUD], "boundary automated_step_contract.error_behavior_enum 必須是 [FAIL_LOUD]", failures)
assert(authority["error_behavior"] == boundary_error_enum.first, "authority.error_behavior 必須與 boundary error_behavior_enum 一致", failures)

output_contract = spec.fetch("output_contract", {})
assert(output_contract.fetch("emitted_fields", []) == EXPECTED_EMITTED_FIELDS, "output_contract.emitted_fields 與鎖定清單不符", failures)

rollback = spec.fetch("disable_and_rollback", {})
assert(hook_rollback_failure(rollback).nil?, "disable_and_rollback 本體必須是 contract-valid rollback 契約", failures)

# cross-reference pointer binding
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "allowed_events_from" => "ai-task-card-record.lifecycle_event_to_status",
  "transitions_from" => "ai-task-card-record.allowed_status_transitions",
  "skill_input_rule_from" => "ai-work-record-skill.input_contract.lifecycle_events_rule",
  "error_behavior_from" => "ai-work-record-boundary.automated_step_contract.error_behavior_enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(card_record_spec.fetch("lifecycle_event_to_status", {})), "card-record lifecycle_event_to_status 必須存在且非空", failures)
assert(present?(card_record_spec.fetch("allowed_status_transitions", {})), "card-record allowed_status_transitions 必須存在且非空", failures)
assert(present?(skill_spec.dig("input_contract", "lifecycle_events_rule")), "skill input_contract.lifecycle_events_rule 必須存在且非空", failures)
assert(present?(boundary.dig("automated_step_contract", "error_behavior_enum")), "boundary error_behavior_enum 必須存在且非空", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_HOOK_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("hook_capture_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} hook capture positive 必須預期 allow", failures)
  actual = hook_capture_failure(test_case.fetch("capture"), card_record_spec, EXPECTED_ALLOWED_EVENTS)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

positive.fetch("hook_rollback_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} hook rollback positive 必須預期 allow", failures)
  actual = hook_rollback_failure(test_case.fetch("rollback"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative.fetch("hook_capture_negative_cases") + negative.fetch("hook_rollback_negative_cases")
negative.fetch("hook_capture_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} hook capture negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = hook_capture_failure(test_case.fetch("capture"), card_record_spec, EXPECTED_ALLOWED_EVENTS)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

negative.fetch("hook_rollback_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} hook rollback negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = hook_rollback_failure(test_case.fetch("rollback"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative_cases.map { |test_case| test_case.fetch("covers_hook_negative_fixture") })
missing_labels = sorted_set(EXPECTED_HOOK_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "hook negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai work record hook contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
