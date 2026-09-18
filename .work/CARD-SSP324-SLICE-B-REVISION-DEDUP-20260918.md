---
id: SSP324-SLICE-B-REVISION-DEDUP-20260918
status: READY
jira: SSP-324
parent_jira: SSP-286
related_jira: SSP-294, SSP-295, SSP-323
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-324｜EMEM-10 切片 B：Immutable Revision 與 Dedup／Resend

## 目標

`SSP-324` 的第二個施工切片（仍是同一張卡，不增 Jira）：immutable
package、previous revision trace、禁止 in-place overwrite，以及 dedup／
resend 規則。

## Scope

1. `規格/v0.1/personal-harness-integration.yaml` 新增
   `evidence_package_revision` 區塊。
2. `scripts/validate_evidence_package_revision_contract.rb`：驗證單位是
   **同一個 candidate 的提交鏈**。
3. 接回 `scripts/validate_personal_memory_contract.rb` 聚合器。

## 關鍵決定：信封，不動封包

切片 A 的 `package_required_fields` 已是封閉 allowlist。若把 revision
欄位加進封包，等於重開一個已 `ACCEPTED_GO` 的封閉 shape。所以切片 B 用
外層信封包住 A 的封包：

```text
submission = { submission_id, supersedes_package_ref, comparison_category,
               disposition, correction_proposal_ref, correction_kind,
               package: <切片 A 的封閉 20 欄，一字不動> }
run        = { candidate_ref, submissions: [ …依序… ] }
```

分層：A 管封包內部形狀，B 管封包之間的關係。B 仍對自己讀到的三個封包欄位
（`package_id`／`candidate_ref`／`content_hash`）做值形狀鎖，不盲信，但不
重做 A 的驗證——兩支都掛在同一個 aggregator 下。

## 不重述任何上游

- dedup／resend 規則 = `historical_comparison.dispositions`，評估當下讀。
  卡片那張對照表一個字都不抄。
- revision 走既有 `correction_flow.contract.correction_kinds`，不建立第二
  套 revision lifecycle。
- 本片唯一新增的決定是「哪些 disposition 不授權對外傳輸」
  （`NO_RESEND`／`LOCAL_RECURRENCE_ONLY`），明寫在契約裡，且每個值都必須
  存在於上游 dispositions，斷言強制，不得自創。

## 不屬本卡

- 切片 C：公司端使用邊界（只可 review／verification／audit，不得進正式
  Retrieval／Canonical）、`NEEDS_ORG_FOLLOWUP + suggested_expert=null`
  合法但無 canonical identity。
- 真人 runtime 證明 → `SSP-295`。
