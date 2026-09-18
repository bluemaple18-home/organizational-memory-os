#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-323（EMEM-09）切片 1：historical comparison / 五態分類與補送規則。
#
# 五態是**比較結果**，不是第二套候選生命週期——不讀、不寫 candidate_status
# 等既有生命週期欄位。SSP-324 的 dedup/resend 規則綁定這裡宣告的 disposition，
# 不重述。
#
# 關鍵設計（回應 review 指出的兩個問題）：
#   1. category／disposition 一律由 evaluator 從原始訊號推導，呼叫端不能
#      自己宣告分類——這正是本 repo 今天一再犯的「只驗自報一致、不驗事實」
#      的反面設計。
#   2. NEW_EVIDENCE 與 MATERIALLY_CHANGED（甚至 CONTRADICTED）可能同時成立
#      （例如新證據剛好又推翻結論），所以用明確優先序解決，不是五個各自獨立
#      的名稱就算完事。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"
require_relative "lib/historical_comparison_derivation"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/historical-comparison-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/historical-comparison-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

# 五態生命週期的既有欄位不得出現在 comparison run 裡——這是「不是第二套
# 生命週期」的機器邊界，不只是文件宣告。
FORBIDDEN_LIFECYCLE_FIELDS = HistoricalComparisonDerivation::FORBIDDEN_LIFECYCLE_FIELDS

EXPECTED_NEGATIVE_LABELS = [
  "a run carrying a forbidden lifecycle field",
  "no_prior_record true together with a prior_content_hash present",
  "a prior_record_ref present with prior_content_hash missing",
  "material_effect true with no reasons",
  "material_effect true with reasons naming no recognised dimension",
  "material_effect true with no evidence_refs",
  "contradicts_prior true with no reasons",
  "contradicts_prior true with reasons naming no recognised dimension",
  "contradicts_prior true with no evidence_refs",
  "material_effect true while no_prior_record is also true",
  "contradicts_prior true while no_prior_record is also true",
  "an evidence_ref that is not an omos URN",
  "an evidence_refs field that is not an array",
  "current_content_hash missing",
  "content hash changed from prior with no new evidence, material_effect or contradicts_prior to explain it"
].freeze

HCD = HistoricalComparisonDerivation

# 推導本體（compute_signals／historical_comparison_failure／classify）住在
# scripts/lib/historical_comparison_derivation.rb，與 SSP-324 切片 B 共用
# 同一份實作——切片 B 消費的是這裡推導出來的結果，不是自己再寫一份規則。
def urn?(value)
  HCD.urn?(value)
end

def historical_comparison_failure(run, material_dimensions)
  HCD.historical_comparison_failure(run, material_dimensions)
end

def classify(run, dispositions)
  HCD.classify(run, dispositions)
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
hc = spec.fetch("historical_comparison")

assert(hc.fetch("categories", []).size == 5, "historical_comparison.categories 必須剛好 5 個", failures)
material_dimensions = hc.fetch("material_effect_dimensions", [])
assert(material_dimensions.any?, "historical_comparison.material_effect_dimensions 不得為空", failures)
dispositions = hc.fetch("dispositions", {})
assert(dispositions.size == 6, "historical_comparison.dispositions 必須剛好 6 個（NEW_EVIDENCE 分兩支）", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = historical_comparison_failure(run, material_dimensions)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)

  next unless actual_failure.nil?

  result = classify(run, dispositions)
  expected = test_case.fetch("expected_classification")
  assert(result == { category: expected["category"], disposition: expected["disposition"] },
         "#{case_id} 分類推導錯誤：預期 #{expected.inspect}，實際 #{result.inspect}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = historical_comparison_failure(run, material_dimensions)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
#
# 本檔的 error_contract 直接宣告在此（historical_comparison 上游沒有既定
# error 清單可綁——這是新契約，不是強制既有宣告），但仍用 AST 綁定
# evaluator 實際可達的 return，避免手寫清單漂移。
ERROR_CONTRACT = {
  "COMPARISON_FORBIDDEN_LIFECYCLE_FIELD" => "historical_comparison.error.forbidden_lifecycle_field",
  "COMPARISON_MISSING_CURRENT_HASH" => "historical_comparison.error.missing_current_hash",
  "COMPARISON_PRIOR_RECORD_INCONSISTENT" => "historical_comparison.error.prior_record_inconsistent",
  "COMPARISON_MISSING_PRIOR_HASH" => "historical_comparison.error.missing_prior_hash",
  "COMPARISON_EVIDENCE_REFS_NOT_ARRAY" => "historical_comparison.error.evidence_refs_not_array",
  "COMPARISON_JUDGMENT_WITHOUT_PRIOR" => "historical_comparison.error.judgment_without_prior",
  "COMPARISON_JUDGMENT_UNSUBSTANTIATED" => "historical_comparison.error.judgment_unsubstantiated",
  "COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION" => "historical_comparison.error.judgment_unrecognised_dimension",
  "COMPARISON_EVIDENCE_REF_NOT_URN" => "historical_comparison.error.evidence_ref_not_urn",
  "COMPARISON_HASH_CHANGED_WITHOUT_EXPLANATION" => "historical_comparison.error.hash_changed_without_explanation"
}.freeze

declared_codes = ERROR_CONTRACT.keys
DERIVATION_PATH = File.join(__dir__, "lib/historical_comparison_derivation.rb")
violations = LoopReturnContract.exit_shape_violations(DERIVATION_PATH, "historical_comparison_failure")
assert(violations.empty?, "historical_comparison_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(DERIVATION_PATH, "historical_comparison_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS historical comparison contract validation (categories=#{hc.fetch('categories').size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
