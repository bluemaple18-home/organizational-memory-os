# frozen_string_literal: true
#
# Minimal Evidence Package 的封包形狀 evaluator —— 由 SSP-324 切片 A 與
# 切片 B 共用的單一實作。
#
# 切片 B repair-01：review 指出「A/B layering 目前只是宣稱，沒有組合
# enforcement」——B 的正例封包只有 3/20 欄仍 PASS，額外塞 extra_secret 也
# PASS，因為 aggregator 只是分別跑兩組 fixtures，不會把 B 裡的 package 丟
# 進 A 的 evaluator。修法不是在 B 再寫一份封包檢查（那就是第二份實作），
# 而是把 A 的封包 evaluator 抽成這支共用 helper，A 與 B 都呼叫它。
#
# 抽取原則：**行為逐字不變**。A 原本的檢查順序（含 package_ref mismatch
# 夾在 unknown-field 與 ref 檢查之間）完整保留——mismatch 那條依賴
# access_request，所以用 expected_package_ref 參數傳入；B 沒有 request 這
# 個概念，傳 nil 即跳過該條，其餘逐條相同。

require_relative "omos_contract_helpers"

module MinimalEvidencePackageShape
  OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

  PACKAGE_REQUIRED_FIELDS = %w[
    package_id tenant_id employee_owner_ref candidate_ref scope_mode
    ownership_mode visibility_scope sensitivity consent_ref content_snapshot
    content_hash evidence_refs source_anchor_refs provenance_chain_refs
    source_acl_snapshot_ref redaction_ref organizational_value_reasons
    unresolved_question suggested_expert submitted_at
  ].freeze

  PACKAGE_FORBIDDEN_FIELDS = %w[
    full_personal_store_ref personal_store_snapshot weekly_work_summary
    candidate_status record_status verification_status acceptance_status
    conflict_resolution_status
  ].freeze

  # 只能驗到「generic omos URN」的欄位：org 端 identity（tenant／employee／
  # consent／redaction），不是 OMOS canonical resource，上游沒有對應 kind。
  URN_FIELDS = %w[package_id employee_owner_ref].freeze
  # 必為「非空陣列」的 ref 清單欄位（元素形狀另外依 ref_binding 逐欄驗）。
  REF_LIST_FIELDS = %w[evidence_refs source_anchor_refs provenance_chain_refs].freeze
  TEXT_FIELDS = %w[tenant_id sensitivity content_snapshot content_hash submitted_at].freeze
  NULLABLE_STRING_FIELDS = %w[consent_ref redaction_ref unresolved_question suggested_expert].freeze

  EVIDENCE_KIND = "EVIDENCE_RECORD"
  SOURCE_ANCHOR_KIND = "SOURCE_ANCHOR"

  module_function

  def urn?(value)
    value.is_a?(String) && OMOS_URN.match?(value)
  end

  def blank?(value)
    !value.is_a?(String) || value.strip.empty?
  end

  def kebab(kind)
    kind.to_s.downcase.tr("_", "-")
  end

  # canonical ref = common-vocabulary 的 ref_template + resource_kinds 詞彙
  # + identifiers.omos_generated.algorithm 宣告的 UUID 版本。三者都在評估
  # 當下讀上游，這裡不手抄 URN 結構，也不把版本號寫死。
  # UUID 版本位在第三段首字、variant 位在第四段首字（RFC 9562：8/9/a/b）。
  def uuid_pattern(version_digit)
    "[0-9a-f]{8}-[0-9a-f]{4}-#{version_digit}[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
  end

  def build_canonical_ref_pattern(ref_template, kind, version_digit)
    literal = Regexp.escape(ref_template).sub(Regexp.escape("{resource-kind}"), Regexp.escape(kebab(kind)))
                                         .sub(Regexp.escape("{uuid}"), uuid_pattern(version_digit))
    /\A#{literal}\z/
  end

  def build_id_template_pattern(id_template, version_digit)
    literal = Regexp.escape(id_template).sub(Regexp.escape("{uuidv7}"), uuid_pattern(version_digit))
    /\A#{literal}\z/
  end

  def canonical_ref?(value, allowed_kinds, patterns)
    return false unless value.is_a?(String)

    allowed_kinds.any? { |kind| patterns[kind]&.match?(value) }
  end

  # 封包形狀本身。expected_package_ref 非 nil 時，在原本的位置做
  # package_ref mismatch 檢查（切片 A 的 bounded lookup 語意）；切片 B 沒有
  # access_request，傳 nil 跳過該條，其餘逐條相同。
  def package_failure(package, bindings, expected_package_ref = nil)
    return "MEP_PACKAGE_NOT_MAP" unless package.is_a?(Hash)
    return "MEP_REQUIRED_FIELD_MISSING" unless PACKAGE_REQUIRED_FIELDS.all? { |f| package.key?(f) }
    return "MEP_FORBIDDEN_FIELD_PRESENT" if PACKAGE_FORBIDDEN_FIELDS.any? { |f| package.key?(f) }
    return "MEP_PACKAGE_UNKNOWN_FIELD" unless (package.keys - PACKAGE_REQUIRED_FIELDS).empty?

    unless expected_package_ref.nil?
      return "MEP_PACKAGE_REF_MISMATCH" unless package["package_id"] == expected_package_ref
    end

    patterns = bindings[:canonical_ref_patterns]
    return "MEP_REF_FIELD_NOT_URN" unless URN_FIELDS.all? { |f| urn?(package[f]) }
    return "MEP_CANDIDATE_REF_NOT_CANDIDATE" unless package["candidate_ref"].is_a?(String) &&
                                                    bindings[:candidate_ref_pattern].match?(package["candidate_ref"])
    return "MEP_REF_LIST_NOT_ARRAY" unless REF_LIST_FIELDS.all? { |f| package[f].is_a?(Array) && !package[f].empty? }

    return "MEP_EVIDENCE_REF_NOT_CANONICAL" unless package["evidence_refs"].all? { |r| canonical_ref?(r, [EVIDENCE_KIND], patterns) }
    return "MEP_SOURCE_ANCHOR_REF_NOT_CANONICAL" unless package["source_anchor_refs"].all? { |r| canonical_ref?(r, [SOURCE_ANCHOR_KIND], patterns) }
    return "MEP_PROVENANCE_REF_NOT_CANONICAL" unless package["provenance_chain_refs"].all? { |r| canonical_ref?(r, bindings[:all_resource_kinds], patterns) }
    return "MEP_ACL_SNAPSHOT_REF_NOT_CANONICAL" unless package["source_acl_snapshot_ref"].is_a?(String) &&
                                                       bindings[:acl_snapshot_pattern].match?(package["source_acl_snapshot_ref"])

    return "MEP_TEXT_FIELD_BLANK" if TEXT_FIELDS.any? { |f| blank?(package[f]) }
    return "MEP_NULLABLE_FIELD_NOT_STRING" if NULLABLE_STRING_FIELDS.any? { |f| !package[f].nil? && !package[f].is_a?(String) }

    reasons = package["organizational_value_reasons"]
    return "MEP_VALUE_REASONS_EMPTY" unless reasons.is_a?(Array) && !reasons.empty? && reasons.all? { |r| !blank?(r) }

    content = package["content_snapshot"]
    return "MEP_CONTENT_SNAPSHOT_OVER_BOUND" if content.bytesize > bindings[:max_content_bytes]
    return "MEP_CONTENT_HASH_NOT_SHA256" unless SHA256_LOCKED_PATTERN.match?(package["content_hash"].to_s)
    return "MEP_CONTENT_HASH_MISMATCH" unless package["content_hash"] == "sha256:#{Digest::SHA256.hexdigest(content)}"

    mode = bindings[:mode_definitions][package["scope_mode"]]
    return "MEP_UNKNOWN_SCOPE_MODE" unless mode.is_a?(Hash)

    return "MEP_OWNERSHIP_MODE_MISMATCH" unless package["ownership_mode"] == mode["ownership_mode"]
    return "MEP_VISIBILITY_SCOPE_MISMATCH" unless package["visibility_scope"] == mode["visibility_scope"]

    if mode["consent_or_notice_required"] == "CONSENT_REQUIRED"
      return "MEP_CONSENT_REQUIRED_BUT_MISSING" if blank?(package["consent_ref"])
    end

    nil
  end

  # 所有上游綁定集中在這裡建立，A 與 B 共用同一組，不會各自讀出不同版本。
  # 回傳 [bindings, problems]；problems 由呼叫端 assert，讓兩支 validator
  # 的失敗訊息維持各自原本的樣子。
  def build_bindings(spec, vocab, std01)
    problems = []

    all_resource_kinds = vocab.fetch("resource_kinds", [])
    ref_template = vocab.dig("identifiers", "omos_generated", "ref_template")
    problems << "common-vocabulary.resource_kinds 必須存在（本片綁定它，不重述）" if all_resource_kinds.empty?
    unless ref_template.is_a?(String) && ref_template.include?("{resource-kind}") && ref_template.include?("{uuid}")
      problems << "common-vocabulary.identifiers.omos_generated.ref_template 必須存在且含兩個 placeholder"
    end
    [EVIDENCE_KIND, SOURCE_ANCHOR_KIND].each do |kind|
      problems << "common-vocabulary.resource_kinds 必須含 #{kind}（本片 pin 它）" unless all_resource_kinds.include?(kind)
    end

    id_algorithm = vocab.dig("identifiers", "omos_generated", "algorithm").to_s
    id_serialization = vocab.dig("identifiers", "omos_generated", "id_serialization").to_s
    unless /\AUUIDv(\d)\z/.match?(id_algorithm)
      problems << "common-vocabulary.identifiers.omos_generated.algorithm 必須是 UUIDv<n> 形式（matcher 由它推導）"
    end
    unless id_serialization == "lowercase-hyphenated-uuid"
      problems << "id_serialization 若改變，本 matcher 的小寫十六進位假設就不再成立，必須一起檢討"
    end
    version_digit = id_algorithm[/\AUUIDv(\d)\z/, 1] || "7"

    patterns = all_resource_kinds.each_with_object({}) do |kind, acc|
      acc[kind] = build_canonical_ref_pattern(ref_template.to_s, kind, version_digit)
    end.freeze

    acl_pattern_source = std01.dig("properties", "access", "properties", "acl_snapshot_ref", "pattern")
    unless acl_pattern_source.is_a?(String) && !acl_pattern_source.empty?
      problems << "STD-01 的 access.acl_snapshot_ref.pattern 必須存在（本片綁定它，不重述）"
    end

    candidate_id_template = spec.dig("personal_memory_resource_contracts", "shared_constraints", "id_templates",
                                     "PersonalMemoryCandidate")
    unless candidate_id_template.is_a?(String) && candidate_id_template.include?("{uuidv7}")
      problems << "id_templates.PersonalMemoryCandidate 的 placeholder 必須是 {uuidv7}（matcher 依它套用 identity shape）"
    end

    mep = spec["minimal_evidence_package"] || {}
    max_content_bytes = mep.dig("content_bound", "max_bytes")
    unless max_content_bytes.is_a?(Integer) && max_content_bytes.positive?
      problems << "minimal_evidence_package.content_bound.max_bytes 必須是正整數（policy 住在契約，不在 evaluator）"
    end

    bindings = {
      all_resource_kinds: all_resource_kinds,
      canonical_ref_patterns: patterns,
      acl_snapshot_pattern: Regexp.new(acl_pattern_source.to_s),
      candidate_ref_pattern: build_id_template_pattern(candidate_id_template.to_s, version_digit),
      mode_definitions: spec.dig("ownership_visibility_contract", "mode_definitions") || {},
      max_content_bytes: max_content_bytes.is_a?(Integer) ? max_content_bytes : 0,
      uuid_version_digit: version_digit
    }
    [bindings, problems]
  end
end
