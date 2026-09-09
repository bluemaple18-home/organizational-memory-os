#!/usr/bin/env ruby

# SSP-305 / AIWR-08：端到端驗收 + 主管進度視圖契約 validator。
# 薄判斷：結構斷言 + 純函式 `e2e_acceptance_failure(run, ...)` evaluator——
#   端到端 lifecycle trace 完整（start 起、終止 event 收、每步帶 evidence receipt URN）、
#   manager_view 只投影非敏感摘要、終止狀態有明確 manager 狀態、WorkRecord 不經 acceptance
#   不得成 Personal Memory、可只靠 Jira 重現、projection-only 不越權、fail-loud。
# 交叉讀 ai-task-card-record.yaml、ai-work-record-boundary.yaml、ai-work-record-harness.yaml
# （pointer binding）。沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-e2e-acceptance.yaml")
CARD_RECORD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
HARNESS_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-harness.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-e2e-acceptance-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-e2e-acceptance-negative-fixtures.json")

EXPECTED_FIRST_EVENT = "start"
EXPECTED_TERMINAL_EVENTS = %w[complete cancel block].freeze
EXPECTED_MANAGER_VIEW_FIELDS = %w[objective status blockers acceptance_summary evidence_links].freeze
EXPECTED_MANAGER_STATUSES = %w[DONE FAILED CANCELLED BLOCKED HUMAN_INTERVENTION].freeze
EXPECTED_TERMINAL_EVENT_TO_STATUS = { "complete" => "DONE", "cancel" => "CANCELLED", "block" => "BLOCKED" }.freeze
EXPECTED_UNSUBSTANTIATED_STATUSES = %w[FAILED HUMAN_INTERVENTION].freeze
# 升格 durable memory 時 work_record 必須帶的完整 promotion-chain refs,對齊
# SSP-298 ai-work-record-boundary promotion_path.ordered_steps(skip_any_step forbidden)。
EXPECTED_PROMOTION_REF_FIELDS = %w[
  raw_evidence_ref
  candidate_ref
  verification_receipt_ref
  personal_acceptance_ref
  record_ref
].freeze
EXPECTED_FORBIDDEN_RUN_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  canonical_write_receipt_ref
].freeze
OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

EXPECTED_E2E_NEGATIVE_LABELS = [
  "the trace does not start with start",
  "the trace does not end on a terminal event",
  "the trace contains an illegal status transition",
  "an evidence receipt is not a reference",
  "the manager view carries an extra field",
  "the manager view copies sensitive content",
  "an evidence link is not a reference",
  "the manager view status disagrees with the final status",
  "the final status does not match the terminal event",
  "the final status is not a manager-visible status",
  "a failed or human-intervention outcome is unsubstantiated",
  "a promoted work record is missing a promotion-chain receipt",
  "the run is not reconstructable from jira",
  "the run declares it is not a projection",
  "the run carries a canonical write field",
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

# 純函式端到端驗收 evaluator。回傳 nil 或精確 machine failure code。
# run 是自足 fixture 物件:
#   lifecycle_trace[{event, evidence_receipt_ref}], manager_view{...},
#   final_status, reconstructable_from_jira, work_records[{personal_memory,
#   candidate_ref, acceptance_ref}], is_projection/performs_acceptance/is_canonical,
#   error, ok。
def e2e_acceptance_failure(run, event_map, transitions)
  lifecycle_events = event_map.keys

  # 1. authority(projection-only:必須明確宣稱 is_projection,且不做 acceptance / canonical write)
  return "E2E_EXCEEDS_AUTHORITY" unless run["is_projection"] == true
  return "E2E_EXCEEDS_AUTHORITY" if run["performs_acceptance"] == true
  return "E2E_EXCEEDS_AUTHORITY" if run["is_canonical"] == true
  return "E2E_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_RUN_FIELDS.any? { |field| run.key?(field) }

  # 2. fail-loud
  return "FAIL_SILENT" if present?(run["error"]) && run["ok"] != false

  # 3. 端到端 lifecycle trace 完整性
  trace = run["lifecycle_trace"]
  return "E2E_TRACE_INCOMPLETE" unless trace.is_a?(Array) && !trace.empty?
  return "E2E_TRACE_INCOMPLETE" unless trace.all? { |step| step.is_a?(Hash) && step.key?("event") && step.key?("evidence_receipt_ref") }

  events = trace.map { |step| step["event"] }
  return "E2E_TRACE_INCOMPLETE" if events.first != EXPECTED_FIRST_EVENT
  return "E2E_TRACE_INCOMPLETE" unless EXPECTED_TERMINAL_EVENTS.include?(events.last)
  return "E2E_TRACE_INCOMPLETE" if events.any? { |event| !lifecycle_events.include?(event) }
  return "E2E_RECEIPT_NOT_REF" if trace.any? { |step| !urn?(step["evidence_receipt_ref"]) }

  # trace 綁定上游 SSP-299 lifecycle:replay allowed_status_transitions
  status = event_map.fetch(events.first)
  events.drop(1).each do |event|
    target = event_map.fetch(event)
    return "E2E_TRACE_ILLEGAL_TRANSITION" unless transitions.fetch(status, []).include?(target)

    status = target
  end

  # 4. manager_view 投影邊界
  view = run["manager_view"]
  return "MANAGER_VIEW_LEAKS_FIELD" unless view.is_a?(Hash)
  return "MANAGER_VIEW_LEAKS_FIELD" unless sorted_set(view.keys) == sorted_set(EXPECTED_MANAGER_VIEW_FIELDS)
  return "MANAGER_VIEW_LEAKS_CONTENT" if run["sensitive_content_copied"] == true || present?(view["raw_work_body"])
  evidence_links = view["evidence_links"]
  return "MANAGER_VIEW_INLINE_CONTENT" unless evidence_links.is_a?(Array) && evidence_links.all? { |link| urn?(link) }

  # 5. 狀態完整性 —— 五個 manager status 都有可驗終止路徑
  final_status = run["final_status"]
  return "E2E_INVALID_STATUS" unless EXPECTED_MANAGER_STATUSES.include?(final_status)
  if EXPECTED_UNSUBSTANTIATED_STATUSES.include?(final_status)
    return "E2E_UNSUBSTANTIATED_OUTCOME" if events.last == "complete"
    return "E2E_UNSUBSTANTIATED_OUTCOME" unless urn?(run["outcome_evidence_ref"])
  else
    return "E2E_STATUS_UNMAPPED" if final_status != EXPECTED_TERMINAL_EVENT_TO_STATUS.fetch(events.last)
  end

  # 6. 主管視圖狀態必須等於 e2e 判定
  return "E2E_MANAGER_STATUS_MISMATCH" if view["status"] != final_status

  # 7. 記憶升格閘門 —— 對齊 SSP-298 promotion_path(完整 chain,skip 任一步即拒)
  run["work_records"].to_a.each do |record|
    next unless record["personal_memory"] == true

    unless EXPECTED_PROMOTION_REF_FIELDS.all? { |ref_field| urn?(record[ref_field]) }
      return "E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE"
    end
  end

  # 8. 可只靠 Jira 視圖重現
  unless run["reconstructable_from_jira"] == true && present?(view["status"]) && !evidence_links.empty?
    return "MANAGER_VIEW_NOT_RECONSTRUCTABLE"
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
card_record_spec = read_yaml(CARD_RECORD_SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)
harness_spec = read_yaml(HARNESS_SPEC_PATH)

event_map = card_record_spec.fetch("lifecycle_event_to_status", {})
transitions = card_record_spec.fetch("allowed_status_transitions", {})
lifecycle_events = event_map.keys

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-e2e-acceptance:0.1.0", "schema_id 必須是 ai-work-record-e2e-acceptance:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-08"), "schema.traces_to 必須包含 AIWR-08", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)

e2e_trace = spec.fetch("e2e_trace", {})
assert(e2e_trace["first_event"] == EXPECTED_FIRST_EVENT, "e2e_trace.first_event 必須是 start", failures)
assert(sorted_set(e2e_trace.fetch("terminal_events", [])) == sorted_set(EXPECTED_TERMINAL_EVENTS), "e2e_trace.terminal_events 必須是 [complete, cancel, block]", failures)
assert((EXPECTED_TERMINAL_EVENTS - lifecycle_events).empty?, "terminal_events 必須是 ai-task-card-record lifecycle_event_to_status 的子集", failures)
assert(present?(transitions), "card-record allowed_status_transitions 必須存在且非空", failures)

manager_view = spec.fetch("manager_view", {})
assert(manager_view.fetch("allowed_fields", []) == EXPECTED_MANAGER_VIEW_FIELDS, "manager_view.allowed_fields 與鎖定清單不符", failures)
assert(manager_view.fetch("reference_only_fields", []) == %w[evidence_links], "manager_view.reference_only_fields 必須是 [evidence_links]", failures)

status_completeness = spec.fetch("status_completeness", {})
assert(sorted_set(status_completeness.fetch("manager_statuses", [])) == sorted_set(EXPECTED_MANAGER_STATUSES), "status_completeness.manager_statuses 與鎖定清單不符", failures)
assert(status_completeness.fetch("terminal_event_to_status", {}) == EXPECTED_TERMINAL_EVENT_TO_STATUS, "status_completeness.terminal_event_to_status 與鎖定對映不符", failures)
assert(sorted_set(status_completeness.fetch("unsubstantiated_outcome_statuses", [])) == sorted_set(EXPECTED_UNSUBSTANTIATED_STATUSES), "status_completeness.unsubstantiated_outcome_statuses 必須是 [FAILED, HUMAN_INTERVENTION]", failures)
# 五個 manager status 都必須有可驗終止路徑(mapped 三個 + unsubstantiated 兩個)
covered_statuses = EXPECTED_TERMINAL_EVENT_TO_STATUS.values + EXPECTED_UNSUBSTANTIATED_STATUSES
assert(sorted_set(covered_statuses) == sorted_set(EXPECTED_MANAGER_STATUSES), "每個 manager_status 都必須有終止路徑(mapped 或 unsubstantiated)", failures)

# memory_promotion_gate 對齊 SSP-298 boundary promotion_path
promotion_gate = spec.fetch("memory_promotion_gate", {})
boundary_promotion_steps = boundary.dig("promotion_path", "ordered_steps").to_a
boundary_promotion_receipts = boundary.dig("promotion_path", "receipts_required") || {}
assert(promotion_gate["promotion_path_ref"] == "ai-work-record-boundary.promotion_path.ordered_steps", "memory_promotion_gate.promotion_path_ref 必須指向 boundary promotion_path.ordered_steps", failures)
promotion_refs = promotion_gate.fetch("promotion_refs", {})
assert(sorted_set(promotion_refs.values) == sorted_set(EXPECTED_PROMOTION_REF_FIELDS), "memory_promotion_gate.promotion_refs 值必須是完整 promotion-chain ref 欄位", failures)
# promotion_refs 的步驟 key 必須都是 boundary ordered_steps 的成員,且涵蓋 boundary receipts_required
assert((promotion_refs.keys - boundary_promotion_steps).empty?, "memory_promotion_gate.promotion_refs 的步驟必須都在 boundary promotion_path.ordered_steps", failures)
boundary_promotion_receipts.each do |step, ref_field|
  assert(promotion_refs[step] == ref_field, "memory_promotion_gate.promotion_refs.#{step} 必須與 boundary receipts_required 一致(#{ref_field})", failures)
end

reconstruction = spec.fetch("reconstruction", {})
assert(reconstruction["reconstructable_from_jira"] == true, "reconstruction.reconstructable_from_jira 必須是 true", failures)

authority = spec.fetch("authority", {})
assert(authority["is_projection"] == true, "authority.is_projection 必須是 true", failures)
assert(authority["performs_acceptance"] == false, "authority.performs_acceptance 必須是 false", failures)
assert(authority["is_canonical"] == false, "authority.is_canonical 必須是 false", failures)
assert(authority["error_behavior"] == "FAIL_LOUD", "authority.error_behavior 必須是 FAIL_LOUD", failures)
assert(
  sorted_set(authority.fetch("forbidden_run_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_RUN_FIELDS),
  "authority.forbidden_run_fields 與鎖定清單不符",
  failures
)
boundary_error_enum = boundary.dig("automated_step_contract", "error_behavior_enum").to_a
assert(boundary_error_enum == %w[FAIL_LOUD], "boundary automated_step_contract.error_behavior_enum 必須是 [FAIL_LOUD]", failures)
assert(authority["error_behavior"] == boundary_error_enum.first, "authority.error_behavior 必須與 boundary error_behavior_enum 一致", failures)

# cross-reference pointer binding
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "lifecycle_events_from" => "ai-task-card-record.lifecycle_event_to_status",
  "allowed_transitions_from" => "ai-task-card-record.allowed_status_transitions",
  "non_acceptance_authority_from" => "ai-work-record-boundary.non_acceptance_authority.signals",
  "promotion_path_from" => "ai-work-record-boundary.promotion_path.ordered_steps",
  "promotion_receipts_from" => "ai-work-record-boundary.promotion_path.receipts_required",
  "harness_schema_id_from" => "ai-work-record-harness.schema.schema_id",
  "error_behavior_from" => "ai-work-record-boundary.automated_step_contract.error_behavior_enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(lifecycle_events), "card-record lifecycle_event_to_status 必須存在且非空", failures)
assert(present?(boundary.dig("non_acceptance_authority", "signals")), "boundary non_acceptance_authority.signals 必須存在且非空", failures)
assert(present?(boundary_promotion_steps) && boundary_promotion_steps.include?("PERSONAL_MEMORY_RECORD"), "boundary promotion_path.ordered_steps 必須存在且含 PERSONAL_MEMORY_RECORD", failures)
assert(harness_spec.dig("schema", "schema_id") == "urn:omos:schema:ai-work-record-harness:0.1.0", "harness schema_id 必須存在且相符", failures)
assert(present?(boundary.dig("automated_step_contract", "error_behavior_enum")), "boundary error_behavior_enum 必須存在且非空", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_E2E_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("e2e_acceptance_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} e2e positive 必須預期 allow", failures)
  actual = e2e_acceptance_failure(test_case.fetch("run"), event_map, transitions)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative.fetch("e2e_acceptance_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} e2e negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = e2e_acceptance_failure(test_case.fetch("run"), event_map, transitions)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative.fetch("e2e_acceptance_negative_cases").map { |test_case| test_case.fetch("covers_e2e_negative_fixture") })
missing_labels = sorted_set(EXPECTED_E2E_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "e2e negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai work record e2e acceptance contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
