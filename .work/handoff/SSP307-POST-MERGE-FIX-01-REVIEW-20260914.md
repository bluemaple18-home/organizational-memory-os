# SSP-307 Post-Merge Fix 01 — Big Review 交付包

平台中立。**這不是重開已關閉的 `SSP-307` big review**——那條 review line
已經 `ACCEPTED_GO` 並 merge 進 `main`（`32b3f82`），是不可變的歷史。這是
對已出貨程式碼的新一輪修正，base 是目前的 `main`。

## 1. 審什麼

已合併的 `codex-native-adapter.yaml` 裡 `task_started → start`／
`task_complete → submit_review` 有跟 `SSP-308`（Claude Code Native
Adapter，姊妹卡）`SSP308-F-02` 同一種缺陷：映射的事件其實是 per-turn
cadence，不是 per-Work-Record 一次，在多 turn session 會產生非法
`IN_REVIEW → IN_REVIEW` transition。

## 2. Frozen commit

```
base             536f110（main，含 SSP-307 與 SSP-308 皆已 merge）
review_commit    78ea865aa02fe9f114bf994b09483fabcd42ffb6
branch           cc/ssp307-per-turn-cadence-fix（已 push origin）
```

```
git fetch origin && git checkout cc/ssp307-per-turn-cadence-fix
git diff 536f110..78ea865 --stat
```

## 3. 觸發與驗證

研究 `SSP-308` repair-01（`SSP308-F-02`）時，注意到 `SSP-307` 的
`task_complete → submit_review` 是同一種設計形狀，記錄於
`.work/CARD-SSP307-PER-TURN-CADENCE-CONCERN-20260914.md`。

驗證方式：對本機**全部 830 個真實 Codex session**，逐一計算每個 session
的出現次數（不是只看聚合總數，避免離群值誤導）：

```
task_started：0或1次 206 個（24.8%）　2次以上 624 個（75.2%，最大 376 次）
task_complete：0或1次 219 個（26.4%）　2次以上 611 個（73.6%，最大 375 次）
```

**73~75% 是絕大多數的常態，不是離群值。**

## 4. 契約變更

| 檔 | 說明 |
| --- | --- |
| `規格/v0.1/codex-native-adapter.yaml` | `lifecycle_event_map` 清空；`task_started`／`task_complete` 移入 `non_lifecycle_event_types`；新增 `hard_stops` 條目 |
| `scripts/validate_codex_native_adapter_contract.rb` | 移除因 map 清空而不可達的 `CODEX_MAPPING_TARGET_MISMATCH` 分支；移除 `lifecycle_map` 非空斷言 |
| `規格/v0.1/fixtures/codex-native-adapter-{positive,negative}-fixtures.json` | 對應調整（見 §6） |
| 新 `.work/CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914.md` | 延後映射決策 |

**未改動任何上游契約**（`ai-task-card-record.yaml`、`ai-work-record-hook.yaml`
逐字未變）。

## 5. 特別請看的點

1. **修法完全比照 `SSP-308` repair-01 的形狀**（`081d960`）——同一種
   問題、同一種修法選擇（清空而非猜一個「更安全」的映射）。請確認這個
   對照是否站得住腳，還是這裡有 `SSP-308` 沒有的額外考量。
2. **死碼移除**：evaluator 裡 `mapped_to` 比對分支因空 map 而移除，
   `error_contract` 綁定沿用既有 AST 模組（`scripts/lib/loop_return_contract.rb`）
   自動同步縮小可回傳集合。
3. **一個結構 probe 因設計改變而失效，誠實記錄，未隱藏**：原本驗證
   「上游 `lifecycle_event_to_status` 移除 `submit_review` 會轉紅」的
   probe，在空 map 下不再適用（沒有條目可迭代）。這不是新漏洞，是跟
   `SSP-308` 同一設計下的同一情況。見 evidence §結構／跨契約 probe。

## 6. Fixture 調整明細

- 正例：兩個 `MAPPED` 案例改為 `NOT_LIFECYCLE`（`task_started`／
  `task_complete`）；`runtime_sample_cases` 的分類切分同步更新。
- 負例：移除 `CODEX_NEG_MAPPED_TO_MISMATCH`（情境不再存在）；
  `CODEX_NEG_NOT_LIFECYCLE_UNCLASSIFIED` 改用真正未觀測過的事件名稱
  重測同一條 guard（原本用的 `task_complete` 現在已經在
  `non_lifecycle_event_types` 裡，不能再測「不在裡面」）。

## 7. Mutation 要求

**A. 三個 evaluator 的 guard parity**：

| evaluator | 我的結果 |
| --- | --- |
| `codex_mapping_failure`（14 條，原 15） | 14 RED / 0 GREEN |
| `codex_rollback_failure`（6 條，未變動） | 6 RED / 0 GREEN（assertion 5 / exception 1） |
| `codex_runtime_sample_failure`（1 條，未變動） | 1 RED / 0 GREEN |

**B. 結構／跨契約 probe（5 條）**：

| # | 動作 | 我的結果 |
| --- | --- | --- |
| 1 | `lifecycle_event_map` 重新填一條與 `non_lifecycle` 重疊的事件 | RED |
| 2 | `error_contract` 改名一個 code、evaluator 未同步 | RED |
| 3 | `non_lifecycle_event_types` 少一個真實觀測到的事件 | RED |
| 4 | runtime sample 多一個真實觀測到但契約未分類的事件類型 | RED |
| 5 | 上游 `lifecycle_event_to_status` 移除 `submit_review`（回歸） | **GREEN(bad)，見 §5-3 說明** |

還原請用 `cp` 備份，不要用 `git checkout --`。

## 8. 邊界

本卡**不做**：不重定義任何映射候選（`task_started`／`task_complete` 是
否有安全的映射方式留給
`.work/CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914.md`）；不動
`turn_aborted` 或其他既有分類；不動 `SSP-308`；不做即時 runtime probe；
不改上游契約。

## 9. 已跑的 gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：validator 336 行、契約 270 行（< 400 硬上限）。

請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
