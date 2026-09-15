# Native Adapters Correlation Closeout — evidence

日期：2026-09-14　branch：`cc/native-adapters-correlation-v2`
base：`28438bb`（main，SSP-307／SSP-308 皆已 merge，狀態不變）

依 Owner 簽定的 `FP-1: A / FP-2: A / FP-3: A` 實作。**這不是重開
`cc/native-adapters-task-ref-correlation`（NO_GO）**——新 worktree／branch，
從 main 重新開始，沿用該 branch裡沒被 finding 否定的部分（`turn_id`／
`prompt_id` 研究、`TaskCreate` 死路排除），三個被否定的點各自修正。

## FP-1-A：`task_ref` → `native_correlation_ref`

兩份契約（`codex-native-adapter.yaml`／`claude-code-native-adapter.yaml`）、
兩支 validator、四個 fixture 檔全面改名。修正過程中發現機械式改名留下
一個錯誤陳述——原文字宣稱「`ai-work-record-hook.yaml` 的
`event_envelope_fields` 就叫這個名字」，改名後這句話變成同義反覆、失去
原本要澄清的意義。重寫成明確陳述：這個欄位**不是** Hook 的 `task_ref`
（task-card URN），本 Adapter 不核發、不解析 task-card URN，翻譯是
呼叫端責任。

## FP-2-A：`stop_hook_active`

只加在 Claude Code。`mapping_run.fields` 新增 `stop_hook_active`；
evaluator 在 `native_event == "Stop"` 分支加一條 guard：
`stop_hook_active == true` 時回傳 `CLAUDE_CODE_STOP_HOOK_ACTIVE_NOT_TERMINAL`，
其餘事件完全不受影響。新增：

- 負例 `CLAUDE_CODE_NEG_STOP_HOOK_ACTIVE_NOT_TERMINAL`（`stop_hook_active: true`）
- 正例 `CLAUDE_CODE_POS_STOP_NOT_ACTIVE_MAPS_SUBMIT_REVIEW`
  （`stop_hook_active: false` 明確值，跟既有正例的「缺席」情況分開測，
  確認兩種都合法）

Codex 沒有加對應欄位——目前沒有測到 `task_started`／`task_complete` 有
同一類「同一 turn 內終態訊號可能重複」的證據。

## FP-3-A：Hook 契約補寫、不改 enforcement

`規格/v0.1/ai-work-record-hook.yaml` 的 `capture_contract` 新增
`batch_scoping_rule`，純文字，明講「一次呼叫的 `raw` 陣列必須屬於同一個
`task_ref` 是呼叫端責任，`hook_capture_failure` 不驗證這件事」。

新增正例 `HOOK_CAP_POS_MIXED_TASK_REF_KNOWN_GAP`：兩個不同 `task_ref`
的事件（`urn:omos:task-card:1111...`、`urn:omos:task-card:2222...`）
組成合法 transition 序列（`start`／`submit_review`），`expected: "allow"`。
**這個案例通過（PASS）本身就是證據**——證明混入不同 `task_ref` 目前確實
不會被攔下，不是我的宣稱。

`scripts/validate_ai_work_record_hook_contract.rb` 對 `capture_contract`
的既有結構斷言只檢查 `allowed_events`／`event_envelope_fields`／
`reference_only`／`idempotency.dedupe_by` 四個既有欄位，新增
`batch_scoping_rule` 是兄弟欄位、不在被斷言的欄位集合裡，確認不影響
既有斷言。

## 驗證

### Guard parity

| 契約 | evaluator | 結果 |
| --- | --- | --- |
| Codex | `codex_mapping_failure`（16 條） | 16 RED / 0 GREEN |
| Codex | `codex_rollback_failure`（6 條） | 6 RED / 0 GREEN |
| Codex | `codex_runtime_sample_failure`（1 條） | 1 RED / 0 GREEN |
| Claude Code | `claude_code_mapping_failure`（17 條，較上一輪多 `STOP_HOOK_ACTIVE_NOT_TERMINAL` 一條） | 17 RED / 0 GREEN |
| Claude Code | `claude_code_rollback_failure`（6 條） | 6 RED / 0 GREEN |

**46/46，第一輪 probe 全紅，無 GREEN(bad)。**

### 結構／跨契約 probe

| 契約 | # | 動作 | 結果 |
| --- | --- | --- | --- |
| Codex | 1 | `lifecycle_event_map` 清空（回歸） | RED/assertion |
| Codex | 2 | `error_contract` 移除 `CODEX_MISSING_NATIVE_CORRELATION_REF` | RED/exception |
| Claude Code | 1 | `lifecycle_event_map` 清空（回歸） | RED/assertion |
| Claude Code | 2 | `error_contract` 移除 `CLAUDE_CODE_STOP_HOOK_ACTIVE_NOT_TERMINAL` | RED/exception |
| Claude Code | 3 | `error_contract` 移除 `CLAUDE_CODE_MISSING_NATIVE_CORRELATION_REF` | RED/exception |

**5/5 RED。** 所有 probe 後檔案 `git diff --name-only` 為空。

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

| 檔 | 行數 |
| --- | --- |
| `codex-native-adapter.yaml` | 321 |
| `validate_codex_native_adapter_contract.rb` | 344 |
| `claude-code-native-adapter.yaml` | 344 |
| `validate_claude_code_native_adapter_contract.rb` | 285 |
| `ai-work-record-hook.yaml` | 176 |
| `validate_ai_work_record_hook_contract.rb` | 301 |

全部在 `< 400` 硬上限內。

## 本輪沒有做的事

- 沒有改 `ai-work-record-hook.yaml` 的任何 evaluator 邏輯（enforcement）。
- 沒有驗證 `native_correlation_ref` 的實際值是否等於真實
  `turn_id`／`prompt_id`。
- 沒有為 Codex 加 `stop_hook_active` 類似機制——沒有證據顯示需要。
- 沒有回收或合併上一輪 NO_GO 的
  `cc/native-adapters-task-ref-correlation`。
