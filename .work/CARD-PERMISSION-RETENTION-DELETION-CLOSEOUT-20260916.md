---
id: PERMISSION-RETENTION-DELETION-CLOSEOUT-20260916
status: NO_GO_REPAIRED_02_AWAITING_TARGETED_REREVIEW
type: implementation
tier: T1
jira: SSP-294 前置（repo #4）
implements_spec_freeze: PERMISSION-RETENTION-DELETION-SPEC-FREEZE-20260916
owner_signature: "FP-1: A / FP-2: A / FP-3: A / FP-4: A / FP-5: A（2026-09-16）"
unblocks: CARD-PERMISSION-RETENTION-DELETION-CONTRACT-20260909（BLOCKED_AWAITING_OWNER_SPEC_FREEZE 起 2026-09-09）
---

# repo #4 — 實作 Owner 簽定的 Permission / Retention / Deletion 契約

👉 [假設與目標確認]
- 目標：把 STD-01 裡三個「欄位已存在、語意未鎖」的欄位鎖起來——
  `payload_retention_state`、`deletion_confirmation_ref`、
  `permission_decision_ref`。
- 邊界：依五個簽定的凍結點實作，不擴大。不建 retention DB／deletion
  queue／legal-hold registry／新 writer，不改 STD-01 欄位名。
- 驗收：見 Acceptance。

## 逐點收法

### FP-1-A：retention 轉移

`allowed_retention_transitions` 宣告線性推進 ＋ legal hold 旁路；
`PURGED` 為終態（`terminal_states`）。

**五個狀態值不在本契約重新宣告**——validator 直接讀 STD-01
（`raw-evidence-envelope.schema.json`）的 `payload_retention_state` enum，
斷言契約的狀態集合與它**完全相同**（多一個少一個都紅），轉移目標也必須
是 STD-01 的合法值。避免兩份清單各自演化。

**實作時的判斷（記錄備查）**：FP-1-A 寫「解除後回到原階段」。若不記錄
原階段，`LEGAL_HOLD → RETAINED` 就能把原本已 `RETENTION_EXPIRED` 的證據
倒退回去、重置保留期——那正是線性推進要防的事。因此解除 hold 必須帶
`pre_hold_state`，且轉移目標必須等於它。這是為了讓「回到原階段」可機器
驗證，不是擴大範圍。

### FP-2-A：刪除保留 identity

進入 `TOMBSTONED`／`PURGED` 必須：`deletion_confirmation_ref` 為合法 URN、
`preserved_identity_fields` 涵蓋 `evidence_id`／`digests`／`provenance`／
`chronology`、且 `inline_payload_present` 不得為 true（墓碑還帶著 payload
就等於沒刪）。

### FP-3-A：legal hold 無條件擋

兩道保證：轉移表裡 `LEGAL_HOLD` 沒有通往 `TOMBSTONED`／`PURGED` 的邊
（契約結構斷言會檢查這件事）；另外 evaluator 獨立檢查
`legal_hold_active == true` 且目標是刪除狀態就直接拒絕，不看 `from_state`
怎麼宣告。

### FP-4-A：ACL delta

`recompute_strategy: ON_NEXT_ACCESS`，並把
`BACKGROUND_BATCH_RECOMPUTE`／`REUSE_STALE_DECISION` 列為
`forbidden_strategies`。evaluator 拒絕「宣告 decision 已 stale 卻仍
`access_granted: true`」的取用，也拒絕完全沒有 decision 的取用。

### FP-5-A：cleanup 收據

進入刪除狀態必須帶合法 URN 的 `projection_cleanup_receipt_ref`。收據背後
的投影是否真的清空，由該投影自己的契約負責——本契約只保證刪除不能默默
略過這個宣告。

## Constraints

- 不建 retention DB／deletion queue／legal-hold registry／新 writer。
- 不改 STD-01 欄位名，也不重新宣告五個 retention 值。
- 薄 validator + fixtures，不引入狀態機引擎。
- validator `< 400` 行。

## Acceptance

1. 契約狀態集合與 STD-01 的 enum 綁定（不一致即紅）。
2. 12 個 error code 全部可達、且全部被負例覆蓋（guard parity 全紅）。
3. `error_contract` 與 evaluator 實際可達 code 由 AST 綁定
   （`LoopReturnContract`），不是兩張手寫清單互比。
4. `LEGAL_HOLD` 無通往刪除狀態的邊；`legal_hold_active` 另有獨立 guard。
5. 既有 25 支 validator 不受影響，全部 PASS。
6. `git diff --check` clean。

## Evidence

`.work/evidence/PERMISSION-RETENTION-DELETION-CLOSEOUT-20260916.md`
