---
id: SSP294-PROMOTION-20260909
status: UNBLOCKED_SLICING_IN_PROGRESS
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

| # | 前置項目 | 狀態（2026-09-17 校正）|
|---|---|---|
| 2 | Document Adapter Mapping | **`ACCEPTED_GO` / merged `ebeaab2`**（2026-09-10）|
| 3 | Jira Adapter Mapping | **`ACCEPTED_GO` / merged `0ac8c09`**（2026-09-10）|
| 4 | Permission / Retention / Deletion Contract | **`ACCEPTED_GO` / merged `153700f`**（2026-09-16）|
| 5 | Canonical Direct-Write Audit | **稽核完成 / merged `a4ac172`**；F-01 已收（`b908339`），F-02 Owner 裁定維持 P3 |

**四個前置全部解除。** 本表原本停在 2026-09-09 的狀態（#2/#3 標「未開工」），
但那兩張其實 9/10 就已 merge——2026-09-17 校正。

`SSP-294` 的 widening gate 與 canonical-writer 不被繞過，直接建構在 #4 / #5 的契約之上。
在 #4 / #5 鎖定前實作 `SSP-294` 會等於自訂一份 Permission/Retention 與 writer 稽核語意，
違反 `文件/待辦重整.md` 施工順序與 `MEASURED_GAP_REQUIRED`。

## 解除後的切法（2026-09-17）

研究後確認：**上游 `personal-harness-integration.yaml` 早已把政策宣告完整**
（`promotion_widening_gate` 6 required ＋ 3 forbidden；`actor_action_policy.PROMOTE`
15 個決策格），但幾乎沒有被強制——gate 只驗到 1 個 required 在清單裡、
forbidden 完全沒驗；15 格只驗「每格存在」＋ 1 條具體條件。

所以本票的性質是**強制既有宣告**，不是設計新政策。切成三張薄卡（一張做完會
超過檔案大小限制，且大卡在本 repo 反覆被 NO_GO）：

| 切片 | 內容 | 綁定上游 | 狀態 |
|---|---|---|---|
| A | gate 組成：6 required 必須全滿足、3 forbidden 任一即拒 | `promotion_widening_gate` | `.work/CARD-SSP294A-PROMOTION-GATE-20260917.md` |
| B | 15 個 actor × 材料類別決策格逐格重放 | `actor_action_policy.PROMOTE` | 待開 |
| C | 升格時的 retention/deletion 傳遞 ＋ 不得繞過 canonical writer | repo #4 契約、repo #5 `promotion_path` | 待開（可能需 T2，碰 authority 邊界）|

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
