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

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/historical-comparison-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/historical-comparison-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

# 五態生命週期的既有欄位不得出現在 comparison run 裡——這是「不是第二套
# 生命週期」的機器邊界，不只是文件宣告。
FORBIDDEN_LIFECYCLE_FIELDS = %w[
  candidate_status record_status verification_status acceptance_status
  conflict_resolution_status
].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a run carrying a forbidden lifecycle field",
  "no_prior_record true together with a prior_content_hash present",
  "material_effect true with no reasons",
  "material_effect true with reasons naming no recognised dimension",
  "material_effect true with no evidence_refs",
  "contradicts_prior true with no reasons",
  "contradicts_prior true with no evidence_refs",
  "material_effect true while no_prior_record is also true",
  "contradicts_prior true while no_prior_record is also true",
  "an evidence_ref that is not an omos URN",
  "current_content_hash missing"
].freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

def blank?(value)
  !value.is_a?(String) || value.strip.empty?
end

# --- 機器可查訊號：從原始資料算，不是呼叫端自報 ---------------------------

def compute_signals(run)
  no_prior_record = run["prior_record_ref"].nil?
  prior_hash = run["prior_content_hash"]
  current_hash = run["current_content_hash"]
  identical_to_prior = !no_prior_record && prior_hash == current_hash

  prior_refs = (run["prior_evidence_refs"] || []).to_set
  current_refs = (run["current_evidence_refs"] || []).to_set
  has_new_evidence = !no_prior_record && !(current_refs - prior_refs).empty?

  { no_prior_record: no_prior_record, identical_to_prior: identical_to_prior,
    has_new_evidence: has_new_evidence }
end

# --- 結構驗證（fail-closed）------------------------------------------------

def historical_comparison_failure(run, material_dimensions)
  forbidden = FORBIDDEN_LIFECYCLE_FIELDS.find { |field| run.key?(field) }
  return "COMPARISON_FORBIDDEN_LIFECYCLE_FIELD" if forbidden

  return "COMPARISON_MISSING_CURRENT_HASH" if blank?(run["current_content_hash"])

  no_prior_record = run["prior_record_ref"].nil?
  return "COMPARISON_PRIOR_RECORD_INCONSISTENT" if no_prior_record && !run["prior_content_hash"].nil?

  material_effect = run["material_effect"] == true
  contradicts_prior = run["contradicts_prior"] == true

  if no_prior_record
    return "COMPARISON_JUDGMENT_WITHOUT_PRIOR" if material_effect || contradicts_prior
  end

  if material_effect
    reasons = run["material_effect_reasons"]
    return "COMPARISON_JUDGMENT_UNSUBSTANTIATED" unless reasons.is_a?(Array) && !reasons.empty?
    return "COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION" unless reasons.all? { |r| material_dimensions.include?(r) }

    refs = run["material_effect_evidence_refs"]
    return "COMPARISON_JUDGMENT_UNSUBSTANTIATED" unless refs.is_a?(Array) && !refs.empty? && refs.all? { |r| urn?(r) }
  end

  if contradicts_prior
    reasons = run["contradiction_reasons"]
    return "COMPARISON_JUDGMENT_UNSUBSTANTIATED" unless reasons.is_a?(Array) && !reasons.empty?

    refs = run["contradiction_evidence_refs"]
    return "COMPARISON_JUDGMENT_UNSUBSTANTIATED" unless refs.is_a?(Array) && !refs.empty? && refs.all? { |r| urn?(r) }
  end

  evidence_fields = [run["prior_evidence_refs"] || [], run["current_evidence_refs"] || []].flatten
  return "COMPARISON_EVIDENCE_REF_NOT_URN" unless evidence_fields.all? { |r| urn?(r) }

  nil
end

# --- 分類推導：優先序，見契約 category_and_disposition_derivation ---------

def classify(run, dispositions)
  signals = compute_signals(run)
  material_effect = run["material_effect"] == true
  contradicts_prior = run["contradicts_prior"] == true

  if signals[:no_prior_record]
    return { category: "UNSEEN", disposition: dispositions.fetch("UNSEEN") }
  end
  if contradicts_prior
    return { category: "CONTRADICTED", disposition: dispositions.fetch("CONTRADICTED") }
  end
  if signals[:has_new_evidence]
    key = material_effect ? "NEW_EVIDENCE_WITH_MATERIAL_EFFECT" : "NEW_EVIDENCE_WITHOUT_MATERIAL_EFFECT"
    return { category: "NEW_EVIDENCE", disposition: dispositions.fetch(key) }
  end
  if material_effect
    return { category: "MATERIALLY_CHANGED", disposition: dispositions.fetch("MATERIALLY_CHANGED") }
  end
  if signals[:identical_to_prior]
    return { category: "UNCHANGED", disposition: dispositions.fetch("UNCHANGED") }
  end

  # 不應該到得了這裡：has_new_evidence 與 identical_to_prior 都是從同一組
  # 資料算出來的互補訊號，兩者都是 false 代表資料本身有缺口。fail loud，
  # 不要預設一個可能是錯的分類。
  { category: nil, disposition: nil }
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
  "COMPARISON_JUDGMENT_WITHOUT_PRIOR" => "historical_comparison.error.judgment_without_prior",
  "COMPARISON_JUDGMENT_UNSUBSTANTIATED" => "historical_comparison.error.judgment_unsubstantiated",
  "COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION" => "historical_comparison.error.judgment_unrecognised_dimension",
  "COMPARISON_EVIDENCE_REF_NOT_URN" => "historical_comparison.error.evidence_ref_not_urn"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "historical_comparison_failure")
assert(violations.empty?, "historical_comparison_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "historical_comparison_failure")
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
