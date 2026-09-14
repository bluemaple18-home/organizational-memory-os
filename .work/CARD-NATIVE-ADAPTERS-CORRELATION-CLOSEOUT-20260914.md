---
id: NATIVE-ADAPTERS-CORRELATION-CLOSEOUT-20260914
status: AWAITING_BIG_REVIEW
type: implementation
tier: T1
jira: SSP-307（已 ACCEPTED_GO + merged）／SSP-308（已 ACCEPTED_GO + merged）
implements_spec_freeze: NATIVE-ADAPTERS-TASK-REF-SPEC-FREEZE-20260914
owner_signature: "FP-1: A / FP-2: A / FP-3: A（2026-09-14）"
supersedes: "cc/native-adapters-task-ref-correlation（NO_GO，未合併，不回收）"
---

# Native Adapters — 實作 Owner 簽定的 correlation 規格（FP-1-A / FP-2-A / FP-3-A）

👉 [假設與目標確認]
- 目標：依 Owner 簽定的三個 freeze point 重新實作，收乾淨大 review 的
  2×P1 + 1×P2。
- 邊界：新 worktree／branch，不回收上一輪 NO_GO 的 branch。`SSP-307`／
  `SSP-308` 已合併的 review line 不重開。
- 驗收：見 Acceptance。

## 逐筆收法

### F-01（P1）：identity 混淆 → FP-1-A

`task_ref` 全面改名 `native_correlation_ref`（兩份契約、兩支 validator、
四個 fixture 檔）。契約明寫這個欄位**不是** `ai-work-record-hook.yaml`
的 `task_ref`（task-card URN）——本 Adapter 不核發、不解析任何
task-card URN，把 `native_correlation_ref` 翻成真正的 `task_ref` 是
呼叫端的責任。

### F-02（P1）：Claude `Stop` 終態前提 → FP-2-A

`mapping_run` 新增 `stop_hook_active`。`native_event == "Stop"` 且
`stop_hook_active == true` 時一律 `CLAUDE_CODE_STOP_HOOK_ACTIVE_NOT_TERMINAL`
——只對 `Stop` 檢查（文件裡這是 `Stop` 特定的欄位），其餘事件不受影響。
只在 Claude Code 這邊加；Codex 沒有對應的已知「同一 turn 內終態訊號會
重複」問題，未套用。

### F-03（P2）：Hook 沒有機器保證依 task_ref 組批 → FP-3-A

`ai-work-record-hook.yaml` 的 `capture_contract` 新增 `batch_scoping_rule`
文字，明講「一次呼叫的 `raw` 陣列必須屬於同一個 `task_ref` 是呼叫端責任，
evaluator 不驗證」。**不動任何 enforcement 邏輯**。新增一個正例
`HOOK_CAP_POS_MIXED_TASK_REF_KNOWN_GAP`，用兩個不同 `task_ref` 的事件
組成合法 transition 序列，證明目前確實不會被攔下——誠實記錄已知邊界，
不是假裝它被保證。

## Traces to

- `.work/CARD-NATIVE-ADAPTERS-TASK-REF-SPEC-FREEZE-20260914.md`（Owner 簽核）
- `cc/native-adapters-task-ref-correlation`（NO_GO，供參考，不合併）

## Constraints

- 不改 `ai-work-record-hook.yaml` 的任何 evaluator 邏輯（FP-3-A 明確排除）。
- 不驗證 `native_correlation_ref` 的實際值。
- 三支 validator 各自 `< 400` 行。

## Acceptance

1. `task_ref` 在兩份 Native Adapter 契約／validator／fixture 裡不再出現
   （只保留對 Hook 真正 `task_ref` 的有意識交叉引用）。
2. `stop_hook_active` 為 `true` 的 `Stop` MAPPED run 一律拒絕；`false`／
   缺席不受影響（正例覆蓋兩種情況）。
3. `ai-work-record-hook.yaml` 新增 `batch_scoping_rule`，既有結構斷言
   不受影響；新增示範性正例證明已知邊界為真。
4. 三支 evaluator（Codex mapping／rollback／runtime_sample、Claude Code
   mapping／rollback）guard parity 全紅。
5. 全部既有 validator + schema engine + cross-layer + `git diff --check`
   全 PASS。

## Stop conditions

無新增——三個 freeze point 已由 Owner 簽定，本卡照實作。

## Evidence

`.work/evidence/NATIVE-ADAPTERS-CORRELATION-CLOSEOUT-20260914.md`
