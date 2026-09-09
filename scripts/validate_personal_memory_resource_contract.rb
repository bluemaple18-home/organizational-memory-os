#!/usr/bin/env ruby

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")

# EMEM-01 / PMCORE-02：PersonalMemoryCandidate／Record／MemorySupportLink／
# MemoryConflictSet 四個 resource 的結構、lifecycle、support／conflict ref 綁定契約。

EXPECTED_PERSONAL_MEMORY_RESOURCES = %w[
  PersonalMemoryCandidate
  PersonalMemoryRecord
  MemorySupportLink
  MemoryConflictSet
].freeze
EXPECTED_CANDIDATE_STATUSES = %w[
  PROPOSED
  NEEDS_VERIFICATION
  VERIFIED
  ACCEPTANCE_REQUESTED
  ACCEPTED_FOR_RECORD
  REJECTED
  BLOCKED
  SUPERSEDED
].freeze
EXPECTED_RECORD_STATUSES = %w[
  ACTIVE
  SUPERSEDED
  INVALIDATED
  ARCHIVED
].freeze
EXPECTED_RESOURCE_NEGATIVE_LABELS = [
  "PersonalMemoryCandidate without support link",
  "PersonalMemoryCandidate treated as accepted record",
  "PersonalMemoryRecord created without personal acceptance",
  "transient task state promoted as personal memory",
  "support link crosses employee owner without permission intersection",
  "support link target_ref mismatches supported resource",
  "support link ref does not resolve",
  "support link uses disallowed source anchor profile",
  "MemoryConflictSet selects winner without review authority",
  "MemoryConflictSet declares canonical_winner_ref",
  "PersonalMemoryRecord lifecycle transition is not allowed",
  "MemoryConflictSet crosses owner without permission intersection",
  "MemoryConflictSet member ref uses wrong resource kind",
  "MemoryConflictSet member ref does not resolve",
  "MemoryConflictSet support link ref does not resolve",
  "MemoryConflictSet support link target or relation is invalid",
  "MemoryConflictSet member owner metadata mismatches parsed member"
].freeze

def has_path?(payload, path)
  value = path.split(".").reduce(payload) do |cursor, key|
    return false unless cursor.is_a?(Hash) && cursor.key?(key)

    cursor[key]
  end
  !value.nil?
end

def assert_required_paths(payload, paths, failures, label)
  paths.each do |path|
    assert(has_path?(payload, path), "#{label} 缺 required field #{path}", failures)
  end
end

def enum_from(spec, *path)
  spec.dig(*path).to_a
end

def collect_resource_entries(resource_cases)
  resource_cases.flat_map do |test_case|
    entries = [[test_case.fetch("resource_type"), test_case.fetch("resource"), test_case.fetch("case_id")]]
    test_case.fetch("related_resources", []).each do |related|
      entries << [related.fetch("resource_type"), related.fetch("resource"), "#{test_case.fetch("case_id")}:related"]
    end
    entries
  end
end

def resource_id_for(type, resource)
  case type
  when "PersonalMemoryCandidate"
    resource["candidate_id"]
  when "PersonalMemoryRecord"
    resource["record_id"]
  when "MemorySupportLink"
    resource["link_id"]
  when "MemoryConflictSet"
    resource["set_id"]
  end
end

def build_indexes(resource_cases)
  indexes = {
    support_links: {},
    resources: {}
  }

  collect_resource_entries(resource_cases).each do |type, resource, case_id|
    resource_id = resource_id_for(type, resource)
    next unless present?(resource_id)

    indexes[:resources][resource_id] = { type: type, resource: resource, case_id: case_id }
    indexes[:support_links][resource_id] = resource if type == "MemorySupportLink"
  end

  indexes
end

def allowed_anchor_profiles(common_vocab)
  common_vocab.dig("source_anchor_profiles", "phase_1").to_a
end

def personal_memory_target_ref?(value)
  allowed_resource_ref?(value, "candidate") || allowed_resource_ref?(value, "record")
end

def validate_lifecycle_transition(contract, resource, status_field, failures, label)
  transition = resource["lifecycle_transition"]
  return unless transition.is_a?(Hash)

  from_status = transition["from"]
  to_status = transition["to"]
  allowed = contract.dig("lifecycle", "allowed_transitions", from_status).to_a
  assert(resource[status_field] == from_status, "#{label} lifecycle_transition.from 必須等於目前 status", failures)
  assert(allowed.include?(to_status), "#{label} lifecycle_transition #{from_status}->#{to_status} 不允許", failures)
end

def validate_support_link_contract(spec, common_vocab, resource, failures, label)
  contracts = spec.fetch("personal_memory_resource_contracts")
  contract = contracts.fetch("resources").fetch("MemorySupportLink")
  assert_required_paths(resource, contract.fetch("required_fields"), failures, label)
  assert(allowed_resource_ref?(resource["link_id"], "support-link"), "#{label} link_id 必須使用 support-link urn", failures)
  assert(personal_memory_target_ref?(resource["target_ref"]), "#{label} target_ref 必須指向 PersonalMemoryCandidate 或 PersonalMemoryRecord", failures)
  assert(resource["evidence_ref"].is_a?(String) && resource["evidence_ref"].start_with?("urn:omos:evidence:"), "#{label} evidence_ref 必須指向 Evidence", failures)
  assert(resource["source_anchor_ref"].is_a?(String) && resource["source_anchor_ref"].start_with?("urn:omos:source-anchor:"), "#{label} source_anchor_ref 必須指向 SourceAnchor", failures)
  assert(allowed_anchor_profiles(common_vocab).include?(resource["source_anchor_profile"]), "#{label} source_anchor_profile 未准入", failures)
  assert(resource["model_summary_only"] != true, "#{label} 不得只靠 model summary", failures)
  allowed_relations = enum_from(spec, "personal_memory_resource_contracts", "enums", "support_relation")
  assert(allowed_relations.include?(resource["relation"]), "#{label} relation 不合法", failures)
  allowed_resolutions = enum_from(spec, "personal_memory_resource_contracts", "enums", "allowed_anchor_resolution_for_support")
  assert(allowed_resolutions.include?(resource["anchor_resolution"]), "#{label} anchor_resolution 不可作為 support", failures)
  if present?(resource["target_employee_owner_ref"]) && resource["target_employee_owner_ref"] != resource["employee_owner_ref"]
    assert(present?(resource["permission_intersection_ref"]), "#{label} 跨 employee owner 必須有 permission_intersection_ref", failures)
  end
end

def validate_support_refs(spec, common_vocab, indexes, resource, resource_id, failures, label)
  resource["support_link_refs"].to_a.each do |support_ref|
    support_link = indexes.fetch(:support_links).fetch(support_ref, nil)
    assert(!support_link.nil?, "#{label} support_link_ref #{support_ref} 無法解析", failures)
    next if support_link.nil?

    link_failures = []
    validate_support_link_contract(spec, common_vocab, support_link, link_failures, "MemorySupportLink #{support_ref}")
    link_failures.each { |failure| failures << failure }
    assert(support_link["target_ref"] == resource_id, "#{label} support_link_ref #{support_ref} target_ref 必須等於被支持資源 id", failures)
  end
end

def validate_conflict_member_refs(indexes, resource, failures)
  member_refs = resource["member_memory_refs"].to_a
  member_owner_refs = resource["member_owner_refs"].to_a
  parsed_member_owners = []

  assert(member_owner_refs.size == member_refs.size, "MemoryConflictSet member_owner_refs 必須逐一對齊 member_memory_refs", failures)

  member_refs.each_with_index do |member_ref, index|
    assert(member_ref != resource["set_id"], "MemoryConflictSet member_memory_refs 不得指向自身", failures)
    entry = indexes.fetch(:resources).fetch(member_ref, nil)
    assert(!entry.nil?, "MemoryConflictSet member_memory_ref #{member_ref} 無法解析", failures)
    next if entry.nil?

    assert(%w[PersonalMemoryCandidate PersonalMemoryRecord].include?(entry.fetch(:type)), "MemoryConflictSet member_memory_ref #{member_ref} 必須是 Candidate 或 Record", failures)
    parsed_owner = entry.fetch(:resource)["employee_owner_ref"]
    parsed_member_owners << parsed_owner if present?(parsed_owner)
    expected_owner = member_owner_refs[index]
    assert(present?(parsed_owner), "MemoryConflictSet member_memory_ref #{member_ref} 缺 employee_owner_ref", failures)
    assert(expected_owner == parsed_owner, "MemoryConflictSet member_owner_refs[#{index}] 必須等於解析 member owner", failures)
  end

  crosses_owner = parsed_member_owners.any? { |owner_ref| owner_ref != resource["employee_owner_ref"] }
  assert(!crosses_owner || present?(resource["permission_intersection_ref"]), "MemoryConflictSet 跨 employee owner 必須有 permission_intersection_ref", failures)
end

def validate_conflict_support_refs(spec, common_vocab, indexes, resource, failures)
  member_refs = resource["member_memory_refs"].to_a
  assert(!resource["support_link_refs"].to_a.empty?, "MemoryConflictSet 必須至少有一個 support_link_ref", failures)

  resource["support_link_refs"].to_a.each do |support_ref|
    assert(support_ref != resource["set_id"], "MemoryConflictSet support_link_refs 不得指向自身", failures)
    support_link = indexes.fetch(:support_links).fetch(support_ref, nil)
    assert(!support_link.nil?, "MemoryConflictSet support_link_ref #{support_ref} 無法解析", failures)
    next if support_link.nil?

    link_failures = []
    validate_support_link_contract(spec, common_vocab, support_link, link_failures, "MemorySupportLink #{support_ref}")
    link_failures.each { |failure| failures << failure }
    assert(member_refs.include?(support_link["target_ref"]), "MemoryConflictSet support_link_ref #{support_ref} target_ref 必須指向集合 member", failures)
    assert(support_link["relation"] == "CONTRADICTS", "MemoryConflictSet support_link_ref #{support_ref} relation 必須是 CONTRADICTS", failures)

    member_entry = indexes.fetch(:resources).fetch(support_link["target_ref"], nil)
    next if member_entry.nil?

    member_owner = member_entry.fetch(:resource)["employee_owner_ref"]
    assert(support_link["target_employee_owner_ref"] == member_owner, "MemoryConflictSet support_link_ref #{support_ref} target_employee_owner_ref 必須等於 member owner", failures)
  end
end

def resource_failures(spec, common_vocab, indexes, test_case)
  failures = []
  type = test_case.fetch("resource_type")
  resource = test_case.fetch("resource")
  contracts = spec.fetch("personal_memory_resource_contracts")
  contract = contracts.fetch("resources").fetch(type)
  assert_required_paths(resource, contract.fetch("required_fields"), failures, type)

  allowed_kinds = spec.fetch("memory_kinds_phase_1")
  transient_kinds = spec.fetch("not_long_lived_memory_by_default")

  case type
  when "PersonalMemoryCandidate"
    candidate_id = resource["candidate_id"]
    support_refs = resource["support_link_refs"].to_a
    governance = resource.fetch("governance", {})

    assert(allowed_resource_ref?(candidate_id, "candidate"), "PersonalMemoryCandidate candidate_id 必須使用 candidate urn", failures)
    assert(allowed_kinds.include?(resource["memory_kind"]), "PersonalMemoryCandidate memory_kind 不在 phase-1 durable kinds", failures)
    assert(!transient_kinds.include?(resource["memory_kind"]), "PersonalMemoryCandidate 不得使用 transient memory kind", failures)
    assert(!support_refs.empty?, "PersonalMemoryCandidate 必須至少有一個 support_link_ref", failures)
    validate_support_refs(spec, common_vocab, indexes, resource, candidate_id, failures, "PersonalMemoryCandidate")
    assert(!resource.key?("record_id"), "PersonalMemoryCandidate 不得帶 record_id", failures)
    assert(resource["resource_kind"] != "PERSONAL_MEMORY_RECORD", "PersonalMemoryCandidate 不得宣告成 PersonalMemoryRecord", failures)
    assert(EXPECTED_CANDIDATE_STATUSES.include?(resource["candidate_status"]), "PersonalMemoryCandidate candidate_status 不合法", failures)
    validate_lifecycle_transition(contract, resource, "candidate_status", failures, "PersonalMemoryCandidate")
    if resource["candidate_status"] == "ACCEPTED_FOR_RECORD" || governance["acceptance_status"] == "ACCEPTED"
      assert(governance["verification_status"] == "PASS", "Candidate acceptance 必須有 verification PASS", failures)
      assert(present?(governance["verification_receipt_ref"]), "Candidate acceptance 必須有 verification_receipt_ref", failures)
      assert(present?(governance["personal_acceptance_ref"]), "Candidate acceptance 必須有 personal_acceptance_ref", failures)
    else
      assert(governance["acceptance_status"] != "ACCEPTED", "未形成 record 的 Candidate 不得是 ACCEPTED", failures)
    end
  when "PersonalMemoryRecord"
    record_id = resource["record_id"]
    origin_candidate_ref = resource["origin_candidate_ref"]
    governance = resource.fetch("governance", {})
    candidate_snapshot = resource.fetch("candidate_snapshot", {})

    assert(allowed_resource_ref?(record_id, "record"), "PersonalMemoryRecord record_id 必須使用 record urn", failures)
    assert(origin_candidate_ref != record_id, "PersonalMemoryRecord record_id 不得等於 origin_candidate_ref", failures)
    assert(allowed_resource_ref?(origin_candidate_ref, "candidate"), "PersonalMemoryRecord origin_candidate_ref 必須指向 candidate", failures)
    assert(allowed_kinds.include?(resource["memory_kind"]), "PersonalMemoryRecord memory_kind 不在 phase-1 durable kinds", failures)
    assert(!transient_kinds.include?(resource["memory_kind"]), "PersonalMemoryRecord 不得使用 transient memory kind", failures)
    assert(!resource["support_link_refs"].to_a.empty?, "PersonalMemoryRecord 必須至少有一個 support_link_ref", failures)
    validate_support_refs(spec, common_vocab, indexes, resource, record_id, failures, "PersonalMemoryRecord")
    assert(governance["verification_status"] == "PASS", "PersonalMemoryRecord verification_status 必須是 PASS", failures)
    assert(governance["acceptance_status"] == "ACCEPTED", "PersonalMemoryRecord acceptance_status 必須是 ACCEPTED", failures)
    assert(present?(governance["verification_receipt_ref"]), "PersonalMemoryRecord 必須有 verification_receipt_ref", failures)
    assert(present?(governance["personal_acceptance_ref"]), "PersonalMemoryRecord 必須有 personal_acceptance_ref", failures)
    assert(present?(governance["acl_ref"]), "PersonalMemoryRecord 必須有 acl_ref", failures)
    assert(present?(governance["freshness"]), "PersonalMemoryRecord 必須有 freshness", failures)
    assert(present?(governance["retention_state"]), "PersonalMemoryRecord 必須有 retention_state", failures)
    assert(candidate_snapshot["candidate_status"] == "ACCEPTED_FOR_RECORD", "PersonalMemoryRecord 必須來自 ACCEPTED_FOR_RECORD candidate", failures)
    assert(candidate_snapshot["verification_status"] == "PASS", "PersonalMemoryRecord candidate_snapshot verification 必須 PASS", failures)
    assert(candidate_snapshot["acceptance_status"] == "ACCEPTED", "PersonalMemoryRecord candidate_snapshot acceptance 必須 ACCEPTED", failures)
    assert(EXPECTED_RECORD_STATUSES.include?(resource["record_status"]), "PersonalMemoryRecord record_status 不合法", failures)
    validate_lifecycle_transition(contract, resource, "record_status", failures, "PersonalMemoryRecord")
  when "MemorySupportLink"
    validate_support_link_contract(spec, common_vocab, resource, failures, "MemorySupportLink")
  when "MemoryConflictSet"
    assert(allowed_resource_ref?(resource["set_id"], "conflict-set"), "MemoryConflictSet set_id 必須使用 conflict-set urn", failures)
    assert(resource["member_memory_refs"].to_a.size >= 2, "MemoryConflictSet 至少需要兩個 member_memory_refs", failures)
    contract.fetch("forbidden_fields").each do |field|
      assert(!resource.key?(field), "MemoryConflictSet 不得自行設定 #{field}", failures)
    end
    assert(resource["canonical_writer_authority"] != true, "MemoryConflictSet 不取得 canonical writer authority", failures)
    assert(resource["grants_acceptance_authority"] != true, "MemoryConflictSet 不取得 acceptance authority", failures)
    validate_conflict_member_refs(indexes, resource, failures)
    validate_conflict_support_refs(spec, common_vocab, indexes, resource, failures)
    allowed_resolution_statuses = enum_from(spec, "personal_memory_resource_contracts", "enums", "conflict_resolution_status")
    assert(allowed_resolution_statuses.include?(resource["resolution_status"]), "MemoryConflictSet resolution_status 不合法", failures)
  else
    assert(false, "未知 resource_type #{type}", failures)
  end

  failures
end

def evaluate_resource_case(spec, common_vocab, indexes, test_case)
  resource_failures(spec, common_vocab, indexes, test_case).empty? ? "allow" : "deny"
end

failures = []
spec = read_yaml(SPEC_PATH)
common_vocab = read_yaml(COMMON_VOCAB_PATH)

resource_contracts = spec.fetch("personal_memory_resource_contracts", {})
assert(resource_contracts["version"] == "0.1.0", "personal_memory_resource_contracts.version 必須是 0.1.0", failures)
assert(
  sorted_set(resource_contracts.dig("resources")&.keys.to_a) == sorted_set(EXPECTED_PERSONAL_MEMORY_RESOURCES),
  "personal_memory_resource_contracts 必須定義四個 PMCORE-02 resources",
  failures
)
assert(resource_contracts.dig("shared_constraints", "model_summary_as_support") == "forbidden", "model summary 不得作為 support", failures)
assert(resource_contracts.dig("shared_constraints", "cross_employee_reference_rule").to_s.include?("permission_intersection_ref"), "跨 employee reference 必須要求 permission_intersection_ref", failures)
assert(enum_from(spec, "personal_memory_resource_contracts", "enums", "candidate_status") == EXPECTED_CANDIDATE_STATUSES, "candidate_status enum 不符合 PMCORE-02", failures)
assert(enum_from(spec, "personal_memory_resource_contracts", "enums", "record_status") == EXPECTED_RECORD_STATUSES, "record_status enum 不符合 PMCORE-02", failures)
assert(
  enum_from(spec, "personal_memory_resource_contracts", "resources", "MemoryConflictSet", "forbidden_authority").include?("winner_selection"),
  "MemoryConflictSet 必須禁止自行選 winner",
  failures
)

positive_resource_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("resource_cases")
negative_resource_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("resource_cases")
fixture_resource_indexes = build_indexes(positive_resource_cases + negative_resource_cases)

positive_resource_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} resource positive fixture 必須預期 allow", failures)
  actual = evaluate_resource_case(spec, common_vocab, fixture_resource_indexes, test_case)
  assert(actual == test_case.fetch("expected"), "#{test_case.fetch("case_id")} 預期 allow，實際 #{actual}: #{resource_failures(spec, common_vocab, fixture_resource_indexes, test_case).join("; ")}", failures)
end

negative_resource_cases.each do |test_case|
  assert(test_case.fetch("expected") == "deny", "#{test_case.fetch("case_id")} resource negative fixture 必須預期 deny", failures)
  actual = evaluate_resource_case(spec, common_vocab, fixture_resource_indexes, test_case)
  assert(actual == test_case.fetch("expected"), "#{test_case.fetch("case_id")} 預期 deny，實際 #{actual}", failures)
end

covered_resource_negative_labels = sorted_set(negative_resource_cases.map { |test_case| test_case.fetch("covers_resource_negative_fixture") })
missing_resource_negative_labels = sorted_set(EXPECTED_RESOURCE_NEGATIVE_LABELS) - covered_resource_negative_labels
assert(missing_resource_negative_labels.empty?, "resource negative fixtures 未覆蓋：#{missing_resource_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS personal memory resource contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
