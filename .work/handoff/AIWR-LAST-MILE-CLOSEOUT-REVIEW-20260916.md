# AIWR 最後一哩 closeout — 大 review 交付包

## 鎖定

```
base    654313b   （Owner 簽核凍結卡的 commit）
review  <見對話中的派工區塊>
branch  cc/aiwr-last-mile
```

只新增／修改三處：

```
.claude/hooks/aiwr_pilot_hook.rb          +declared_task_ref（FP-1-A 透傳）
scripts/build_aiwr_capture_batch.rb       新增，104 行
.work/CARD-... / .work/evidence/...       卡片與證據
```

**未修改任何既有契約檔案或既有 validator。**

## 這張卡在做什麼

`SSP-307`～`SSP-310` 之後，Adapter 能產出 `mapping_run`，但沒有任何東西
把它接到既有 Hook 擷取契約——`native_correlation_ref`（`prompt_id`）與
`task_ref`（task-card URN）是兩種身分，契約明訂翻譯是「呼叫端責任」，
而那個呼叫端一直不存在。本卡就是那個呼叫端。

三個凍結點已由 Owner 簽核（`A A A`），實作逐條對應，未擴大。

## 請重播

```bash
export CLAUDE_PROJECT_DIR="$PWD"
TASK="urn:omos:task-card:11111111-2222-3333-4444-555555555555"
rm -f .work/evidence/ssp310-pilot-runtime-log.jsonl

# 兩個 turn + 重放 turn-1 + 一筆未宣告
for t in turn-1 turn-2 turn-1; do
  OMOS_TASK_REF="$TASK" ruby .claude/hooks/aiwr_pilot_hook.rb <<< \
    "{\"session_id\":\"sess-A\",\"prompt_id\":\"$t\",\"hook_event_name\":\"UserPromptSubmit\"}"
  OMOS_TASK_REF="$TASK" ruby .claude/hooks/aiwr_pilot_hook.rb <<< \
    "{\"session_id\":\"sess-A\",\"prompt_id\":\"$t\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}"
done
ruby .claude/hooks/aiwr_pilot_hook.rb <<< \
  '{"session_id":"sess-B","prompt_id":"x","hook_event_name":"UserPromptSubmit"}'

ruby scripts/build_aiwr_capture_batch.rb .work/evidence/ssp310-pilot-runtime-log.jsonl /tmp/out
```

我的結果：讀入 7 筆、組出 1 個 batch、略過 1 筆未宣告；raw 6 → 去重 4；
序列 `["start","submit_review","start","submit_review"]`。

然後把 batch 餵回**機械抽取**（勿手抄）自
`validate_ai_work_record_hook_contract.rb` 的 `hook_capture_failure`
（連同 `replay_transition_failure`／`urn?`／相依常數），我的結果：`nil`。

測完請 `rm -f .work/evidence/ssp310-pilot-runtime-log.jsonl` 並
`git checkout --` 還原真人 pilot 的那 2 筆。

## 請特別判斷

1. **`declared_task_ref` 這個欄位名與語意是否真的守住邊界**——Adapter
   契約明訂不核發／不解析 task-card 身分。我的主張是「原樣透傳呼叫端的
   宣告」不等於解析；請判斷這個區分是否成立，或是否仍越界。
2. **`event_key` 的決定性與碰撞風險**：`session_id + native_correlation_ref
   + event`。同一 turn 同事件會去重（想要的）；請判斷有沒有會**誤併**
   不同事件的情境。
3. **未宣告時的行為**：目前是「照常記 mapping_run，但不進 batch」。請判斷
   這是否符合 FP-1-A 的「沒宣告就不產出 batch」，或應該連記錄都不寫。
4. **batch 驗證不在常設 gate 內**（見卡片「已知限制」）。請判斷這是否構成
   finding，或接受為本卡範圍外的 Refactor 議題。

## Gate

```
ruby scripts/validate_*.rb（24 支既有）  → PASS
git diff --check                         → clean
新腳本                                    → 104 行（< 400）
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
