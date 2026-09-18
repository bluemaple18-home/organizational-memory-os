---
id: SSP323-SLICE2-ORG-VALUE-ASSESSMENT-20260918
status: READY
jira: SSP-323
parent_jira: SSP-286
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-323｜EMEM-09 切片 2：Organizational Value Assessment ／ NEEDS_ORG_FOLLOWUP

## 目標

沿用 `.work/CARD-SSP323-WEEKLY-PERSONAL-HARNESS-20260917.md` 第 6 節
「Organizational Value Assessment」與第 3 節 Weekly Grill 裡的
`NEEDS_ORG_FOLLOWUP` 規則，做成可機器驗的契約 + evaluator。

`Organizational Value Assessment != Promotion Eligibility`：一個 HIGH
評分本身不授權 promotion，SSP-294 已驗收的 gate／policy／scope-ceiling
對之後真的送出的 proposal 仍照樣套用不變。

`NEEDS_ORG_FOLLOWUP != Company Knowledge`：它是 follow-up signal，不建立
任何 candidate/record identity。

## Scope

1. `規格/v0.1/personal-harness-integration.yaml` 新增
   `organizational_value_assessment` 區塊：9 個構面、3 級評分、不要求假
   精準單一分數、`needs_org_followup` 的觸發規則。
2. `scripts/validate_organizational_value_assessment_contract.rb`：
   - 結構性禁止碰 lifecycle 欄位（Assessment != Promotion Eligibility）。
   - 結構性禁止任何聚合分數欄位（不要求假精準單一分數）。
   - 九個構面必須逐一評分，不能少報或只挑喜歡的講。
   - HIGH 評分（唯一會驅動 `needs_org_followup` 的關鍵主張）必須附非空
     reasons 與至少一個 URN evidence_ref；LOW/MEDIUM 不要求佐證。
   - `needs_org_followup=true` 需同時滿足：未回答、有非空
     unresolved_question、缺外部證據、至少一個 HIGH 且已佐證的構面。
   - `suggested_expert` optional，`null` 合法。
3. 接回 `scripts/validate_personal_memory_contract.rb` 聚合器。

## 承接切片 1 的兩項硬要求

1. **聚合器接回實測**：新增 guard 至少一個要證明不只直接呼叫這支會紅，
   呼叫聚合器也同步轉紅。
2. **機器可查訊號 vs 判斷型訊號分離**：九個構面本質上都是人的價值判斷，
   沒有原始資料可推導（不像切片 1 的 identity/hash/evidence-set）。機器
   能守住的邊界是「完整性 + 佐證」，不是「推導」——不接受 HIGH 評分靠一個
   bare label 就被信任。

## 不屬本卡

- 切片 3（platform-neutral local-first 具體機制）。
- 切片 4（weekly grill／batch UX／收尾）。
- `SSP-324` 的 Minimal Evidence Package 實作（沿用本卡的 reasons／
  unresolved_question／suggested_expert 欄位，另卡）。
- expert routing／taxonomy／cross-person conflict resolution（明確留在
  Organizational Layer）。
