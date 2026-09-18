#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-323（EMEM-09）切片 2：Organizational Value Assessment ／
# NEEDS_ORG_FOLLOWUP。
#
# Assessment != Promotion Eligibility：不讀、不寫 candidate_status 等既有
# 生命週期欄位——一個 HIGH 評分本身不授權 promotion，SSP-294 既有的 gate／
# policy／scope ceiling 對之後真的送出的 proposal 仍照樣套用。
# NEEDS_ORG_FOLLOWUP != Knowledge：它是 follow-up signal，不建立任何
# candidate/record identity。
#
# 關鍵設計（承接切片 1 立下、對本卡以後每片都適用的兩項硬要求）：
#   1. 聚合器接回實測：新增的每個 guard 至少一個要驗證不只直接呼叫這支會
#      紅，呼叫 validate_personal_memory_contract.rb 也要同步轉紅。
#   2. 機器可查訊號 vs 判斷型訊號分離：這九個構面本質上都是人的價值判斷，
#      沒有原始資料可以推導——不像切片 1 有 identity/hash/evidence-set 可
#      算。所以這裡機器能守住的邊界不是「推導」，而是「完整性 + 佐證」：
#      九個構面一個都不能少報，每個構面都要有非空 reasons；HIGH 評分額外
#      要求至少一個 URN evidence_ref，不接受「因為我說是 HIGH」這種純自報。
#
# repair-01（大 review NO_GO，2026-09-18，三筆 P1）：
#   F-01 needs_org_followup 原本是 caller 自報的 boolean，evaluator 只驗
#        它「宣告為 true 時」合不合法——caller 大可在條件全部成立時仍宣告
#        false，直接通過。這正是切片 1 對 category/disposition 定下的同一
#        條規則（不能自己宣告分類）這裡漏套用了。改成完全由 needs_org_
#        followup? 這個函式從原始訊號推導，run 裡禁止出現這個欄位。
#   F-02 Owner 原文「本人不知道答案 *或* 缺外部 evidence，且組織價值仍
#        高」——「或」被前一版寫成了「且」，把合法的 follow-up 擋掉。
#   F-03 上游卡「必須輸出可讀 reasons」原本只在 HIGH 評分才要求，全部
#        LOW/MEDIUM、完全不寫 reasons 的評估仍會通過——改成九個構面全部
#        都要非空 reasons；evidence_ref 維持只有 HIGH 才要求（reviewer
#        明確保留這條）。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/organizational-value-assessment-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/organizational-value-assessment-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

# 與 historical_comparison 共用同一份「不是第二套生命週期」邊界——本卡的
# run 同樣結構性禁止碰這些欄位，證明 assessment 真的不是 promotion 判定。
FORBIDDEN_LIFECYCLE_FIELDS = %w[
  candidate_status record_status verification_status acceptance_status
  conflict_resolution_status
].freeze

# 「不要求假精準單一分數」的機器邊界——任何看起來像聚合數字分數的欄位一律
# 結構性禁止出現在 run 裡。
FORBIDDEN_SCORE_FIELDS = %w[overall_score value_score total_score score aggregate_score].freeze

# repair-01 F-01：needs_org_followup 不是輸入，是 evaluator 推導出的結果
# （見 needs_org_followup? ）。run 裡出現這個欄位一律 fail-closed 拒絕，
# 不留一個「夾帶了但被忽略」的殘留欄位——切片 1 的 review 已經指出過這種
# 殘留欄位會誤導後續讀者以為有自報路徑。
FORBIDDEN_SELF_DECLARED_FIELDS = %w[needs_org_followup].freeze

RATING_LEVELS = %w[LOW MEDIUM HIGH].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a run carrying a forbidden lifecycle field",
  "a run carrying a forbidden aggregate score field",
  "a run declaring needs_org_followup itself",
  "subject_ref that is not an omos URN",
  "dimension_ratings missing a required dimension",
  "dimension_ratings naming an unknown dimension",
  "a dimension_ratings value outside rating_levels",
  "dimension_reasons or dimension_evidence_refs that is not a map",
  "a dimension with no reasons at all",
  "a HIGH rating with no evidence_refs",
  "an evidence_ref that is not an omos URN",
  "a non-HIGH dimension's evidence_refs that is not an array",
  "answer_provided true together with a non-empty unresolved_question",
  "answer_provided false together with an empty unresolved_question",
  "suggested_expert present but not a string"
].freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

def blank?(value)
  !value.is_a?(String) || value.strip.empty?
end

def high_dimensions_of(ratings)
  ratings.select { |_, level| level == "HIGH" }.keys
end

# --- 結構驗證（fail-closed）------------------------------------------------

def assessment_failure(run, dimensions)
  forbidden_lifecycle = FORBIDDEN_LIFECYCLE_FIELDS.find { |field| run.key?(field) }
  return "OVA_FORBIDDEN_LIFECYCLE_FIELD" if forbidden_lifecycle

  forbidden_score = FORBIDDEN_SCORE_FIELDS.find { |field| run.key?(field) }
  return "OVA_FORBIDDEN_SCORE_FIELD" if forbidden_score

  forbidden_self_declared = FORBIDDEN_SELF_DECLARED_FIELDS.find { |field| run.key?(field) }
  return "OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP" if forbidden_self_declared

  return "OVA_SUBJECT_REF_NOT_URN" unless urn?(run["subject_ref"])

  ratings = run["dimension_ratings"]
  return "OVA_DIMENSION_RATINGS_INCOMPLETE" unless ratings.is_a?(Hash) && ratings.keys.to_set == dimensions.to_set
  return "OVA_DIMENSION_RATING_INVALID" unless ratings.values.all? { |v| RATING_LEVELS.include?(v) }

  reasons_map = run["dimension_reasons"] || {}
  evidence_map = run["dimension_evidence_refs"] || {}
  return "OVA_DIMENSION_RATINGS_INCOMPLETE" unless reasons_map.is_a?(Hash) && evidence_map.is_a?(Hash)

  # repair-01 F-03：九個構面全部都要非空 reasons，不只 HIGH——上游卡明寫
  # 「必須輸出可讀 reasons」，沒有分級豁免。
  dimensions.each do |dim|
    reasons = reasons_map[dim]
    return "OVA_DIMENSION_REASONS_INCOMPLETE" unless reasons.is_a?(Array) && reasons.any? { |r| !blank?(r) }
  end

  # 形狀先鎖，不分 HIGH／LOW／MEDIUM：出現在 dimension_evidence_refs 裡的
  # 每個值都必須是「全為 URN 的 Array」。一個 scalar 或非 URN 字串不該因為
  # 該構面評分不是 HIGH 就被放行——這裡只有一個 return site 負責 URN 形狀，
  # 不再跟下面的「HIGH 必須有佐證」分開兩處各自檢查同一件事。
  evidence_map.each_value do |refs|
    return "OVA_EVIDENCE_REF_NOT_URN" unless refs.is_a?(Array) && refs.all? { |r| urn?(r) }
  end

  # evidence_ref 仍然只有 HIGH 才要求非空——reviewer 明確保留這條，問題只
  # 在 reasons 不該分級，不在 evidence。
  high_dimensions_of(ratings).each do |dim|
    refs = evidence_map[dim]
    return "OVA_RATING_UNSUBSTANTIATED" unless refs.is_a?(Array) && !refs.empty?
  end

  answer_provided = run["answer_provided"]
  return "OVA_ANSWER_PROVIDED_NOT_BOOLEAN" unless [true, false].include?(answer_provided)

  unresolved_question = run["unresolved_question"]
  question_present = !blank?(unresolved_question)
  # 內部一致性檢查：已回答卻還留著未解問題，或未回答卻沒有說明留了什麼問題，
  # 兩者都是自我矛盾——這是這裡唯一機器可查的一致性，不是相信 caller 另一個
  # 自報旗標。reviewer 已確認這條「存在性檢查」已足夠，不需要再判內容品質。
  if answer_provided == true && question_present
    return "OVA_ANSWER_INCONSISTENT"
  elsif answer_provided == false && !question_present
    return "OVA_ANSWER_INCONSISTENT"
  end

  missing_external_evidence = run["missing_external_evidence"]
  return "OVA_MISSING_EVIDENCE_NOT_BOOLEAN" unless [true, false].include?(missing_external_evidence)

  suggested_expert = run["suggested_expert"]
  return "OVA_SUGGESTED_EXPERT_NOT_STRING" unless suggested_expert.nil? || suggested_expert.is_a?(String)

  nil
end

# --- 分類推導：needs_org_followup 完全由 evaluator 算 ---------------------
#
# repair-01 F-01/F-02：跟切片 1 的 classify() 同一個模式——這是推導結果，
# 不是輸入。只在 assessment_failure 回傳 nil（run 本身合法）之後才有意義
# 呼叫。Owner 原文「本人不知道答案 *或* 缺外部 evidence，且組織價值仍
# 高」，「或」不是「且」。
def needs_org_followup?(run, high_dimensions)
  answer_provided = run["answer_provided"]
  missing_external_evidence = run["missing_external_evidence"]
  (answer_provided == false || missing_external_evidence == true) && high_dimensions.any?
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
ova = spec.fetch("organizational_value_assessment")

dimensions = ova.fetch("dimensions", [])
assert(dimensions.size == 9, "organizational_value_assessment.dimensions 必須剛好 9 個", failures)
rating_levels = ova.fetch("rating_levels", [])
assert(rating_levels == RATING_LEVELS, "organizational_value_assessment.rating_levels 必須是 #{RATING_LEVELS.inspect}", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual_failure = assessment_failure(run, dimensions)
  assert(actual_failure.nil?, "#{case_id} 預期 allow，實際被拒：#{actual_failure}", failures)

  next unless actual_failure.nil?

  actual_followup = needs_org_followup?(run, high_dimensions_of(run.fetch("dimension_ratings")))
  expected_followup = test_case.fetch("expected_needs_org_followup")
  assert(actual_followup == expected_followup,
         "#{case_id} needs_org_followup 推導錯誤：預期 #{expected_followup.inspect}，實際 #{actual_followup.inspect}",
         failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = assessment_failure(run, dimensions)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
ERROR_CONTRACT = {
  "OVA_FORBIDDEN_LIFECYCLE_FIELD" => "organizational_value_assessment.error.forbidden_lifecycle_field",
  "OVA_FORBIDDEN_SCORE_FIELD" => "organizational_value_assessment.error.forbidden_score_field",
  "OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP" => "organizational_value_assessment.error.forbidden_self_declared_followup",
  "OVA_SUBJECT_REF_NOT_URN" => "organizational_value_assessment.error.subject_ref_not_urn",
  "OVA_DIMENSION_RATINGS_INCOMPLETE" => "organizational_value_assessment.error.dimension_ratings_incomplete",
  "OVA_DIMENSION_RATING_INVALID" => "organizational_value_assessment.error.dimension_rating_invalid",
  "OVA_DIMENSION_REASONS_INCOMPLETE" => "organizational_value_assessment.error.dimension_reasons_incomplete",
  "OVA_RATING_UNSUBSTANTIATED" => "organizational_value_assessment.error.rating_unsubstantiated",
  "OVA_EVIDENCE_REF_NOT_URN" => "organizational_value_assessment.error.evidence_ref_not_urn",
  "OVA_ANSWER_PROVIDED_NOT_BOOLEAN" => "organizational_value_assessment.error.answer_provided_not_boolean",
  "OVA_ANSWER_INCONSISTENT" => "organizational_value_assessment.error.answer_inconsistent",
  "OVA_MISSING_EVIDENCE_NOT_BOOLEAN" => "organizational_value_assessment.error.missing_evidence_not_boolean",
  "OVA_SUGGESTED_EXPERT_NOT_STRING" => "organizational_value_assessment.error.suggested_expert_not_string"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "assessment_failure")
assert(violations.empty?, "assessment_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "assessment_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS organizational value assessment contract validation (dimensions=#{dimensions.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
