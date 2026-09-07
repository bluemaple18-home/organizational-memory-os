#!/usr/bin/env ruby

require "json"
require "set"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")
MAIN_DOC_PATH = File.join(ROOT, "文件/個人知識庫Harness提案查核與整合裁決-20260830.md")
BACKLOG_DOC_PATH = File.join(ROOT, "文件/待辦補充-個人知識庫Harness-20260830.md")

EXPECTED_MODES = %w[
  EMPLOYEE_PRIVATE
  COMPANY_MANAGED_PERSONAL
  SHARED_WORK_CONTEXT
].freeze

EXPECTED_ACTORS = %w[
  EMPLOYEE
  MANAGER
  ADMIN
  REVIEWER
  SYSTEM
].freeze

EXPECTED_ACTIONS = %w[
  READ
  WRITE
  DELETE
  EXPORT
  PROMOTE
].freeze

EXPECTED_CAPABILITY_LEVELS = %w[
  L1
  L2
  L3
  L4
].freeze
EXPECTED_CAPABILITY_KEYS = (EXPECTED_CAPABILITY_LEVELS + %w[same_contract_all_levels]).freeze
LEVEL_ORDER = %w[L1 L2 L3 L4].freeze

EXPECTED_MATRIX_CAPABILITIES = %w[
  manual_capture
  candidate_generation
  employee_confirmation
  basic_recall_with_citation
  automatic_source_ingestion
  deterministic_dedup_version_acl_retention
  automatic_candidate_queue
  cross_source_object_linking
  workrecord_correlation
  conflict_freshness_gap_suggestion
  context_aware_recall
  promotion_suggestion
  continuous_stale_conflict_gap_monitoring
  correction_proposal
  promotion_proposal
  projection_rebuild_regression_evaluation
].freeze

EXPECTED_LEVEL_GRANTS = {
  "L1" => %w[manual_capture candidate_generation employee_confirmation basic_recall_with_citation],
  "L2" => %w[automatic_source_ingestion deterministic_dedup_version_acl_retention automatic_candidate_queue],
  "L3" => %w[cross_source_object_linking workrecord_correlation conflict_freshness_gap_suggestion context_aware_recall promotion_suggestion],
  "L4" => %w[continuous_stale_conflict_gap_monitoring correction_proposal promotion_proposal projection_rebuild_regression_evaluation]
}.freeze

EXPECTED_CAPABILITY_SAFETY_FLOOR = %w[
  permission_before_retrieval
  provenance_required
  canonical_single_writer
  candidate_not_auto_accepted_by_level
  promotion_requires_widening_gate
].freeze

L4_AUTHORITY_GATED_ACTIONS = %w[correction_proposal promotion_proposal].freeze

EXPECTED_CAPABILITY_NEGATIVE_LABELS = [
  "level claims capability above its grant",
  "downgrade removes a safety-floor invariant",
  "L4 action bypasses the authority gate",
  "profile references a non-existent level",
  "level transition skips a step",
  "capability level forks the core contract"
].freeze

EXPECTED_BACKLOG = (0..8).map { |number| format("EMEM_%02d", number) }.freeze
EXPECTED_BACKLOG_DOC = EXPECTED_BACKLOG.map { |item| item.tr("_", "-") }.freeze
VALID_DECISIONS = %w[ALLOW DENY CONDITIONAL].freeze
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

HARD_DENY_FLAGS = %w[
  admin_default_personal_search
  attempts_direct_shared_canonical_copy
  attempts_history_erasure
  attempts_role_lifecycle_redefinition
  attempts_shared_context_include_private_material
  freshness_warning_missing
  is_not_long_lived_by_default
  model_confidence_only
  treats_ai_core_layout_as_universal_schema
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
  values.to_set
end

def present?(value)
  !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
end

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

def allowed_resource_ref?(value, resource_kind)
  value.is_a?(String) && value.start_with?("urn:omos:personal-memory:#{resource_kind}:")
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

def evaluate_request(policy, request)
  context = request.fetch("context", {})
  return "deny" if HARD_DENY_FLAGS.any? { |flag| context[flag] == true }

  actor = request.fetch("actor")
  action = request.fetch("action")
  mode = request.fetch("scope_mode")
  rule = policy.dig(actor, action, mode)
  return "deny" if rule.nil?

  decision = rule.fetch("decision")
  required_conditions = rule.fetch("required_conditions", [])

  return "deny" if decision == "DENY"

  conditions_met = required_conditions.all? { |condition| context[condition] == true }
  return "allow" if decision == "ALLOW" && conditions_met
  return "allow" if decision == "CONDITIONAL" && conditions_met

  "deny"
end

def effective_capability_grant(level)
  index = LEVEL_ORDER.index(level)
  return nil if index.nil?

  LEVEL_ORDER[0..index].flat_map { |lvl| EXPECTED_LEVEL_GRANTS.fetch(lvl) }
end

# Returns nil when the capability profile is contract-valid, otherwise the exact
# machine failure code. Fixtures declare the expected code so that an unrelated
# rejection cannot stand in for real coverage.
def capability_profile_failure(profile)
  level = profile["capability_level"]
  return "UNKNOWN_CAPABILITY_LEVEL" unless LEVEL_ORDER.include?(level)
  return "LEVEL_FORKS_CORE_CONTRACT" if profile["forks_core_contract"] == true

  granted = effective_capability_grant(level)
  claimed = profile["claimed_capabilities"].to_a
  return "CAPABILITY_ABOVE_LEVEL_GRANT" if claimed.any? { |capability| !granted.include?(capability) }

  if level == "L4" && !(claimed & L4_AUTHORITY_GATED_ACTIONS).empty? && profile["authority_gate_satisfied"] != true
    return "L4_ACTION_BYPASSES_AUTHORITY_GATE"
  end

  if profile.key?("safety_floor_state")
    floor = profile.fetch("safety_floor_state", {})
    return "SAFETY_FLOOR_INVARIANT_MISSING" if EXPECTED_CAPABILITY_SAFETY_FLOOR.any? { |invariant| floor[invariant] != true }
  end

  nil
end

# Returns nil when the level transition is contract-valid, otherwise the exact
# machine failure code.
def level_transition_failure(spec, transition)
  from_level = transition["from"]
  to_level = transition["to"]
  return "UNKNOWN_CAPABILITY_LEVEL" unless LEVEL_ORDER.include?(from_level) && LEVEL_ORDER.include?(to_level)

  contract = spec.fetch("level_transitions")
  is_upgrade = LEVEL_ORDER.index(to_level) > LEVEL_ORDER.index(from_level)
  allowed = if is_upgrade
              contract.dig("allowed_upgrades", from_level).to_a
            else
              contract.dig("allowed_downgrades", from_level).to_a
            end
  return "LEVEL_TRANSITION_NOT_SINGLE_STEP" unless allowed.include?(to_level)
  return "LEVEL_TRANSITION_UNAUTHORIZED_ACTOR" unless transition["actor_authorized"] == true
  return "LEVEL_TRANSITION_REASON_NOT_RECORDED" unless transition["reason_recorded"] == true
  return "LEVEL_TRANSITION_FORKS_CORE_CONTRACT" if transition["forks_core_contract"] == true

  unless is_upgrade
    floor = transition.fetch("safety_floor_after", {})
    return "DOWNGRADE_REMOVES_SAFETY_FLOOR" if EXPECTED_CAPABILITY_SAFETY_FLOOR.any? { |invariant| floor[invariant] != true }
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
common_vocab = read_yaml(COMMON_VOCAB_PATH)

schema = spec.fetch("schema", {})
assert(schema["version"] == "0.3.0", "schema.version 必須是 0.3.0", failures)
assert(
  schema["schema_id"] == "urn:omos:schema:employee-personal-memory-standard:0.3.0",
  "schema_id 必須與 employee personal memory standard 版本一致",
  failures
)

scope_modes = spec.fetch("employee_memory_scope_modes", {})
assert(scope_modes.is_a?(Hash), "employee_memory_scope_modes 必須是 mapping，不可混用 list 與 rule", failures)
assert(sorted_set(scope_modes.fetch("modes", [])) == sorted_set(EXPECTED_MODES), "scope modes 必須剛好是三種 PERSONAL 模式", failures)
assert(sorted_set(scope_modes.fetch("derived_from", [])) == sorted_set(%w[ownership_mode visibility_scope]), "scope modes 必須由 ownership_mode 與 visibility_scope 分軸組成", failures)

contract = spec.fetch("ownership_visibility_contract", {})
mode_definitions = contract.fetch("mode_definitions", {})
EXPECTED_MODES.each do |mode|
  definition = mode_definitions.fetch(mode, {})
  assert(definition.key?("ownership_mode"), "#{mode} 必須定義 ownership_mode", failures)
  assert(definition.key?("visibility_scope"), "#{mode} 必須定義 visibility_scope", failures)
  assert(definition.key?("consent_or_notice_required"), "#{mode} 必須定義 consent_or_notice_required", failures)
  assert(definition.key?("offboarding_default"), "#{mode} 必須定義 offboarding_default", failures)
end

policy = contract.fetch("actor_action_policy", {})
EXPECTED_ACTORS.each do |actor|
  EXPECTED_ACTIONS.each do |action|
    EXPECTED_MODES.each do |mode|
      rule = policy.dig(actor, action, mode)
      assert(!rule.nil?, "#{actor}/#{action}/#{mode} 缺 policy", failures)
      next if rule.nil?

      assert(VALID_DECISIONS.include?(rule["decision"]), "#{actor}/#{action}/#{mode} decision 不合法", failures)
      assert(rule.fetch("required_conditions", []).is_a?(Array), "#{actor}/#{action}/#{mode} required_conditions 必須是 array", failures)
    end
  end
end

%w[EMPLOYEE SYSTEM].each do |actor|
  shared_write_conditions = policy.dig(actor, "WRITE", "SHARED_WORK_CONTEXT", "required_conditions") || []
  assert(shared_write_conditions.include?("private_material_redacted"), "#{actor}/WRITE/SHARED_WORK_CONTEXT 必須要求 private_material_redacted", failures)
end

manager_company_promotion_conditions = policy.dig("MANAGER", "PROMOTE", "COMPANY_MANAGED_PERSONAL", "required_conditions") || []
assert(manager_company_promotion_conditions.include?("manager_business_need"), "MANAGER/PROMOTE/COMPANY_MANAGED_PERSONAL 必須要求 manager_business_need", failures)
assert(manager_company_promotion_conditions.include?("company_policy_allows_manager_promotion"), "MANAGER/PROMOTE/COMPANY_MANAGED_PERSONAL 必須要求 company_policy_allows_manager_promotion", failures)
assert(manager_company_promotion_conditions.include?("employee_notice_given"), "MANAGER/PROMOTE/COMPANY_MANAGED_PERSONAL 必須要求 employee_notice_given", failures)

manager_shared_promotion_conditions = policy.dig("MANAGER", "PROMOTE", "SHARED_WORK_CONTEXT", "required_conditions") || []
assert(manager_shared_promotion_conditions.include?("manager_business_need"), "MANAGER/PROMOTE/SHARED_WORK_CONTEXT 必須要求 manager_business_need", failures)
assert(manager_shared_promotion_conditions.include?("source_acl_allows_requester"), "MANAGER/PROMOTE/SHARED_WORK_CONTEXT 必須要求 source_acl_allows_requester", failures)

assert(contract.dig("retention_and_lifecycle_policy", "legal_hold_overrides_delete_and_purge") == true, "legal hold 必須覆蓋 delete/purge", failures)
assert(contract.dig("source_acl_inheritance", "rule").to_s.include?("cannot widen"), "source ACL 繼承必須明確禁止未審核放寬", failures)
assert(contract.dig("promotion_widening_gate", "required").to_a.include?("reviewer_approval"), "promotion widening gate 必須要求 reviewer_approval", failures)

capability_levels = spec.fetch("capability_levels", {})
assert(sorted_set(capability_levels.keys) == sorted_set(EXPECTED_CAPABILITY_KEYS), "capability_levels 必須只包含 L1～L4 與 same_contract_all_levels", failures)
assert(capability_levels["same_contract_all_levels"] == true, "L1～L4 必須共用同一核心契約", failures)
assert(capability_levels.dig("L4", "authority_gate_required") == true, "capability_levels.L4 authority_gate_required 必須維持 true", failures)

capability_matrix = spec.fetch("capability_matrix", {})
assert(
  sorted_set(capability_matrix.fetch("capabilities", [])) == sorted_set(EXPECTED_MATRIX_CAPABILITIES),
  "capability_matrix.capabilities 必須剛好是鎖定的 phase-1 capability 清單",
  failures
)
assert(capability_matrix["cumulative"] == true, "capability_matrix.cumulative 必須為 true", failures)
matrix_grants = capability_matrix.fetch("grants", {})
assert(sorted_set(matrix_grants.keys) == sorted_set(LEVEL_ORDER), "capability_matrix.grants 必須剛好涵蓋 L1～L4", failures)
LEVEL_ORDER.each do |level|
  assert(
    matrix_grants[level].to_a == EXPECTED_LEVEL_GRANTS.fetch(level),
    "capability_matrix.grants.#{level} 與鎖定 grant 不符",
    failures
  )
end
all_grant_rows = LEVEL_ORDER.flat_map { |level| matrix_grants[level].to_a }
assert(all_grant_rows.uniq.length == all_grant_rows.length, "capability_matrix.grants 各級不得重複列同一 capability", failures)
assert(
  sorted_set(all_grant_rows) == sorted_set(EXPECTED_MATRIX_CAPABILITIES),
  "capability_matrix.grants 各級聯集必須等於 capabilities",
  failures
)
assert(
  capability_matrix.dig("level_gated_actions", "L4").to_a == L4_AUTHORITY_GATED_ACTIONS,
  "capability_matrix.level_gated_actions.L4 必須是 correction_proposal 與 promotion_proposal",
  failures
)

level_transitions = spec.fetch("level_transitions", {})
assert(level_transitions["single_step_only"] == true, "level_transitions.single_step_only 必須為 true", failures)
assert(level_transitions.dig("allowed_upgrades", "L1").to_a == %w[L2], "L1 只能升級到 L2", failures)
assert(level_transitions.dig("allowed_upgrades", "L2").to_a == %w[L3], "L2 只能升級到 L3", failures)
assert(level_transitions.dig("allowed_upgrades", "L3").to_a == %w[L4], "L3 只能升級到 L4", failures)
assert(level_transitions.dig("allowed_upgrades", "L4").to_a.empty?, "L4 之上不得有升級目標", failures)
assert(level_transitions.dig("allowed_downgrades", "L4").to_a == %w[L3], "L4 只能降級到 L3", failures)
assert(level_transitions.dig("allowed_downgrades", "L3").to_a == %w[L2], "L3 只能降級到 L2", failures)
assert(level_transitions.dig("allowed_downgrades", "L2").to_a == %w[L1], "L2 只能降級到 L1", failures)
assert(level_transitions.dig("allowed_downgrades", "L1").to_a.empty?, "L1 之下不得有降級目標", failures)
assert(
  sorted_set(level_transitions.fetch("transition_requirements", [])) == sorted_set(%w[authorized_actor reason_recorded]),
  "level transition 必須要求 authorized_actor 與 reason_recorded",
  failures
)
assert(level_transitions.dig("downgrade_rules", "must_preserve_safety_floor") == true, "降級必須保留 safety floor", failures)
assert(
  level_transitions.fetch("forbidden", []).include?("downgrade_that_removes_safety_floor"),
  "level_transitions.forbidden 必須列出 downgrade_that_removes_safety_floor",
  failures
)

capability_safety_floor = spec.fetch("capability_safety_floor", {})
assert(
  sorted_set(capability_safety_floor.fetch("invariants", [])) == sorted_set(EXPECTED_CAPABILITY_SAFETY_FLOOR),
  "capability_safety_floor.invariants 與鎖定清單不符",
  failures
)
assert(capability_safety_floor["applies_to_all_levels"] == true, "capability_safety_floor 必須適用所有 level", failures)
assert(capability_safety_floor["downgrade_preserves_all_invariants"] == true, "capability_safety_floor 降級不得移除任一不變項", failures)
assert(
  capability_safety_floor.dig("l4_authority_gate", "authority_gate_required") == true,
  "capability_safety_floor.l4_authority_gate.authority_gate_required 必須為 true",
  failures
)
assert(
  capability_safety_floor.dig("l4_authority_gate", "gated_actions").to_a == L4_AUTHORITY_GATED_ACTIONS,
  "capability_safety_floor.l4_authority_gate.gated_actions 必須是 correction_proposal 與 promotion_proposal",
  failures
)

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

backlog = spec.fetch("backlog", {})
assert(sorted_set(backlog.keys) == sorted_set(EXPECTED_BACKLOG), "YAML backlog 必須是 EMEM_00～EMEM_08", failures)

[MAIN_DOC_PATH, BACKLOG_DOC_PATH].each do |path|
  ids = File.read(path).scan(/EMEM-\d{2}/).uniq.sort
  assert((EXPECTED_BACKLOG_DOC - ids).empty?, "#{File.basename(path)} 缺 #{(EXPECTED_BACKLOG_DOC - ids).join(", ")}", failures)
end

positive_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("cases")
negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("cases")
positive_resource_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("resource_cases")
negative_resource_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("resource_cases")
fixture_resource_indexes = build_indexes(positive_resource_cases + negative_resource_cases)

positive_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} positive fixture 必須預期 allow", failures)
  actual = evaluate_request(policy, test_case.fetch("request"))
  assert(actual == test_case.fetch("expected"), "#{test_case.fetch("case_id")} 預期 allow，實際 #{actual}", failures)
end

negative_cases.each do |test_case|
  assert(test_case.fetch("expected") == "deny", "#{test_case.fetch("case_id")} negative fixture 必須預期 deny", failures)
  actual = evaluate_request(policy, test_case.fetch("request"))
  assert(actual == test_case.fetch("expected"), "#{test_case.fetch("case_id")} 預期 deny，實際 #{actual}", failures)
end

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

required_negative_labels = sorted_set(spec.fetch("required_negative_fixtures", []))
covered_negative_labels = sorted_set(negative_cases.map { |test_case| test_case.fetch("covers_required_negative_fixture") })
missing_negative_labels = required_negative_labels - covered_negative_labels
assert(missing_negative_labels.empty?, "negative fixtures 未覆蓋：#{missing_negative_labels.to_a.join(", ")}", failures)

covered_resource_negative_labels = sorted_set(negative_resource_cases.map { |test_case| test_case.fetch("covers_resource_negative_fixture") })
missing_resource_negative_labels = sorted_set(EXPECTED_RESOURCE_NEGATIVE_LABELS) - covered_resource_negative_labels
assert(missing_resource_negative_labels.empty?, "resource negative fixtures 未覆蓋：#{missing_resource_negative_labels.to_a.join(", ")}", failures)

capability_profile_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("capability_profile_cases")
level_transition_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("level_transition_cases")
capability_profile_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("capability_profile_negative_cases")
level_transition_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("level_transition_negative_cases")

capability_profile_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} capability profile positive fixture 必須預期 allow", failures)
  actual = capability_profile_failure(test_case.fetch("profile"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

level_transition_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} level transition positive fixture 必須預期 allow", failures)
  actual = level_transition_failure(spec, test_case.fetch("transition"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

capability_profile_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} capability profile negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = capability_profile_failure(test_case.fetch("profile"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

level_transition_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} level transition negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = level_transition_failure(spec, test_case.fetch("transition"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_capability_negative_labels = sorted_set(
  (capability_profile_negative_cases + level_transition_negative_cases).map { |test_case| test_case.fetch("covers_capability_negative_fixture") }
)
missing_capability_negative_labels = sorted_set(EXPECTED_CAPABILITY_NEGATIVE_LABELS) - covered_capability_negative_labels
assert(missing_capability_negative_labels.empty?, "capability negative fixtures 未覆蓋：#{missing_capability_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS personal memory contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
