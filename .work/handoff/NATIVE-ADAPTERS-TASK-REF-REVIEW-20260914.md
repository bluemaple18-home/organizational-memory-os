# Native Adapters task_ref Correlation — Big Review 交付包

平台中立。**這不是重開任何已關閉的 review line。** `SSP-307`／`SSP-308`
都已 `ACCEPTED_GO` 並 merge，是不可變的歷史。這是對已出貨程式碼的新一輪
修正，同一個設計決策套用到兩張卡，走全新 worktree／branch／big review。

## 1. 審什麼

兩份 Native Adapter 契約的 `mapping_run` 都少了一個關聯鍵欄位
（`task_ref`），導致下游 Hook 無法把翻譯出來的事件正確歸屬到哪一張任務卡。
兩輪先前的修正（`SSP307-POST_MERGE_FIX_01`、`SSP308-repair-01`）判定
「per-turn 事件不安全、只能清空映射」在**當時的資訊**下是對的——問題不是
映射本身錯，是這個欄位一直不存在。

## 2. Frozen commit

```
base             28438bb（main，SSP-307／SSP-308 皆已 merge）
review_commit    869a5ca8422b7707a003d8309de3ff960ada7a87
branch           cc/native-adapters-task-ref-correlation（已 push origin）
```

```
git fetch origin && git checkout cc/native-adapters-task-ref-correlation
git diff 28438bb..869a5ca --stat
```

## 3. 發現過程（含一條死路，如實記錄）

1. 查 `TaskCreate` 工具語意，想找比 `Stop` 更安全的候選——**死路**：官方
   文件確認這是 session 內可建立很多個的 todo-list 機制，比 `Stop` 粒度
   還細。
2. 讀 Codex 真實 session 裡 `task_started`／`task_complete` 的實際
   payload（只讀結構欄位與純量值，未讀任何文字內容），發現同一個 turn
   的兩者帶著相同 `turn_id`，每個 turn 各自不同：

```
task_started payload keys: turn_id, started_at, model_context_window, collaboration_mode_kind
task_complete payload keys: turn_id, started_at, completed_at, duration_ms,
                             time_to_first_token_ms, last_agent_message
```

3. 對照 `ai-work-record-hook.yaml`，`capture_contract.event_envelope_fields`
   本來就有 `task_ref`——批次組裝（去重、排序、transition 合法性）是在
   `task_ref` 範圍內做的，不是整個 host session 一批。
4. 查 Claude Code `Stop` hook 的真實輸入 schema，官方文件確認
   `prompt_id`「可用來關聯 `UserPromptSubmit`（start）與 `Stop`（end）
   是同一個 turn」；`SessionStart` **沒有** `prompt_id`。

## 4. 契約變更

| 檔 | 變更 |
| --- | --- |
| `規格/v0.1/codex-native-adapter.yaml` | `lifecycle_event_map` 恢復 `task_started`／`task_complete`；`mapping_run` 新增 `task_ref` |
| `scripts/validate_codex_native_adapter_contract.rb` | 恢復 `CODEX_MAPPING_TARGET_MISMATCH`；新增 `CODEX_MISSING_TASK_REF` |
| `規格/v0.1/claude-code-native-adapter.yaml` | `lifecycle_event_map` 新增 `UserPromptSubmit`／`Stop`（不是 `SessionStart`）；`mapping_run` 新增 `task_ref` |
| `scripts/validate_claude_code_native_adapter_contract.rb` | 恢復 `CLAUDE_CODE_MAPPING_TARGET_MISMATCH`；新增 `CLAUDE_CODE_MISSING_TASK_REF` |
| 兩份 fixture 檔（各 positive/negative） | 對應調整 |

**未改動任何上游契約**（`ai-task-card-record.yaml`、`ai-work-record-hook.yaml`
逐字未變）。

## 5. 特別請看的點

1. **`task_ref` 只驗非空字串，不驗值本身**。契約明講：`mapping_run` 是
   抽象化後的分類紀錄，不是原始 native/hook payload，所以這裡不驗證
   `task_ref` 是否真的等於某個 `turn_id`／`prompt_id`。請判斷這個抽象
   層級合不合理——如果你認為需要更強的綁定（例如驗證 `task_ref` 的格式
   像 UUID），這是可討論的點。
2. **`SessionStart` 刻意不映射到 `start`，改用 `UserPromptSubmit`**。
   理由是 `SessionStart` 沒有 `prompt_id`（文件原文：「absent until the
   first user input」）。這代表如果 session 一開始就有訊息但
   `UserPromptSubmit` 因故沒有正確觸發，這個 Work Record 永遠不會有
   `start` 事件。請評估這個風險是否需要額外的保護。
3. **`TaskCreated`／`TaskCompleted` 這條線索最後證實是死路**，寫在
   evidence 裡，不是藏起來。如果你認為這個排除本身站不住腳，請提出來。
4. **兩張延後卡的狀態**：`CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG` 標
   `SUPERSEDED_BY_TASK_REF_FIX`；`CARD-SSP308-RUNTIME-PROBE-BACKLOG` 標
   `PARTIALLY_SUPERSEDED_BY_TASK_REF_FIX`（`SessionEnd` 與其餘 31 個
   Claude Code 事件仍未解決，那張卡對它們仍然有效）。

## 6. Mutation 要求

**A. 兩份 evaluator 的 guard parity**：

| 契約 | evaluator | 結果 |
| --- | --- | --- |
| Codex | `codex_mapping_failure`（16 條） | 16 RED / 0 GREEN |
| Codex | `codex_rollback_failure`（6 條） | 6 RED / 0 GREEN |
| Codex | `codex_runtime_sample_failure`（1 條） | 1 RED / 0 GREEN |
| Claude Code | `claude_code_mapping_failure`（16 條） | 16 RED / 0 GREEN |
| Claude Code | `claude_code_rollback_failure`（6 條） | 6 RED / 0 GREEN |

**45/45，第一輪 probe 全紅，無 GREEN(bad)。**

**B. 結構／跨契約 probe**：

| 契約 | # | 動作 | 結果 |
| --- | --- | --- | --- |
| Codex | 1 | `lifecycle_event_map` 清空（回歸） | RED |
| Codex | 2 | map 指向不存在的 lifecycle key | RED |
| Codex | 3 | non_lifecycle 與 map 重疊 | RED |
| Codex | 4 | error_contract 移除 `CODEX_MISSING_TASK_REF` | RED |
| Claude Code | 1~4 | 同上四種 | 全 RED |
| Claude Code | 5 | 凍結快照 drift（回歸 F-03 修法） | RED |

還原請用 `cp` 備份，不要用 `git checkout --`。

## 7. 邊界

不驗證 `task_ref` 的實際值；不映射 `SessionStart` 或
`TaskCreated`／`TaskCompleted`；不動上游契約；不做即時 hook 觸發。

## 8. 已跑的 gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：`codex-native-adapter.yaml` 308 行／validator 343 行；
`claude-code-native-adapter.yaml` 313 行／validator 274 行。全數 `< 400`。

請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
