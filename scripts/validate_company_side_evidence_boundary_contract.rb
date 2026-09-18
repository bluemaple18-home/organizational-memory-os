#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-324（EMEM-10）切片 C：公司端拿到 Minimal Evidence Package 之後的
# 使用邊界，以及 NEEDS_ORG_FOLLOWUP 不得取得 canonical identity。
#
# 驗證單位是一筆「公司端處理紀錄」：哪個封包、為了什麼用途、產出了什麼、
# 以及（若同時發生）一次正式 retrieval 的 pack。三者要一起看——「封包只能
# 拿來 review／verification／audit」是用途問題，「封包不得被正式 retrieval
# 命中」是產出問題，分開驗就會各自留一半。
#
# 切片 A／B 三輪 review 的教訓在這裡先套用，不等 review 抓：
#   1. 封閉 allowlist，不是禁用清單——「不在 ban list 上」正是切片 A 初版
#      漏掉 private_blob 的原因。
#   2. 每個讀到的值都做形狀鎖，不只鎖欄位名。
#   3. 最重要的一條：每個檢查都要先問「權威對照物是誰、在不在我手上」。
#      - canonical 是否走完整路徑 → 比對 promotion_flow.required_steps（上游）
#      - retrieval 的欄位詞彙     → 讀 recall_context_pack 的 pack_required_fields（上游）
#      - 封包是否混進 retrieval   → 用本筆自己的 package_ref（同筆事實）比對
#      - followup 不得 canonical  → 重用 historical_comparison 的 lifecycle 禁列

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"
require_relative "lib/minimal_evidence_package_shape"
require_relative "lib/historical_comparison_derivation"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/company-side-evidence-boundary-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json")

MEPShape = MinimalEvidencePackageShape
HCD = HistoricalComparisonDerivation

HANDLING_ALLOWED_FIELDS = %w[
  package_ref purpose promotion_proposal_ref promotion_steps_completed
  needs_org_followup retrieval_pack
].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a handling record that is not a map",
  "a package_ref that is not an evidence package identity",
  "a handling record carrying a field outside the allowlist",
  "a handling record carrying a forbidden output field",
  "a purpose outside the allowed enum",
  "a purpose taken from the forbidden list",
  "a promotion_proposal_ref on a non-promotion purpose",
  "a promotion_proposal_ref that is not an omos URN",
  "promotion_steps_completed that does not match promotion_flow.required_steps",
  "a retrieval pack naming the handled package_ref",
  "a retrieval pack naming another evidence package",
  "a retrieval pack that is not a map",
  "a needs_org_followup that is not a map",
  "a needs_org_followup carrying canonical identity",
  "a needs_org_followup carrying a forbidden lifecycle field",
  "a needs_org_followup suggested_expert that is present but not a string"
].freeze

# --- 結構驗證（fail-closed）------------------------------------------------

def company_handling_failure(run, allowed_purposes, forbidden_output_fields, required_promotion_steps,
                             retrieval_ref_fields, package_prefix)
  return "CSB_HANDLING_NOT_MAP" unless run.is_a?(Hash)
  # 禁用清單放在 allowlist 之前：那幾個名字要以自己的明確錯誤碼失敗，而不是
  # 被歸進泛用的 unknown field（切片 A 也是這個順序）。
  return "CSB_HANDLING_FORBIDDEN_FIELD" if forbidden_output_fields.any? { |f| run.key?(f) }
  return "CSB_HANDLING_UNKNOWN_FIELD" unless (run.keys - HANDLING_ALLOWED_FIELDS).empty?

  package_ref = run["package_ref"]
  return "CSB_PACKAGE_REF_NOT_EVIDENCE_PACKAGE" unless MEPShape.urn?(package_ref) &&
                                                       package_ref.start_with?(package_prefix)

  purpose = run["purpose"]
  return "CSB_PURPOSE_NOT_ALLOWED" unless allowed_purposes.include?(purpose)

  # canonical 不是封包能走的捷徑：帶 promotion_proposal_ref 就必須是
  # promotion review 用途，而且必須走完上游宣告的整串 required_steps。
  proposal_ref = run["promotion_proposal_ref"]
  if proposal_ref
    return "CSB_PROMOTION_REF_ON_NON_PROMOTION_PURPOSE" unless purpose == "PROMOTION_REVIEW_SUPPORT"
    return "CSB_PROMOTION_REF_NOT_URN" unless MEPShape.urn?(proposal_ref)
    return "CSB_PROMOTION_STEPS_INCOMPLETE" unless run["promotion_steps_completed"] == required_promotion_steps
  end

  retrieval_pack = run["retrieval_pack"]
  unless retrieval_pack.nil?
    return "CSB_RETRIEVAL_PACK_NOT_MAP" unless retrieval_pack.is_a?(Hash)

    # 正式 retrieval 的欄位詞彙讀自 recall_context_pack，不是本片自創。
    retrieval_refs = retrieval_ref_fields.flat_map { |field| retrieval_pack[field] || [] }
    return "CSB_RETRIEVAL_NAMES_HANDLED_PACKAGE" if retrieval_refs.include?(package_ref)
    return "CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE" if retrieval_refs.any? { |r| r.is_a?(String) && r.start_with?(package_prefix) }
  end

  followup = run["needs_org_followup"]
  unless followup.nil?
    return "CSB_FOLLOWUP_NOT_MAP" unless followup.is_a?(Hash)
    # follow-up signal 不得取得 canonical identity，也不得夾帶既有生命週期
    # 欄位——後者直接重用 historical_comparison 已封的禁列。
    return "CSB_FOLLOWUP_CARRIES_CANONICAL" if followup.key?("canonical_record_ref")
    return "CSB_FOLLOWUP_CARRIES_LIFECYCLE_FIELD" if HCD::FORBIDDEN_LIFECYCLE_FIELDS.any? { |f| followup.key?(f) }

    expert = followup["suggested_expert"]
    return "CSB_FOLLOWUP_SUGGESTED_EXPERT_NOT_STRING" unless expert.nil? || expert.is_a?(String)
  end

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
csb = spec.fetch("company_side_evidence_boundary")

allowed_purposes = csb.fetch("allowed_purposes", [])
forbidden_purposes = csb.fetch("forbidden_purposes", [])
assert(allowed_purposes.any? && forbidden_purposes.any?, "allowed／forbidden purposes 不得為空", failures)
assert((allowed_purposes.to_set & forbidden_purposes.to_set).empty?,
       "allowed_purposes 與 forbidden_purposes 不得重疊", failures)

forbidden_output_fields = csb.fetch("handling_forbidden_fields", [])
assert(forbidden_output_fields.any?, "handling_forbidden_fields 不得為空", failures)
assert((forbidden_output_fields.to_set & HANDLING_ALLOWED_FIELDS.to_set).empty?,
       "禁用輸出欄位不得同時在 allowlist 裡", failures)

# canonical 路徑的權威對照物：上游的 promotion_flow.required_steps。
required_promotion_steps = spec.dig("promotion_flow", "required_steps") || []
assert(required_promotion_steps.any?, "promotion_flow.required_steps 必須存在（本片比對它，不重述）", failures)
assert(required_promotion_steps.include?("canonical_single_writer"),
       "promotion_flow.required_steps 必須以 canonical_single_writer 收尾（本片依賴這個保證）", failures)
assert(spec.dig("promotion_flow", "direct_copy_to_shared_canonical") == "forbidden",
       "promotion_flow.direct_copy_to_shared_canonical 必須維持 forbidden（本片不加例外）", failures)

# permission-before-retrieval／canonical-single-writer 是既有 floor，本片
# 只確認它們還在，不重新定義。
floor = spec.dig("capability_safety_floor", "invariants") || []
%w[permission_before_retrieval canonical_single_writer].each do |invariant|
  assert(floor.include?(invariant), "capability_safety_floor.invariants 必須含 #{invariant}", failures)
end
assert((spec["core_invariants"] || []).include?("PERSONAL_MEMORY_NE_COMPANY_CANONICAL_KNOWLEDGE"),
       "core_invariants 必須含 PERSONAL_MEMORY_NE_COMPANY_CANONICAL_KNOWLEDGE（本片的上位宣告）", failures)

# retrieval 的欄位詞彙讀自 recall_context_pack，不是本片自創。
pack_fields = spec.dig("recall_context_pack", "contract", "pack_required_fields") || []
retrieval_ref_fields = %w[selected_memories source_refs]
retrieval_ref_fields.each do |field|
  assert(pack_fields.include?(field),
         "recall_context_pack 的 pack_required_fields 必須含 #{field}（本片檢查它，不自創欄位名）", failures)
end

package_prefix = csb.dig("retrieval_exclusion", "evidence_package_ref_prefix").to_s
assert(!package_prefix.empty?, "retrieval_exclusion.evidence_package_ref_prefix 不得為空", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)
EVAL_ARGS = [allowed_purposes, forbidden_output_fields, required_promotion_steps,
             retrieval_ref_fields, package_prefix].freeze

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual = company_handling_failure(run, *EVAL_ARGS)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
  # 宣告的 prefix 不得與實際使用的封包 identity 脫鉤。
  assert(run["package_ref"].to_s.start_with?(package_prefix),
         "#{case_id} 的 package_ref 必須符合宣告的 evidence_package_ref_prefix（宣告不得漂移）", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = company_handling_failure(run, *EVAL_ARGS)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 卡片列的每一個 forbidden purpose 都必須有負例實際打過，不能只宣告在
# YAML 裡（切片 A 的 forbidden request kind 也是這樣要求的）。
covered_forbidden_purposes = sorted_set(
  negative_cases.map { |c| r = c["run"]; r.is_a?(Hash) ? r["purpose"] : nil }.compact & forbidden_purposes
)
missing_purposes = sorted_set(forbidden_purposes) - covered_forbidden_purposes
assert(missing_purposes.empty?, "forbidden purpose 未被負例實際打過：#{missing_purposes.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
ERROR_CONTRACT = {
  "CSB_HANDLING_NOT_MAP" => "company_side_evidence_boundary.error.handling_not_map",
  "CSB_HANDLING_UNKNOWN_FIELD" => "company_side_evidence_boundary.error.handling_unknown_field",
  "CSB_HANDLING_FORBIDDEN_FIELD" => "company_side_evidence_boundary.error.handling_forbidden_field",
  "CSB_PACKAGE_REF_NOT_EVIDENCE_PACKAGE" => "company_side_evidence_boundary.error.package_ref_not_evidence_package",
  "CSB_PURPOSE_NOT_ALLOWED" => "company_side_evidence_boundary.error.purpose_not_allowed",
  "CSB_PROMOTION_REF_ON_NON_PROMOTION_PURPOSE" => "company_side_evidence_boundary.error.promotion_ref_on_non_promotion_purpose",
  "CSB_PROMOTION_REF_NOT_URN" => "company_side_evidence_boundary.error.promotion_ref_not_urn",
  "CSB_PROMOTION_STEPS_INCOMPLETE" => "company_side_evidence_boundary.error.promotion_steps_incomplete",
  "CSB_RETRIEVAL_PACK_NOT_MAP" => "company_side_evidence_boundary.error.retrieval_pack_not_map",
  "CSB_RETRIEVAL_NAMES_HANDLED_PACKAGE" => "company_side_evidence_boundary.error.retrieval_names_handled_package",
  "CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE" => "company_side_evidence_boundary.error.retrieval_names_evidence_package",
  "CSB_FOLLOWUP_NOT_MAP" => "company_side_evidence_boundary.error.followup_not_map",
  "CSB_FOLLOWUP_CARRIES_CANONICAL" => "company_side_evidence_boundary.error.followup_carries_canonical",
  "CSB_FOLLOWUP_CARRIES_LIFECYCLE_FIELD" => "company_side_evidence_boundary.error.followup_carries_lifecycle_field",
  "CSB_FOLLOWUP_SUGGESTED_EXPERT_NOT_STRING" => "company_side_evidence_boundary.error.followup_suggested_expert_not_string"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "company_handling_failure")
assert(violations.empty?, "company_handling_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "company_handling_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS company side evidence boundary contract validation (purposes=#{allowed_purposes.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
