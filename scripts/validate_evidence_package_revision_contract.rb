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

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/evidence-package-revision-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

EXPECTED_NEGATIVE_LABELS = [
  "a candidate_ref that is not an omos URN",
  "submissions that is not a non-empty array",
  "a submission that is not a map",
  "a submission carrying a field outside the allowlist",
  "a submission_id that is not an omos URN",
  "a package that is not a map",
  "a package_id that is not an omos URN",
  "a content_hash that is not a sha256 serialization",
  "a package whose candidate_ref disagrees with the chain",
  "a comparison_category not declared in historical_comparison.categories",
  "a disposition that is not the one upstream declares for the category",
  "a submission whose disposition authorizes no transmission",
  "a first submission that supersedes something",
  "a first submission that is not the UNSEEN/INITIAL_SUBMISSION case",
  "a later submission that supersedes nothing",
  "a predecessor that does not appear earlier in the chain",
  "a duplicate package_id within the chain",
  "two submissions naming the same predecessor",
  "a revision whose content_hash is unchanged from its predecessor",
  "a correction disposition with no correction_proposal_ref",
  "a correction_kind not declared in correction_flow",
  "a non-correction disposition carrying correction fields"
].freeze

# --- 結構驗證（fail-closed）------------------------------------------------

def revision_chain_failure(run, categories, dispositions, correction_kinds, allowed_fields,
                           non_transmittable, correction_required)
  candidate_ref = run["candidate_ref"]
  return "PKGREV_CANDIDATE_REF_NOT_URN" unless urn?(candidate_ref)

  submissions = run["submissions"]
  return "PKGREV_SUBMISSIONS_NOT_ARRAY" unless submissions.is_a?(Array) && !submissions.empty?

  seen_package_ids = Set.new
  claimed_predecessors = Set.new
  hash_by_package_id = {}

  submissions.each_with_index do |submission, index|
    return "PKGREV_SUBMISSION_NOT_MAP" unless submission.is_a?(Hash)
    return "PKGREV_SUBMISSION_UNKNOWN_FIELD" unless (submission.keys - allowed_fields).empty?
    return "PKGREV_SUBMISSION_ID_NOT_URN" unless urn?(submission["submission_id"])

    package = submission["package"]
    return "PKGREV_PACKAGE_NOT_MAP" unless package.is_a?(Hash)

    package_id = package["package_id"]
    return "PKGREV_PACKAGE_ID_NOT_URN" unless urn?(package_id)
    return "PKGREV_CONTENT_HASH_NOT_SHA256" unless SHA256_LOCKED_PATTERN.match?(package["content_hash"].to_s)
    return "PKGREV_PACKAGE_CANDIDATE_REF_MISMATCH" unless package["candidate_ref"] == candidate_ref

    category = submission["comparison_category"]
    return "PKGREV_UNKNOWN_CATEGORY" unless categories.include?(category)

    # disposition 必須是上游對該 category 宣告的那一個，不接受自報。
    # NEW_EVIDENCE 在上游是兩支（有／無 material effect），所以是「屬於
    # 該 category 的合法集合」而不是單一值。
    expected = dispositions.select { |key, _| key == category || key.start_with?("#{category}_") }.values
    return "PKGREV_DISPOSITION_NOT_DECLARED_FOR_CATEGORY" unless expected.include?(submission["disposition"])
    # UNCHANGED／NEW_EVIDENCE-without-material-effect 授權的是「不要送」，
    # 所以帶著這種 disposition 出現在提交鏈裡，本身就是矛盾。
    return "PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE" if non_transmittable.include?(submission["disposition"])

    predecessor = submission["supersedes_package_ref"]
    if index.zero?
      return "PKGREV_FIRST_SUBMISSION_SUPERSEDES" unless predecessor.nil?
      return "PKGREV_FIRST_SUBMISSION_NOT_INITIAL" unless category == "UNSEEN"
    else
      return "PKGREV_LATER_SUBMISSION_WITHOUT_PREDECESSOR" if predecessor.nil?
      return "PKGREV_PREDECESSOR_NOT_IN_CHAIN" unless seen_package_ids.include?(predecessor)
      return "PKGREV_CHAIN_FORK" if claimed_predecessors.include?(predecessor)
      # revision 必須真的改了內容；內容相同就是 UNCHANGED，而 UNCHANGED 不
      # 可傳輸（上面那條已擋），所以這裡出現等於繞過 dedup。
      return "PKGREV_CONTENT_HASH_UNCHANGED" if hash_by_package_id[predecessor] == package["content_hash"]

      claimed_predecessors << predecessor
    end

    correction_ref = submission["correction_proposal_ref"]
    correction_kind = submission["correction_kind"]
    if correction_required.include?(submission["disposition"])
      return "PKGREV_CORRECTION_REF_MISSING" unless urn?(correction_ref)
      return "PKGREV_UNKNOWN_CORRECTION_KIND" unless correction_kinds.include?(correction_kind)
    else
      return "PKGREV_CORRECTION_FIELDS_NOT_APPLICABLE" if correction_ref || correction_kind
    end

    return "PKGREV_DUPLICATE_PACKAGE_ID" if seen_package_ids.include?(package_id)

    seen_package_ids << package_id
    hash_by_package_id[package_id] = package["content_hash"]
  end

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
rev = spec.fetch("evidence_package_revision")

hc = spec.fetch("historical_comparison")
categories = hc.fetch("categories", [])
dispositions = hc.fetch("dispositions", {})
assert(categories.any? && dispositions.any?,
       "historical_comparison.categories／dispositions 必須存在（本片綁定它們，不重述）", failures)

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

# 切片 A 的封包是本片信封裡的內容物：確認那份契約存在，且本片讀的三個欄位
# 確實是它宣告的 required field，不是本片自己想出來的欄位名。
mep_required = spec.dig("minimal_evidence_package", "package_required_fields") || []
assert(mep_required.any?, "minimal_evidence_package.package_required_fields 必須存在（本片包的是它）", failures)
%w[package_id candidate_ref content_hash].each do |field|
  assert(mep_required.include?(field),
         "本片讀的 package.#{field} 必須是切片 A 宣告的 required field", failures)
end

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual = revision_chain_failure(run, categories, dispositions, correction_kinds, allowed_fields,
                                  non_transmittable, correction_required)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = revision_chain_failure(run, categories, dispositions, correction_kinds, allowed_fields,
                                  non_transmittable, correction_required)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 卡片 Acceptance #7：每一個 non-transmittable disposition 都必須有負例
# 實際打過，不能只宣告在 YAML 裡。
covered_non_transmittable = sorted_set(
  negative_cases.flat_map { |c|
    subs = c.dig("run", "submissions")
    subs.is_a?(Array) ? subs.map { |s| s.is_a?(Hash) ? s["disposition"] : nil } : []
  }.compact & non_transmittable
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
  "PKGREV_PACKAGE_ID_NOT_URN" => "evidence_package_revision.error.package_id_not_urn",
  "PKGREV_CONTENT_HASH_NOT_SHA256" => "evidence_package_revision.error.content_hash_not_sha256",
  "PKGREV_PACKAGE_CANDIDATE_REF_MISMATCH" => "evidence_package_revision.error.package_candidate_ref_mismatch",
  "PKGREV_UNKNOWN_CATEGORY" => "evidence_package_revision.error.unknown_category",
  "PKGREV_DISPOSITION_NOT_DECLARED_FOR_CATEGORY" => "evidence_package_revision.error.disposition_not_declared_for_category",
  "PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE" => "evidence_package_revision.error.resend_despite_non_transmittable",
  "PKGREV_FIRST_SUBMISSION_SUPERSEDES" => "evidence_package_revision.error.first_submission_supersedes",
  "PKGREV_FIRST_SUBMISSION_NOT_INITIAL" => "evidence_package_revision.error.first_submission_not_initial",
  "PKGREV_LATER_SUBMISSION_WITHOUT_PREDECESSOR" => "evidence_package_revision.error.later_submission_without_predecessor",
  "PKGREV_PREDECESSOR_NOT_IN_CHAIN" => "evidence_package_revision.error.predecessor_not_in_chain",
  "PKGREV_CHAIN_FORK" => "evidence_package_revision.error.chain_fork",
  "PKGREV_CONTENT_HASH_UNCHANGED" => "evidence_package_revision.error.content_hash_unchanged",
  "PKGREV_DUPLICATE_PACKAGE_ID" => "evidence_package_revision.error.duplicate_package_id",
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
  puts "PASS evidence package revision contract validation (categories=#{categories.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
