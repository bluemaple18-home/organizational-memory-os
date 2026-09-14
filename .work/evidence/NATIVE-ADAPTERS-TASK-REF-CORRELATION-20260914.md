# Native Adapters task_ref Correlation — evidence

日期：2026-09-14　branch：`cc/native-adapters-task-ref-correlation`
base：`28438bb`（main，含 SSP-307／SSP-308 皆已 merge）

**這不是重開任何已關閉的 review line。** `SSP-307`／`SSP-308` 都已
`ACCEPTED_GO` 並 merge，是不可變的歷史。這是對已出貨程式碼的新一輪修正，
同一個設計決策套用到兩張卡。

## 發現過程（如實記錄，含一條死路）

1. 先查 `TaskCreate` 工具語意，想確認 `TaskCreated`／`TaskCompleted` 是否
   是比 `Stop` 更安全的候選——結果是死路：官方文件確認這是 session 內
   可以建立很多個的 todo-list 機制，比 `Stop` 粒度還細。

2. 轉向 Codex 真實 session 裡 `task_started`／`task_complete` 的實際
   payload 結構（只讀結構欄位與純量值，未讀任何文字內容）：

```
task_started payload keys: turn_id, started_at, model_context_window, collaboration_mode_kind
task_complete payload keys: turn_id, started_at, completed_at, duration_ms,
                             time_to_first_token_ms, last_agent_message
```

   同一個 turn 的 `task_started`／`task_complete` 帶著**相同**的
   `turn_id`；連續四個 turn 的實際值：

```
01a08a6f-40cb-7fd3-8c47-e53b18265215
01a08a87-9566-7081-853d-cac79dd834f1
01a08a88-104f-7773-9f53-9643284414ec
01a08a8a-6c82-7d82-a329-05cb480ba95c
```

3. 對照 `ai-work-record-hook.yaml`，`capture_contract.event_envelope_fields`
   本來就有 `task_ref`——批次組裝（去重、排序、transition 合法性檢查）
   是在 `task_ref` 範圍內做的，不是整個 host session 一批。

4. 查 Claude Code `Stop` hook 的真實輸入 schema（不是 transcript 紀錄）：

```
prompt_id: "UUID identifying the user prompt currently being processed...
            so you can correlate hook output with telemetry for a single
            prompt"
```

   且明確文件化「可用來關聯 UserPromptSubmit（start）與 Stop（end）是
   同一個 turn」。`SessionStart` **沒有** `prompt_id`（「absent until the
   first user input」）。

## 結論

兩輪修正判定「per-turn 事件不安全」在當時的資訊下是對的——`mapping_run`
從頭到尾都沒有欄位可以告訴下游 Hook 這個事件屬於哪個 `task_ref`。加上
`task_ref`、要求從原生事件自己的 `turn_id`／`prompt_id` 填入，映射重新
安全：每個 `task_ref` 各自開一批，`start`／`submit_review` 在同一批裡
永遠只出現一次。

## 修法

**兩份契約**都：
- `mapping_run.fields` 新增 `task_ref`。
- 新增 `task_ref_rule`：MAPPED 時必須非空字串，否則
  `CODEX_MISSING_TASK_REF`／`CLAUDE_CODE_MISSING_TASK_REF`。明確聲明本檔
  不驗證值是否等於真實 `turn_id`／`prompt_id`——`mapping_run` 是抽象化
  分類紀錄，不是原始 payload。

**Codex**：`lifecycle_event_map.map` 恢復
`{task_started: start, task_complete: submit_review}`；兩者移出
`non_lifecycle_event_types`；`CODEX_MAPPING_TARGET_MISMATCH` 分支恢復
（map 重新非空，該分支重新可達）。

**Claude Code**：`lifecycle_event_map.map` 新增
`{UserPromptSubmit: start, Stop: submit_review}`（**不是**
`SessionStart: start`——沒有 `prompt_id`）；兩者移出
`non_lifecycle_event_types`；`CLAUDE_CODE_MAPPING_TARGET_MISMATCH` 分支
恢復；`session_start_note` 改寫成解釋 `SessionStart` 為何仍非生命週期。

兩張延後卡標註 superseded／partially superseded，不刪除（保留歷史）。

## Fixture 調整

**Codex**：
- 正例：`task_started`／`task_complete` 從 `NOT_LIFECYCLE` 改回
  `MAPPED`，附上真實格式的 `task_ref`（`turn-<uuid>`）。
- `runtime_sample_cases` 分類切分同步。
- 負例：`CODEX_NEG_UNKNOWN_NATIVE_EVENT_MAPPED`／`CODEX_NEG_MAPPED_NO_MAP_ENTRY`
  補上 `task_ref`（否則會被新加的 task_ref 檢查攔在前面，測不到原本要測
  的分支）；恢復 `CODEX_NEG_MAPPED_TO_MISMATCH`；新增
  `CODEX_NEG_TASK_REF_ABSENT`／`CODEX_NEG_TASK_REF_WHITESPACE`。

**Claude Code**：同樣的調整套用到
`CLAUDE_CODE_POS_USERPROMPTSUBMIT_MAPS_START`／
`CLAUDE_CODE_POS_STOP_MAPS_SUBMIT_REVIEW`，以及對應的負例補齊。

## 驗證

### Guard parity

| 契約 | evaluator | 結果 |
| --- | --- | --- |
| Codex | `codex_mapping_failure`（16 條，原 14） | 16 RED / 0 GREEN |
| Codex | `codex_rollback_failure`（6 條） | 6 RED / 0 GREEN |
| Codex | `codex_runtime_sample_failure`（1 條） | 1 RED / 0 GREEN |
| Claude Code | `claude_code_mapping_failure`（16 條，原 14） | 16 RED / 0 GREEN |
| Claude Code | `claude_code_rollback_failure`（6 條） | 6 RED / 0 GREEN |

**45/45，第一輪 probe 全紅，無 GREEN(bad)。**

### 結構／跨契約 probe

**Codex（4 條）**：map 清空回歸 / map 指向不存在 key / overlap / error_contract
移除 code — 4/4 RED。

**Claude Code（5 條）**：map 清空回歸 / map 指向不存在 key / overlap /
error_contract 移除 code / 凍結快照 drift（回歸 F-03 修法）— 5/5 RED。

所有 probe 後上游／快照檔 `git diff --name-only` 為空。

### Gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：
- `codex-native-adapter.yaml` 308 行、其 validator 343 行
- `claude-code-native-adapter.yaml` 313 行、其 validator 274 行

全部在 `< 400` 硬上限內。

## 本輪沒有做的事

- 沒有驗證 `task_ref` 的實際值是否等於真實 `turn_id`／`prompt_id`——
  `mapping_run` 是抽象化分類紀錄，只驗非空字串。
- 沒有把 `SessionStart` 或 `TaskCreated`／`TaskCompleted` 映射進生命週期
  （前者無 `prompt_id`，後者是 session 內可多次建立的機制，皆已排除）。
- 沒有動上游 `ai-task-card-record.yaml`／`ai-work-record-hook.yaml`。
- 沒有做即時 hook 觸發或即時訂閱。
