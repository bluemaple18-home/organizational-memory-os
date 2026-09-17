---
id: SSP323-SLICE1-HISTORICAL-COMPARISON-20260917
status: AWAITING_BIG_REVIEW
type: implementation
tier: T1
jira: SSP-323（EMEM-09）切片 1
sibling: repo main card CARD-SSP323-WEEKLY-PERSONAL-HARNESS-20260917
---

# SSP-323 切片 1 — historical comparison 五態分類與補送規則

👉 [假設與目標確認]
- 目標：定義五態比較結果（`UNSEEN/UNCHANGED/NEW_EVIDENCE/MATERIALLY_CHANGED/
  CONTRADICTED`）與對應 disposition，供 `SSP-324` 的 dedup/resend 規則綁定。
- 邊界：這是**比較結果**，不是第二套候選生命週期；不碰
  `candidate_status`／`verification_status` 等既有欄位。
- 驗收：見 Acceptance。

## 回應派工前的兩個 review 意見

### 1. category／disposition 不能是呼叫端自報

evaluator 從原始訊號（`prior_record_ref`／content hash／`evidence_refs` 的
集合差）計算 `no_prior_record`／`identical_to_prior`／`has_new_evidence`，
不讀呼叫端宣告的分類欄位——run 的 schema 裡根本沒有 `category`／
`disposition` 這兩個輸入欄位，它們只會是 evaluator 的輸出。這是刻意的
設計，不是遺漏：避免重蹈「只驗自報一致、不驗事實」的覆轍。

`material_effect`／`contradicts_prior` 需要語意判斷，evaluator 做不到，
由呼叫端宣告——但宣告為 `true` 時必須附非空 `reasons`（且限定在
`material_effect_dimensions` 之內）與至少一個 `evidence_refs`，不接受
裸 boolean。

### 2. 五態可能同時成立，需要明確優先序

`NEW_EVIDENCE` 與 `MATERIALLY_CHANGED`（甚至 `CONTRADICTED`）可能同時
成立（例如新證據剛好又推翻結論）。契約明寫優先序：

```
1. no_prior_record   → UNSEEN
2. contradicts_prior → CONTRADICTED
3. has_new_evidence  → NEW_EVIDENCE（material_effect 再選兩個 disposition 之一）
4. material_effect   → MATERIALLY_CHANGED（無新證據但重新評估推翻結論）
5. identical_to_prior → UNCHANGED
```

正例 `HC_POS_CONTRADICTION_PRECEDENCE_OVER_NEW_EVIDENCE` 同時滿足
`material_effect` 與 `contradicts_prior`，驗證推導出 `CONTRADICTED` 而非
`NEW_EVIDENCE`——不是五個名稱列完就算數。

## 接回總入口

`validate_personal_memory_contract.rb`（既有六支 slice 的 aggregator）新增
第七支。**已實測**：把新片的一個 guard 中和掉，不只是直接呼叫新片會紅，
**呼叫總入口 `ruby scripts/validate_personal_memory_contract.rb` 也會紅**
——避免只加檔案、不接入口，舊命令驗不到新片的假綠。

## Constraints

- 不碰 `candidate_status`／`record_status`／`verification_status`／
  `acceptance_status`／`conflict_resolution_status`（結構斷言擋）。
- 不建新的候選生命週期或第二套 workflow。
- validator `< 400` 行。

## Acceptance

1. 五個 category、六個 disposition（`NEW_EVIDENCE` 依 `material_effect`
   分兩支）全部由正例覆蓋，含一個同時觸發多訊號的優先序驗證案例。
2. `category`／`disposition` 純由 evaluator 推導，run 沒有可宣告這兩者的
   欄位。
3. `material_effect`／`contradicts_prior` 為 `true` 時必須附理由與
   `evidence_refs`；缺一律 fail-closed。
4. 沒有 `prior_record_ref` 卻宣告 `material_effect`／`contradicts_prior`
   → 拒絕（沒有「之前」可以比較或推翻）。
5. 接回 `validate_personal_memory_contract.rb`；弄壞新片、總入口也紅。
6. 逐 return site parity 全紅；既有 30 支 validator 不受影響。

## Evidence

`.work/evidence/SSP323-SLICE1-HISTORICAL-COMPARISON-20260917.md`
