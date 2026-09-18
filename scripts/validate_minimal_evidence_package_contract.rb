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
require_relative "lib/minimal_evidence_package_shape"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/minimal-evidence-package-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json")
VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
STD01_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")

EVIDENCE_KIND = "EVIDENCE_RECORD"
SOURCE_ANCHOR_KIND = "SOURCE_ANCHOR"

MEPShape = MinimalEvidencePackageShape

ALLOWED_REQUEST_KINDS = %w[PACKAGE_LOOKUP].freeze
FORBIDDEN_REQUEST_KINDS = %w[BROWSE SEARCH PULL REMOTE_QUERY REMOTE_MOUNT].freeze
ALLOWED_REQUEST_FIELDS = %w[request_kind package_ref].freeze

# 封包形狀（required／forbidden 清單、ref 綁定、content bound／hash）全部住在
# scripts/lib/minimal_evidence_package_shape.rb，與切片 B 共用同一份實作。
PACKAGE_REQUIRED_FIELDS = MEPShape::PACKAGE_REQUIRED_FIELDS
PACKAGE_FORBIDDEN_FIELDS = MEPShape::PACKAGE_FORBIDDEN_FIELDS

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
  "a package_id that is not an evidence package identity",
  "a candidate_ref that is not a PersonalMemoryCandidate identity",
  "a ref list field that is not a non-empty array",
  "an evidence_ref that is not a canonical EVIDENCE_RECORD ref",
  "a source_anchor_ref that is not a canonical SOURCE_ANCHOR ref",
  "a provenance_chain_ref that is not a canonical omos resource ref",
  "a source_acl_snapshot_ref that does not match the STD-01 acl_snapshot_ref pattern",
  "an evidence_ref whose identity is not the upstream-declared UUID version",
  "a source_anchor_ref whose identity is not the upstream-declared UUID version",
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

# 取得路徑（access_request）留在本片；封包本身交給共用 evaluator
# （MEPShape.package_failure，切片 B 呼叫的是同一支）。兩段都各自受
# LoopReturnContract 的出口形狀凍結約束，組合順序與 repair-01 前逐條相同。
def access_request_failure(request)
  return "MEP_ACCESS_REQUEST_NOT_MAP" unless request.is_a?(Hash)
  return "MEP_FORBIDDEN_ACCESS_KIND" unless ALLOWED_REQUEST_KINDS.include?(request["request_kind"])
  return "MEP_ACCESS_REQUEST_UNKNOWN_FIELD" unless (request.keys - ALLOWED_REQUEST_FIELDS).empty?
  return "MEP_PACKAGE_REF_NOT_URN" unless MEPShape.urn?(request["package_ref"])

  nil
end

def transmission_failure(run, bindings)
  request = run["access_request"]
  request_failure = access_request_failure(request)
  return request_failure unless request_failure.nil?

  MEPShape.package_failure(run["package"], bindings, request["package_ref"])
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

# --- 上游綁定：與切片 B 共用同一組（repair-01 / slice B repair-01）-------
vocab = read_yaml(VOCAB_PATH)
std01 = read_json(STD01_SCHEMA_PATH)
bindings, binding_problems = MEPShape.build_bindings(spec, vocab, std01)
binding_problems.each { |problem| assert(false, problem, failures) }

assert(mep.dig("ref_binding", "acl_snapshot_pattern_source").to_s.include?("raw-evidence-envelope.schema.json"),
       "ref_binding.acl_snapshot_pattern_source 必須指向 STD-01 schema", failures)
assert(mep.dig("ref_binding", "evidence_refs") == MEPShape::EVIDENCE_KIND &&
       mep.dig("ref_binding", "source_anchor_refs") == MEPShape::SOURCE_ANCHOR_KIND,
       "ref_binding 宣告的 pinned kind 必須與 evaluator 實際 pin 的一致", failures)
assert(mep.dig("content_hash_basis", "algorithm") == "SHA256",
       "content_hash_basis.algorithm 必須是 SHA256（evaluator 依此重算）", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = transmission_failure(run, bindings)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = transmission_failure(run, bindings)
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
  "MEP_PACKAGE_ID_NOT_EVIDENCE_PACKAGE" => "minimal_evidence_package.error.package_id_not_evidence_package",
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
SHAPE_PATH = File.join(__dir__, "lib/minimal_evidence_package_shape.rb")
[[__FILE__, "access_request_failure"], [SHAPE_PATH, "package_failure"]].each do |path, evaluator|
  shape_violations = LoopReturnContract.exit_shape_violations(path, evaluator)
  assert(shape_violations.empty?, "#{evaluator} 有不合契約的 return 形式：#{shape_violations.inspect}", failures)
end
# 封包檢查已搬到共用 helper，所以可達 code 是兩個 evaluator 的聯集——
# 這也是「A 與 B 真的共用同一份封包 evaluator」的機器證明之一。
reachable = LoopReturnContract.reachable_codes(__FILE__, "access_request_failure") +
            LoopReturnContract.reachable_codes(SHAPE_PATH, "package_failure")
reachable = reachable.uniq
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
