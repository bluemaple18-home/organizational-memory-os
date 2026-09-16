# AIWR 端到端真實 capture — 大 review 交付包

## 鎖定

```
base    f35de26
review  7ce9bfb
branch  cc/aiwr-e2e-evidence
```

本輪**只新增證據，不改任何程式碼或契約**：

```
.work/evidence/ssp310-pilot-runtime-log.jsonl                    +2 筆真實記錄
.work/evidence/capture-batch-11111111-...json                    新增（產出的 batch）
.work/evidence/AIWR-END-TO-END-REAL-CAPTURE-20260916.md          新增
.work/handoff/...（本檔）
```

## 這一輪是什麼

最後一哩（`80a198a`）合併後，Owner 親自帶 `OMOS_TASK_REF` 實跑一個 turn，
產出本 lane 第一筆端到端真實 capture batch：

```
真人的一個 turn
  → UserPromptSubmit / Stop
  → mapping_run（帶 declared_task_ref）
  → 依 task_ref 組批
  → hook_capture_failure = nil
  → OPEN → IN_REVIEW
```

## 請重播

```bash
ruby scripts/build_aiwr_capture_batch.rb \
  .work/evidence/ssp310-pilot-runtime-log.jsonl /tmp/out
# 我的結果：讀入 4 筆；組出 1 個 batch（略過 2 筆未宣告／非 MAPPED）

diff <(python3 -m json.tool /tmp/out/capture-batch-*.json) \
     <(python3 -m json.tool .work/evidence/capture-batch-*.json)
# 應無差異：入庫的 batch 與重跑結果一致（確認我沒有手改過產出）
```

再把入庫的 batch 餵回**機械抽取**（勿手抄）自
`validate_ai_work_record_hook_contract.rb` 的 `hook_capture_failure`。
我的結果：`nil`。

## 請特別判斷

1. **入庫的 batch 是否與重跑結果逐位元一致**——我想排除「證據是手工修過
   的」這種可能，重播指令已附。
2. **證據範圍的措辭是否過度宣稱**。我在 evidence 裡明確限定為「單一真人
   turn、單一 task card、單一平台」，並註明 `task_ref` 是測試用 UUID、
   不對應真實存在的 task card。請判斷這個限定是否足夠，或仍有外推嫌疑。
3. **略過 2026-09-15 那兩筆未宣告記錄**，我在 evidence 裡當成「FP-1-A 在
   真實資料上生效的證明」。請判斷這個推論是否成立（那兩筆是因為機制當時
   還不存在而沒有宣告，不是使用者刻意不宣告）。
4. **把真實 runtime log 與產出 batch 長期留在 `.work/evidence/`** 是否
   恰當——裡面是 session/turn 的 UUID 與時間戳，沒有任何對話內容。

## Gate

```
ruby scripts/validate_*.rb（25 支）  → PASS
git diff --check                      → clean
未改動任何 .rb／契約／設定檔
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
