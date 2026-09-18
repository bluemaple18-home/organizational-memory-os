#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-323（EMEM-09）切片 3：Personal Store Portability ／ Local-First
# export surface。
#
# 延伸（不重造）`runtime_policy.executor_authority_over_memory`／
# `optional_executors`——這兩個宣告已存在，且已被
# `validate_ai_work_record_boundary_contract.rb` 的 cross_reference 強制。
# 這裡新增的是把「AI 平台只是 executor，不是 Personal Memory authority」
# 變成可機器驗證的宣告：
#
#   1. Acceptance #1（同一份 Personal Store 可由至少兩種 executor fixture
#      處理，核心語意不因 vendor 改變）——用兩個不同 `optional_executors`
#      各自對同一筆 record 產生的本機投影，比對 `portable_fields` 是否
#      逐項相等來證明，不是相信一句宣稱。
#   2. Acceptance #2（換 AI executor 不需 migration Personal truth）——
#      結構性要求 `portable_fields` 與 `executor_provenance_fields`
#      不相交：任何會隨 executor 改變的欄位都不能同時是判定「這是同一份
#      Personal truth」的依據。
#   3. Local-first export surface 是封閉列舉（只有 minimal_evidence_
#      package 與 weekly_closeout_receipt），不是開放集合——這是「公司端
#      只得到明確送出的 package 與 receipt」在契約層的機器邊界。
#
# 機器可查訊號 vs 判斷型訊號：這支的核心斷言（欄位相等、集合不相交、
# executor 屬於既有清單、export surface 恰好兩個）全部是結構性事實，沒有
# 需要人類判斷的維度——不像切片 2 的九構面評分，這裡不存在「自報」的空間
# 可以驗。

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
  "a portable field missing from one projection",
  "a portable field mismatched between the two projections",
  "an executor_ref that is not a string"
].freeze

def portability_failure(test_case, portable_fields, optional_executors)
  a = test_case["projection_a"]
  b = test_case["projection_b"]

  [a, b].each do |projection|
    ref = projection["executor_ref"]
    return "PORTABILITY_EXECUTOR_REF_NOT_STRING" unless ref.is_a?(String)
    return "PORTABILITY_UNKNOWN_EXECUTOR" unless optional_executors.include?(ref)
  end

  return "PORTABILITY_SAME_EXECUTOR" if a["executor_ref"] == b["executor_ref"]

  portable_fields.each do |field|
    return "PORTABILITY_FIELD_MISSING" unless a.key?(field) && b.key?(field)

    va = a[field]
    vb = b[field]
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

portable_contract = runtime_policy.fetch("portable_record_contract", {})
portable_fields = portable_contract.fetch("portable_fields", [])
executor_provenance_fields = portable_contract.fetch("executor_provenance_fields", [])
assert(portable_fields.any?, "portable_record_contract.portable_fields 不得為空", failures)
assert(executor_provenance_fields.any?, "portable_record_contract.executor_provenance_fields 不得為空", failures)
assert((portable_fields.to_set & executor_provenance_fields.to_set).empty?,
       "portable_fields 與 executor_provenance_fields 不得相交（换 executor 不得動到任何 portable_field）", failures)

export_surface = runtime_policy.fetch("local_first_export_surface", [])
assert(export_surface.to_set == EXPECTED_EXPORT_SURFACE.to_set,
       "runtime_policy.local_first_export_surface 必須剛好是 #{EXPECTED_EXPORT_SURFACE.inspect}（封閉列舉，不是開放集合）", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = portability_failure(test_case, portable_fields, optional_executors)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = portability_failure(test_case, portable_fields, optional_executors)
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
  puts "PASS personal store portability contract validation (portable_fields=#{portable_fields.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
