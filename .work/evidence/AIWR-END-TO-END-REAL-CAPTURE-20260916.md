# AIWR 端到端真實 capture — evidence

日期：2026-09-16　執行者：Owner（matt）　平台：Claude Code v2.1.272

這是本條 lane（`SSP-298`～最後一哩）**第一次產出端到端的真實 capture
batch**：從真人在終端機做的一件真事，一路走到通過既有 Hook 契約驗證的
Work Record 批次。

## 鏈路

```
真人的一個 turn
  → Claude Code 原生事件（UserPromptSubmit / Stop）
  → .claude/hooks/aiwr_pilot_hook.rb 分類成 mapping_run，
    並原樣帶上呼叫端宣告的 OMOS_TASK_REF
  → scripts/build_aiwr_capture_batch.rb 依 task_ref 組批
  → capture batch → hook_capture_failure = nil（VALID）
  → task-card 狀態：OPEN → IN_REVIEW
```

## 啟動方式

```
cd /Users/matt/Documents/ChatGPT/知識庫
export OMOS_TASK_REF=urn:omos:task-card:11111111-2222-3333-4444-555555555555
cc --settings .claude/settings.pilot.json
```

`cc` 是 Owner `~/.zshrc` 既有的啟動函式。**注意**：`OMOS_TASK_REF=... cc ...`
這種前綴寫法在 zsh 對 shell 函式會失敗（實測 Claude Code 啟動即報錯），
必須先 `export` 再另行啟動。已寫進下方「操作注意事項」。

## 擷取到的真實記錄

`.work/evidence/ssp310-pilot-runtime-log.jsonl` 現有 4 筆，本輪新增後兩筆：

```
session f45bea53-915d-4d2b-8a03-c20e4449c032
turn    c49e9276-841b-4d14-869b-ca795c4b48b2
  UserPromptSubmit → start          2026-09-16T07:22:09Z
  Stop             → submit_review  2026-09-16T07:22:42Z
  兩筆皆帶 declared_task_ref = urn:omos:task-card:11111111-...-555555555555
```

前兩筆是 2026-09-15 的 pilot，當時 `declared_task_ref` 機制尚未存在，
**沒有**歸屬宣告。

## 組批結果

```
讀入 4 筆；組出 1 個 batch（略過 2 筆未宣告／非 MAPPED）
capture-batch-11111111-....json  events=["start","submit_review"]
```

略過的正是 2026-09-15 那兩筆——這同時是 **FP-1-A 在真實資料上生效的證明**：
沒有宣告歸屬的記錄真的進不了 batch，不是靠合成負例假設出來的。

產出的 batch 已入庫：
`.work/evidence/capture-batch-11111111-2222-3333-4444-555555555555.json`

## 驗證

把該 batch 餵回**機械抽取自** `validate_ai_work_record_hook_contract.rb`
的 `hook_capture_failure`（連同 `replay_transition_failure`／`urn?`／
相依常數，非手抄）：

```
hook_capture_failure → VALID (nil)
task_ref 唯一值      → ["urn:omos:task-card:11111111-...-555555555555"]（一卡一批）
序列                  → ["start","submit_review"] → OPEN → IN_REVIEW（合法邊）
debug log            → 空（本輪沒有任何跳過或錯誤）
```

## 證據範圍（誠實限定）

- **單一真人 turn、單一 task card、單一平台**。多 turn 振盪、併發 session、
  `stop_hook_active=true`、多張卡分批等情境，目前仍只有合成案例與常設
  gate（`validate_aiwr_capture_batch_builder.rb`）覆蓋，**未有真人資料**。
- `task_ref` 是 Owner 手動指定的測試用 UUID，**不對應任何真實存在的
  task card**——本輪驗證的是鏈路與契約合規，不是任務卡本身的真實性。
- 這條路徑永遠不會發出 `complete`（Adapter 無完成權限），所以卡片不會
  因此走到 `DONE`。設計如此。

## 操作注意事項（實測踩到的坑，記錄備查）

1. **環境變數不能用前綴寫法**：`OMOS_TASK_REF=... cc ...` 會讓 Claude Code
   啟動失敗（錯誤訊息誤報為 "low max file descriptors"）。必須
   `export OMOS_TASK_REF=...` 後另行啟動。
2. **從 `~/Documents` 底下啟動需要終端機的「完全取用磁碟」權限**，否則
   macOS TCC 會擋（同樣誤報成 file descriptor 問題）。2026-09-15 已授予。
