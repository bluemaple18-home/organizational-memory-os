---
id: SSP294-PROMOTION-20260909
status: BLOCKED
type: implementation
jira: SSP-294
lane: A
tier: T1
---

# SSP-294｜EMEM-05 Promotion（升格閉環）

👉 [假設與目標確認]
- 目標：把「PersonalMemoryRecord → Company / Shared 升格」寫成可驗契約：誰能提案、
  widening gate（reviewer_approval / source_acl_allows_requester）、retention / deletion
  傳遞、canonical single-writer 不被繞過。
- 邊界：只封升格的提案 → gate → receipt 契約；不做 connector、不做 runtime。
- 驗收：待解除 blocker 後補。

## Blockers（本卡不開工，回 Owner）

`SSP-294` 依賴 repo 施工順序（`文件/待辦重整.md` 第八節）尚未完成的前置：

| # | 前置項目 | 狀態 |
|---|---|---|
| 2 | Document Adapter Mapping | 未開工 |
| 3 | Jira Adapter Mapping | 未開工 |
| 4 | Permission / Retention / Deletion Contract | 未開工（升格的 retention/deletion 傳遞語意來源） |
| 5 | Canonical Direct-Write Audit | 未開工，P0 FIRST FRONTIER（升格不得繞過 Proposal/Acceptance/Single Writer 的稽核基準） |

`SSP-294` 的 widening gate 與 canonical-writer 不被繞過，直接建構在 #4 / #5 的契約之上。
在 #4 / #5 鎖定前實作 `SSP-294` 會等於自訂一份 Permission/Retention 與 writer 稽核語意，
違反 `文件/待辦重整.md` 施工順序與 `MEASURED_GAP_REQUIRED`。

## 解除條件

repo 施工順序 #2～#5 完成並 Owner 接受後，本卡轉 `DRAFT_OWNER_REVIEW`，依 T1 迴圈實作。
在那之前 Lane A 無可推進的下一票（`SSP-291` EMEM-02 同樣卡在 #2 / #3 Adapter Mapping）。

## Traces to

- `規格/v0.1/personal-harness-integration.yaml`：`ownership_visibility_contract.promotion_widening_gate`、
  `actor_action_policy` 的 `PROMOTE` 規則、`retention_and_lifecycle_policy`。
- `文件/待辦重整.md` 第八節施工順序、第 41 行 `Canonical Direct-Write Audit`（P0）。
- `jira-tasks` `JIRA-DRAFT-EMEM-005`（若存在）／`SSP-294` acceptance。

## Likely files（解除後）

- `規格/v0.1/personal-harness-integration.yaml`（`promotion_flow.contract` 新區塊）或新 `規格/v0.1/emem-promotion.yaml`
- `scripts/validate_promotion_flow_contract.rb`（新薄 validator）
- `規格/v0.1/fixtures/*promotion*fixtures.json`
- `.work/evidence/SSP294-PROMOTION-<date>.md`
