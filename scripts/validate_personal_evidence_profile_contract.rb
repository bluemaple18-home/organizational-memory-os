#!/usr/bin/env ruby
#
# EMEM-02 / SSP-291：Personal Evidence Profile 擷取准入契約 validator。
#
# 這支驗的是「這位員工的這筆擷取是否合法，以及它是否真的走了已驗收的 adapter mapping
# 落成同一份 RawEvidence」。所有可列舉值都在執行期從上游已鎖規格讀取，本檔不重述任何
# 清單；上游一改，判斷即跟著改，靠舊清單寫成的 fixture 會轉紅。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
CONTRACT_PATH = File.join(ROOT, "規格/v0.1/personal-evidence-profile.yaml")
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")

EXPECTED_FORBIDDEN_GRANTS = %w[
  CANONICAL_DIRECT_WRITE
  COMPANY_WIDE_SEARCH
  CROSS_EMPLOYEE_READ
  AUTO_PROMOTE_WITHOUT_REVIEW
].freeze

EXPECTED_EVIDENCE_PROFILE_NEGATIVE_LABELS = [
  "profile missing a required memory policy field",
  "profile group that is not an object",
  "consent or notice reference key absent from the profile",
  "policy reference present but blank",
  "profile claiming canonical direct write authority",
  "unknown role profile",
  "capability level outside the upstream levels",
  "scope mode outside the upstream modes",
  "ownership mode outside the upstream modes",
  "visibility scope outside the upstream scopes",
  "capture belonging to a different employee",
  "source type absent from the upstream source catalog",
  "source type outside the employee role profile",
  "phase-2 source captured before the policy contract is frozen",
  "source type with no active connector grant",
  "profile with no consent or notice reference",
  "capture from a source instance outside the capture scope",
  "projected source_system not produced by the bound adapter mapping",
  "projected source instance different from the declared capture",
  "consent reference that is boolean false rather than a reference",
  "consent reference that is whitespace only",
  "connector grant reference that is boolean false rather than a reference",
  "policy reference that is boolean false rather than a reference",
  "identity value that is not a string",
  "connector grant list that is not a list",
  "capture scope that is not an object",
  "connector grant list that is present but empty",
  "capture scope source instance list that is not a list",
  "capture scope container list that is not a list",
  "capture that names no source instance",
  "capture that names no container",
  "null container scope member matching a capture with no container",
  "null source instance scope member matching a capture with no source instance",
  "projected source system that is not a string",
  "projected source identity that is not an object",
  "projected source identity that names no source instance",
  "document source consent reference that is boolean false",
  "document source connector grant reference that is boolean false",
  "document source null scope member matching a capture with no source instance"
].freeze

# 上游 employee_memory_profile_minimum 的三個欄位群；本檔只讀 key，不重述欄位名。
PROFILE_FIELD_GROUPS = %w[identity source_policy memory_policy].freeze

# 執行期解析：把上游規格與 contract 的 *_path 轉成實際清單。
class UpstreamVocabulary
  attr_reader :roles, :source_catalog, :phase_sources, :capability_levels,
              :scope_modes, :ownership_modes, :visibility_scopes, :profile_fields

  def initialize(spec, contract)
    bindings = contract.fetch("upstream_bindings")
    @profile_fields = PROFILE_FIELD_GROUPS.each_with_object({}) do |group, acc|
      acc[group] = read_path(spec, "#{bindings.fetch("profile_shape_path")}/#{group}").to_a
    end
    @roles = read_path(spec, bindings.fetch("role_profiles_path")).keys.reject { |key| key == "rules" }
    @source_catalog = bindings.fetch("source_catalog_paths").flat_map { |path| read_path(spec, path).to_a }
    @phase_sources = read_path(spec, contract.dig("phase_gate", "admitted_source_types_ref")).to_a
    @capability_levels = read_path(spec, bindings.fetch("capability_levels_path")).keys.reject { |key| key == "same_contract_all_levels" }
    @scope_modes = read_path(spec, bindings.fetch("scope_modes_path")).to_a
    @ownership_modes = read_path(spec, bindings.fetch("ownership_modes_path")).keys
    @visibility_scopes = read_path(spec, bindings.fetch("visibility_scopes_path")).keys
  end

  def role_sources(spec, role)
    spec.dig("role_profiles", role, "likely_sources").to_a
  end
end

# adapter mapping 的 source_system 在執行期從那份 mapping spec 讀，不在本檔複寫。
def bound_adapter_source_system(contract, source_type)
  entry = contract.dig("adapter_mapping_binding", "admitted_source_adapters", source_type)
  return nil if entry.nil?

  mapping = read_yaml(File.join(ROOT, entry.fetch("mapping_spec")))
  read_path(mapping, entry.fetch("source_system_path"))
end

# --- 本卡自有的准入值約束 --------------------------------------------------
#
# SSP291-F-01：共用 present? 只排除 nil 與 empty?,因此 false、0、純空白字串、
# 非空 Array/Hash 都會被當成「存在」,它從未驗證那個值是不是一個 reference。
# 這裡刻意在本檔加入准入專用檢查,**不改共用 present? 的全域語意** ——
# 那會改動本輪未受審的其他呼叫端行為。
#
# reference 與識別值一律要求「非空白 String」。不造 URI scheme、不連外解析:
# 問題不在於 consent/grant 的內容是否屬實,而在於 false 根本不是一個 reference。
def admission_value?(value)
  value.is_a?(String) && !value.strip.empty?
end

# source_policy 這兩個欄位是容器,型別由本卡的准入形狀決定,不是上游列舉,
# 因此列在這裡不違反「零列舉重述」。
ADMISSION_CONTAINER_TYPES = { "connector_grants" => Array, "capture_scope" => Hash }.freeze

def active_grant?(grants, source_type)
  grants.to_a.any? do |grant|
    grant.is_a?(Hash) &&
      grant["source_type"] == source_type &&
      grant["status"] == "ACTIVE" &&
      admission_value?(grant["grant_ref"])
  end
end

def within_capture_scope?(scope, capture)
  return false unless scope.is_a?(Hash)

  instances = scope["source_instance_ids"]
  containers = scope["containers"]
  return false unless instances.is_a?(Array) && containers.is_a?(Array)

  # 「兩邊都缺值」不等於「擷取來自已授權的同一個來源/容器」:先要求 capture
  # 帶有合法識別值,否則 include?(nil) 會讓 null 與缺失欄位互相匹配。
  return false unless admission_value?(capture["source_instance_id"])
  return false unless admission_value?(capture["container"])

  instances.include?(capture["source_instance_id"]) && containers.include?(capture["container"])
end

# 回傳 nil 代表這筆擷取通過准入；否則回傳精確的 machine failure code。
# 判斷順序即 contract 的 evaluation_order。
def evidence_profile_failure(spec, contract, vocabulary, test_case)
  profile = test_case.fetch("profile", {})
  capture = test_case.fetch("capture", {})

  PROFILE_FIELD_GROUPS.each do |group|
    group_value = profile[group]
    return "EPROFILE_PROFILE_FIELD_MISSING" unless group_value.is_a?(Hash)

    vocabulary.profile_fields.fetch(group).each do |field|
      return "EPROFILE_PROFILE_FIELD_MISSING" unless group_value.key?(field)

      container_type = ADMISSION_CONTAINER_TYPES[field]
      if container_type
        container = group_value[field]
        return "EPROFILE_PROFILE_FIELD_MISSING" unless container.is_a?(container_type) && !container.empty?

        next
      end

      next if field == "consent_or_notice_ref" # 語意檢查排在 evaluation_order 的授權段之後
      return "EPROFILE_PROFILE_FIELD_MISSING" unless admission_value?(group_value[field])
    end
  end

  granted = profile.fetch("granted_authorities", []).to_a
  forbidden = contract.dig("authority_floor", "forbidden_profile_grants").to_a
  return "EPROFILE_EXCEEDS_AUTHORITY" if granted.any? { |authority| forbidden.include?(authority) }

  identity = profile.fetch("identity")
  memory_policy = profile.fetch("memory_policy")
  role = identity.fetch("role_profile")
  return "EPROFILE_UNKNOWN_ROLE_PROFILE" unless vocabulary.roles.include?(role)
  return "EPROFILE_INVALID_CAPABILITY_LEVEL" unless vocabulary.capability_levels.include?(memory_policy["capability_level"])
  return "EPROFILE_INVALID_SCOPE_MODE" unless vocabulary.scope_modes.include?(memory_policy["personal_scope_mode"])
  return "EPROFILE_INVALID_OWNERSHIP_MODE" unless vocabulary.ownership_modes.include?(memory_policy["ownership_mode"])
  return "EPROFILE_INVALID_VISIBILITY_SCOPE" unless vocabulary.visibility_scopes.include?(memory_policy["visibility_scope"])

  if capture["tenant_id"] != identity["tenant_id"] || capture["employee_id"] != identity["employee_id"]
    return "EPROFILE_TENANT_OR_EMPLOYEE_MISMATCH"
  end

  source_type = capture["source_type"]
  return "EPROFILE_SOURCE_NOT_DECLARED" unless vocabulary.source_catalog.include?(source_type)
  return "EPROFILE_SOURCE_NOT_IN_ROLE_PROFILE" unless vocabulary.role_sources(spec, role).include?(source_type)
  return "EPROFILE_SOURCE_NOT_IN_PHASE_1" unless vocabulary.phase_sources.include?(source_type)

  source_policy = profile.fetch("source_policy")
  return "EPROFILE_NO_CONNECTOR_GRANT" unless active_grant?(source_policy["connector_grants"], source_type)
  return "EPROFILE_NO_CONSENT_OR_NOTICE" unless admission_value?(source_policy["consent_or_notice_ref"])
  return "EPROFILE_OUTSIDE_CAPTURE_SCOPE" unless within_capture_scope?(source_policy["capture_scope"], capture)

  # phase gate 與結構斷言已保證每個可通過的來源都有綁定 mapping，故此處不再有未綁定分支。
  source_system = bound_adapter_source_system(contract, source_type)
  # projected identity 不另設型別 guard:右手邊兩個值都已被保證是合法識別值 ——
  # source_system 由結構斷言要求 mapping 必須提供非空值,capture 的 source_instance_id
  # 由 within_capture_scope? 要求為非空白字串。因此相等比較本身就會拒絕 nil/false/錯型別,
  # 額外的型別 guard 會是永遠踩不到的死分支。若日後鬆動任一前提,這裡必須同步補回。
  projected = capture["projected_source_identity"]
  projected = {} unless projected.is_a?(Hash)
  return "EPROFILE_ADAPTER_MAPPING_MISMATCH" unless projected["source_system"] == source_system
  return "EPROFILE_PROJECTED_IDENTITY_INCONSISTENT" unless projected["source_instance_id"] == capture["source_instance_id"]

  nil
end

# 掃描本檔 evaluator 實際可回傳的 code 字面量。SSP-302 TIGHTEN-F-01 的教訓：
# 用兩份手寫清單互比證明不了 evaluator，必須從原始碼取事實。
def reachable_failure_codes
  source = File.read(__FILE__)
  body = source[/^def evidence_profile_failure.*?^end$/m].to_s
  body.scan(/return "([A-Z][A-Z0-9_]*)"/).flatten.uniq
end

failures = []
contract = read_yaml(CONTRACT_PATH)
spec = read_yaml(SPEC_PATH)

# --- 契約結構斷言 ---------------------------------------------------------

assert(contract["contract_id"] == "personal-evidence-profile-v0.1", "contract_id 必須是 personal-evidence-profile-v0.1", failures)
assert(contract["requirement_id"] == "EMEM02-S01", "requirement_id 必須是 EMEM02-S01", failures)

bindings = contract.fetch("upstream_bindings", {})
assert(bindings["personal_harness_spec"] == "規格/v0.1/personal-harness-integration.yaml", "upstream_bindings 必須指向 personal-harness-integration.yaml", failures)
%w[profile_shape_path role_profiles_path phase_gate_path capability_levels_path scope_modes_path ownership_modes_path visibility_scopes_path].each do |key|
  assert(present?(bindings[key]), "upstream_bindings.#{key} 必須存在", failures)
  assert(!read_path(spec, bindings[key]).nil?, "upstream_bindings.#{key} 必須在上游規格解析得到（#{bindings[key]}）", failures)
end
assert(bindings.fetch("source_catalog_paths", []).to_a.length == 2, "source_catalog_paths 必須涵蓋 universal 與 advanced 兩份上游清單", failures)
bindings.fetch("source_catalog_paths", []).to_a.each do |path|
  assert(!read_path(spec, path).nil?, "source_catalog_paths #{path} 必須在上游規格解析得到", failures)
end
assert(present?(bindings["rule"]), "upstream_bindings.rule 必須說明執行期讀取而非重述", failures)

# 本檔不得重述上游列舉：只允許 PROFILE_FIELD_GROUPS 這三個群組名。
contract_text = File.read(CONTRACT_PATH)
(vocab_probe = read_path(spec, "source_profiles/universal_examples").to_a).each do |source_type|
  assert(!contract_text.include?(source_type) || contract.dig("adapter_mapping_binding", "admitted_source_adapters").to_h.key?(source_type),
         "contract 不得重述上游 source 清單（#{source_type} 只能以 adapter binding 出現）", failures)
end
assert(!vocab_probe.empty?, "上游 source_profiles.universal_examples 不得為空", failures)

phase_gate = contract.fetch("phase_gate", {})
assert(phase_gate["active_phase"] == "PHASE_1", "phase_gate.active_phase 必須是 PHASE_1", failures)
assert(phase_gate["admitted_source_types_ref"] == "phase_1_pilot/first_sources", "phase gate 必須綁上游 phase_1_pilot.first_sources", failures)
assert(phase_gate["deferred_source_types_ref"] == "phase_1_pilot/next_sources_if_policy_ready", "phase gate 必須宣告 deferred 來源出處", failures)
assert(present?(phase_gate["rule"]), "phase_gate.rule 必須說明 fail-closed 理由", failures)

adapters = contract.dig("adapter_mapping_binding", "admitted_source_adapters").to_h
assert(!adapters.empty?, "adapter_mapping_binding.admitted_source_adapters 不得為空", failures)
phase_sources = read_path(spec, "phase_1_pilot/first_sources").to_a
assert(sorted_set(adapters.keys) == sorted_set(phase_sources), "每個 phase-1 來源都必須綁定一份 adapter mapping，且不得多綁", failures)
adapters.each do |source_type, entry|
  mapping_path = File.join(ROOT, entry.fetch("mapping_spec"))
  assert(File.exist?(mapping_path), "#{source_type} 綁定的 adapter mapping 檔不存在：#{entry["mapping_spec"]}", failures)
  next unless File.exist?(mapping_path)

  source_system = read_path(read_yaml(mapping_path), entry.fetch("source_system_path"))
  assert(present?(source_system), "#{source_type} 的 adapter mapping 必須在 #{entry["source_system_path"]} 提供 source_system", failures)
  assert(!contract_text.include?("\"#{source_system}\"") && !contract_text.match?(/^\s*source_system:\s*#{Regexp.escape(source_system.to_s)}\s*$/),
         "#{source_type} 的 source_system 必須執行期讀取，不得複寫進本契約", failures)
end
assert(contract.dig("adapter_mapping_binding", "rule").to_s.include?("ALL_SOURCES_MAP_TO_SAME_RAW_EVIDENCE_CONTRACT"),
       "adapter_mapping_binding.rule 必須承接上游 source_profiles.rule", failures)
assert(read_path(spec, "source_profiles/rule") == "ALL_SOURCES_MAP_TO_SAME_RAW_EVIDENCE_CONTRACT",
       "上游 source_profiles.rule 必須維持 ALL_SOURCES_MAP_TO_SAME_RAW_EVIDENCE_CONTRACT", failures)

assert(
  sorted_set(contract.dig("authority_floor", "forbidden_profile_grants").to_a) == sorted_set(EXPECTED_FORBIDDEN_GRANTS),
  "authority_floor.forbidden_profile_grants 必須剛好是四項鎖定禁止授權",
  failures
)
assert(present?(contract.dig("authority_floor", "rule")), "authority_floor.rule 必須存在", failures)
assert(present?(contract.dig("identity_binding", "rule")), "identity_binding.rule 必須存在", failures)
constraints = contract.fetch("admission_value_constraints", {})
%w[reference_fields_rule identifier_values_rule container_fields_rule shared_helper_rule].each do |key|
  assert(present?(constraints[key]), "admission_value_constraints.#{key} 必須存在（SSP291-F-01）", failures)
end

assert(contract.fetch("evaluation_order", []).to_a.length == 12, "evaluation_order 必須逐項列出十二段判斷", failures)

# --- error_contract 由原始碼綁定 ------------------------------------------

declared_codes = contract.fetch("error_contract", {}).keys
reachable_codes = reachable_failure_codes
assert(!reachable_codes.empty?, "無法從 evaluator 原始碼取得可回傳 code，掃描失效", failures)
assert(
  sorted_set(declared_codes) == sorted_set(reachable_codes),
  "error_contract 與 evaluator 實際可回傳 code 不符：僅宣告 #{(sorted_set(declared_codes) - sorted_set(reachable_codes)).to_a.join(", ")}；僅可回傳 #{(sorted_set(reachable_codes) - sorted_set(declared_codes)).to_a.join(", ")}",
  failures
)
contract.fetch("error_contract", {}).each do |code, meaning|
  assert(present?(meaning), "error_contract.#{code} 必須說明語意", failures)
end

assert(
  sorted_set(contract.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_EVIDENCE_PROFILE_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定負例清單不符",
  failures
)

# --- fixture 驗證 ----------------------------------------------------------

vocabulary = UpstreamVocabulary.new(spec, contract)
positive_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("evidence_profile_cases")
negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("evidence_profile_negative_cases")

assert(!positive_cases.empty?, "evidence_profile_cases 不得為空", failures)
positive_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} positive fixture 必須預期 allow", failures)
  actual = evidence_profile_failure(spec, contract, vocabulary, test_case)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

# 正例必須真的覆蓋兩個 phase-1 來源，否則 adapter binding 只有一條路被走過。
covered_sources = sorted_set(positive_cases.map { |test_case| test_case.dig("capture", "source_type") })
assert(covered_sources == sorted_set(phase_sources), "positive fixtures 必須覆蓋全部 phase-1 來源：#{phase_sources.join(", ")}", failures)

negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code), "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = evidence_profile_failure(spec, contract, vocabulary, test_case)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative_cases.map { |test_case| test_case.fetch("covers_evidence_profile_negative_fixture") })
missing_labels = sorted_set(EXPECTED_EVIDENCE_PROFILE_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "evidence profile negative fixtures 未覆蓋：#{missing_labels.to_a.join(", ")}", failures)

# 每個可回傳 code 都必須有負例踩到，否則 evaluator 有無人走過的分支。
covered_codes = sorted_set(negative_cases.map { |test_case| test_case.fetch("expected_failure_code") })
uncovered_codes = sorted_set(reachable_codes) - covered_codes
assert(uncovered_codes.empty?, "以下 failure code 沒有任何負例覆蓋：#{uncovered_codes.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS personal evidence profile contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
