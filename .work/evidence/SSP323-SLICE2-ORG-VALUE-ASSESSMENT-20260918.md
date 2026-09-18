# SSP-323 切片 2 — evidence

日期：2026-09-18　branch：`cc/ssp323-org-value-assessment`　base：`f38e82c`

## 交付

```
規格/v0.1/personal-harness-integration.yaml   +organizational_value_assessment 區塊
scripts/validate_organizational_value_assessment_contract.rb   224 行（< 400）
規格/v0.1/fixtures/organizational-value-assessment-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
```

## 設計回應

### Assessment != Promotion Eligibility

`FORBIDDEN_LIFECYCLE_FIELDS`（與切片 1 同一份清單：`candidate_status`／
`record_status`／`verification_status`／`acceptance_status`／
`conflict_resolution_status`）結構性禁止出現在 assessment run 裡。

### 不要求假精準單一分數

`FORBIDDEN_SCORE_FIELDS`（`overall_score`／`value_score`／`total_score`／
`score`／`aggregate_score`）結構性禁止——run 裡沒有任何地方能塞一個看起來
像聚合分數的欄位，只有九個構面各自的 `LOW`/`MEDIUM`/`HIGH`。

### 完整性 + 佐證，不是推導

九個構面本質上都是人的價值判斷，沒有原始資料可以像切片 1 那樣算出
`no_prior_record`／`identical_to_prior`／`has_new_evidence`。這裡機器能
守住的邊界改成：

1. **完整性**：`dimension_ratings` 必須恰好是這九個 key，不能少報也不能
   夾帶未知構面。
2. **佐證**：HIGH 評分（唯一會驅動 `needs_org_followup` 的關鍵主張）必須
   附非空 `dimension_reasons` 與至少一個 URN `dimension_evidence_refs`；
   LOW/MEDIUM 不要求佐證。
3. 任何出現在 `dimension_evidence_refs` 的值，不分評分等級，形狀都必須是
   全為 URN 的 Array——一個 scalar 不會因為該構面不是 HIGH 就被放行。

### `needs_org_followup` 的機器可查一致性

`needs_org_followup=true` 需同時滿足四個條件，其中「未回答」不是相信
呼叫端另一個自報旗標，而是跟 `unresolved_question` 做內部一致性交叉檢查
（`answer_provided=true` 卻留著非空 `unresolved_question`，或
`answer_provided=false` 卻沒有說明留了什麼問題，兩者都自相矛盾，一律
`OVA_ANSWER_INCONSISTENT`）。「組織價值仍高」直接重用同一套 HIGH 佐證
規則，不是另立一個單獨被信任的旗標。

## 接回總入口的實測

```
中和 OVA_FOLLOWUP_WITHOUT_ORG_VALUE 的 guard：

直接呼叫新片   → FAIL OVA_NEG_FOLLOWUP_WITHOUT_ORG_VALUE 預期 deny，實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_organizational_value_assessment_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## 逐 return site parity（非逐 code）

初版 sweep（19 個 return site）抓到兩個真實缺口，開發階段就修掉，沒有留到
review：

1. `dimension_reasons`／`dimension_evidence_refs` 不是 Hash 的形狀檢查
   （原第 92 行）——沒有任何 fixture 真的送這種輸入，中和後仍是綠的。已
   補負例 `OVA_NEG_REASONS_MAP_NOT_HASH`。
2. HIGH 構面內部的 URN 檢查（原第 101 行）與全域 URN 形狀檢查（原第 109
   行）功能重疊——中和其中任一個，HIGH 構面的壞 URN 仍會被另一個攔下，
   兩處都測不出獨立必要性；同時 LOW/MEDIUM 構面若帶 scalar（非 Array）
   evidence_ref 完全沒被攔下（`next unless refs.is_a?(Array)` 直接放行）。
   重構成單一迴圈，不分評分等級統一檢查 `dimension_evidence_refs` 每個值
   都必須是「全為 URN 的 Array」，刪掉重複的 HIGH-only URN 檢查。已補負例
   `OVA_NEG_LOW_DIMENSION_EVIDENCE_NOT_ARRAY`。

修正後重跑：18 個 return site → 18/18 全紅，未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（32 支，含新增這支）  → PASS
四支 Python schema engine                         → 環境缺 jsonschema 模組
                                                     （pre-existing，未安裝
                                                     venv，本卡未改動其涵蓋
                                                     範圍）
git diff --check                                   → clean
```

## 明確不在本卡範圍

- 平台中立本機邊界的具體機制（切片 3）。
- weekly grill／batch UX／收尾（切片 4）。
- `SSP-324` 綁定本卡欄位（`dimension_reasons`／`unresolved_question`／
  `suggested_expert`）的 Minimal Evidence Package 實作（另卡）。
