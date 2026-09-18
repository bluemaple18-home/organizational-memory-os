#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-324（EMEM-10）切片 A：Minimal Evidence Package 的封包邊界與
# reverse-access 邊界。
#
# 驗證單位是一次「傳輸事件」：公司端用某個 access_request 取得某個
# package。兩半必須一起驗，因為「公司只能拿到明確送出的封包」這句話同時
# 是封包形狀問題（裡面能放什麼）與取得路徑問題（怎麼拿到的）——只驗其中
# 一半，另一半就是宣稱。
#
# 不重述既有 authority：
#   - scope_mode 對應的 ownership_mode／visibility_scope／consent 要求，
#     全部在評估當下讀 `ownership_visibility_contract.mode_definitions`；
#     package 只宣告自己屬於哪個 mode，數值必須跟上游對得上，不是自報。
#   - consent 是否必要，讀上游該 mode 的 consent_or_notice_required，
#     不把「EMPLOYEE_PRIVATE 才要 consent」寫死在這裡。
#   - candidate_ref 綁 `personal_memory_resource_contracts` 的
#     id_templates.PersonalMemoryCandidate。
#   - SSP-294 的 promotion gate／policy matrix／ACL ceiling 完全不動，本片
#     只管封包本身，不決定能不能 promote。
#
# 這片同時收掉 SSP-323 切片 3 review 留下的 P2：`runtime_policy.
# local_first_export_surface` 原本只是一個封閉列舉宣告，沒有任何機器
# enforcement 說明「minimal_evidence_package」這個管道實際上長什麼樣、
# 不能被當成 browse/search/pull 用。本片就是那一項的 enforcement。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/minimal-evidence-package-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json")
VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
STD01_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")

EVIDENCE_KIND = "EVIDENCE_RECORD"
SOURCE_ANCHOR_KIND = "SOURCE_ANCHOR"

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

def blank?(value)
  !value.is_a?(String) || value.strip.empty?
end

# canonical ref = common-vocabulary 的 ref_template + resource_kinds 詞彙。
# 兩者都在評估當下讀上游，這裡不手抄 URN 結構。
def kebab(kind)
  kind.to_s.downcase.tr("_", "-")
end

def canonical_ref?(value, allowed_kinds)
  return false unless value.is_a?(String)

  allowed_kinds.any? { |kind| CANONICAL_REF_PATTERNS[kind]&.match?(value) }
end

def build_canonical_ref_pattern(ref_template, kind)
  uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
  literal = Regexp.escape(ref_template).sub(Regexp.escape("{resource-kind}"), Regexp.escape(kebab(kind)))
                                       .sub(Regexp.escape("{uuid}"), uuid)
  /\A#{literal}\z/
end

ALLOWED_REQUEST_KINDS = %w[PACKAGE_LOOKUP].freeze
FORBIDDEN_REQUEST_KINDS = %w[BROWSE SEARCH PULL REMOTE_QUERY REMOTE_MOUNT].freeze
ALLOWED_REQUEST_FIELDS = %w[request_kind package_ref].freeze

PACKAGE_REQUIRED_FIELDS = %w[
  package_id tenant_id employee_owner_ref candidate_ref scope_mode
  ownership_mode visibility_scope sensitivity consent_ref content_snapshot
  content_hash evidence_refs source_anchor_refs provenance_chain_refs
  source_acl_snapshot_ref redaction_ref organizational_value_reasons
  unresolved_question suggested_expert submitted_at
].freeze

PACKAGE_FORBIDDEN_FIELDS = %w[
  full_personal_store_ref personal_store_snapshot weekly_work_summary
  candidate_status record_status verification_status acceptance_status
  conflict_resolution_status
].freeze

# 只能驗到「generic omos URN」的欄位：org 端 identity（tenant／employee／
# consent／redaction），不是 OMOS canonical resource，上游沒有對應 kind。
URN_FIELDS = %w[package_id employee_owner_ref].freeze
# 必為「非空陣列」的 ref 清單欄位（元素形狀另外依 ref_binding 逐欄驗）。
REF_LIST_FIELDS = %w[evidence_refs source_anchor_refs provenance_chain_refs].freeze
# 必為非空字串的欄位。
TEXT_FIELDS = %w[tenant_id sensitivity content_snapshot content_hash submitted_at].freeze
# 可為 null，但若有值必須是字串的欄位（形狀鎖，不接受 Hash／Array 夾帶）。
NULLABLE_STRING_FIELDS = %w[consent_ref redaction_ref unresolved_question suggested_expert].freeze

EXPECTED_NEGATIVE_LABELS = [
  "an access_request that is not a map",
  "an access_request naming a forbidden request kind",
  "an access_request carrying a field outside the allowlist",
  "an access_request package_ref that is not an omos URN",
  "a package that is not a map",
  "a package missing a required field",
  "a package carrying a forbidden field",
  "a package carrying a field outside the allowlist",
  "a package_id that does not match the requested package_ref",
  "a single-value ref field that is not an omos URN",
  "a candidate_ref that is not a PersonalMemoryCandidate identity",
  "a ref list field that is not a non-empty array",
  "an evidence_ref that is not a canonical EVIDENCE_RECORD ref",
  "a source_anchor_ref that is not a canonical SOURCE_ANCHOR ref",
  "a provenance_chain_ref that is not a canonical omos resource ref",
  "a source_acl_snapshot_ref that does not match the STD-01 acl_snapshot_ref pattern",
  "a content_snapshot over the declared byte bound",
  "a content_hash that is not a sha256 serialization",
  "a content_hash that does not match the recomputed digest of content_snapshot",
  "a scope_mode not declared in ownership_visibility_contract.mode_definitions",
  "an ownership_mode that disagrees with the upstream mode definition",
  "a visibility_scope that disagrees with the upstream mode definition",
  "a consent-requiring scope_mode with no consent_ref",
  "a text field that is blank or not a string",
  "a nullable field present but not a string",
  "organizational_value_reasons that is not a non-empty array of non-blank strings"
].freeze

# --- 結構驗證（fail-closed）------------------------------------------------

def transmission_failure(run, mode_definitions, candidate_ref_prefix, all_resource_kinds,
                         acl_snapshot_pattern, max_content_bytes)
  request = run["access_request"]
  return "MEP_ACCESS_REQUEST_NOT_MAP" unless request.is_a?(Hash)
  return "MEP_FORBIDDEN_ACCESS_KIND" unless ALLOWED_REQUEST_KINDS.include?(request["request_kind"])
  return "MEP_ACCESS_REQUEST_UNKNOWN_FIELD" unless (request.keys - ALLOWED_REQUEST_FIELDS).empty?
  return "MEP_PACKAGE_REF_NOT_URN" unless urn?(request["package_ref"])

  package = run["package"]
  return "MEP_PACKAGE_NOT_MAP" unless package.is_a?(Hash)
  return "MEP_REQUIRED_FIELD_MISSING" unless PACKAGE_REQUIRED_FIELDS.all? { |f| package.key?(f) }
  return "MEP_FORBIDDEN_FIELD_PRESENT" if PACKAGE_FORBIDDEN_FIELDS.any? { |f| package.key?(f) }
  # repair-01：required_fields 同時就是完整 allowlist——禁用清單只擋得住已經
  # 想到的名字，改個欄位名就能把 whole-store material 帶進來。
  return "MEP_PACKAGE_UNKNOWN_FIELD" unless (package.keys - PACKAGE_REQUIRED_FIELDS).empty?
  # bounded lookup 不能被拿來換一個別的封包。
  return "MEP_PACKAGE_REF_MISMATCH" unless package["package_id"] == request["package_ref"]

  return "MEP_REF_FIELD_NOT_URN" unless URN_FIELDS.all? { |f| urn?(package[f]) }
  return "MEP_CANDIDATE_REF_NOT_CANDIDATE" unless package["candidate_ref"].is_a?(String) &&
                                                  package["candidate_ref"].start_with?(candidate_ref_prefix)
  return "MEP_REF_LIST_NOT_ARRAY" unless REF_LIST_FIELDS.all? { |f| package[f].is_a?(Array) && !package[f].empty? }

  # repair-01：ref 不再只驗「是某種 omos URN」，而是綁上游真正定義它的形狀。
  return "MEP_EVIDENCE_REF_NOT_CANONICAL" unless package["evidence_refs"].all? { |r| canonical_ref?(r, [EVIDENCE_KIND]) }
  return "MEP_SOURCE_ANCHOR_REF_NOT_CANONICAL" unless package["source_anchor_refs"].all? { |r| canonical_ref?(r, [SOURCE_ANCHOR_KIND]) }
  return "MEP_PROVENANCE_REF_NOT_CANONICAL" unless package["provenance_chain_refs"].all? { |r| canonical_ref?(r, all_resource_kinds) }
  return "MEP_ACL_SNAPSHOT_REF_NOT_CANONICAL" unless package["source_acl_snapshot_ref"].is_a?(String) &&
                                                     acl_snapshot_pattern.match?(package["source_acl_snapshot_ref"])

  return "MEP_TEXT_FIELD_BLANK" if TEXT_FIELDS.any? { |f| blank?(package[f]) }
  return "MEP_NULLABLE_FIELD_NOT_STRING" if NULLABLE_STRING_FIELDS.any? { |f| !package[f].nil? && !package[f].is_a?(String) }

  reasons = package["organizational_value_reasons"]
  # repair-01：any? 改成 all?——只要有一個非空字串就放行，等於其餘元素可以是
  # 任意 nested payload。
  return "MEP_VALUE_REASONS_EMPTY" unless reasons.is_a?(Array) && !reasons.empty? && reasons.all? { |r| !blank?(r) }

  # repair-01：bounded content + 真正可驗的 integrity。
  content = package["content_snapshot"]
  return "MEP_CONTENT_SNAPSHOT_OVER_BOUND" if content.bytesize > max_content_bytes
  return "MEP_CONTENT_HASH_NOT_SHA256" unless SHA256_LOCKED_PATTERN.match?(package["content_hash"].to_s)
  return "MEP_CONTENT_HASH_MISMATCH" unless package["content_hash"] == "sha256:#{Digest::SHA256.hexdigest(content)}"

  scope_mode = package["scope_mode"]
  mode = mode_definitions[scope_mode]
  return "MEP_UNKNOWN_SCOPE_MODE" unless mode.is_a?(Hash)

  # governance 不是自報：宣告了 scope_mode，數值就必須等於上游對那個 mode
  # 的定義。
  return "MEP_OWNERSHIP_MODE_MISMATCH" unless package["ownership_mode"] == mode["ownership_mode"]
  return "MEP_VISIBILITY_SCOPE_MISMATCH" unless package["visibility_scope"] == mode["visibility_scope"]

  # 是否需要 consent 讀上游那個 mode 的宣告，不把 mode 名稱寫死在這裡。
  if mode["consent_or_notice_required"] == "CONSENT_REQUIRED"
    return "MEP_CONSENT_REQUIRED_BUT_MISSING" if blank?(package["consent_ref"])
  end

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
mep = spec.fetch("minimal_evidence_package")

access_boundary = mep.fetch("access_boundary", {})
assert(access_boundary.fetch("allowed_request_kinds", []) == ALLOWED_REQUEST_KINDS,
       "minimal_evidence_package.access_boundary.allowed_request_kinds 必須剛好是 #{ALLOWED_REQUEST_KINDS.inspect}", failures)
assert(sorted_set(access_boundary.fetch("forbidden_request_kinds", [])) == sorted_set(FORBIDDEN_REQUEST_KINDS),
       "forbidden_request_kinds 與鎖定清單不符", failures)
assert(sorted_set(access_boundary.fetch("allowed_request_fields", [])) == sorted_set(ALLOWED_REQUEST_FIELDS),
       "allowed_request_fields 與鎖定清單不符", failures)
assert((ALLOWED_REQUEST_KINDS.to_set & FORBIDDEN_REQUEST_KINDS.to_set).empty?,
       "allowed 與 forbidden request kind 不得重疊", failures)
assert(sorted_set(mep.fetch("package_required_fields", [])) == sorted_set(PACKAGE_REQUIRED_FIELDS),
       "package_required_fields 與鎖定清單不符", failures)
assert(sorted_set(mep.fetch("package_forbidden_fields", [])) == sorted_set(PACKAGE_FORBIDDEN_FIELDS),
       "package_forbidden_fields 與鎖定清單不符", failures)

# 切片 3 的 P2 收斂點：本契約必須真的是 local_first_export_surface 裡
# minimal_evidence_package 那一項的 enforcement，不是各說各話的兩份宣告。
export_surface = spec.dig("runtime_policy", "local_first_export_surface") || []
assert(export_surface.include?("minimal_evidence_package"),
       "runtime_policy.local_first_export_surface 必須含 minimal_evidence_package（本契約是它的 enforcement）", failures)

mode_definitions = spec.dig("ownership_visibility_contract", "mode_definitions") || {}
assert(mode_definitions.any?, "ownership_visibility_contract.mode_definitions 必須存在（本片綁定它，不重述）", failures)
assert(mode_definitions.values.any? { |m| m.is_a?(Hash) && m["consent_or_notice_required"] == "CONSENT_REQUIRED" },
       "至少要有一個 mode 宣告 CONSENT_REQUIRED，否則 consent 規則無從綁定", failures)

# --- 上游 ref 形狀綁定（repair-01）----------------------------------------
vocab = read_yaml(VOCAB_PATH)
all_resource_kinds = vocab.fetch("resource_kinds", [])
ref_template = vocab.dig("identifiers", "omos_generated", "ref_template")
assert(all_resource_kinds.any?, "common-vocabulary.resource_kinds 必須存在（本片綁定它，不重述）", failures)
assert(ref_template.is_a?(String) && ref_template.include?("{resource-kind}") && ref_template.include?("{uuid}"),
       "common-vocabulary.identifiers.omos_generated.ref_template 必須存在且含兩個 placeholder", failures)
[EVIDENCE_KIND, SOURCE_ANCHOR_KIND].each do |kind|
  assert(all_resource_kinds.include?(kind), "common-vocabulary.resource_kinds 必須含 #{kind}（本片 pin 它）", failures)
end
CANONICAL_REF_PATTERNS = all_resource_kinds.each_with_object({}) do |kind, acc|
  acc[kind] = build_canonical_ref_pattern(ref_template.to_s, kind)
end.freeze

# acl_snapshot_ref 的 pattern 直接取自 STD-01 schema，不手抄——與
# validate_permission_retention_deletion_contract.rb 綁的是同一個來源。
std01 = read_json(STD01_SCHEMA_PATH)
acl_pattern_source = std01.dig("properties", "access", "properties", "acl_snapshot_ref", "pattern")
assert(acl_pattern_source.is_a?(String) && !acl_pattern_source.empty?,
       "STD-01 的 access.acl_snapshot_ref.pattern 必須存在（本片綁定它，不重述）", failures)
acl_snapshot_pattern = Regexp.new(acl_pattern_source.to_s)
assert(mep.dig("ref_binding", "acl_snapshot_pattern_source").to_s.include?("raw-evidence-envelope.schema.json"),
       "ref_binding.acl_snapshot_pattern_source 必須指向 STD-01 schema", failures)
assert(mep.dig("ref_binding", "evidence_refs") == EVIDENCE_KIND &&
       mep.dig("ref_binding", "source_anchor_refs") == SOURCE_ANCHOR_KIND,
       "ref_binding 宣告的 pinned kind 必須與 evaluator 實際 pin 的一致", failures)

max_content_bytes = mep.dig("content_bound", "max_bytes")
assert(max_content_bytes.is_a?(Integer) && max_content_bytes.positive?,
       "minimal_evidence_package.content_bound.max_bytes 必須是正整數（policy 住在契約，不在 evaluator）", failures)
assert(mep.dig("content_hash_basis", "algorithm") == "SHA256",
       "content_hash_basis.algorithm 必須是 SHA256（evaluator 依此重算）", failures)

candidate_id_template = spec.dig("personal_memory_resource_contracts", "shared_constraints", "id_templates",
                                  "PersonalMemoryCandidate")
assert(candidate_id_template.is_a?(String) && candidate_id_template.include?("{"),
       "id_templates.PersonalMemoryCandidate 必須存在（本片綁定它，不重述）", failures)
candidate_ref_prefix = candidate_id_template.to_s.split("{").first

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = transmission_failure(run, mode_definitions, candidate_ref_prefix, all_resource_kinds,
                                       acl_snapshot_pattern, max_content_bytes)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = transmission_failure(run, mode_definitions, candidate_ref_prefix, all_resource_kinds,
                                       acl_snapshot_pattern, max_content_bytes)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 卡片 Acceptance #3：每一種 forbidden request kind 都必須有負例實際打過，
# 不能只宣告在 YAML 裡。
covered_forbidden_kinds = sorted_set(
  negative_cases.map { |c|
    request = c.dig("run", "access_request")
    request.is_a?(Hash) ? request["request_kind"] : nil
  }.compact & FORBIDDEN_REQUEST_KINDS
)
missing_kinds = sorted_set(FORBIDDEN_REQUEST_KINDS) - covered_forbidden_kinds
assert(missing_kinds.empty?, "forbidden request kind 未被負例實際打過：#{missing_kinds.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
ERROR_CONTRACT = {
  "MEP_ACCESS_REQUEST_NOT_MAP" => "minimal_evidence_package.error.access_request_not_map",
  "MEP_FORBIDDEN_ACCESS_KIND" => "minimal_evidence_package.error.forbidden_access_kind",
  "MEP_ACCESS_REQUEST_UNKNOWN_FIELD" => "minimal_evidence_package.error.access_request_unknown_field",
  "MEP_PACKAGE_REF_NOT_URN" => "minimal_evidence_package.error.package_ref_not_urn",
  "MEP_PACKAGE_NOT_MAP" => "minimal_evidence_package.error.package_not_map",
  "MEP_REQUIRED_FIELD_MISSING" => "minimal_evidence_package.error.required_field_missing",
  "MEP_FORBIDDEN_FIELD_PRESENT" => "minimal_evidence_package.error.forbidden_field_present",
  "MEP_PACKAGE_REF_MISMATCH" => "minimal_evidence_package.error.package_ref_mismatch",
  "MEP_PACKAGE_UNKNOWN_FIELD" => "minimal_evidence_package.error.package_unknown_field",
  "MEP_REF_FIELD_NOT_URN" => "minimal_evidence_package.error.ref_field_not_urn",
  "MEP_CANDIDATE_REF_NOT_CANDIDATE" => "minimal_evidence_package.error.candidate_ref_not_candidate",
  "MEP_REF_LIST_NOT_ARRAY" => "minimal_evidence_package.error.ref_list_not_array",
  "MEP_EVIDENCE_REF_NOT_CANONICAL" => "minimal_evidence_package.error.evidence_ref_not_canonical",
  "MEP_SOURCE_ANCHOR_REF_NOT_CANONICAL" => "minimal_evidence_package.error.source_anchor_ref_not_canonical",
  "MEP_PROVENANCE_REF_NOT_CANONICAL" => "minimal_evidence_package.error.provenance_ref_not_canonical",
  "MEP_ACL_SNAPSHOT_REF_NOT_CANONICAL" => "minimal_evidence_package.error.acl_snapshot_ref_not_canonical",
  "MEP_CONTENT_SNAPSHOT_OVER_BOUND" => "minimal_evidence_package.error.content_snapshot_over_bound",
  "MEP_CONTENT_HASH_NOT_SHA256" => "minimal_evidence_package.error.content_hash_not_sha256",
  "MEP_CONTENT_HASH_MISMATCH" => "minimal_evidence_package.error.content_hash_mismatch",
  "MEP_TEXT_FIELD_BLANK" => "minimal_evidence_package.error.text_field_blank",
  "MEP_NULLABLE_FIELD_NOT_STRING" => "minimal_evidence_package.error.nullable_field_not_string",
  "MEP_VALUE_REASONS_EMPTY" => "minimal_evidence_package.error.value_reasons_empty",
  "MEP_UNKNOWN_SCOPE_MODE" => "minimal_evidence_package.error.unknown_scope_mode",
  "MEP_OWNERSHIP_MODE_MISMATCH" => "minimal_evidence_package.error.ownership_mode_mismatch",
  "MEP_VISIBILITY_SCOPE_MISMATCH" => "minimal_evidence_package.error.visibility_scope_mismatch",
  "MEP_CONSENT_REQUIRED_BUT_MISSING" => "minimal_evidence_package.error.consent_required_but_missing"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "transmission_failure")
assert(violations.empty?, "transmission_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "transmission_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS minimal evidence package contract validation (package_fields=#{PACKAGE_REQUIRED_FIELDS.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
