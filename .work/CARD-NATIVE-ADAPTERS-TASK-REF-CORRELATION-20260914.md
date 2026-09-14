---
id: NATIVE-ADAPTERS-TASK-REF-CORRELATION-20260914
status: NO_GO_ESCALATED_TO_OWNER_SPEC_FREEZE
type: post_merge_fix
tier: T1
jira: SSP-307（已 ACCEPTED_GO + merged）／SSP-308（已 ACCEPTED_GO + merged）
sibling_of: "同一個設計決策套用到兩張已合併的卡"
origin: "研究 SSP-308 runtime-probe backlog 卡時發現的根本原因，見過程對話"
---

# Native Adapter mapping_run 加入 task_ref 關聯鍵

👉 [假設與目標確認]
- 目標：修正兩張已合併的 Native Adapter 卡（`codex-native-adapter.yaml`／
  `claude-code-native-adapter.yaml`）共同的設計缺陷——`mapping_run` 沒有
  `task_ref` 欄位，導致下游 Hook 無法把事件正確歸屬到哪一張任務卡。
- 邊界：這**不是**重開任何已關閉的 review line。兩張卡都已 `ACCEPTED_GO`
  並 merge，這是對已出貨程式碼的新一輪修正，走全新 worktree／branch／
  big review，base 是目前的 `main`。
- 驗收：見 Acceptance。

## Root question

`task_started`／`task_complete`（Codex）跟 `Stop`（Claude Code）之前被
判定「per-turn cadence、不安全」，但這是映射本身的問題，還是
`mapping_run` 這個抽象格式本身少了一個必要欄位？

## 發現過程

研究 `SSP-308` 的 runtime-probe backlog 卡時，先查了 Claude Code 的
`TaskCreate` 工具語意（想確認 `TaskCreated`／`TaskCompleted` 是否是更安全
的候選）——結果發現那是 session 內可以建立很多個的 todo-list 機制，比
`Stop` 粒度還細，死路一條。

轉而去讀 Codex 真實 session 裡 `task_started`／`task_complete` 的完整
payload 結構（不只是事件名稱，而是欄位鍵名與非文字內容的純量值）：

```
task_started payload keys: turn_id, started_at, model_context_window, collaboration_mode_kind
task_complete payload keys: turn_id, started_at, completed_at, duration_ms,
                             time_to_first_token_ms, last_agent_message
```

**每一對 `task_started`／`task_complete` 都帶著相同的 `turn_id`，且每個
turn 的 `turn_id` 都不一樣。**

對照 `ai-work-record-hook.yaml` 的 `capture_contract.event_envelope_fields`，
發現裡面本來就有 `task_ref`——這是下游 Hook 用來把事件歸屬到哪一張卡的
關聯鍵，批次組裝（去重、排序、transition 合法性）是**在 `task_ref` 範圍內**
做的，不是整個 host session 一批。

再查 Claude Code `Stop` hook 的真實輸入欄位（不是 transcript 紀錄，是
hook 實際收到的 stdin JSON），官方文件確認：

> `prompt_id`：「UUID identifying the user prompt currently being
> processed... so you can correlate hook output with telemetry for a
> single prompt」

且明確寫「可以用來關聯 `UserPromptSubmit`（start）與 `Stop`（end）是同
一個 turn」。`SessionStart` 則**沒有** `prompt_id`（要等第一個使用者輸入
才有）。

## 結論

兩輪修正（`SSP307-POST_MERGE_FIX_01`、`SSP308-repair-01`）判定
「per-turn 事件不安全、只能清空映射」是對的**在當時的資訊下**——
`mapping_run` 從一開始就沒有任何欄位可以告訴下游 Hook 這個事件屬於哪個
`task_ref`。加上 `task_ref` 欄位、要求呼叫端從原生事件自己的
`turn_id`／`prompt_id` 填入，映射就重新安全：每個 `task_ref` 各自開一批，
`start`／`submit_review` 在同一個 `task_ref` 裡永遠只出現一次。

## 修法（兩張卡同一個設計，各自套用）

**Codex（`codex-native-adapter.yaml`）**：
- `lifecycle_event_map.map` 恢復 `task_started: start`／
  `task_complete: submit_review`。
- `mapping_run.fields` 新增 `task_ref`；MAPPED 時必須是非空字串，否則
  `CODEX_MISSING_TASK_REF`。
- `task_started`／`task_complete` 移出 `non_lifecycle_event_types`。
- 恢復 `CODEX_MAPPING_TARGET_MISMATCH` 分支（`task_ref` 讓 map 重新非空，
  這條 guard 重新可達）。

**Claude Code（`claude-code-native-adapter.yaml`）**：
- `lifecycle_event_map.map` 新增 `UserPromptSubmit: start`／
  `Stop: submit_review`（**不是** `SessionStart: start`——`SessionStart`
  沒有 `prompt_id`，無法關聯到特定 turn 的 `task_ref`）。
- `mapping_run.fields` 新增 `task_ref`；同 Codex 的規則。
- `UserPromptSubmit`／`Stop` 移出 `non_lifecycle_event_types`。
- 恢復 `CLAUDE_CODE_MAPPING_TARGET_MISMATCH` 分支。

兩張 backlog 卡（`CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG`、
`CARD-SSP308-RUNTIME-PROBE-BACKLOG`）已標註被此修法部分／完全取代。

## Traces to

- `規格/v0.1/ai-work-record-hook.yaml`（`capture_contract.event_envelope_fields.task_ref`）
- `.work/CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914.md`（superseded）
- `.work/CARD-SSP308-RUNTIME-PROBE-BACKLOG-20260914.md`（partially superseded）

## Constraints

- 不改上游 `ai-task-card-record.yaml`／`ai-work-record-hook.yaml`。
- 不驗證 `task_ref` 的實際值是否等於真實 `turn_id`／`prompt_id`——
  `mapping_run` 是抽象化後的分類紀錄，不是原始 payload；只驗非空字串。
- 不做即時 hook 觸發或即時訂閱。
- 兩支 validator 各自 `< 400` 行。

## Acceptance

1. `task_ref` 加入兩份 `mapping_run.fields`；MAPPED 時非空字串，否則對應
   `MISSING_TASK_REF` code。
2. Codex：`task_started`／`task_complete` 重新在 `lifecycle_event_map`。
3. Claude Code：`UserPromptSubmit`／`Stop` 重新在 `lifecycle_event_map`；
   `SessionStart` 維持非生命週期（無 `prompt_id`，記錄理由）。
4. 兩份 `error_contract` 恢復 `MAPPING_TARGET_MISMATCH`，AST 綁定機制
   自動同步（不手動調整清單）。
5. 兩支 evaluator 的 guard parity 全紅。
6. 全部既有 validator + schema engine + cross-layer + `git diff --check`
   全 PASS。

## Stop conditions

- 若無法確認 `task_ref` 的抽象化程度是否足夠（例如下游 Hook 實際還需要
  更多欄位才能正確組批），停，回 Owner。

## Evidence

`.work/evidence/NATIVE-ADAPTERS-TASK-REF-CORRELATION-20260914.md`
