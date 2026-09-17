# SSP-323 切片 1 — repair-01 定點複審交付包

## 鎖定

```
base             38b5d59   （校正——原始 handoff 誤記 63464c3，見下方）
original_review  0205d7b
repair_commit    f7af260   （程式碼修法本身）
delivery         2fa4be2   （branch HEAD，含本 handoff／evidence 文件）
branch           cc/ssp323-historical-comparison
```

### SHA 校正

原始 `.work/handoff/SSP323-SLICE1-HISTORICAL-COMPARISON-REVIEW-20260917.md`
記 `base: 63464c3`。核對後這不是分支實際 base——`63464c3` 是 SSP-294 切片 C
驗收 commit；分支建立時 `main` 已經因 Owner 直接推的 SSP-323/324 決策文件
再走三個 commit（`7ef51cf`→`e4a4240`→`38b5d59`）。
`git merge-base main cc/ssp323-historical-comparison` = `38b5d59`，本次起
以此為準，原文件不回改。

## 這輪只收三筆 P1

依你的判斷「repair-01 建議只收這三筆 P1；P2 可留 residual」，本輪只動：

1. **F-01**：`contradiction_reasons` 補 `material_effect_dimensions`
   allowlist（與 `material_effect_reasons` 對稱）。
2. **F-02**：`classify()` 補成 total function——新增
   `COMPARISON_MISSING_PRIOR_HASH`（有 `prior_record_ref` 卻缺
   `prior_content_hash`）與 `COMPARISON_HASH_CHANGED_WITHOUT_EXPLANATION`
   （雜湊變了但沒有任何訊號解釋）兩條 fail-closed 檢查；`classify()` 尾端
   防禦分支從回傳 `nil/nil` 改成 `raise`。
3. **F-03**：`evidence_refs` 陣列形狀在 `compute_signals` 可能被呼叫前
   先鎖，非 `nil` 又非 `Array` 一律 `COMPARISON_EVIDENCE_REFS_NOT_ARRAY`。

P2（`category`／`disposition` 被夾帶但忽略）已登
`文件/待辦重整.md`，本輪未動。

## 請重播

```bash
ruby scripts/validate_historical_comparison_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb          # 應 PASS（聚合器）

# 三個你的原始 exploit 現在是負例：
grep -A2 "case_id.*HC_NEG_CONTRADICTS_UNRECOGNISED_DIMENSION" 規格/v0.1/fixtures/historical-comparison-negative-fixtures.json
grep -A2 "case_id.*HC_NEG_HASH_CHANGED_WITHOUT_EXPLANATION" 規格/v0.1/fixtures/historical-comparison-negative-fixtures.json
grep -A2 "case_id.*HC_NEG_MISSING_PRIOR_HASH" 規格/v0.1/fixtures/historical-comparison-negative-fixtures.json
grep -A2 "case_id.*HC_NEG_EVIDENCE_REFS_NOT_ARRAY" 規格/v0.1/fixtures/historical-comparison-negative-fixtures.json
```

## 逐 return site parity

14 個 return site（原 10 個 + 本輪新增 4 個）逐一中和 → 14/14 全紅。
額外驗證：中和本輪新增的 guard 之一（`COMPARISON_HASH_CHANGED_WITHOUT_
EXPLANATION`），不只直接呼叫新片會紅，呼叫聚合器
`validate_personal_memory_contract.rb` 也會轉紅（並印出
`slice validate_historical_comparison_contract exited 1`）。還原後兩個
入口都回到 PASS，diff 對備份逐位元相同。

## 請特別判斷

1. **F-02 的「hash 變了卻無解釋」是否真的窮盡**：目前邏輯是
   `historical_comparison_failure` 保證任何通過檢查、有 prior record 的
   run，若 `current_content_hash != prior_content_hash`，必然滿足
   `has_new_evidence || material_effect || contradicts_prior` 其中之一；
   因此 `classify()` 尾端只剩 `identical_to_prior` 為真的情形，理論上
   `raise` 真的不可達。請確認這個「窮盡性論證」本身有沒有漏洞。
2. **`classify()` raise 是否為恰當的 fail-closed 手段**：改成 raise 而非
   回傳另一種 sentinel 值，代表若真的觸發，聚合器／呼叫端會拿到未捕捉的
   例外而非乾淨的 deny。是否該改成回傳一個明確的
   `INTERNAL_INVARIANT_VIOLATION` 供上層捕捉，而不是讓 Ruby exception
   直接往外傳？

## Gate

```
ruby scripts/validate_*.rb（31 支）  → PASS
4 支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本輪未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
