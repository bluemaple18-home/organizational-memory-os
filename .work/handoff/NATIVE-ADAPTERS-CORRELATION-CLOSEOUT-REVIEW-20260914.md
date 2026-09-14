# Native Adapters Correlation Closeout — Big Review 交付包

平台中立。**這不是重開 `cc/native-adapters-task-ref-correlation`
（NO_GO，未合併）。** 這是 Owner 簽定 spec-freeze（`FP-1: A / FP-2: A /
FP-3: A`）之後的全新實作，新 worktree／branch，從 `main` 重新開始。

## 1. 審什麼

`.work/CARD-NATIVE-ADAPTERS-TASK-REF-SPEC-FREEZE-20260914.md` 三個
freeze point 有沒有正確落實，以及大 review 上一輪的三筆 finding
（identity 混淆、Claude `Stop` 終態前提不成立、Hook 沒有機器保證依欄位
組批）是否真的收乾淨。

## 2. Frozen commit

```
base             28438bb（main，SSP-307／SSP-308 皆已 merge，狀態不變）
review_commit    a01f26c5118fef69572dfcdcd654ac71f7bf41e1
branch           cc/native-adapters-correlation-v2（已 push origin）
```

參考（不合併、僅供對照）：`cc/native-adapters-task-ref-correlation`
（NO_GO 內容，`P1=2 / P2=1`）。

```
git fetch origin && git checkout cc/native-adapters-correlation-v2
git diff 28438bb..a01f26c --stat
```

## 3. Owner 簽定的三個 freeze point，各自怎麼落實

**FP-1-A（identity 分離）**：`task_ref` 全面改名
`native_correlation_ref`。契約明寫這**不是** `ai-work-record-hook.yaml`
的 `task_ref`（task-card URN）——本 Adapter 不核發、不解析 task-card
URN，翻譯是呼叫端的責任。請確認兩份契約、兩支 validator、四個 fixture
檔沒有殘留的 `task_ref` 欄位名混用。

**FP-2-A（Stop 終態判斷）**：Claude Code `mapping_run` 新增
`stop_hook_active`。`native_event == "Stop"` 且該欄位為 `true` 一律
`CLAUDE_CODE_STOP_HOOK_ACTIVE_NOT_TERMINAL`。只加在 Claude Code——
Codex 沒有對應證據顯示需要同一機制，未套用。

**FP-3-A（Hook 邊界誠實記錄，不改 enforcement）**：
`ai-work-record-hook.yaml` 新增 `capture_contract.batch_scoping_rule`
純文字，**沒有**改 `hook_capture_failure` 的任何判斷邏輯。新增正例
`HOOK_CAP_POS_MIXED_TASK_REF_KNOWN_GAP`：兩個不同 `task_ref` 組成合法
transition 序列，`expected: allow`——這個案例通過本身就是「混批不會被
攔下」的證據，請自行重播確認這不是宣稱。

## 4. 特別請看的點

1. **這條線已經有過一輪同類型 NO_GO**（identity 混淆、終態前提）。
   請特別檢查這輪的修法有沒有引入同一類問題的變體——例如
   `native_correlation_ref` 改名後，會不會有別的地方又把它跟某個真正的
   身分概念搞混。
2. **FP-3-A 刻意選擇「不改 enforcement，只誠實記錄」**——這代表混入
   不同 `task_ref` 的批次目前**仍然**不會被攔下，只是現在有一個正例
   明講這件事，而不是靠 handoff 文字宣稱。如果你認為這個邊界的風險
   等級需要真正的 enforcement（`FP-3-B`，改 `hook_capture_failure`），
   那是 Owner 尚未簽的選項，請提出來。
3. **Codex 沒有 `stop_hook_active` 類似機制**——這是刻意的，不是遺漏：
   沒有測到 `task_started`／`task_complete` 有同一類「同一 turn 內
   終態訊號可能重複」的證據。如果你認為這個排除本身需要更多驗證，
   請指出。

## 5. Mutation 要求

**A. 五支 evaluator 的 guard parity**：

| 契約 | evaluator | 結果 |
| --- | --- | --- |
| Codex | `codex_mapping_failure`（16 條） | 16 RED / 0 GREEN |
| Codex | `codex_rollback_failure`（6 條） | 6 RED / 0 GREEN |
| Codex | `codex_runtime_sample_failure`（1 條） | 1 RED / 0 GREEN |
| Claude Code | `claude_code_mapping_failure`（17 條） | 17 RED / 0 GREEN |
| Claude Code | `claude_code_rollback_failure`（6 條） | 6 RED / 0 GREEN |

**46/46，第一輪 probe 全紅，無 GREEN(bad)。**

**B. 結構／跨契約 probe（5 條）**：

| 契約 | 動作 | 結果 |
| --- | --- | --- |
| Codex | `lifecycle_event_map` 清空（回歸） | RED |
| Codex | `error_contract` 移除 `MISSING_NATIVE_CORRELATION_REF` | RED |
| Claude Code | `lifecycle_event_map` 清空（回歸） | RED |
| Claude Code | `error_contract` 移除 `STOP_HOOK_ACTIVE_NOT_TERMINAL` | RED |
| Claude Code | `error_contract` 移除 `MISSING_NATIVE_CORRELATION_REF` | RED |

還原請用 `cp` 備份，不要用 `git checkout --`。

## 6. 邊界

不動 `ai-work-record-hook.yaml` 的任何 evaluator 邏輯；不驗證
`native_correlation_ref` 的實際值；不為 Codex 加 `stop_hook_active`
類似機制；不回收或合併上一輪 NO_GO 的 branch；不重開
`SSP-307`／`SSP-308` 已關閉的 review line。

## 7. 已跑的 gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：

| 檔 | 行數 |
| --- | --- |
| `codex-native-adapter.yaml` | 321 |
| `validate_codex_native_adapter_contract.rb` | 344 |
| `claude-code-native-adapter.yaml` | 344 |
| `validate_claude_code_native_adapter_contract.rb` | 285 |
| `ai-work-record-hook.yaml` | 176 |
| `validate_ai_work_record_hook_contract.rb` | 301 |

全部在 `< 400` 硬上限內。

請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
