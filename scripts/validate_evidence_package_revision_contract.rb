#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-324（EMEM-10）切片 B：Minimal Evidence Package 的 immutable
# submission／revision 語意與 dedup-resend 規則。
#
# 驗證單位是**同一個 candidate 的提交鏈**，不是單筆封包：「不得每週因同一
# 知識再次發生就往公司重送 duplicate package」與「previous package 必須可
# 追溯」都只在跨筆比對時才看得見——跟 weekly_review_cycle 對 closeout 歷史
# 學到的是同一課。
#
# 不重述任何上游：
#   - dedup／resend 規則就是 `historical_comparison.dispositions`，評估當下
#     從上游讀。SSP-324 卡片那張對照表一個字都不抄。
#   - revision 走既有 `correction_flow.contract.correction_kinds`，不建立
#     第二套 revision lifecycle。
#   - 封包內部形狀是切片 A 的職責（其 package_required_fields 是封閉
#     allowlist）。本片把 A 的封包包在信封裡，而不是往封包加欄位——後者會
#     逼著重開一個已驗收的封閉 shape。
#
# 切片 A 兩輪 NO_GO 的教訓在這裡先套用，不等 review 抓：
#   1. 欄位名有 allowlist 不等於值被鎖 → 本片讀到的每個值都做形狀檢查。
#   2. 綁上游要綁到 identity 那一層 → sha256 用既有 SHA256_LOCKED_PATTERN。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"
require_relative "lib/minimal_evidence_package_shape"
require_relative "lib/historical_comparison_derivation"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/evidence-package-revision-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json")
VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
STD01_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")

MEPShape = MinimalEvidencePackageShape
HCD = HistoricalComparisonDerivation

def urn?(value)
  MEPShape.urn?(value)
end

EXPECTED_NEGATIVE_LABELS = [
  "a candidate_ref that is not an omos URN",
  "submissions that is not a non-empty array",
  "a submission that is not a map",
  "a submission carrying a field outside the allowlist",
  "a submission_id that is not an omos URN",
  "a package that is not a map",
  "a package that does not pass the slice A package contract",
  "a package whose candidate_ref disagrees with the chain",
  "a submission declaring comparison_category or disposition itself",
  "a comparison block that is not a map",
  "a comparison that does not pass the slice 1 historical comparison contract",
  "a comparison current_content_hash not bound to the submission package",
  "a comparison prior hash or prior record not bound to the chain",
  "a submission whose disposition authorizes no transmission",
  "a first submission that supersedes something",
  "a first submission that is not the UNSEEN/INITIAL_SUBMISSION case",
  "a later submission that supersedes nothing",
  "a predecessor that does not appear earlier in the chain",
  "a duplicate package_id within the chain",
  "a duplicate submission_id within the chain",
  "a later submission repeating the UNSEEN/INITIAL_SUBMISSION case",
  "two submissions naming the same predecessor",
  "a correction disposition with no correction_proposal_ref",
  "a correction_kind not declared in correction_flow",
  "a non-correction disposition carrying correction fields"
].freeze

# --- 結構驗證（fail-closed）------------------------------------------------

def revision_chain_failure(run, dispositions, material_dimensions, correction_kinds, allowed_fields,
                           forbidden_self_declared, non_transmittable, correction_required, bindings)
  candidate_ref = run["candidate_ref"]
  return "PKGREV_CANDIDATE_REF_NOT_URN" unless urn?(candidate_ref)

  submissions = run["submissions"]
  return "PKGREV_SUBMISSIONS_NOT_ARRAY" unless submissions.is_a?(Array) && !submissions.empty?

  seen_package_ids = Set.new
  seen_submission_ids = Set.new
  claimed_predecessors = Set.new
  hash_by_package_id = {}

  submissions.each_with_index do |submission, index|
    return "PKGREV_SUBMISSION_NOT_MAP" unless submission.is_a?(Hash)
    # repair-02：category／disposition 是推導結果，不是輸入。夾帶即拒絕，
    # 跟切片 1／切片 2 對自報分類的處理一致。
    return "PKGREV_SELF_DECLARED_CLASSIFICATION" if forbidden_self_declared.any? { |f| submission.key?(f) }
    return "PKGREV_SUBMISSION_UNKNOWN_FIELD" unless (submission.keys - allowed_fields).empty?
    return "PKGREV_SUBMISSION_ID_NOT_URN" unless urn?(submission["submission_id"])

    package = submission["package"]
    return "PKGREV_PACKAGE_NOT_MAP" unless package.is_a?(Hash)
    # repair-01 F-01：layering 不能只是宣稱。信封裡的封包直接丟進切片 A
    # 的同一支 evaluator（MEPShape.package_failure），不是在這裡另寫一份
    # 檢查，也不是靠「同掛 aggregator」。expected_package_ref 傳 nil，因為
    # 本片沒有 access_request 這個概念。
    return "PKGREV_PACKAGE_FAILS_SLICE_A_CONTRACT" unless MEPShape.package_failure(package, bindings).nil?

    package_id = package["package_id"]
    return "PKGREV_PACKAGE_CANDIDATE_REF_MISMATCH" unless package["candidate_ref"] == candidate_ref

    # repair-02：category／disposition 由切片 1 的同一支 evaluator 從
    # primitive signals 推導，本片不再讀任何自報分類。
    comparison = submission["comparison"]
    return "PKGREV_COMPARISON_NOT_MAP" unless comparison.is_a?(Hash)
    return "PKGREV_COMPARISON_FAILS_SLICE_1_CONTRACT" unless HCD.historical_comparison_failure(comparison, material_dimensions).nil?

    # primitives 必須描述這條鏈本身，否則只是把自報往上挪一層。
    return "PKGREV_COMPARISON_HASH_NOT_BOUND_TO_PACKAGE" unless comparison["current_content_hash"] == package["content_hash"]

    derived = HCD.classify(comparison, dispositions)
    category = derived[:category]
    disposition = derived[:disposition]
    # UNCHANGED／NEW_EVIDENCE-without-material-effect 推導出的是「不要送」，
    # 所以它出現在提交鏈裡本身就是矛盾。
    return "PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE" if non_transmittable.include?(disposition)

    predecessor = submission["supersedes_package_ref"]
    if index.zero?
      return "PKGREV_FIRST_SUBMISSION_SUPERSEDES" unless predecessor.nil?
      # 這裡不需要再檢查 comparison["prior_record_ref"] 為 nil：category 為
      # UNSEEN 的定義就是 no_prior_record，上一行已經保證。多寫一條會是
      # 永遠不可達的 dead code。
      return "PKGREV_FIRST_SUBMISSION_NOT_INITIAL" unless category == "UNSEEN"
    else
      # repair-01 F-03：原本只要求「第一筆必須 UNSEEN」，沒有反向要求
      # 「UNSEEN 只能是第一筆」——第二筆再宣稱一次 initial submission 會
      # 直接通過。單向檢查正是這條線一再被抓到的同一種洞。
      return "PKGREV_REPEATED_INITIAL_SUBMISSION" if category == "UNSEEN"
      return "PKGREV_LATER_SUBMISSION_WITHOUT_PREDECESSOR" if predecessor.nil?
      return "PKGREV_PREDECESSOR_NOT_IN_CHAIN" unless seen_package_ids.include?(predecessor)
      return "PKGREV_CHAIN_FORK" if claimed_predecessors.include?(predecessor)
      # 前一份的 hash 必須真的是鏈上那一份的 hash——這是「有沒有 material
      # effect」這個推導能不能被信任的前提。
      return "PKGREV_COMPARISON_PRIOR_NOT_BOUND_TO_CHAIN" unless comparison["prior_content_hash"] == hash_by_package_id[predecessor]

      claimed_predecessors << predecessor
    end

    correction_ref = submission["correction_proposal_ref"]
    correction_kind = submission["correction_kind"]
    if correction_required.include?(disposition)
      return "PKGREV_CORRECTION_REF_MISSING" unless urn?(correction_ref)
      return "PKGREV_UNKNOWN_CORRECTION_KIND" unless correction_kinds.include?(correction_kind)
    else
      return "PKGREV_CORRECTION_FIELDS_NOT_APPLICABLE" if correction_ref || correction_kind
    end

    return "PKGREV_DUPLICATE_PACKAGE_ID" if seen_package_ids.include?(package_id)
    # repair-01 P2：submission_id 也要唯一，否則 immutable submission audit
    # 會出現身份歧義。
    return "PKGREV_DUPLICATE_SUBMISSION_ID" if seen_submission_ids.include?(submission["submission_id"])

    seen_package_ids << package_id
    seen_submission_ids << submission["submission_id"]
    hash_by_package_id[package_id] = package["content_hash"]
  end

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
rev = spec.fetch("evidence_package_revision")

hc = spec.fetch("historical_comparison")
dispositions = hc.fetch("dispositions", {})
material_dimensions = hc.fetch("material_effect_dimensions", [])
assert(dispositions.any? && material_dimensions.any?,
       "historical_comparison.dispositions／material_effect_dimensions 必須存在（本片消費它們的推導，不重述）", failures)
forbidden_self_declared = rev.fetch("forbidden_self_declared_fields", [])
assert(sorted_set(forbidden_self_declared) == sorted_set(%w[comparison_category disposition]),
       "forbidden_self_declared_fields 必須是 comparison_category／disposition（推導結果不得自報）", failures)
assert((forbidden_self_declared & rev.fetch("submission_allowed_fields", [])).empty?,
       "被禁止自報的欄位不得同時出現在 submission_allowed_fields", failures)

correction_kinds = spec.dig("correction_flow", "contract", "correction_kinds") || {}
assert(correction_kinds.any?,
       "correction_flow.contract.correction_kinds 必須存在（revision 走既有 correction，不另建 lifecycle）", failures)

allowed_fields = rev.fetch("submission_allowed_fields", [])
assert(allowed_fields.include?("package") && allowed_fields.include?("supersedes_package_ref"),
       "submission_allowed_fields 必須含 package 與 supersedes_package_ref", failures)

non_transmittable = rev.fetch("non_transmittable_dispositions", [])
correction_required = rev.fetch("correction_required_dispositions", [])
assert(non_transmittable.any?, "non_transmittable_dispositions 不得為空", failures)
# 這兩份清單是本片新增的決定，但只能從上游既有詞彙裡挑，不得自創值。
(non_transmittable + correction_required).each do |value|
  assert(dispositions.values.include?(value),
         "#{value} 不在 historical_comparison.dispositions 宣告的值裡（不得自創 disposition）", failures)
end
assert((non_transmittable.to_set & correction_required.to_set).empty?,
       "non_transmittable 與 correction_required 不得重疊", failures)

# repair-01 F-01：切片 A 的封包 evaluator 由本片直接呼叫（共用 helper），
# 所以綁定也用同一支 build_bindings 建立——兩片不可能各自讀出不同版本的
# 上游。契約的 required_fields 宣告也必須與共用 helper 的實作一致。
vocab = read_yaml(VOCAB_PATH)
std01 = read_json(STD01_SCHEMA_PATH)
bindings, binding_problems = MEPShape.build_bindings(spec, vocab, std01)
binding_problems.each { |problem| assert(false, problem, failures) }

mep_required = spec.dig("minimal_evidence_package", "package_required_fields") || []
assert(sorted_set(mep_required) == sorted_set(MEPShape::PACKAGE_REQUIRED_FIELDS),
       "minimal_evidence_package.package_required_fields 必須與共用 evaluator 的實作一致", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual = revision_chain_failure(run, dispositions, material_dimensions, correction_kinds, allowed_fields,
                                  forbidden_self_declared, non_transmittable, correction_required, bindings)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = revision_chain_failure(run, dispositions, material_dimensions, correction_kinds, allowed_fields,
                                  forbidden_self_declared, non_transmittable, correction_required, bindings)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 卡片 Acceptance #7：每一個 non-transmittable disposition 都必須有負例
# 實際打過，不能只宣告在 YAML 裡。
covered_non_transmittable = sorted_set(
  negative_cases.select { |c| c.fetch("expected_failure_code") == "PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE" }
                .map { |c| c["derived_disposition_under_test"] }.compact & non_transmittable
)
missing_nt = sorted_set(non_transmittable) - covered_non_transmittable
assert(missing_nt.empty?, "non-transmittable disposition 未被負例實際打過：#{missing_nt.to_a.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------
ERROR_CONTRACT = {
  "PKGREV_CANDIDATE_REF_NOT_URN" => "evidence_package_revision.error.candidate_ref_not_urn",
  "PKGREV_SUBMISSIONS_NOT_ARRAY" => "evidence_package_revision.error.submissions_not_array",
  "PKGREV_SUBMISSION_NOT_MAP" => "evidence_package_revision.error.submission_not_map",
  "PKGREV_SUBMISSION_UNKNOWN_FIELD" => "evidence_package_revision.error.submission_unknown_field",
  "PKGREV_SUBMISSION_ID_NOT_URN" => "evidence_package_revision.error.submission_id_not_urn",
  "PKGREV_PACKAGE_NOT_MAP" => "evidence_package_revision.error.package_not_map",
  "PKGREV_PACKAGE_FAILS_SLICE_A_CONTRACT" => "evidence_package_revision.error.package_fails_slice_a_contract",
  "PKGREV_PACKAGE_CANDIDATE_REF_MISMATCH" => "evidence_package_revision.error.package_candidate_ref_mismatch",
  "PKGREV_SELF_DECLARED_CLASSIFICATION" => "evidence_package_revision.error.self_declared_classification",
  "PKGREV_COMPARISON_NOT_MAP" => "evidence_package_revision.error.comparison_not_map",
  "PKGREV_COMPARISON_FAILS_SLICE_1_CONTRACT" => "evidence_package_revision.error.comparison_fails_slice_1_contract",
  "PKGREV_COMPARISON_HASH_NOT_BOUND_TO_PACKAGE" => "evidence_package_revision.error.comparison_hash_not_bound_to_package",
  "PKGREV_COMPARISON_PRIOR_NOT_BOUND_TO_CHAIN" => "evidence_package_revision.error.comparison_prior_not_bound_to_chain",
  "PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE" => "evidence_package_revision.error.resend_despite_non_transmittable",
  "PKGREV_FIRST_SUBMISSION_SUPERSEDES" => "evidence_package_revision.error.first_submission_supersedes",
  "PKGREV_FIRST_SUBMISSION_NOT_INITIAL" => "evidence_package_revision.error.first_submission_not_initial",
  "PKGREV_LATER_SUBMISSION_WITHOUT_PREDECESSOR" => "evidence_package_revision.error.later_submission_without_predecessor",
  "PKGREV_PREDECESSOR_NOT_IN_CHAIN" => "evidence_package_revision.error.predecessor_not_in_chain",
  "PKGREV_CHAIN_FORK" => "evidence_package_revision.error.chain_fork",
  "PKGREV_DUPLICATE_PACKAGE_ID" => "evidence_package_revision.error.duplicate_package_id",
  "PKGREV_DUPLICATE_SUBMISSION_ID" => "evidence_package_revision.error.duplicate_submission_id",
  "PKGREV_REPEATED_INITIAL_SUBMISSION" => "evidence_package_revision.error.repeated_initial_submission",
  "PKGREV_CORRECTION_REF_MISSING" => "evidence_package_revision.error.correction_ref_missing",
  "PKGREV_UNKNOWN_CORRECTION_KIND" => "evidence_package_revision.error.unknown_correction_kind",
  "PKGREV_CORRECTION_FIELDS_NOT_APPLICABLE" => "evidence_package_revision.error.correction_fields_not_applicable"
}.freeze

declared_codes = ERROR_CONTRACT.keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "revision_chain_failure")
assert(violations.empty?, "revision_chain_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "revision_chain_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS evidence package revision contract validation (dispositions=#{dispositions.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
