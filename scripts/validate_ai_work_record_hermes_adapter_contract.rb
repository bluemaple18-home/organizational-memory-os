#!/usr/bin/env ruby

# SSP-304 / AIWR-07：Hermes 薄 Adapter 契約 validator。
# 薄判斷：結構斷言 + 兩個純函式 evaluator——
#   hermes_adapter_failure  : 只映射既有 Skill I/O、不加語意、不取得 acceptance/permission/
#                             canonical authority、可選依賴、版本不相容 fail-loud、非全員安裝、
#                             停用不再映射。
#   hermes_rollback_failure : disable switch / fallback / 逐副作用 side_effects。
# 交叉讀 ai-work-record-skill.yaml、ai-task-card-record.yaml、ai-work-record-harness.yaml、
# ai-work-record-boundary.yaml（pointer binding）。沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-hermes-adapter.yaml")
SKILL_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-skill.yaml")
CARD_RECORD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
HARNESS_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-harness.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-hermes-adapter-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-hermes-adapter-negative-fixtures.json")

EXPECTED_SUPPORTED_VERSIONS = %w[1.0 1.1 1.2].freeze
EXPECTED_MAPPING_RUN_FIELDS = %w[hermes_event mapped_to adapter_output_ref hermes_version outcome].freeze
EXPECTED_HERMES_OUTCOMES = %w[MAPPED INCOMPATIBLE_FAIL_LOUD DISABLED].freeze
EXPECTED_FORBIDDEN_RUN_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  canonical_write_receipt_ref
  permission_decision_ref
].freeze
OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

EXPECTED_HERMES_NEGATIVE_LABELS = [
  "a mapping targets something outside the existing skill I/O",
  "the adapter declares an added field",
  "a run carries a permission decision field",
  "the run declares hermes as required",
  "an incompatible hermes version did not fail loud",
  "outcome is not one of the allowed outcomes",
  "the adapter output is not a reference",
  "the adapter requires an org-wide install",
  "the adapter is disabled but still mapping",
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

# 純函式 Hermes Adapter run evaluator。回傳 nil 或精確 machine failure code。
# run 是自足 fixture 物件:
#   hermes_event_map[{hermes_event, mapped_to}], adapter_adds_fields[],
#   hermes_required, core_flow_blocked_without_hermes, requires_all_users_install,
#   supported_hermes_versions[], hermes_event, mapped_to, adapter_output_ref,
#   hermes_version, outcome, grants_acceptance/permission/canonical_writer, error, ok。
def hermes_adapter_failure(run, allowed_map_targets)
  # 1. authority(不取得 acceptance / permission / canonical writer)
  return "HERMES_EXCEEDS_AUTHORITY" if run["grants_acceptance"] == true
  return "HERMES_EXCEEDS_AUTHORITY" if run["grants_permission"] == true
  return "HERMES_EXCEEDS_AUTHORITY" if run["grants_canonical_writer"] == true
  return "HERMES_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_RUN_FIELDS.any? { |field| run.key?(field) }

  # 2. fail-loud
  return "FAIL_SILENT" if present?(run["error"]) && run["ok"] != false

  # 3. Hermes 為可選依賴
  return "HERMES_MANDATORY" if run["hermes_required"] == true
  return "HERMES_MANDATORY" if run["core_flow_blocked_without_hermes"] == true

  # 4. 非全員安裝
  return "HERMES_ORG_WIDE_INSTALL" if run["requires_all_users_install"] == true

  # 5. Adapter 只翻譯,不加語意
  return "HERMES_ADAPTER_ADDS_SEMANTICS" unless run["adapter_adds_fields"].to_a.empty?
  event_map = run["hermes_event_map"]
  return "HERMES_MAP_TARGET_UNKNOWN" unless event_map.is_a?(Array) && !event_map.empty?
  event_map.each do |entry|
    return "HERMES_MAP_TARGET_UNKNOWN" unless entry.is_a?(Hash) && allowed_map_targets.include?(entry["mapped_to"])
  end

  # 6. mapping_run outcome / output ref / 版本相容
  return "HERMES_INVALID_OUTCOME" unless EXPECTED_HERMES_OUTCOMES.include?(run["outcome"])

  supported = run["supported_hermes_versions"].to_a
  version_ok = supported.include?(run["hermes_version"])

  if run["outcome"] == "DISABLED"
    return "HERMES_DISABLED_STILL_MAPPING" if present?(run["adapter_output_ref"])

    return nil
  end

  return "HERMES_INCOMPAT_NOT_LOUD" if !version_ok && run["outcome"] != "INCOMPATIBLE_FAIL_LOUD"
  return nil if run["outcome"] == "INCOMPATIBLE_FAIL_LOUD"

  # outcome == MAPPED
  return "HERMES_OUTPUT_NOT_REF" unless urn?(run["adapter_output_ref"])
  return "HERMES_MAP_TARGET_UNKNOWN" unless allowed_map_targets.include?(run["mapped_to"])

  nil
end

# disable / rollback 契約 evaluator。純函式。回傳 nil 或精確 machine failure code。
def hermes_rollback_failure(rollback)
  return "HERMES_ROLLBACK_MISSING_FIELD" unless rollback.is_a?(Hash)
  return "HERMES_ROLLBACK_MISSING_FIELD" unless rollback["disable_switch"] == true
  return "HERMES_ROLLBACK_MISSING_FIELD" unless rollback["fallback"] == "CORE_FLOW_DIRECT"

  side_effects = rollback["side_effects"]
  return "HERMES_ROLLBACK_MISSING_FIELD" unless side_effects.is_a?(Array) && !side_effects.empty?

  side_effects.each do |side_effect|
    unless side_effect.is_a?(Hash) && %w[name teardown failure_state].all? { |key| present?(side_effect[key]) }
      return "HERMES_ROLLBACK_SIDE_EFFECT_UNSPECIFIED"
    end
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
skill_spec = read_yaml(SKILL_SPEC_PATH)
card_record_spec = read_yaml(CARD_RECORD_SPEC_PATH)
harness_spec = read_yaml(HARNESS_SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)

lifecycle_events = card_record_spec.fetch("lifecycle_event_to_status", {}).keys
seed_field_keys = skill_spec.dig("input_contract", "seed_field_keys").to_a
allowed_map_targets = (lifecycle_events + seed_field_keys).freeze

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-hermes-adapter:0.1.0", "schema_id 必須是 ai-work-record-hermes-adapter:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-07"), "schema.traces_to 必須包含 AIWR-07", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)

event_mapping = spec.fetch("event_mapping", {})
assert(event_mapping.fetch("adapter_adds_fields", ["x"]).empty?, "event_mapping.adapter_adds_fields 必須是空清單", failures)

authority = spec.fetch("authority", {})
assert(authority["grants_acceptance"] == false, "authority.grants_acceptance 必須是 false", failures)
assert(authority["grants_permission"] == false, "authority.grants_permission 必須是 false", failures)
assert(authority["grants_canonical_writer"] == false, "authority.grants_canonical_writer 必須是 false", failures)
assert(authority["error_behavior"] == "FAIL_LOUD", "authority.error_behavior 必須是 FAIL_LOUD", failures)
assert(
  sorted_set(authority.fetch("forbidden_run_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_RUN_FIELDS),
  "authority.forbidden_run_fields 與鎖定清單不符",
  failures
)

optional_dependency = spec.fetch("optional_dependency", {})
assert(optional_dependency["hermes_required"] == false, "optional_dependency.hermes_required 必須是 false", failures)
assert(optional_dependency["core_flow_without_hermes"] == "SUPPORTED", "optional_dependency.core_flow_without_hermes 必須是 SUPPORTED", failures)

compatibility = spec.fetch("compatibility", {})
assert(compatibility.fetch("supported_hermes_versions", []) == EXPECTED_SUPPORTED_VERSIONS, "compatibility.supported_hermes_versions 與鎖定清單不符", failures)
assert(compatibility["on_incompatible"] == "FAIL_LOUD", "compatibility.on_incompatible 必須是 FAIL_LOUD", failures)
assert(compatibility["adapter_disable"] == "SUPPORTED", "compatibility.adapter_disable 必須是 SUPPORTED", failures)

assert(spec.dig("no_org_wide_install", "requires_all_users_install") == false, "no_org_wide_install.requires_all_users_install 必須是 false", failures)

mapping_run = spec.fetch("mapping_run", {})
assert(mapping_run.fetch("fields", []) == EXPECTED_MAPPING_RUN_FIELDS, "mapping_run.fields 與鎖定清單不符", failures)
assert(sorted_set(mapping_run.fetch("outcomes", [])) == sorted_set(EXPECTED_HERMES_OUTCOMES), "mapping_run.outcomes 與鎖定清單不符", failures)

boundary_error_enum = boundary.dig("automated_step_contract", "error_behavior_enum").to_a
assert(boundary_error_enum == %w[FAIL_LOUD], "boundary automated_step_contract.error_behavior_enum 必須是 [FAIL_LOUD]", failures)
assert(authority["error_behavior"] == boundary_error_enum.first, "authority.error_behavior 必須與 boundary error_behavior_enum 一致", failures)

rollback = spec.fetch("disable_and_rollback", {})
assert(hermes_rollback_failure(rollback).nil?, "disable_and_rollback 本體必須是 contract-valid rollback 契約", failures)

# cross-reference pointer binding
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "lifecycle_events_from" => "ai-task-card-record.lifecycle_event_to_status",
  "seed_field_keys_from" => "ai-work-record-skill.input_contract.seed_field_keys",
  "harness_schema_id_from" => "ai-work-record-harness.schema.schema_id",
  "error_behavior_from" => "ai-work-record-boundary.automated_step_contract.error_behavior_enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(lifecycle_events), "card-record lifecycle_event_to_status 必須存在且非空", failures)
assert(present?(seed_field_keys), "skill input_contract.seed_field_keys 必須存在且非空", failures)
assert(harness_spec.dig("schema", "schema_id") == "urn:omos:schema:ai-work-record-harness:0.1.0", "harness schema_id 必須存在且相符", failures)
assert(present?(boundary.dig("automated_step_contract", "error_behavior_enum")), "boundary error_behavior_enum 必須存在且非空", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_HERMES_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("hermes_adapter_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} hermes adapter positive 必須預期 allow", failures)
  actual = hermes_adapter_failure(test_case.fetch("run"), allowed_map_targets)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

positive.fetch("hermes_rollback_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} hermes rollback positive 必須預期 allow", failures)
  actual = hermes_rollback_failure(test_case.fetch("rollback"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative.fetch("hermes_adapter_negative_cases") + negative.fetch("hermes_rollback_negative_cases")
negative.fetch("hermes_adapter_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} hermes adapter negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = hermes_adapter_failure(test_case.fetch("run"), allowed_map_targets)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

negative.fetch("hermes_rollback_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} hermes rollback negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = hermes_rollback_failure(test_case.fetch("rollback"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative_cases.map { |test_case| test_case.fetch("covers_hermes_negative_fixture") })
missing_labels = sorted_set(EXPECTED_HERMES_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "hermes negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai work record hermes adapter contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
