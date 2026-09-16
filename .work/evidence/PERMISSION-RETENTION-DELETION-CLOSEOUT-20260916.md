# repo #4 Permission / Retention / Deletion closeout — evidence

日期：2026-09-16　branch：`cc/permission-retention-deletion`　base：`23e6a95`
Owner 簽核：`FP-1: A / FP-2: A / FP-3: A / FP-4: A / FP-5: A`

這張卡從 2026-09-09 起就是 `BLOCKED_AWAITING_OWNER_SPEC_FREEZE`，卡住的是
決策不是工作量。本輪先把五個凍結點攤成可簽選項，簽完才實作。

## 研究縮小了範圍

1. `payload_retention_state` 的五個值**早已鎖在 STD-01**
   （`RETAINED / LEGAL_HOLD / RETENTION_EXPIRED / TOMBSTONED / PURGED`，
   且是 `required`）。所以 FP-1 不是發明狀態機，只是定義合法轉移。
2. legal hold 擋刪除在 `personal-harness-integration.yaml` 已有先例：
   `DELETE` 的三類材料**全部**把 `legal_hold_absent` 列為必要條件。

## 新增檔案

```
規格/v0.1/permission-retention-deletion.yaml                     179 行
scripts/validate_permission_retention_deletion_contract.rb       229 行（< 400）
規格/v0.1/fixtures/permission-retention-deletion-positive-fixtures.json   7 正例
規格/v0.1/fixtures/permission-retention-deletion-negative-fixtures.json  13 負例
```

## 綁定，不是手抄

- **狀態集合綁 STD-01**：validator 讀
  `raw-evidence-envelope.schema.json` 的 `payload_retention_state` enum，
  斷言契約的 `allowed_retention_transitions` 鍵集合與它完全相同，且每個
  轉移目標都是 STD-01 的合法值。多一個少一個都紅。
- **error code 綁 AST**：`error_contract` 與 evaluator 實際可達的
  `return "<CODE>"` 集合用 `LoopReturnContract`（Ripper 語法樹）雙向比對，
  missing 與 unreachable 都會紅——不是兩張手寫清單互比。

## Guard parity：12/12 全紅

逐一把每個 `return "PRD_..."` 中和成 `return nil`，確認 validator 轉紅：

```
PRD_HOLD_RELEASE_MISSING_PRE_STATE   → RED      PRD_MISSING_DELETION_CONFIRMATION → RED
PRD_HOLD_RELEASE_STATE_MISMATCH      → RED      PRD_MISSING_PERMISSION_DECISION   → RED
PRD_IDENTITY_NOT_PRESERVED           → RED      PRD_STALE_DECISION_HONOURED       → RED
PRD_ILLEGAL_RETENTION_TRANSITION     → RED      PRD_TERMINAL_STATE_DEPARTURE      → RED
PRD_LEGAL_HOLD_BLOCKS_DELETION       → RED      PRD_TOMBSTONE_RETAINS_PAYLOAD     → RED
PRD_MISSING_CLEANUP_RECEIPT          → RED      PRD_UNKNOWN_RETENTION_STATE       → RED
```

未被測到的 guard：**無**。還原後與備份逐位元相同。

## 實作時的一個判斷（主動揭露）

FP-1-A 寫「解除後回到原階段」。若不記錄原階段，`LEGAL_HOLD → RETAINED`
就能把原本已 `RETENTION_EXPIRED` 的證據倒退、重置保留期——正是線性推進
要防的事。因此解除 hold 必須帶 `pre_hold_state` 且目標須等於它
（`PRD_HOLD_RELEASE_MISSING_PRE_STATE` / `PRD_HOLD_RELEASE_STATE_MISMATCH`）。

這是為了讓簽定的語意可機器驗證，但**確實是簽核文字沒有明說的一個欄位**，
請 reviewer 判斷是否算擴大範圍。

## Gate

```
ruby scripts/validate_*.rb（26 支，含新增這支）  → PASS
四支 Python schema engine                         → PASS
git diff --check                                   → clean
```

## 沒有做的事

- 沒建 retention DB／deletion queue／legal-hold registry／任何新 writer。
- 沒改 STD-01 欄位名，也沒重新宣告五個 retention 值。
- 沒碰 repo #5（T3，另需 Owner 定稽核範圍）。
