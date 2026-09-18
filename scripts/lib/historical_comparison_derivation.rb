# frozen_string_literal: true
#
# historical_comparison 的推導 evaluator —— 由 SSP-323 切片 1 與 SSP-324
# 切片 B 共用的單一實作。
#
# 切片 B repair-02：review 指出切片 B 只做了「詞彙綁定」（驗 category／
# disposition 是不是合法配對），沒做「結果綁定」——caller 可以自報
# MATERIALLY_CHANGED 加上合法的 correction metadata，在 content_hash／
# evidence_refs／redaction／sensitivity 全部相同的情況下照樣送出 revision，
# 直接穿過父卡 Acceptance #7。
#
# 上游 historical_comparison 早就規定 category／disposition 一律由
# evaluator 從 primitive signals 推導、呼叫端不得宣告。修法因此不是在切片
# B 再寫一份規則，而是把切片 1 的推導抽成這支共用 helper，讓 B 真的消費
# 它的推導結果。
#
# 抽取原則：行為逐字不變（切片 1 的 fixtures 與多重違規順序敏感度組合
# 前後逐字相同）。

require_relative "omos_contract_helpers"

module HistoricalComparisonDerivation
  OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze

  # 五態生命週期的既有欄位不得出現在 comparison run 裡——這是「不是第二套
  # 生命週期」的機器邊界，不只是文件宣告。
  FORBIDDEN_LIFECYCLE_FIELDS = %w[
    candidate_status record_status verification_status acceptance_status
    conflict_resolution_status
  ].freeze

  module_function

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
end
