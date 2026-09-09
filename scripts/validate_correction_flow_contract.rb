#!/usr/bin/env ruby

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")


# SSP-293 / EMEM-04 Correction / Supersession 契約 validator。

EXPECTED_CORRECTION_KINDS = {
  "AMEND" => "SUPERSEDED",
  "INVALIDATE" => "INVALIDATED",
  "SUPERSEDE" => "SUPERSEDED"
}.freeze

EXPECTED_CORRECTION_PROPOSAL_FIELDS = %w[
  proposal_id
  tenant_id
  employee_owner_ref
  target_record_ref
  correction_kind
  correction_evidence_refs
  proposed_by
  chronology.created_at
].freeze

EXPECTED_SUPERSESSION_RECEIPT_FIELDS = %w[
  receipt_id
  tenant_id
  employee_owner_ref
  origin_proposal_ref
  target_record_ref
  correction_kind
  old_record_ref
  resulting_record_status
  verification_status
  chronology.created_at
].freeze
# verification_receipt_ref / personal_acceptance_ref 不放 required list —— 由 gate
# 分支強制（缺 → CORRECTION_SKIPS_VERIFICATION / CORRECTION_SKIPS_ACCEPTANCE），
# 才不會被通用 missing-field 檢查先攔掉、失去語意。
EXPECTED_CORRECTION_GATE_FIELDS = %w[verification_receipt_ref personal_acceptance_ref].freeze

EXPECTED_CORRECTION_FORBIDDEN = %w[
  history_erasure
  in_place_record_overwrite
  skip_verification
  skip_acceptance
  receipt_mutation
].freeze

EXPECTED_CORRECTION_NEGATIVE_LABELS = [
  "correction proposal without correction evidence",
  "supersession receipt skips verification",
  "supersession receipt skips acceptance",
  "correction overwrites the record in place",
  "supersession receipt erases history",
  "correction kind maps to the wrong lifecycle status",
  "supersession receipt mutated after the fact"
].freeze

OMOS_URN_PATTERN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

def omos_urn?(value, namespace)
  value.is_a?(String) && value.start_with?("urn:omos:#{namespace}:") && OMOS_URN_PATTERN.match?(value)
end

def dig_dotted(payload, dotted)
  dotted.split(".").reduce(payload) { |cursor, key| cursor.is_a?(Hash) ? cursor[key] : nil }
end

# Thin correction-proposal check. Returns nil or the exact machine failure code.
def correction_proposal_failure(proposal)
  (EXPECTED_CORRECTION_PROPOSAL_FIELDS - ["correction_evidence_refs"]).each do |field|
    return "CORRECTION_PROPOSAL_MISSING_FIELD" unless present?(dig_dotted(proposal, field))
  end
  return "CORRECTION_PROPOSAL_MISSING_FIELD" unless proposal.key?("correction_evidence_refs")
  return "CORRECTION_PROPOSAL_INVALID_ID" unless allowed_resource_ref?(proposal["proposal_id"], "correction-proposal")
  return "CORRECTION_TARGET_NOT_RECORD" unless allowed_resource_ref?(proposal["target_record_ref"], "record")
  return "CORRECTION_KIND_INVALID" unless EXPECTED_CORRECTION_KINDS.key?(proposal["correction_kind"])
  evidence_refs = proposal["correction_evidence_refs"]
  unless evidence_refs.is_a?(Array) && !evidence_refs.empty? && evidence_refs.all? { |ref| omos_urn?(ref, "evidence") }
    return "CORRECTION_MISSING_EVIDENCE"
  end

  nil
end

# Thin supersession-receipt check. Enforces the verify->accept gate, the
# correction_kind -> lifecycle mapping, no in-place overwrite, receipt
# immutability, and no history erasure. Returns nil or the exact code.
def supersession_receipt_failure(receipt)
  return "SUPERSESSION_RECEIPT_MISSING_FIELD" if EXPECTED_SUPERSESSION_RECEIPT_FIELDS.any? { |field| !present?(dig_dotted(receipt, field)) }
  return "SUPERSESSION_RECEIPT_INVALID_ID" unless allowed_resource_ref?(receipt["receipt_id"], "supersession-receipt")
  return "SUPERSESSION_RECEIPT_INVALID_ID" unless allowed_resource_ref?(receipt["old_record_ref"], "record")

  return "CORRECTION_RECEIPT_MUTATED" if receipt["mutated"] == true || present?(receipt["receipt_superseded_by"])
  return "CORRECTION_HISTORY_ERASURE" if receipt["history_erasure"] == true
  return "CORRECTION_IN_PLACE_OVERWRITE" if receipt["in_place_overwrite"] == true || present?(receipt["in_place_content_patch"])

  return "CORRECTION_KIND_INVALID" unless EXPECTED_CORRECTION_KINDS.key?(receipt["correction_kind"])
  return "CORRECTION_SKIPS_VERIFICATION" if receipt["verification_status"] != "PASS"
  return "CORRECTION_SKIPS_VERIFICATION" unless omos_urn?(receipt["verification_receipt_ref"], "verification")
  return "CORRECTION_SKIPS_ACCEPTANCE" unless omos_urn?(receipt["personal_acceptance_ref"], "acceptance")

  expected_status = EXPECTED_CORRECTION_KINDS.fetch(receipt["correction_kind"])
  return "CORRECTION_KIND_LIFECYCLE_MISMATCH" if receipt["resulting_record_status"] != expected_status

  if receipt["correction_kind"] == "SUPERSEDE"
    return "CORRECTION_SUPERSEDE_MISSING_NEW_RECORD" unless allowed_resource_ref?(receipt["new_record_ref"], "record")
    return "CORRECTION_SUPERSEDE_MISSING_NEW_RECORD" if receipt["new_record_ref"] == receipt["old_record_ref"]
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)

correction_flow = spec.fetch("correction_flow", {})
assert(correction_flow["history_erasure"] == "forbidden", "correction_flow.history_erasure 必須 forbidden", failures)
correction_contract = correction_flow.fetch("contract", {})
assert(correction_contract.fetch("correction_kinds", {}) == EXPECTED_CORRECTION_KINDS, "correction_flow.contract.correction_kinds 與鎖定映射不符", failures)
assert(
  correction_contract.fetch("proposal_required_fields", []) == EXPECTED_CORRECTION_PROPOSAL_FIELDS,
  "correction_flow.contract.proposal_required_fields 與鎖定清單不符",
  failures
)
assert(
  correction_contract.fetch("supersession_receipt_required_fields", []) == EXPECTED_SUPERSESSION_RECEIPT_FIELDS,
  "correction_flow.contract.supersession_receipt_required_fields 與鎖定清單不符",
  failures
)
assert(correction_contract.dig("gate", "verification_status_must_be") == "PASS", "correction gate verification_status_must_be 必須是 PASS", failures)
assert(
  sorted_set(correction_contract.dig("gate", "requires").to_a) == sorted_set(EXPECTED_CORRECTION_GATE_FIELDS),
  "correction gate requires 必須是 verification_receipt_ref 與 personal_acceptance_ref",
  failures
)
assert(
  sorted_set(correction_contract.fetch("gate_enforced_fields", [])) == sorted_set(EXPECTED_CORRECTION_GATE_FIELDS),
  "correction_flow.contract.gate_enforced_fields 必須是 verification_receipt_ref 與 personal_acceptance_ref",
  failures
)
assert(correction_contract["supersede_requires_new_record_ref"] == true, "SUPERSEDE 必須要求 new_record_ref", failures)
assert(correction_contract["immutable_receipt"] == true, "correction_flow.contract.immutable_receipt 必須為 true", failures)
assert(
  sorted_set(correction_contract.fetch("forbidden", [])) == sorted_set(EXPECTED_CORRECTION_FORBIDDEN),
  "correction_flow.contract.forbidden 與鎖定清單不符",
  failures
)
assert(
  spec.dig("contract_registry", "define_for_employee_memory", "MemoryCorrectionProposal", "required_fields_ref") == "correction_flow.contract.proposal_required_fields",
  "MemoryCorrectionProposal.required_fields_ref 必須指向 proposal_required_fields",
  failures
)
assert(
  spec.dig("contract_registry", "define_for_employee_memory", "MemorySupersessionReceipt", "required_fields_ref") == "correction_flow.contract.supersession_receipt_required_fields",
  "MemorySupersessionReceipt.required_fields_ref 必須指向 supersession_receipt_required_fields",
  failures
)
# correction_kind 映射的目標 status 必須是 PersonalMemoryRecord lifecycle 的合法值
pmr_record_statuses = spec.dig("personal_memory_resource_contracts", "enums", "record_status").to_a
pmr_active_transitions = spec.dig(
  "personal_memory_resource_contracts", "resources", "PersonalMemoryRecord", "lifecycle", "allowed_transitions", "ACTIVE"
).to_a
EXPECTED_CORRECTION_KINDS.each_value do |status|
  assert(pmr_record_statuses.include?(status), "correction_kind 目標 status #{status} 必須是 record_status enum 成員", failures)
  assert(pmr_active_transitions.include?(status), "correction_kind 目標 status #{status} 必須是 PersonalMemoryRecord ACTIVE 的合法 transition", failures)
end

correction_proposal_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("correction_proposal_cases")
supersession_receipt_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("supersession_receipt_cases")
correction_proposal_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("correction_proposal_negative_cases")
supersession_receipt_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("supersession_receipt_negative_cases")

correction_proposal_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} correction proposal positive 必須預期 allow", failures)
  actual = correction_proposal_failure(test_case.fetch("proposal"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

supersession_receipt_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} supersession receipt positive 必須預期 allow", failures)
  actual = supersession_receipt_failure(test_case.fetch("receipt"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

[[correction_proposal_negative_cases, method(:correction_proposal_failure), "proposal"],
 [supersession_receipt_negative_cases, method(:supersession_receipt_failure), "receipt"]].each do |cases, evaluator, key|
  cases.each do |test_case|
    case_id = test_case.fetch("case_id")
    assert(test_case.fetch("expected") == "deny", "#{case_id} correction negative 必須預期 deny", failures)
    expected_code = test_case.fetch("expected_failure_code")
    actual = evaluator.call(test_case.fetch(key))
    assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
    assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
  end
end

covered_correction_negative_labels = sorted_set(
  (correction_proposal_negative_cases + supersession_receipt_negative_cases).map { |test_case| test_case.fetch("covers_correction_negative_fixture") }
)
missing_correction_negative_labels = sorted_set(EXPECTED_CORRECTION_NEGATIVE_LABELS) - covered_correction_negative_labels
assert(missing_correction_negative_labels.empty?, "correction negative fixtures 未覆蓋：#{missing_correction_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS correction flow contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
