#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-323（EMEM-09）切片 3：Personal Store Portability ／ Local-First
# export surface。
#
# 延伸（不重造）`runtime_policy.executor_authority_over_memory`／
# `optional_executors`——這兩個宣告已存在，且已被
# `validate_ai_work_record_boundary_contract.rb` 的 cross_reference 強制。
#
# repair-01（大 review NO_GO，2026-09-18，一筆 P1）：初版自己維護一份四欄
# 「portable_fields」（record_id／content_digest／evidence_refs／
# created_at），跟既有 `PersonalMemoryCandidate`／`PersonalMemoryRecord`
# 的真實 required_fields（ownership／visibility／ACL／status／真實
# content 等）完全脫鉤——兩個 executor 在這些真實欄位上不同，portability
# 仍會判定合法；`content_digest` 只是自報，從未真的跟內容綁定；甚至第一個
# 正例直接用了 `record_id` 這個既有 `PersonalMemoryCandidate.forbidden`
# 明文禁止的欄位名。修法：不再維護第二份核心語意清單，改成直接讀
# `personal_memory_resource_contracts.resources.<kind>.required_fields`／
# `.forbidden`（呼叫端宣告 resource_kind，evaluator 從真正的權威 schema
# 抓欄位清單），executor_provenance_fields 只允許活在 `resource` 物件
# 之外。
#
# 機器可查訊號 vs 判斷型訊號：這支的核心斷言（欄位存在、欄位相等、
# forbidden 欄位不得出現、resource_kind 一致且已知）全部是結構性事實，
# 沒有需要人類判斷的維度。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-store-portability-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-store-portability-negative-fixtures.json")

EXPECTED_EXPORT_SURFACE = %w[minimal_evidence_package weekly_closeout_receipt].freeze

EXPECTED_NEGATIVE_LABELS = [
  "an executor_ref not in optional_executors",
  "both projections declaring the same executor_ref",
  "an executor_ref that is not a string",
  "an unknown resource_kind not declared in personal_memory_resource_contracts.resources",
  "the two projections declaring different resource_kind",
  "a resource field that is not a map",
  "a resource carrying a field the resource contract forbids",
  "a required field missing from one projection's resource",
  "content that differs between the two projections' resource",
  "governance ownership_mode that differs between the two projections' resource"
].freeze

# dig_dotted / dotted_key_present? 已移入 lib/omos_contract_helpers，
# 與 EMEM-11 切片 1 的 runtime row 檢查共用同一份實作。

# 只挑 forbidden 清單裡「真的是某個 resource kind 的欄位名」的條目
# （例如 record_id）；`resource_kind=PERSONAL_MEMORY_RECORD` 或
# `memory_kind in not_long_lived_memory_by_default` 這種複合語意宣告不是
# 欄位名，也不是本片職責（那是既有 resource contract validator 的事），
# 跳過。
def literal_forbidden_fields(forbidden, known_field_names)
  (forbidden || []).select { |f| known_field_names.include?(f) }
end

def portability_failure(test_case, resources, all_required_field_names, optional_executors)
  a = test_case["projection_a"]
  b = test_case["projection_b"]

  [a, b].each do |projection|
    ref = projection["executor_ref"]
    return "PORTABILITY_EXECUTOR_REF_NOT_STRING" unless ref.is_a?(String)
    return "PORTABILITY_UNKNOWN_EXECUTOR" unless optional_executors.include?(ref)
  end

  return "PORTABILITY_SAME_EXECUTOR" if a["executor_ref"] == b["executor_ref"]

  kind_a = a["resource_kind"]
  kind_b = b["resource_kind"]
  return "PORTABILITY_UNKNOWN_RESOURCE_KIND" unless resources.key?(kind_a) && resources.key?(kind_b)
  return "PORTABILITY_RESOURCE_KIND_MISMATCH" unless kind_a == kind_b

  resource_a = a["resource"]
  resource_b = b["resource"]
  return "PORTABILITY_RESOURCE_NOT_MAP" unless resource_a.is_a?(Hash) && resource_b.is_a?(Hash)

  resource_def = resources.fetch(kind_a)
  forbidden = literal_forbidden_fields(resource_def["forbidden"], all_required_field_names)
  forbidden.each do |field|
    [resource_a, resource_b].each do |resource|
      return "PORTABILITY_FORBIDDEN_FIELD_PRESENT" if dotted_key_present?(resource, field)
    end
  end

  resource_def.fetch("required_fields", []).each do |field|
    return "PORTABILITY_FIELD_MISSING" unless dotted_key_present?(resource_a, field) && dotted_key_present?(resource_b, field)

    va = dig_dotted(resource_a, field)
    vb = dig_dotted(resource_b, field)
    equal = (va.is_a?(Array) && vb.is_a?(Array)) ? va.to_set == vb.to_set : va == vb
    return "PORTABILITY_FIELD_MISMATCH" unless equal
  end

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
runtime_policy = spec.fetch("runtime_policy")

optional_executors = runtime_policy.fetch("optional_executors", [])
assert(optional_executors.size >= 2, "runtime_policy.optional_executors 必須至少 2 個，才可能有跨 executor 的 fixture", failures)
assert(runtime_policy["executor_authority_over_memory"] == false, "runtime_policy.executor_authority_over_memory 必須是 false", failures)

resources = spec.dig("personal_memory_resource_contracts", "resources") || {}
assert(resources.any?, "personal_memory_resource_contracts.resources 必須存在且非空", failures)
all_required_field_names = resources.values.flat_map { |r| r["required_fields"] || [] }.to_set

portable_contract = runtime_policy.fetch("portable_record_contract", {})
executor_provenance_fields = portable_contract.fetch("executor_provenance_fields", [])
assert(executor_provenance_fields.any?, "portable_record_contract.executor_provenance_fields 不得為空", failures)
assert((executor_provenance_fields.to_set & all_required_field_names).empty?,
       "executor_provenance_fields 不得與 personal_memory_resource_contracts 任何 resource 的 required_fields 相交（否則就不只是補充 provenance）",
       failures)

export_surface = runtime_policy.fetch("local_first_export_surface", [])
assert(export_surface.to_set == EXPECTED_EXPORT_SURFACE.to_set,
       "runtime_policy.local_first_export_surface 必須剛好是 #{EXPECTED_EXPORT_SURFACE.inspect}（封閉列舉，不是開放集合）", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = portability_failure(test_case, resources, all_required_field_names, optional_executors)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = portability_failure(test_case, resources, all_required_field_names, optional_executors)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
ERROR_CONTRACT = {
  "PORTABILITY_EXECUTOR_REF_NOT_STRING" => "personal_store_portability.error.executor_ref_not_string",
  "PORTABILITY_UNKNOWN_EXECUTOR" => "personal_store_portability.error.unknown_executor",
  "PORTABILITY_SAME_EXECUTOR" => "personal_store_portability.error.same_executor",
  "PORTABILITY_UNKNOWN_RESOURCE_KIND" => "personal_store_portability.error.unknown_resource_kind",
  "PORTABILITY_RESOURCE_KIND_MISMATCH" => "personal_store_portability.error.resource_kind_mismatch",
  "PORTABILITY_RESOURCE_NOT_MAP" => "personal_store_portability.error.resource_not_map",
  "PORTABILITY_FORBIDDEN_FIELD_PRESENT" => "personal_store_portability.error.forbidden_field_present",
  "PORTABILITY_FIELD_MISSING" => "personal_store_portability.error.field_missing",
  "PORTABILITY_FIELD_MISMATCH" => "personal_store_portability.error.field_mismatch"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "portability_failure")
assert(violations.empty?, "portability_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "portability_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS personal store portability contract validation (resource_kinds=#{resources.keys.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
