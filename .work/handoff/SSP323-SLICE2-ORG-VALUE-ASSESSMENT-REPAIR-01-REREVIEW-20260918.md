# SSP-323 切片 2 — repair-01 定點複審交付包

## 鎖定

```
base             f38e82c
original_review  80bce4c
repair_commit    71124da   （程式碼修法本身）
branch           cc/ssp323-org-value-assessment
```

## 這輪只收三筆 P1

依你的判斷「repair-01 建議只收上面 3 個 P1；P2 可登 backlog」，本輪只動：

1. **F-01**：`needs_org_followup` 從 caller 自報 boolean 改成完全由
   evaluator 推導——run 裡出現這個欄位一律 `OVA_FORBIDDEN_SELF_DECLARED_
   FOLLOWUP` 拒絕；新增 `needs_org_followup?(run, high_dimensions)` 從
   `answer_provided`／`missing_external_evidence`／已佐證的 `high_
   dimensions` 三個原始訊號算出結果。
2. **F-02**：推導條件的「或」改回真的 OR：
   `(answer_provided == false || missing_external_evidence == true) &&
   high_dimensions.any?`，取代原本等同 AND 的兩個獨立 guard。
3. **F-03**：`dimension_reasons` 從「只有 HIGH 才要求」改成「九個構面全部
   都要非空 reasons」；`dimension_evidence_refs` 維持 HIGH-only（你明確
   保留這條）。

P2（結構性禁止宣稱比 enforcement 大）已登 `文件/待辦重整.md`，本輪未動。

## 請重播

```bash
ruby scripts/validate_organizational_value_assessment_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb                    # 應 PASS（聚合器）

# 你的三個原始 exploit 現在都被擋下：
# 1. run 裡宣告 needs_org_followup（任何值）→ OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP
grep -A6 "OVA_NEG_SELF_DECLARED_FOLLOWUP" 規格/v0.1/fixtures/organizational-value-assessment-negative-fixtures.json

# 2. 只有 answer_provided=false 成立（missing_external_evidence=false）
#    仍推導出 needs_org_followup=true
grep -A5 "OVA_POS_NEEDS_FOLLOWUP_UNANSWERED_ONLY" 規格/v0.1/fixtures/organizational-value-assessment-positive-fixtures.json

# 3. 只有 missing_external_evidence=true 成立（answer_provided=true）
#    仍推導出 needs_org_followup=true
grep -A5 "OVA_POS_NEEDS_FOLLOWUP_MISSING_EVIDENCE_ONLY" 規格/v0.1/fixtures/organizational-value-assessment-positive-fixtures.json

# 4. 九構面全 LOW、完全沒有 dimension_reasons → OVA_DIMENSION_REASONS_INCOMPLETE
grep -A6 "OVA_NEG_DIMENSION_REASONS_MISSING" 規格/v0.1/fixtures/organizational-value-assessment-negative-fixtures.json
```

## 逐 return site parity

15 個 return site（拿掉 4 個已不可能觸發的舊 guard，新增 2 個）逐一中和 →
15/15 全紅。額外驗證：中和本輪新增的 `OVA_FORBIDDEN_SELF_DECLARED_
FOLLOWUP` guard，不只直接呼叫新片會紅，呼叫聚合器
`validate_personal_memory_contract.rb` 也會轉紅（並印出
`slice validate_organizational_value_assessment_contract exited 1`）。
還原後兩個入口都回到 PASS，diff 對備份逐位元相同。

## 請特別判斷

1. **`needs_org_followup?` 完全移出 `assessment_failure` 的錯誤契約
   （`ERROR_CONTRACT`／`LoopReturnContract` 綁定）是否恰當**：它現在是
   一個獨立函式，回傳純布林值，不經過 `LoopReturnContract` 的 return-site
   AST 綁定機制（那套機制只綁 `assessment_failure`）。這跟切片 1 的
   `classify()` 是同樣的處理方式（`classify()` 也不受
   `LoopReturnContract` 約束），但 `classify()` 尾端有 `raise` 防禦
   unreachable 分支；`needs_org_followup?` 目前是純布林運算式，理論上沒有
   「推導不出結果」的分支需要防禦。請判斷這個處理是否足夠一致。
2. **移除三個舊負例（`OVA_NEG_FOLLOWUP_WHILE_ANSWERED`／`OVA_NEG_
   FOLLOWUP_WITHOUT_MISSING_EVIDENCE`／`OVA_NEG_FOLLOWUP_WITHOUT_ORG_
   VALUE`）是否洽當**：它們測試的自報檢查已經整個移除（改成禁止宣告該
   欄位），所以這三個 code 不再存在、負例也隨之刪除。請確認沒有遺漏應該
   換一種方式保留覆蓋的情境。

## Gate

```
ruby scripts/validate_*.rb（32 支）  → PASS
4 支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本輪未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
