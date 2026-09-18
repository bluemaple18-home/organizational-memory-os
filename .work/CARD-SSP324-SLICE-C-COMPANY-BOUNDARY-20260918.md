---
id: SSP324-SLICE-C-COMPANY-BOUNDARY-20260918
status: READY
jira: SSP-324
parent_jira: SSP-286
related_jira: SSP-294, SSP-295, SSP-323
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-324｜EMEM-10 切片 C：公司端使用邊界

## 目標

`SSP-324` 的最後一個施工切片（仍是同一張卡，不增 Jira）：公司端拿到
Minimal Evidence Package 之後可以做什麼、不可以做什麼，以及
`NEEDS_ORG_FOLLOWUP` 不得取得 canonical identity。

`Evidence Package != Company Knowledge`；`NEEDS_ORG_FOLLOWUP != Company
Knowledge`。

## Scope

1. `規格/v0.1/personal-harness-integration.yaml` 新增
   `company_side_evidence_boundary` 區塊。
2. `scripts/validate_company_side_evidence_boundary_contract.rb`：驗證單位
   是一筆「公司端處理紀錄」（封包、用途、產出、以及同時發生的 retrieval
   pack）。
3. 接回 `scripts/validate_personal_memory_contract.rb` 聚合器。

## 每個檢查的權威對照物（施工前先答完）

這是切片 A／B 三輪 repair 換來的紀律：**先問「權威對照物是誰、在不在我
手上」**，答不出來就不要寫那條檢查。

| 要驗的事 | 權威對照物 | 在哪 |
|---|---|---|
| canonical 是否走完整路徑 | `promotion_flow.required_steps` | 上游，逐項比對 |
| 正式 retrieval 的欄位詞彙 | `recall_context_pack.contract.pack_required_fields` | 上游，讀欄位名 |
| 封包有沒有混進 retrieval | 本筆自己的 `package_ref` | 同筆事實 |
| follow-up 不得 canonical | `historical_comparison` 的 lifecycle 禁列 | 共用 helper |
| 上位宣告仍在 | `core_invariants` / `capability_safety_floor.invariants` | 上游，只確認未被繞過 |

唯一自創的是 purpose 詞彙（上游沒有），因此採**封閉 allowlist**，並斷言
allowed／forbidden 不重疊、每個 forbidden purpose 都必須被負例實際打過。

## 不屬本卡

- expert routing／taxonomy／cross-person conflict resolution：明確留在
  Organizational Layer。
- 「公司端確實無 reverse-access path」的 runtime 實證 → `SSP-295` 真人
  pilot。本片鎖的是契約層。
