# SSP-307 Post-Merge Fix 01 — evidence

日期：2026-09-14　branch：`cc/ssp307-per-turn-cadence-fix`　base：`536f110`
（`main`，`SSP-307` 已合併於此線更早的 `32b3f82`）

**這不是重開已關閉的 big review。** `SSP-307` 那條 review line 已經
`ACCEPTED_GO` 並 merge，是不可變的歷史。這是對已出貨程式碼的新一輪修正，
走全新的 worktree／branch／big review 流程。

## 觸發

研究 `SSP-308` repair-01（`SSP308-F-02`：`Stop → submit_review` 在多 turn
session 產生非法 transition）時，注意到 `SSP-307` 的
`task_complete → submit_review` 是同一種設計形狀，只是原本沒有公開文件
可查發生頻率，只能靠量測數據回推。記錄於
`.work/CARD-SSP307-PER-TURN-CADENCE-CONCERN-20260914.md`，Owner 指示驗證。

## 驗證（實測，非只看聚合平均）

`SSP-307` 原始實作時的證據是「818 個 session 總計 `task_started` 9529 次、
`task_complete` 9392 次」——只有總數，沒有分布。用總數除以 session 數
（≈11.6 次/session）只能看出「平均不是 1」，看不出「這是離群值撐出來的，
還是普遍現象」。

本輪對本機**全部 830 個真實 session**（比原始實作時的 818 多，因為時間
過去有新 session），逐一計算每個 session 的出現次數：

```
task_started 分布：
  0 或 1 次：206 個 session（24.8%）
  2 次以上：624 個 session（75.2%，最大單一 session 376 次）

task_complete 分布：
  0 或 1 次：219 個 session（26.4%）
  2 次以上：611 個 session（73.6%，最大單一 session 375 次）
```

**73~75% 是絕大多數的常態，不是離群值。** 這確認了：`task_complete →
submit_review` 在多 turn session 的第二次觸發會嘗試
`IN_REVIEW → IN_REVIEW`——`ai-task-card-record.yaml` 的
`allowed_status_transitions` 沒有這條邊，與 `SSP308-F-02` 同一種缺陷形狀。

## 修法（完全比照 SSP-308 repair-01）

1. `lifecycle_event_map.map` 從 `{task_started: start, task_complete:
   submit_review}` 清空為 `{}`。
2. `task_started`／`task_complete` 移入 `non_lifecycle_event_types`
   （原本 8 項 → 10 項），各自留下 `_note` 記錄實測依據（分布數字、
   最大值、與哪個 SSP-308 finding 同形狀）。
3. `lifecycle_event_map.design_note` 新增 `POST_MERGE_FIX_01` 段落，
   完整記錄發現過程、驗證方法、修法理由，不覆蓋或刪除原本
   `SSP307-F-01`（repair-01）的既有記錄。
4. `hard_stops` 新增一條：沒有真實發生頻率證據前，`lifecycle_event_map`
   不得新增條目。
5. Evaluator（`scripts/validate_codex_native_adapter_contract.rb`）裡
   「`mapped_to` 是否等於 declared map entry」的分支因 map 清空而不可達，
   主動移除（同 `SSP-308` repair-01 對這個模式的處理），並在原處留註解
   說明這是資料驅動的暫時不可達，不是邏輯上永遠不可達。
6. `error_contract` 移除 `CODEX_MAPPING_TARGET_MISMATCH`——綁定沿用既有
   AST 模組（`scripts/lib/loop_return_contract.rb`），移除 return 後
   宣告集合自動同步縮小，不需要手動調整清單。
7. `required_negative_fixtures` 對應調整（合併兩條 label 為一條，措辭
   與 `SSP-308` 的最終版本一致）。
8. 新開 `.work/CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914.md`，把
   「哪個事件安全可以映射」的決策延後。

## Fixture 調整

- 正例：`CODEX_POS_TASK_STARTED_MAPS_START`／
  `CODEX_POS_TASK_COMPLETE_MAPS_SUBMIT_REVIEW` 改為
  `CODEX_POS_TASK_STARTED_NOT_LIFECYCLE`／`CODEX_POS_TASK_COMPLETE_NOT_LIFECYCLE`，
  outcome 改為 `NOT_LIFECYCLE`。
- `runtime_sample_cases` 的 `classified_lifecycle_keys` 改為空、
  `classified_non_lifecycle_types` 加入 `task_started`／`task_complete`。
- 負例：移除 `CODEX_NEG_MAPPED_TO_MISMATCH`（情境不再存在，同 `SSP-308`
  的處理）；`CODEX_NEG_NOT_LIFECYCLE_UNCLASSIFIED` 原本用 `task_complete`
  測「不在 non_lifecycle 裡」，現在 `task_complete` 就在裡面，改用一個
  真正未觀測過的事件名稱重新測同一條 guard；
  `CODEX_NEG_MAPPED_NO_MAP_ENTRY` 的 `covers_negative_fixture` 措辭同步。

## 驗證

### Guard parity（三個 evaluator，逐 guard）

| evaluator | 結果 |
| --- | --- |
| `codex_mapping_failure`（14 條，原 15，少了移除的死碼） | **14 RED / 0 GREEN** |
| `codex_rollback_failure`（6 條，未變動） | **6 RED / 0 GREEN**（assertion 5 / exception 1） |
| `codex_runtime_sample_failure`（1 條，未變動） | **1 RED / 0 GREEN** |

**21/21，無 GREEN(bad)。**

### 結構／跨契約 probe（5 條）

| # | 動作 | 結果 |
| --- | --- | --- |
| 1 | `lifecycle_event_map` 重新填一條與 `non_lifecycle` 重疊的事件 | RED/assertion |
| 2 | `error_contract` 改名一個 code，evaluator 未同步 | RED/assertion |
| 3 | `non_lifecycle_event_types` 少一個真實觀測到的事件（`turn_aborted`） | RED/assertion |
| 4 | runtime sample 多一個真實觀測到但契約未分類的事件類型 | RED/assertion |
| 5 | 上游 `lifecycle_event_to_status` 移除 `submit_review`（回歸） | **GREEN(bad)** |

**4/5 RED，1 個誠實記錄的例外**：probe 5 在 v0.1（有映射時）是有效
probe，但 `lifecycle_event_map` 清空後，逐條驗證 target 合法性的迴圈
不會執行任何一次（沒有條目可迭代），所以這個 probe **對目前的設計不再
適用**——不是新發現的漏洞，是設計改變後自然失效的舊 probe，跟
`SSP-308` 同一個設計下的同一個情況完全一致。等 `lifecycle_event_map`
重新有條目（`CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914.md` 完成後），
這個 probe 會重新有意義。

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

檔案大小：validator 336 行、契約 270 行。皆在 `< 400` 硬上限內。

## 本輪沒有做的事

- 沒有重開已關閉的 `SSP-307` big review——這是全新的 post-merge 修正
  流程。
- 沒有動 `turn_aborted` 或其他既有分類（`Stop conditions` 明確排除）。
- 沒有做即時 runtime probe。
- 沒有動 `SSP-308`（姊妹卡，已獨立 `ACCEPTED_GO`）或任何上游契約。
