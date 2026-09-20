# frozen_string_literal: true
#
# Weekly Grill closeout 歷程 evaluator —— 由 SSP-323 切片 4
# （validate_weekly_review_cycle_contract.rb）與 EMEM-11 切片 1
# （validate_personal_memory_runtime_contract.rb）共用的單一實作。
#
# 抽取原因（EMEM-11 切片 1 repair-01，P1-2）：runtime 的 CLOSEOUT_COMMIT
# 原本自己列了一份 status／attempt 詞彙，而且完全沒有落地 weekly cycle 的
# promotion idempotency 規則——retry 換掉 promotion_idempotency_key 會直接
# 通過。修法不是在 runtime 再寫一份 closeout 檢查（那就是第二份實作），
# 而是把切片 4 的歷程 evaluator 抽成這支共用 helper：runtime 依
# review_period_id 分組，每一組就是切片 4 眼中的一段 closeout 歷程。
#
# 抽取原則：**行為逐字不變**。函式本體、檢查順序、錯誤碼、常數內容全部
# 原封搬移，只是加上 module 外殼。切片 4 自己的 fixture 套組（逐例比對
# 精確錯誤碼）就是這次搬移的 golden test，另加多重違規的順序敏感度探針。
module WeeklyCloseoutHistory
  OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

  REQUIRED_FIELDS = %w[
    review_period_id scheduled_review_period_start scheduled_anchor_at
    actual_closeout_at attempt_kind final_status catch_up_deadline_passed
    selected_item_refs item_dispositions
  ].freeze

  FORBIDDEN_FIELDS = %w[
    full_personal_store_ref weekly_work_summary personal_store_snapshot
    candidate_status record_status verification_status acceptance_status
    conflict_resolution_status
  ].freeze

  ATTEMPT_KINDS = %w[SCHEDULED CATCH_UP RETRY].freeze
  CLOSEOUT_STATUSES = %w[COMPLETE FAILED SKIPPED NO_PROMOTION].freeze
  TERMINAL_STATUSES = %w[COMPLETE SKIPPED NO_PROMOTION].freeze

  CADENCE_STRING_FIELDS = %w[scheduled_review_period_start scheduled_anchor_at actual_closeout_at].freeze
  ALLOWED_DISPOSITION_FIELDS = %w[category record_ref promotion_ref promotion_idempotency_key].freeze

  module_function

  def urn?(value)
    value.is_a?(String) && OMOS_URN.match?(value)
  end

  def blank?(value)
    !value.is_a?(String) || value.strip.empty?
  end

  def weekly_review_cycle_failure(run, categories, candidate_ref_prefix, record_ref_prefix)
    review_period_id = run["review_period_id"]
    return "WRC_REVIEW_PERIOD_ID_NOT_URN" unless urn?(review_period_id)

    closeouts = run["closeouts"]
    return "WRC_CLOSEOUTS_NOT_ARRAY" unless closeouts.is_a?(Array) && !closeouts.empty?

    scheduled_count = 0
    period_starts = Set.new
    terminal_indices = []
    # repair-01 F-02：追蹤 (promotion_ref, promotion_idempotency_key) 這一整
    # 組，不是只追蹤 key——reviewer 指出只比對 key 時，retry 換掉
    # promotion_ref 但沿用同一個 key 仍會放行。
    promotion_identity_by_item = {}

    closeouts.each_with_index do |entry, index|
      # repair-01 F-03：先確認 entry 本身是 Hash，才呼叫 entry.key?——修正前
      # 一個非 Hash 的 entry（例如純字串）會直接讓 evaluator 拋
      # NoMethodError 當掉，不是 fail-closed 拒絕。
      return "WRC_CLOSEOUT_ENTRY_NOT_MAP" unless entry.is_a?(Hash)
      return "WRC_REQUIRED_FIELD_MISSING" unless REQUIRED_FIELDS.all? { |f| entry.key?(f) }
      return "WRC_FORBIDDEN_FIELD_PRESENT" if FORBIDDEN_FIELDS.any? { |f| entry.key?(f) }
      # repair-01 P2：cadence 欄位原本只驗 key 存在、值可以是 nil——
      # 「catch-up 沿用原排定週期」這句話沒有一個可驗的值可以比對。
      return "WRC_CADENCE_FIELD_NOT_STRING" unless CADENCE_STRING_FIELDS.all? { |f| !blank?(entry[f]) }
      return "WRC_REVIEW_PERIOD_ID_MISMATCH" unless entry["review_period_id"] == review_period_id
      return "WRC_INVALID_ATTEMPT_KIND" unless ATTEMPT_KINDS.include?(entry["attempt_kind"])
      return "WRC_INVALID_FINAL_STATUS" unless CLOSEOUT_STATUSES.include?(entry["final_status"])

      scheduled_count += 1 if entry["attempt_kind"] == "SCHEDULED"
      period_starts << entry["scheduled_review_period_start"]
      terminal_indices << index if TERMINAL_STATUSES.include?(entry["final_status"])

      if entry["final_status"] == "SKIPPED"
        return "WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED" unless entry["catch_up_deadline_passed"] == true
      end

      selected = entry["selected_item_refs"]
      dispositions = entry["item_dispositions"]
      return "WRC_ITEM_DISPOSITION_INCOMPLETE" unless selected.is_a?(Array) && dispositions.is_a?(Hash) &&
                                                       selected.to_set == dispositions.keys.to_set

      dispositions.each do |item_ref, disposition|
        # repair-01 F-01：item ref 必須真的是 PersonalMemoryCandidate 的
        # identity（讀既有 personal_memory_resource_contracts 的
        # id_templates，不自己另立字串規則）——修正前 selected_item_refs／
        # item_dispositions 的 key 可以是任意字串，包括 PersonalMemoryRecord
        # 的 URN，直接打穿「只能引用 Candidate」的契約宣稱。
        return "WRC_ITEM_REF_NOT_CANDIDATE" unless item_ref.start_with?(candidate_ref_prefix)
        return "WRC_ITEM_DISPOSITION_NOT_MAP" unless disposition.is_a?(Hash)
        # repair-01 F-01：disposition 只能帶這四個欄位——修正前沒有
        # allowlist，`candidate_status`／`weekly_work_summary` 這類欄位可以
        # 直接夾帶進來，直接打穿 receipt「bounded refs + enum、不能 inline
        # content／lifecycle state」的宣稱。
        return "WRC_ITEM_DISPOSITION_UNKNOWN_FIELD" unless (disposition.keys - ALLOWED_DISPOSITION_FIELDS).empty?

        category = disposition["category"]
        return "WRC_UNKNOWN_DISPOSITION_CATEGORY" unless categories.include?(category)

        record_ref = disposition["record_ref"]
        promotion_ref = disposition["promotion_ref"]
        promotion_key = disposition["promotion_idempotency_key"]

        # repair-02：allowlist 只鎖住了 disposition 的欄位「名稱」，沒有鎖
        # 這些欄位的「值形狀」——reviewer 證明 record_ref／promotion_ref 可以
        # 塞一整個 Hash（例如再夾帶一次 weekly_work_summary），繞過上一輪
        # 才剛關掉的同一種 bypass。record_ref 綁既有 PersonalMemoryRecord
        # 的 id_template（跟 F-01 綁 Candidate 同樣的做法）；promotion_ref
        # 沒有對應的上游 id_template 可綁，退而求其次要求它至少是合法的
        # omos URN；promotion_idempotency_key 沒有格式約定，至少要求非空
        # 字串——三者都不接受 Hash／Array 等任意 payload。
        return "WRC_RECORD_REF_NOT_RECORD" if record_ref && !(record_ref.is_a?(String) && record_ref.start_with?(record_ref_prefix))
        return "WRC_PROMOTION_REF_NOT_URN" if promotion_ref && !urn?(promotion_ref)
        return "WRC_PROMOTION_IDEMPOTENCY_KEY_NOT_STRING" if promotion_key && blank?(promotion_key)

        return "WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_PROMOTION_REF" if category == "NEEDS_ORG_FOLLOWUP" && (record_ref || promotion_ref)

        # repair-01 F-02：promotion_ref 出現時，promotion_idempotency_key
        # 不得省略——修正前這整個 idempotency 檢查是 `next unless key`，
        # retry 只要把 key 刪掉就完全繞過本卡對「不重複 Promotion」的核心
        # 承諾。
        return "WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY" if promotion_ref && !promotion_key

        next unless promotion_key

        prior = promotion_identity_by_item[item_ref]
        if prior && (prior[:key] != promotion_key || prior[:ref] != promotion_ref)
          return "WRC_PROMOTION_IDENTITY_DRIFT"
        end

        promotion_identity_by_item[item_ref] = { key: promotion_key, ref: promotion_ref }
      end
    end

    return "WRC_MULTIPLE_SCHEDULED_ATTEMPTS" if scheduled_count > 1
    return "WRC_PERIOD_START_INCONSISTENT" if period_starts.size > 1
    return "WRC_DUPLICATE_TERMINAL_CLOSEOUT" if terminal_indices.size > 1
    return "WRC_CLOSEOUT_AFTER_TERMINAL" if terminal_indices.any? && terminal_indices.first != closeouts.size - 1

    nil
  end
end
