#!/usr/bin/env ruby

# SSP-299 / AIWR-02：AI 任務卡自動紀錄格式 validator。
# 薄判斷：結構斷言 + record shape / lifecycle replay 評估。不建立狀態機引擎。
# allowed_status_transitions 與 lifecycle_event_to_status 是資料表。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-task-card-record-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-task-card-record-negative-fixtures.json")

EXPECTED_FIELDS = %w[card_id objective scope constraints acceptance status evidence_refs].freeze
EXPECTED_NON_EMPTY_STRING_FIELDS = %w[objective scope constraints acceptance].freeze
EXPECTED_STATUS_ENUM = %w[OPEN BLOCKED IN_REVIEW DONE CANCELLED].freeze
EXPECTED_STATUS_TRANSITIONS = {
  "OPEN" => %w[BLOCKED IN_REVIEW CANCELLED],
  "BLOCKED" => %w[OPEN CANCELLED],
  "IN_REVIEW" => %w[OPEN DONE CANCELLED],
  "DONE" => [],
  "CANCELLED" => []
}.freeze
EXPECTED_LIFECYCLE_EVENT_MAP = {
  "start" => "OPEN",
  "block" => "BLOCKED",
  "unblock" => "OPEN",
  "submit_review" => "IN_REVIEW",
  "complete" => "DONE",
  "cancel" => "CANCELLED"
}.freeze

EXPECTED_RECORD_NEGATIVE_LABELS = [
  "task card missing a required field",
  "status DONE with empty evidence_refs",
  "status DONE with empty acceptance",
  "illegal status transition",
  "unknown lifecycle event",
  "sensitive content copied into the card",
  "boundary forbidden field present on the card"
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

CARD_ID_URN = /\Aurn:omos:task-card:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze
OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

def urn?(value, pattern)
  value.is_a?(String) && pattern.match?(value)
end

# 回傳 nil 或精確 machine failure code。
def task_card_record_failure(card, boundary_forbidden_fields)
  return "CARD_MISSING_REQUIRED_FIELD" if EXPECTED_FIELDS.any? { |field| !card.key?(field) }
  return "CARD_MISSING_REQUIRED_FIELD" if EXPECTED_NON_EMPTY_STRING_FIELDS.any? { |field| blank_string?(card[field]) }
  return "CARD_MISSING_REQUIRED_FIELD" unless card["evidence_refs"].is_a?(Array)
  return "CARD_MISSING_REQUIRED_FIELD" unless present?(card["card_id"])

  return "CARD_INVALID_FIELD_TYPE" unless urn?(card["card_id"], CARD_ID_URN)
  return "CARD_INVALID_FIELD_TYPE" unless card["evidence_refs"].all? { |ref| urn?(ref, OMOS_URN) }

  return "CARD_INVALID_STATUS" unless EXPECTED_STATUS_ENUM.include?(card["status"])
  return "CARD_CARRIES_FORBIDDEN_FIELD" if boundary_forbidden_fields.any? { |field| card.key?(field) }
  return "CARD_SENSITIVE_CONTENT_COPIED" if card["sensitive_content_copied"] == true

  # `acceptance` 一律必須非空（已在上方 EXPECTED_NON_EMPTY_STRING_FIELDS 擋下，
  # 包含「DONE 但 acceptance 空」的假完成情境）。`evidence_refs` 只有 DONE 時
  # 必須非空 —— OPEN / BLOCKED 的卡片可以尚無 evidence。
  return "CARD_DONE_WITHOUT_EVIDENCE" if card["status"] == "DONE" && card["evidence_refs"].to_a.empty?

  nil
end

# 回傳 nil 或精確 machine failure code。純函式：同輸入必回同結果。
def lifecycle_replay_failure(events, final_status)
  events = events.to_a
  return "CARD_UNKNOWN_LIFECYCLE_EVENT" if events.any? { |event| !EXPECTED_LIFECYCLE_EVENT_MAP.key?(event) }
  return "CARD_EMPTY_LIFECYCLE" if events.empty?
  return "CARD_LIFECYCLE_MUST_START" if events.first != "start"

  status = EXPECTED_LIFECYCLE_EVENT_MAP.fetch("start")
  events.drop(1).each do |event|
    target = EXPECTED_LIFECYCLE_EVENT_MAP.fetch(event)
    return "CARD_ILLEGAL_STATUS_TRANSITION" unless EXPECTED_STATUS_TRANSITIONS.fetch(status).include?(target)

    status = target
  end

  return "CARD_RECONSTRUCTION_MISMATCH" if present?(final_status) && final_status != status

  nil
end

# Integrated check: the card and its lifecycle events must be mutually
# consistent — the card is contract-valid, the events replay cleanly, and the
# replayed final status equals card["status"]. Returns nil or the exact code.
def reconstruction_failure(card, events, boundary_forbidden_fields)
  card_fail = task_card_record_failure(card, boundary_forbidden_fields)
  return card_fail if card_fail

  lifecycle_fail = lifecycle_replay_failure(events, nil)
  return lifecycle_fail if lifecycle_fail

  events = events.to_a
  status = EXPECTED_LIFECYCLE_EVENT_MAP.fetch(events.first)
  events.drop(1).each { |event| status = EXPECTED_LIFECYCLE_EVENT_MAP.fetch(event) }
  return "CARD_STATUS_LIFECYCLE_MISMATCH" if card["status"] != status

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)
boundary_task_card = boundary.dig("authority_boundary", "task_card") || {}
boundary_forbidden_fields = boundary_task_card.fetch("forbidden_fields", [])

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-task-card-record:0.1.0", "schema_id 必須是 ai-task-card-record:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-02"), "schema.traces_to 必須包含 AIWR-02", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)

fields = spec.fetch("fields", {})
assert(sorted_set(fields.keys) == sorted_set(EXPECTED_FIELDS), "fields 必須剛好是 7 個控制欄位", failures)
EXPECTED_FIELDS.each do |field|
  assert(fields.dig(field, "required") == true, "fields.#{field}.required 必須為 true", failures)
end
EXPECTED_NON_EMPTY_STRING_FIELDS.each do |field|
  assert(fields.dig(field, "non_empty") == true, "fields.#{field}.non_empty 必須為 true", failures)
end
assert(fields.dig("card_id", "type") == "urn", "fields.card_id.type 必須是 urn", failures)
assert(fields.dig("evidence_refs", "type") == "urn_array", "fields.evidence_refs.type 必須是 urn_array", failures)

assert(spec.fetch("status_enum", []) == EXPECTED_STATUS_ENUM, "status_enum 與鎖定清單不符", failures)
assert(
  boundary_task_card.fetch("status_enum", []).sort == EXPECTED_STATUS_ENUM.sort,
  "status_enum 必須與 boundary contract 的 task_card.status_enum 一致",
  failures
)

transitions = spec.fetch("allowed_status_transitions", {})
EXPECTED_STATUS_TRANSITIONS.each do |from, tos|
  assert(transitions.fetch(from, nil).to_a.sort == tos.sort, "allowed_status_transitions.#{from} 與鎖定表不符", failures)
end
assert(sorted_set(transitions.keys) == sorted_set(EXPECTED_STATUS_ENUM), "allowed_status_transitions 必須涵蓋所有 status", failures)

event_map = spec.fetch("lifecycle_event_to_status", {})
assert(event_map == EXPECTED_LIFECYCLE_EVENT_MAP, "lifecycle_event_to_status 與鎖定表不符", failures)

assert(spec.dig("reconstruction", "deterministic") == true, "reconstruction.deterministic 必須為 true", failures)
assert(
  spec.dig("cross_reference", "must_match", "is_personal_memory") == false,
  "cross_reference.must_match.is_personal_memory 必須是 false",
  failures
)
assert(boundary_task_card["is_personal_memory"] == false, "boundary task_card.is_personal_memory 必須是 false", failures)
assert(
  boundary_task_card.fetch("required_fields", []).sort == EXPECTED_FIELDS.sort,
  "boundary task_card.required_fields 必須與本卡 fields 一致",
  failures
)
assert(present?(boundary_forbidden_fields), "boundary task_card.forbidden_fields 必須存在且非空", failures)

# Acceptance #7 is satisfied here as *pointer binding*: this slice does not copy
# the boundary values, it locks the must_match pointers to the exact boundary
# paths and requires the referenced boundary fields to be present.
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "status_enum_from" => "authority_boundary.task_card.status_enum",
  "required_fields_from" => "authority_boundary.task_card.required_fields",
  "forbidden_fields_from" => "authority_boundary.task_card.forbidden_fields",
  "forbidden_authority_from" => "authority_boundary.task_card.forbidden_authority"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(boundary_task_card["forbidden_authority"]), "boundary task_card.forbidden_authority 必須存在且非空", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_RECORD_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("task_card_record_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} record positive 必須預期 allow", failures)
  actual = task_card_record_failure(test_case.fetch("card"), boundary_forbidden_fields)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

positive.fetch("lifecycle_replay_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} lifecycle positive 必須預期 allow", failures)
  actual = lifecycle_replay_failure(test_case.fetch("events"), test_case["final_status"])
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
  # deterministic: same input, same result
  again = lifecycle_replay_failure(test_case.fetch("events"), test_case["final_status"])
  assert(actual == again, "#{test_case.fetch("case_id")} lifecycle replay 非 deterministic", failures)
end

positive.fetch("integrated_reconstruction_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} integrated positive 必須預期 allow", failures)
  actual = reconstruction_failure(test_case.fetch("card"), test_case.fetch("lifecycle_events"), boundary_forbidden_fields)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

def check_negative(cases, kind, failures, &evaluator)
  cases.each do |test_case|
    case_id = test_case.fetch("case_id")
    assert(test_case.fetch("expected") == "deny", "#{case_id} #{kind} negative 必須預期 deny", failures)
    expected_code = test_case.fetch("expected_failure_code")
    actual = evaluator.call(test_case)
    assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
    assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
  end
end

check_negative(negative.fetch("task_card_record_negative_cases"), "record", failures) do |test_case|
  task_card_record_failure(test_case.fetch("card"), boundary_forbidden_fields)
end
check_negative(negative.fetch("lifecycle_replay_negative_cases"), "lifecycle", failures) do |test_case|
  lifecycle_replay_failure(test_case.fetch("events"), test_case["final_status"])
end
check_negative(negative.fetch("integrated_reconstruction_negative_cases"), "integrated", failures) do |test_case|
  reconstruction_failure(test_case.fetch("card"), test_case.fetch("lifecycle_events"), boundary_forbidden_fields)
end

covered_labels = sorted_set(
  (negative.fetch("task_card_record_negative_cases") +
   negative.fetch("lifecycle_replay_negative_cases") +
   negative.fetch("integrated_reconstruction_negative_cases"))
    .map { |test_case| test_case.fetch("covers_record_negative_fixture") }
)
missing_labels = sorted_set(EXPECTED_RECORD_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "record negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai task card record contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
