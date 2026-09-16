# AIWR 最後一哩 closeout — evidence

日期：2026-09-16　branch：`cc/aiwr-last-mile`　base：`654313b`
Owner 簽核：`FP-1: A / FP-2: A / FP-3: A`

## 端到端驗證（真實 hook 呼叫，非模擬函式）

用真的 `.claude/hooks/aiwr_pilot_hook.rb`（帶 `OMOS_TASK_REF` 環境變數）
逐一送入事件，再用 `scripts/build_aiwr_capture_batch.rb` 組批，最後把
產出的 batch 餵回**機械抽取自 `validate_ai_work_record_hook_contract.rb`**
的 `hook_capture_failure`（連同 `replay_transition_failure`、`urn?` 與
相依常數一併抽取，非手抄）。

### 情境與結果

送入 9 筆事件：

| session | turn | 事件 | 宣告的 task_ref |
|---|---|---|---|
| sess-A | turn-1 | start / submit_review | 卡 1 |
| sess-A | turn-2 | start / submit_review | 卡 1 |
| sess-A | turn-1（**重放**） | start / submit_review | 卡 1 |
| sess-C | t9 | start / submit_review | 卡 2 |
| sess-B | turn-x | start | **無宣告** |

組批結果：

```
讀入 9 筆；組出 2 個 batch（略過 1 筆未宣告／非 MAPPED）

capture-batch-1111...json  raw 6 筆 → 去重後 4 筆
  序列 ["start","submit_review","start","submit_review"]   → VALID (nil)

capture-batch-9999...json  raw 2 筆 → 去重後 2 筆
  序列 ["start","submit_review"]                           → VALID (nil)
```

### 逐條對應 Acceptance

1. **FP-1-A 生效**：`sess-B`（無 `OMOS_TASK_REF`）那筆被略過，沒有被
   套用任何預設值或推論。
2. **FP-2-A 達成**：兩個 batch 都通過真實 `hook_capture_failure`（`nil`）。
3. **`batch_scoping_rule` 滿足**：兩張卡各自成檔，每個 batch 的
   `task_ref` 唯一值為 1。
4. **FP-3-A 冪等生效**：卡 1 的 raw 有 6 筆（含重放的 2 筆），去重後
   4 筆，`emitted.lifecycle_events` 等於去重後序列——證明
   `session_id+native_correlation_ref+event` 這個 key 真的收斂重複事件，
   且不會把不同 turn 誤併。
5. **多 turn 合法**：`start→submit_review→start→submit_review` 對應
   `OPEN→IN_REVIEW→OPEN→IN_REVIEW`，`IN_REVIEW→OPEN` 在
   `allowed_status_transitions` 裡是合法邊，轉移重放通過。

## 真實 pilot log 未受污染

測試全程在本 worktree 進行，測完刪除並 `git checkout --` 還原，確認
`.work/evidence/ssp310-pilot-runtime-log.jsonl` 仍是真人 pilot 的 2 筆。

## Gate

```
ruby scripts/validate_*.rb（24 支既有）  → PASS（未改動任何既有 validator）
git diff --check                         → clean
scripts/build_aiwr_capture_batch.rb      → 104 行（< 400）
```

## 本輪沒有做的事

- 真人帶 `OMOS_TASK_REF` 的實跑（下一步，需 Owner 開 session）。
- 把 `hook_capture_failure` 抽成共用 lib 讓 batch 驗證進常設 gate——會動到
  已 `ACCEPTED_GO` 的 SSP-301 交付物，屬 Refactor Mode，不在本卡。
- 任何 canonical store 寫入（FP-2-A 明確排除，且系統裡不存在該 store）。
