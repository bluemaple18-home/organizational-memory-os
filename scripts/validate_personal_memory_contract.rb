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

EXPECTED_BACKLOG = (0..8).map { |number| format("EMEM_%02d", number) }.freeze
EXPECTED_BACKLOG_DOC = EXPECTED_BACKLOG.map { |item| item.tr("_", "-") }.freeze
VALID_DECISIONS = %w[ALLOW DENY CONDITIONAL].freeze

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

backlog = spec.fetch("backlog", {})
assert(sorted_set(backlog.keys) == sorted_set(EXPECTED_BACKLOG), "YAML backlog 必須是 EMEM_00～EMEM_08", failures)

[MAIN_DOC_PATH, BACKLOG_DOC_PATH].each do |path|
  ids = File.read(path).scan(/EMEM-\d{2}/).uniq.sort
  assert((EXPECTED_BACKLOG_DOC - ids).empty?, "#{File.basename(path)} 缺 #{(EXPECTED_BACKLOG_DOC - ids).join(", ")}", failures)
end

positive_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("cases")
negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("cases")

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

required_negative_labels = sorted_set(spec.fetch("required_negative_fixtures", []))
covered_negative_labels = sorted_set(negative_cases.map { |test_case| test_case.fetch("covers_required_negative_fixture") })
missing_negative_labels = required_negative_labels - covered_negative_labels
assert(missing_negative_labels.empty?, "negative fixtures 未覆蓋：#{missing_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS personal memory contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
