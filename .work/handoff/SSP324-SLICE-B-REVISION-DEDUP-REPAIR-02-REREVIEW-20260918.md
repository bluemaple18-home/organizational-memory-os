# SSP-324 切片 B — repair-02 定點複審交付包

## 鎖定

```
base             72ac78d
repair-01        15074ce（delivery f250451）
repair_commit    （本次 commit，待 push 後補上）
branch           cc/ssp324-revision-dedup
```

## P1：從「詞彙綁定」改成「結果綁定」

你的裁決是「不要再複製規則，讓 B 實際消費 historical-comparison evaluator
的推導結果」。做法：

1. 切片 1 的推導（`compute_signals`／`historical_comparison_failure`／
   `classify`）抽成 `scripts/lib/historical_comparison_derivation.rb`，
   切片 1 改為呼叫它——**行為逐字不變**，golden 27/27 相同（22 筆 fixtures
   ＋ 5 組多重違規順序敏感度）。
2. 切片 B 的 submission **不再能宣告** `comparison_category`／
   `disposition`（夾帶即 `PKGREV_SELF_DECLARED_CLASSIFICATION`），改帶
   `comparison` primitive signals。
3. B 呼叫共用 evaluator 取得推導結果，之後所有規則都作用在推導出來的
   disposition 上。
4. primitives 必須綁回這條鏈：`current_content_hash` 必須等於本筆封包的
   hash；後續筆的 `prior_content_hash` 必須等於鏈上前一份的 hash。否則
   只是把自報往上挪一層。

## 你的 bypass 重播

```
自報 MATERIALLY_CHANGED（實質全同）        → PKGREV_SELF_DECLARED_CLASSIFICATION
  SAME_CONTENT_HASH=true / SAME_EVIDENCE_REFS=true
  SAME_REDACTION=true / SAME_SENSITIVITY=true
同一情境改送真實 primitives                → PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE
                                            （推導為 UNCHANGED / NO_RESEND）
宣稱 material_effect 但無 reasons/evidence → PKGREV_COMPARISON_FAILS_SLICE_1_CONTRACT
```

三層都擋住，而不是只擋住你示範的那一條路。

## 組合證明（第二個共用 evaluator）

```
在共用推導 helper 裡中和 COMPARISON_EVIDENCE_REF_NOT_URN：
  切片 1 → FAIL HC_NEG_EVIDENCE_REF_NOT_URN
  切片 B → FAIL PKGREV_NEG_COMPARISON_FAILS_SLICE_1
  aggregator → FAIL ... validate_evidence_package_revision_contract exited 1
```

## ⚠️ 本輪動到已 `ACCEPTED_GO` 的切片 1，請覆核

抽取共用推導必然要改切片 1。立場同前輪：行為逐字不變，證據為 golden
27/27（含多重違規順序敏感度，例如 `scalar_refs+missing_prior_hash` 前後都
仍是 `COMPARISON_MISSING_PRIOR_HASH`）。切片 1 的 `LoopReturnContract`
綁定改指向 helper 檔。

## P3 已修正

前一份 handoff 寫「39 筆 fixtures」是錯的。實際：

```
切片 A：3 positive + 34 negative = 37；37 + 5 probe = 42
切片 B：4 positive + 27 negative = 31
```

## 請重播

```bash
ruby scripts/validate_historical_comparison_contract.rb      # 應 PASS
ruby scripts/validate_minimal_evidence_package_contract.rb   # 應 PASS
ruby scripts/validate_evidence_package_revision_contract.rb  # 應 PASS
ruby scripts/validate_personal_memory_contract.rb            # 應 PASS

grep -A6 "PKGREV_NEG_SELF_DECLARED_CLASSIFICATION" 規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A12 "PKGREV_NEG_RESEND_UNCHANGED"           規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A8  "PKGREV_NEG_COMPARISON_HASH_NOT_BOUND"  規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
```

## 逐 return site parity

```
共用推導 helper（COMPARISON_）  14 sites → 14/14 全紅
共用封包 helper（MEP_）          22 sites → 22/22 全紅
切片 A（access_request）          4 sites → 4/4 全紅
切片 B（PKGREV_）                25 sites → 25/25 全紅
```

## 請特別判斷

1. **`comparison` 的 primitives 仍由提交方提供**：我已把它們綁回鏈上的
   真實 hash（current 對本筆封包、prior 對前一份封包），所以「宣稱」與
   「鏈上事實」必須一致。但 `prior_evidence_refs`／`current_evidence_refs`
   目前只綁到「與封包 evidence_refs 無交叉檢查」——`has_new_evidence` 的
   推導因此仍依賴提交方給的集合。要不要也把 `current_evidence_refs` 綁成
   必須等於封包的 `evidence_refs`？我傾向要，但那會讓兩者永遠相同、
   `prior_evidence_refs` 仍無從驗證，想先聽你的判斷再動。
2. **本輪已連續動了兩張 ACCEPTED_GO 的切片**（A 與 1）以抽共用 evaluator。
   請確認這個方向是否該繼續，或之後應改為「新 slice 一開始就寫進共用
   helper」。

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
golden：切片 1 → 27/27；切片 A → 42/42
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
