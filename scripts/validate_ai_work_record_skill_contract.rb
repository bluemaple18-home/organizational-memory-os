#!/usr/bin/env ruby

# SSP-300 / AIWR-03：工作紀錄 Skill 契約 validator。
# 薄判斷：結構斷言 + skill_transform_failure（純函式）評估。
# Skill = lifecycle events + seed fields -> 合規草稿；不接受 Memory、不寫 Company Knowledge。
# 交叉讀 ai-work-record-boundary.yaml 與 ai-task-card-record.yaml（pointer binding）。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-skill.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
CARD_RECORD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-skill-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-skill-negative-fixtures.json")

EXPECTED_INPUT_REQUIRED_FIELDS = %w[lifecycle_events seed_fields].freeze
EXPECTED_SEED_FIELD_KEYS = %w[objective scope constraints acceptance].freeze
EXPECTED_OUTPUT_REQUIRED_FIELDS = %w[draft_card evidence_refs dry_run replayed_status].freeze
EXPECTED_FORBIDDEN_OUTPUT_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  canonical_write_receipt_ref
].freeze
CARD_ID_URN = /\Aurn:omos:task-card:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze
OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

EXPECTED_SKILL_NEGATIVE_LABELS = [
  "missing a seed field",
  "unknown lifecycle event",
  "skill accepts an illegal lifecycle transition",
  "draft card is not contract-valid",
  "draft card copies sensitive content",
  "evidence ref carries inline content",
  "dry_run is not a boolean",
  "output carries a memory acceptance field",
  "replayed status does not match the events",
  "draft card status disagrees with the replay",
  "error but output still claims success"
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

def blank_string?(value)
  !value.is_a?(String) || value.strip.empty?
end

def urn?(value, pattern)
  value.is_a?(String) && pattern.match?(value)
end

# 等效於 ai-task-card-record 的 record shape 檢查（資料驅動，讀 card-record spec）。
# NOTE: 這是 SSP-299 record 檢查的第二份實作 —— repo-wide validator Refactor 卡
# 會把它抽成共用 helper 讓 SSP-299 / SSP-300 共用。在那之前，本函式必須與
# validate_ai_task_card_record_contract.rb 的 task_card_record_failure 逐項對齊
# （唯一刻意省略：SSP-299 的 lifecycle 一致性，改由本卡的 DRAFT_CARD_STATUS_MISMATCH
# 覆蓋）。
def draft_card_contract_valid?(card, card_record_spec, boundary_forbidden_fields)
  return false unless card.is_a?(Hash)

  fields = card_record_spec.fetch("fields", {}).keys
  return false if fields.any? { |field| !card.key?(field) }
  return false if %w[objective scope constraints acceptance].any? { |field| blank_string?(card[field]) }
  return false unless urn?(card["card_id"], CARD_ID_URN)
  return false unless card["evidence_refs"].is_a?(Array) && card["evidence_refs"].all? { |ref| urn?(ref, OMOS_URN) }
  return false unless card_record_spec.fetch("status_enum", []).include?(card["status"])
  return false if boundary_forbidden_fields.any? { |field| card.key?(field) }
  return false if card["sensitive_content_copied"] == true
  return false if card["status"] == "DONE" && card["evidence_refs"].to_a.empty?

  true
end

# 逐步 replay lifecycle events；回傳 [failure_code_or_nil, final_status]。
def replay_lifecycle(events, card_record_spec)
  event_map = card_record_spec.fetch("lifecycle_event_to_status", {})
  transitions = card_record_spec.fetch("allowed_status_transitions", {})
  status = event_map.fetch(events.first)
  events.drop(1).each do |event|
    target = event_map.fetch(event)
    return ["ILLEGAL_STATUS_TRANSITION", nil] unless transitions.fetch(status, []).include?(target)

    status = target
  end
  [nil, status]
end

# 回傳 nil 或精確 machine failure code。純函式。
def skill_transform_failure(input, output, card_record_spec, boundary_forbidden_fields)
  return "MISSING_INPUT_FIELD" if EXPECTED_INPUT_REQUIRED_FIELDS.any? { |field| !input.key?(field) }

  seed = input["seed_fields"]
  return "MISSING_INPUT_FIELD" unless seed.is_a?(Hash)
  return "MISSING_INPUT_FIELD" if EXPECTED_SEED_FIELD_KEYS.any? { |key| blank_string?(seed[key]) }

  events = input["lifecycle_events"]
  return "MISSING_INPUT_FIELD" unless events.is_a?(Array) && !events.empty?

  event_map = card_record_spec.fetch("lifecycle_event_to_status", {})
  return "UNKNOWN_LIFECYCLE_EVENT" if events.any? { |event| !event_map.key?(event) }
  return "SKILL_LIFECYCLE_MUST_START" if events.first != "start"

  replay_code, final_status = replay_lifecycle(events, card_record_spec)
  return replay_code if replay_code

  return "MISSING_INPUT_FIELD" if EXPECTED_OUTPUT_REQUIRED_FIELDS.any? { |field| !output.key?(field) }

  return "SKILL_EXCEEDS_AUTHORITY" if output["writes_company_knowledge"] == true
  return "SKILL_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_OUTPUT_FIELDS.any? { |field| output.key?(field) }
  return "SKILL_EXCEEDS_AUTHORITY" if output.fetch("draft_card", {}).is_a?(Hash) &&
                                      EXPECTED_FORBIDDEN_OUTPUT_FIELDS.any? { |field| output["draft_card"].key?(field) }

  return "DRAFT_CARD_INVALID" unless draft_card_contract_valid?(output["draft_card"], card_record_spec, boundary_forbidden_fields)

  evidence = output["evidence_refs"]
  return "EVIDENCE_INLINE_CONTENT" unless evidence.is_a?(Array) && evidence.all? { |ref| urn?(ref, OMOS_URN) }

  return "DRY_RUN_NOT_BOOLEAN" unless [true, false].include?(output["dry_run"])

  return "REPLAYED_STATUS_MISMATCH" if output["replayed_status"] != final_status
  return "DRAFT_CARD_STATUS_MISMATCH" if output.fetch("draft_card", {})["status"] != output["replayed_status"]

  return "FAIL_SILENT" if present?(output["error"]) && output["ok"] != false

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)
card_record_spec = read_yaml(CARD_RECORD_SPEC_PATH)
boundary_forbidden_fields = boundary.dig("authority_boundary", "task_card", "forbidden_fields").to_a

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-skill:0.1.0", "schema_id 必須是 ai-work-record-skill:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-03"), "schema.traces_to 必須包含 AIWR-03", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)

input_contract = spec.fetch("input_contract", {})
assert(sorted_set(input_contract.fetch("required_fields", [])) == sorted_set(EXPECTED_INPUT_REQUIRED_FIELDS), "input_contract.required_fields 與鎖定清單不符", failures)
assert(input_contract.fetch("seed_field_keys", []) == EXPECTED_SEED_FIELD_KEYS, "input_contract.seed_field_keys 與鎖定清單不符", failures)

output_contract = spec.fetch("output_contract", {})
assert(output_contract.fetch("required_fields", []) == EXPECTED_OUTPUT_REQUIRED_FIELDS, "output_contract.required_fields 與鎖定清單不符", failures)

authority = spec.fetch("authority", {})
assert(authority["accepts_memory"] == false, "authority.accepts_memory 必須是 false", failures)
assert(authority["writes_company_knowledge"] == false, "authority.writes_company_knowledge 必須是 false", failures)
assert(authority["error_behavior"] == "FAIL_LOUD", "authority.error_behavior 必須是 FAIL_LOUD", failures)
assert(
  sorted_set(authority.fetch("forbidden_output_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_OUTPUT_FIELDS),
  "authority.forbidden_output_fields 與鎖定清單不符",
  failures
)
boundary_gate_positions = boundary.dig("automated_step_contract", "allowed_gate_positions").to_a
assert(
  present?(authority["human_acceptance_gate_position"]) && boundary_gate_positions.include?(authority["human_acceptance_gate_position"]),
  "authority.human_acceptance_gate_position 必須存在且 ∈ boundary automated_step_contract.allowed_gate_positions",
  failures
)

# cross-reference pointer binding
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "lifecycle_events_from" => "ai-task-card-record.lifecycle_event_to_status",
  "gate_positions_from" => "ai-work-record-boundary.automated_step_contract.allowed_gate_positions",
  "non_acceptance_authority_from" => "ai-work-record-boundary.non_acceptance_authority.signals"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
# 被引用的目標必須存在且非空
assert(present?(card_record_spec.fetch("lifecycle_event_to_status", {})), "card-record spec lifecycle_event_to_status 必須存在且非空", failures)
assert(present?(boundary.dig("automated_step_contract", "allowed_gate_positions")), "boundary allowed_gate_positions 必須存在且非空", failures)
assert(present?(boundary.dig("non_acceptance_authority", "signals")), "boundary non_acceptance_authority.signals 必須存在且非空", failures)
assert(present?(boundary_forbidden_fields), "boundary task_card.forbidden_fields 必須存在且非空", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_SKILL_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("skill_transform_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} skill positive 必須預期 allow", failures)
  actual = skill_transform_failure(test_case.fetch("input"), test_case.fetch("output"), card_record_spec, boundary_forbidden_fields)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative.fetch("skill_transform_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} skill negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = skill_transform_failure(test_case.fetch("input"), test_case.fetch("output"), card_record_spec, boundary_forbidden_fields)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative.fetch("skill_transform_negative_cases").map { |test_case| test_case.fetch("covers_skill_negative_fixture") })
missing_labels = sorted_set(EXPECTED_SKILL_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "skill negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai work record skill contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
