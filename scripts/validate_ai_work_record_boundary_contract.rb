#!/usr/bin/env ruby

# SSP-298 / AIWR-01：AI 工作紀錄與 Personal Memory 邊界契約 validator。
# 只做薄判斷：結構斷言 + fixture 評估，不建立第二套 workflow engine / registry / FSM。

require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
PERSONAL_SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-boundary-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-boundary-negative-fixtures.json")

EXPECTED_TASK_CARD_REQUIRED_FIELDS = %w[
  card_id
  objective
  scope
  constraints
  acceptance
  status
  evidence_refs
].freeze

EXPECTED_TASK_CARD_STATUS = %w[OPEN BLOCKED IN_REVIEW DONE CANCELLED].freeze

EXPECTED_TASK_CARD_FORBIDDEN_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  memory_kind
  record_id
  candidate_status
].freeze

EXPECTED_PROMOTION_STEPS = %w[
  TASK_CARD_OR_WORK_RECORD
  RAW_EVIDENCE_ENVELOPE
  PERSONAL_MEMORY_CANDIDATE
  VERIFICATION
  PERSONAL_ACCEPTANCE
  PERSONAL_MEMORY_RECORD
].freeze

# 升格路徑中「PERSONAL_MEMORY_RECORD 之前必須依序出現」的步驟。
PROMOTION_PREREQ_ORDER = %w[
  RAW_EVIDENCE_ENVELOPE
  PERSONAL_MEMORY_CANDIDATE
  VERIFICATION
  PERSONAL_ACCEPTANCE
].freeze

EXPECTED_NON_ACCEPTANCE_SIGNALS = %w[branch worktree runtime_completion model_confidence].freeze

EXPECTED_AUTOMATED_STEP_FIELDS = %w[
  input_schema_ref
  output_schema_ref
  error_behavior
  human_acceptance_gate
  dry_run_supported
].freeze

EXPECTED_REUSED_CORE_INVARIANTS = %w[
  WORK_RECORD_NE_PERSONAL_MEMORY
  CANDIDATE_NE_ACCEPTED_PERSONAL_MEMORY
  CAPTURED_NE_REMEMBERED
  MODEL_CONFIDENCE_NE_VERIFICATION
].freeze

EXPECTED_BOUNDARY_NEGATIVE_LABELS = [
  "current task status promoted as long-lived memory",
  "temporary branch or worktree state promoted as memory",
  "runtime completion message treated as accepted",
  "model confidence auto-accepts candidate",
  "task card creates record skipping evidence",
  "automated step bypasses human acceptance gate",
  "task card carries a memory acceptance field"
].freeze

class DuplicateKeyError < StandardError; end

class StrictJsonObject < Hash
  def []=(key, value)
    raise DuplicateKeyError, "duplicate JSON object key #{key.inspect}" if key?(key)

    super
  end
end

def assert_unique_yaml_mapping_keys(node, path = "$")
  case node
  when Psych::Nodes::Stream, Psych::Nodes::Document
    node.children.each { |child| assert_unique_yaml_mapping_keys(child, path) }
  when Psych::Nodes::Sequence
    node.children.each_with_index { |child, index| assert_unique_yaml_mapping_keys(child, "#{path}[#{index}]") }
  when Psych::Nodes::Mapping
    seen = {}
    node.children.each_slice(2) do |key_node, value_node|
      key = key_node.respond_to?(:value) ? key_node.value : key_node.to_s
      child_path = "#{path}.#{key}"
      raise DuplicateKeyError, "duplicate YAML mapping key #{child_path}" if seen.key?(key)

      seen[key] = true
      assert_unique_yaml_mapping_keys(value_node, child_path)
    end
  end
end

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

def present?(value)
  !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
end

# 回傳 nil（契約有效）或精確 machine failure code。
def task_card_failure(card)
  return "TASK_CARD_CLAIMS_PERSONAL_MEMORY" if card["is_personal_memory"] != false

  missing = EXPECTED_TASK_CARD_REQUIRED_FIELDS.find { |field| !present?(card[field]) }
  return "TASK_CARD_MISSING_CONTROL_FIELD" if missing

  forbidden = EXPECTED_TASK_CARD_FORBIDDEN_FIELDS.find { |field| card.key?(field) }
  return "TASK_CARD_CARRIES_MEMORY_ACCEPTANCE_FIELD" if forbidden

  return "TASK_CARD_INVALID_STATUS" unless EXPECTED_TASK_CARD_STATUS.include?(card["status"])
  return "TASK_CARD_SENSITIVE_CONTENT_COPIED" if card["sensitive_content_copied"] == true

  nil
end

# 回傳 nil 或精確 machine failure code。
def promotion_path_failure(promotion, transient_kinds)
  signal = promotion["acceptance_authority_signal"]
  return "NON_ACCEPTANCE_SIGNAL_USED_AS_AUTHORITY" if EXPECTED_NON_ACCEPTANCE_SIGNALS.include?(signal)

  candidate_kind = promotion["candidate_memory_kind"]
  return "TRANSIENT_KIND_PROMOTED" if present?(candidate_kind) && transient_kinds.include?(candidate_kind)

  steps = promotion["steps"].to_a
  unknown = steps.find { |step| !EXPECTED_PROMOTION_STEPS.include?(step) }
  return "PROMOTION_UNKNOWN_STEP" if unknown

  if steps.include?("PERSONAL_MEMORY_RECORD")
    before_record = steps[0...steps.index("PERSONAL_MEMORY_RECORD")]

    unless before_record.include?("RAW_EVIDENCE_ENVELOPE")
      return "TASK_CARD_DIRECT_TO_RECORD" if before_record.empty?

      return "PROMOTION_SKIPS_EVIDENCE"
    end

    PROMOTION_PREREQ_ORDER.each do |prereq|
      return "PROMOTION_SKIPS_VERIFICATION_OR_ACCEPTANCE" unless before_record.include?(prereq)
    end

    present_prereq_indexes = PROMOTION_PREREQ_ORDER.map { |prereq| before_record.index(prereq) }
    return "PROMOTION_STEPS_OUT_OF_ORDER" if present_prereq_indexes != present_prereq_indexes.sort
  end

  return "PROMOTION_MISSING_RECEIPT" if steps.include?("VERIFICATION") && !present?(promotion["verification_receipt_ref"])
  return "PROMOTION_MISSING_RECEIPT" if steps.include?("PERSONAL_ACCEPTANCE") && !present?(promotion["personal_acceptance_ref"])

  nil
end

# 回傳 nil 或精確 machine failure code。
def automated_step_failure(step)
  missing = EXPECTED_AUTOMATED_STEP_FIELDS.find { |field| !step.key?(field) }
  return "AUTOMATED_STEP_MISSING_CONTRACT_FIELD" if missing

  return "AUTOMATED_STEP_FAIL_SILENT" if step["error_behavior"] != "FAIL_LOUD"
  return "AUTOMATED_STEP_BYPASSES_HUMAN_GATE" if step["human_acceptance_gate"] != true
  return "AUTOMATED_STEP_NO_DRY_RUN" if step["dry_run_supported"] != true

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
personal_spec = read_yaml(PERSONAL_SPEC_PATH)

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-boundary:0.1.0", "schema_id 必須是 ai-work-record-boundary:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-01"), "schema.traces_to 必須包含 AIWR-01", failures)

purpose = spec.fetch("purpose", {})
assert(purpose["no_second_workflow_authority"] == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(
  sorted_set(purpose.fetch("does_not_define", [])).include?("registry, finite state machine, database, canonical writer"),
  "purpose.does_not_define 必須排除 registry/FSM/DB/canonical writer",
  failures
)

task_card = spec.dig("authority_boundary", "task_card") || {}
assert(task_card["role"] == "WORK_CONTROL_AND_REPORT_ARTIFACT", "task_card.role 必須是 WORK_CONTROL_AND_REPORT_ARTIFACT", failures)
assert(task_card["is_personal_memory"] == false, "task_card.is_personal_memory 必須是 false", failures)
assert(
  task_card.fetch("required_fields", []) == EXPECTED_TASK_CARD_REQUIRED_FIELDS,
  "task_card.required_fields 與鎖定清單不符",
  failures
)
assert(
  sorted_set(task_card.fetch("status_enum", [])) == sorted_set(EXPECTED_TASK_CARD_STATUS),
  "task_card.status_enum 與鎖定清單不符",
  failures
)
assert(
  sorted_set(task_card.fetch("forbidden_fields", [])) == sorted_set(EXPECTED_TASK_CARD_FORBIDDEN_FIELDS),
  "task_card.forbidden_fields 與鎖定清單不符",
  failures
)
assert(task_card.fetch("forbidden_authority", []).include?("memory_acceptance"), "task_card 不得取得 memory_acceptance authority", failures)
assert(task_card["sensitive_content_rule"] == "reference_only_never_copied", "task_card 敏感內容必須只存 reference", failures)

work_record = spec.dig("authority_boundary", "work_record") || {}
assert(work_record["role"] == "REBUILDABLE_PROJECTION", "work_record.role 必須是 REBUILDABLE_PROJECTION", failures)
assert(work_record["may_generate_candidates"] == "0..N", "work_record.may_generate_candidates 必須是 0..N", failures)
assert(work_record.fetch("forbidden_authority", []).include?("memory_acceptance"), "work_record 不得取得 memory_acceptance authority", failures)

promotion_path = spec.fetch("promotion_path", {})
assert(promotion_path.fetch("ordered_steps", []) == EXPECTED_PROMOTION_STEPS, "promotion_path.ordered_steps 與鎖定順序不符", failures)
assert(promotion_path.dig("rules", "evidence_step_required") == true, "promotion_path 必須要求 evidence step", failures)
assert(promotion_path.dig("rules", "task_card_direct_to_record") == "forbidden", "promotion_path 必須禁止 task card 直接建 record", failures)
assert(promotion_path.dig("rules", "skip_any_step") == "forbidden", "promotion_path 必須禁止跳過任一步驟", failures)
assert(promotion_path.dig("receipts_required", "VERIFICATION") == "verification_receipt_ref", "VERIFICATION 必須要求 verification_receipt_ref", failures)
assert(promotion_path.dig("receipts_required", "PERSONAL_ACCEPTANCE") == "personal_acceptance_ref", "PERSONAL_ACCEPTANCE 必須要求 personal_acceptance_ref", failures)

non_acceptance_authority = spec.fetch("non_acceptance_authority", {})
assert(
  sorted_set(non_acceptance_authority.fetch("signals", [])) == sorted_set(EXPECTED_NON_ACCEPTANCE_SIGNALS),
  "non_acceptance_authority.signals 必須剛好是 branch/worktree/runtime_completion/model_confidence",
  failures
)

automated_step_contract = spec.fetch("automated_step_contract", {})
assert(
  sorted_set(automated_step_contract.fetch("required_per_step", [])) == sorted_set(EXPECTED_AUTOMATED_STEP_FIELDS),
  "automated_step_contract.required_per_step 與鎖定清單不符",
  failures
)
assert(automated_step_contract.fetch("error_behavior_enum", []) == %w[FAIL_LOUD], "automated_step_contract.error_behavior_enum 必須剛好是 [FAIL_LOUD]", failures)
assert(automated_step_contract["fail_silent"] == "forbidden", "automated_step_contract.fail_silent 必須 forbidden", failures)

cross_reference = spec.fetch("cross_reference", {})
transient_kinds = personal_spec.fetch("not_long_lived_memory_by_default", [])
assert(present?(transient_kinds), "personal spec 的 not_long_lived_memory_by_default 必須存在且非空", failures)
assert(cross_reference["transient_kinds_source"] == "not_long_lived_memory_by_default", "cross_reference.transient_kinds_source 必須指向 not_long_lived_memory_by_default", failures)
assert(cross_reference["transient_kinds_must_match"] == true, "cross_reference.transient_kinds_must_match 必須為 true", failures)
assert(
  personal_spec.dig("runtime_policy", "executor_authority_over_memory") == false,
  "personal spec 的 runtime_policy.executor_authority_over_memory 必須是 false",
  failures
)
assert(cross_reference["executor_authority_over_memory_must_be"] == false, "cross_reference.executor_authority_over_memory_must_be 必須是 false", failures)
personal_core_invariants = personal_spec.fetch("core_invariants", [])
EXPECTED_REUSED_CORE_INVARIANTS.each do |invariant|
  assert(cross_reference.fetch("reused_core_invariants", []).include?(invariant), "cross_reference.reused_core_invariants 必須含 #{invariant}", failures)
  assert(personal_core_invariants.include?(invariant), "personal spec core_invariants 必須含被引用的 #{invariant}", failures)
end

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_BOUNDARY_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("task_card_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} task card positive 必須預期 allow", failures)
  actual = task_card_failure(test_case.fetch("task_card"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

positive.fetch("promotion_path_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} promotion positive 必須預期 allow", failures)
  actual = promotion_path_failure(test_case.fetch("promotion"), transient_kinds)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

positive.fetch("automated_step_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} automated step positive 必須預期 allow", failures)
  actual = automated_step_failure(test_case.fetch("automated_step"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

def check_negative(cases, expected_kind_label, failures, &evaluator)
  cases.each do |test_case|
    case_id = test_case.fetch("case_id")
    assert(test_case.fetch("expected") == "deny", "#{case_id} #{expected_kind_label} negative 必須預期 deny", failures)
    expected_code = test_case.fetch("expected_failure_code")
    actual = evaluator.call(test_case)
    assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
    assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
  end
end

check_negative(negative.fetch("task_card_negative_cases"), "task card", failures) do |test_case|
  task_card_failure(test_case.fetch("task_card"))
end
check_negative(negative.fetch("promotion_path_negative_cases"), "promotion", failures) do |test_case|
  promotion_path_failure(test_case.fetch("promotion"), transient_kinds)
end
check_negative(negative.fetch("automated_step_negative_cases"), "automated step", failures) do |test_case|
  automated_step_failure(test_case.fetch("automated_step"))
end

covered_labels = sorted_set(
  (negative.fetch("task_card_negative_cases") +
   negative.fetch("promotion_path_negative_cases") +
   negative.fetch("automated_step_negative_cases")).map { |test_case| test_case.fetch("covers_boundary_negative_fixture") }
)
missing_labels = sorted_set(EXPECTED_BOUNDARY_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "boundary negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS ai work record boundary contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
