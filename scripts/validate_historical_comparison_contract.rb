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
  # repair-01 F-02a：有 prior_record_ref 卻缺 prior_content_hash，會讓後面
  # 的雜湊比對用 nil 當「之前的值」，產生不可信的 identical_to_prior 判定。
  return "COMPARISON_MISSING_PRIOR_HASH" if !no_prior_record && blank?(run["prior_content_hash"])

  # repair-01 F-03：evidence_refs 的陣列形狀必須先鎖，才能安全做集合運算。
  # 修正前：scalar 字串會在 compute_signals 的 `.to_set` 直接 NoMethodError
  # ——不是 fail-closed 拒絕，是程式當掉。
  [run["prior_evidence_refs"], run["current_evidence_refs"]].each do |refs|
    next if refs.nil?

    return "COMPARISON_EVIDENCE_REFS_NOT_ARRAY" unless refs.is_a?(Array)
  end

  evidence_fields = [run["prior_evidence_refs"] || [], run["current_evidence_refs"] || []].flatten
  return "COMPARISON_EVIDENCE_REF_NOT_URN" unless evidence_fields.all? { |r| urn?(r) }

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
    # repair-01 F-01：contradicts_prior 的理由跟 material_effect 一樣，必須
    # 落在 material_effect_dimensions 之內——修正前這裡沒有 allowlist，任意
    # 文字（例如 "vibes"）就能讓優先序最高的 CONTRADICTED 成立。
    return "COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION" unless reasons.all? { |r| material_dimensions.include?(r) }

    refs = run["contradiction_evidence_refs"]
    return "COMPARISON_JUDGMENT_UNSUBSTANTIATED" unless refs.is_a?(Array) && !refs.empty? && refs.all? { |r| urn?(r) }
  end

  # repair-01 F-02b：讓 classify 對任何通過以上檢查的 run 都是 total function。
  # 有 prior record、雜湊真的不同，卻沒有任何訊號解釋為什麼（沒有新證據、
  # 沒有宣告 material_effect、沒有宣告 contradicts_prior），代表送進來的資料
  # 本身不完整——必須在這裡 fail-closed，不能讓 classify 落到「不應該到得了
  # 這裡」的分支後悄悄回傳 nil/nil。
  unless no_prior_record
    signals = compute_signals(run)
    hash_changed = run["current_content_hash"] != run["prior_content_hash"]
    if hash_changed && !signals[:has_new_evidence] && !material_effect && !contradicts_prior
      return "COMPARISON_HASH_CHANGED_WITHOUT_EXPLANATION"
    end
  end

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

  # repair-01：這裡現在必須真的不可達。historical_comparison_failure 已經
  # 對「有 prior、雜湊改變、卻沒有 has_new_evidence／material_effect／
  # contradicts_prior 任何訊號解釋」fail-closed 擋掉，所以任何通過前面檢查
  # 才呼叫到這裡的 run，identical_to_prior 必為 true，會在上面分支命中。
  # 如果真的落到這裡，代表兩支函式的邏輯已經不同步——fail loud（raise），
  # 不要回傳看起來合法、實際上是缺口的 nil/nil。
  raise "unreachable classify state：has_new_evidence 與 identical_to_prior 皆為 false，" \
        "但 historical_comparison_failure 應已擋下這種 run（資料可能未先過 failure 檢查）"
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
