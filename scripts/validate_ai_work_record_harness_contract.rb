#!/usr/bin/env ruby

# SSP-303 / AIWR-06：輕量 Harness 編排契約 validator。
# 薄判斷：結構斷言 + 兩個純函式 evaluator——
#   harness_run_failure      : 只編排 HOOK/SKILL/LOOP、順序單 agent、fan-out 需 measured gap、
#                              不建第二套 runtime、每步可追溯、單步失敗 loud、不越權、不依賴常駐服務。
#   harness_rollback_failure : removable / fallback / 逐副作用 side_effects。
# 交叉讀 ai-work-record-hook.yaml、ai-work-record-skill.yaml、ai-work-record-loop.yaml、
# ai-work-record-boundary.yaml（pointer binding）。沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-harness.yaml")
HOOK_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-hook.yaml")
SKILL_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-skill.yaml")
LOOP_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-loop.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-harness-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-harness-negative-fixtures.json")

EXPECTED_ALLOWED_CAPABILITIES = %w[HOOK SKILL LOOP].freeze
EXPECTED_EXECUTION_MODE = "SEQUENTIAL_SINGLE_AGENT"
EXPECTED_SECOND_RUNTIME_FLAGS = %w[builds_registry builds_fsm builds_database builds_canonical_writer].freeze
EXPECTED_STEP_FIELDS = %w[step capability input_ref output_ref timeout_seconds error receipt_ref].freeze
EXPECTED_STEP_URN_FIELDS = %w[input_ref output_ref receipt_ref].freeze
EXPECTED_HARNESS_OUTCOMES = %w[COMPLETED STEP_FAILED].freeze
EXPECTED_FORBIDDEN_RUN_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  canonical_write_receipt_ref
  permission_decision_ref
].freeze
OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

EXPECTED_HARNESS_NEGATIVE_LABELS = [
  "a step names a capability that is not HOOK / SKILL / LOOP",
  "the run did not execute in sequential single-agent mode",
  "a step fans out without a measured gap ref",
  "the harness builds a registry / FSM / database / canonical writer",
  "an executed step is missing a traceability field",
  "a step reference is not a URN",
  "outcome is not one of the allowed outcomes",
  "a step failed silently while the run claims COMPLETED",
  "outcome STEP_FAILED without naming a failed step",
  "run carries a permission decision field",
  "the harness requires an always-on service",
  "a rollback side effect is missing a field",
  "error but the run still claims success"
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

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

def positive_integer?(value)
  value.is_a?(Integer) && value.positive?
end

# 純函式 Harness run evaluator。回傳 nil 或精確 machine failure code。
# run 是自足 fixture 物件:
#   execution_mode, steps[{step, capability, input_ref, output_ref, timeout_seconds,
#   error, receipt_ref, fan_out, measured_gap_ref}], outcome, failed_step,
#   builds_registry/builds_fsm/builds_database/builds_canonical_writer,
#   requires_always_on_service, performs_memory_acceptance, writes_company_knowledge,
#   makes_permission_decisions, error, ok。
def harness_run_failure(run, allowed_capabilities)
  # 1. 不建第二套 runtime
  return "HARNESS_SECOND_RUNTIME" if EXPECTED_SECOND_RUNTIME_FLAGS.any? { |flag| run[flag] == true }

  # 2. 不依賴常駐服務
  return "HARNESS_REQUIRES_ALWAYS_ON" if run["requires_always_on_service"] == true

  # 3. authority(不做 memory acceptance / canonical write / permission decision)
  return "HARNESS_EXCEEDS_AUTHORITY" if run["performs_memory_acceptance"] == true
  return "HARNESS_EXCEEDS_AUTHORITY" if run["writes_company_knowledge"] == true
  return "HARNESS_EXCEEDS_AUTHORITY" if run["makes_permission_decisions"] == true
  return "HARNESS_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_RUN_FIELDS.any? { |field| run.key?(field) }

  # 4. fail-loud
  return "FAIL_SILENT" if present?(run["error"]) && run["ok"] != false

  return "HARNESS_NOT_SEQUENTIAL" unless run["execution_mode"] == EXPECTED_EXECUTION_MODE

  steps = run["steps"]
  return "HARNESS_STEP_NOT_TRACEABLE" unless steps.is_a?(Array) && !steps.empty?

  steps.each do |step|
    unless step.is_a?(Hash) && EXPECTED_STEP_FIELDS.all? { |field| step.key?(field) } &&
           positive_integer?(step["timeout_seconds"])
      return "HARNESS_STEP_NOT_TRACEABLE"
    end
    return "HARNESS_STEP_REF_NOT_URN" if EXPECTED_STEP_URN_FIELDS.any? { |field| !urn?(step[field]) }
    return "HARNESS_UNKNOWN_CAPABILITY" unless allowed_capabilities.include?(step["capability"])
    return "HARNESS_UNJUSTIFIED_FANOUT" if step["fan_out"] == true && !urn?(step["measured_gap_ref"])
  end

  # 5. 單步失敗必須 loud 且標記
  return "HARNESS_INVALID_OUTCOME" unless EXPECTED_HARNESS_OUTCOMES.include?(run["outcome"])
  step_has_error = steps.any? { |step| present?(step["error"]) }
  return "HARNESS_SILENT_STEP_FAILURE" if step_has_error && run["outcome"] == "COMPLETED"
  if run["outcome"] == "STEP_FAILED"
    step_numbers = steps.map { |step| step["step"] }
    return "HARNESS_STEP_FAILURE_UNMARKED" unless step_numbers.include?(run["failed_step"])
  end

  nil
end

# disable / rollback 契約 evaluator。純函式。回傳 nil 或精確 machine failure code。
def harness_rollback_failure(rollback)
  return "HARNESS_ROLLBACK_MISSING_FIELD" unless rollback.is_a?(Hash)
  return "HARNESS_ROLLBACK_MISSING_FIELD" unless rollback["removable"] == true
  return "HARNESS_ROLLBACK_MISSING_FIELD" unless rollback["fallback"] == "DIRECT_SKILL_INVOCATION"

  side_effects = rollback["side_effects"]
  return "HARNESS_ROLLBACK_MISSING_FIELD" unless side_effects.is_a?(Array) && !side_effects.empty?

  side_effects.each do |side_effect|
    unless side_effect.is_a?(Hash) && %w[name teardown failure_state].all? { |key| present?(side_effect[key]) }
      return "HARNESS_ROLLBACK_SIDE_EFFECT_UNSPECIFIED"
    end
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
hook_spec = read_yaml(HOOK_SPEC_PATH)
skill_spec = read_yaml(SKILL_SPEC_PATH)
loop_spec = read_yaml(LOOP_SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-harness:0.1.0", "schema_id 必須是 ai-work-record-harness:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-06"), "schema.traces_to 必須包含 AIWR-06", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)

orchestration = spec.fetch("orchestration", {})
assert(orchestration.fetch("allowed_capabilities", []) == EXPECTED_ALLOWED_CAPABILITIES, "orchestration.allowed_capabilities 必須剛好是 [HOOK, SKILL, LOOP]", failures)
assert(orchestration["execution_mode"] == EXPECTED_EXECUTION_MODE, "orchestration.execution_mode 必須是 SEQUENTIAL_SINGLE_AGENT", failures)

second_runtime = spec.fetch("no_second_runtime", {})
EXPECTED_SECOND_RUNTIME_FLAGS.each do |flag|
  assert(second_runtime[flag] == false, "no_second_runtime.#{flag} 必須是 false", failures)
end

step_record = spec.fetch("step_record", {})
assert(step_record.fetch("required_fields", []) == EXPECTED_STEP_FIELDS, "step_record.required_fields 與鎖定清單不符", failures)
assert(sorted_set(step_record.fetch("urn_fields", [])) == sorted_set(EXPECTED_STEP_URN_FIELDS), "step_record.urn_fields 與鎖定清單不符", failures)

step_failure = spec.fetch("step_failure", {})
assert(sorted_set(step_failure.fetch("outcomes", [])) == sorted_set(EXPECTED_HARNESS_OUTCOMES), "step_failure.outcomes 與鎖定清單不符", failures)

authority = spec.fetch("authority", {})
assert(authority["performs_memory_acceptance"] == false, "authority.performs_memory_acceptance 必須是 false", failures)
assert(authority["writes_company_knowledge"] == false, "authority.writes_company_knowledge 必須是 false", failures)
assert(authority["makes_permission_decisions"] == false, "authority.makes_permission_decisions 必須是 false", failures)
assert(authority["error_behavior"] == "FAIL_LOUD", "authority.error_behavior 必須是 FAIL_LOUD", failures)
assert(
  sorted_set(authority.fetch("forbidden_run_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_RUN_FIELDS),
  "authority.forbidden_run_fields 與鎖定清單不符",
  failures
)
boundary_error_enum = boundary.dig("automated_step_contract", "error_behavior_enum").to_a
assert(boundary_error_enum == %w[FAIL_LOUD], "boundary automated_step_contract.error_behavior_enum 必須是 [FAIL_LOUD]", failures)
assert(authority["error_behavior"] == boundary_error_enum.first, "authority.error_behavior 必須與 boundary error_behavior_enum 一致", failures)

assert(spec.dig("no_always_on", "requires_always_on_service") == false, "no_always_on.requires_always_on_service 必須是 false", failures)

rollback = spec.fetch("disable_and_rollback", {})
assert(harness_rollback_failure(rollback).nil?, "disable_and_rollback 本體必須是 contract-valid rollback 契約", failures)

# cross-reference pointer binding
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "hook_schema_id_from" => "ai-work-record-hook.schema.schema_id",
  "skill_schema_id_from" => "ai-work-record-skill.schema.schema_id",
  "loop_schema_id_from" => "ai-work-record-loop.schema.schema_id",
  "error_behavior_from" => "ai-work-record-boundary.automated_step_contract.error_behavior_enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(hook_spec.dig("schema", "schema_id") == "urn:omos:schema:ai-work-record-hook:0.1.0", "hook schema_id 必須存在且相符", failures)
assert(skill_spec.dig("schema", "schema_id") == "urn:omos:schema:ai-work-record-skill:0.1.0", "skill schema_id 必須存在且相符", failures)
assert(loop_spec.dig("schema", "schema_id") == "urn:omos:schema:ai-work-record-loop:0.1.0", "loop schema_id 必須存在且相符", failures)
assert(present?(boundary.dig("automated_step_contract", "error_behavior_enum")), "boundary error_behavior_enum 必須存在且非空", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_HARNESS_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("harness_run_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} harness run positive 必須預期 allow", failures)
  actual = harness_run_failure(test_case.fetch("run"), EXPECTED_ALLOWED_CAPABILITIES)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

positive.fetch("harness_rollback_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} harness rollback positive 必須預期 allow", failures)
  actual = harness_rollback_failure(test_case.fetch("rollback"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative.fetch("harness_run_negative_cases") + negative.fetch("harness_rollback_negative_cases")
negative.fetch("harness_run_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} harness run negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = harness_run_failure(test_case.fetch("run"), EXPECTED_ALLOWED_CAPABILITIES)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

negative.fetch("harness_rollback_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} harness rollback negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = harness_rollback_failure(test_case.fetch("rollback"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative_cases.map { |test_case| test_case.fetch("covers_harness_negative_fixture") })
missing_labels = sorted_set(EXPECTED_HARNESS_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "harness negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai work record harness contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
