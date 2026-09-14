# SSP-308 Repair 01 — 定點 re-review 交付包

同一條 review line。收 `SSP308-F-01`／`F-02`／`F-03` 全部三筆。

## 1. 鎖定

```
base                9a6fd1c
original_review     90bc32d881abb5a3fae9490a6cfffd2f283c5729   （immutable，NO_GO）
repair_commit       081d9601ee33b9ff1a39ead21e713dbac989a375
branch              cc/ssp308-claude-code-native-adapter
```

定點 diff：`git diff 90bc32d..081d960`

## 2. 逐筆收法（全部重新去源頭查證，不是照單全收）

**F-01**：用 `WebFetch` 直接抓 `https://code.claude.com/docs/en/hooks`，
實際 **33 個**事件名稱（你說約 29 個，更多）。凍結成
`規格/v0.1/fixtures/claude-code-hook-events-doc-snapshot.json`，帶
`source_url` + `captured_at`。

**F-02**：`WebFetch` 查證兩件事並引用原文：

- `Stop`：「When Claude finishes responding」，per-turn cadence。
- `SessionStart`：「after `/clear` or a compaction, `SessionStart` fires
  again with the servers already available」，同一 session 內會重複。

對照 `allowed_status_transitions`：`OPEN`／`IN_REVIEW` 都沒有自迴圈邊，
所以第二個 turn 的 `Stop` 或 compaction 前的重複 `SessionStart` 都會產生
非法 transition——這是正常多 turn 使用，不是邊緣案例。

**修法**：`lifecycle_event_map` 本輪清空，33 個事件全部分類為
`non_lifecycle_event_types`。沒有任何 hook 有文件確認的「每個 Work Record
最多一次」保證，而本 Adapter 依 `hard_stops` 是無狀態純函式，無法靠事件
名稱分辨首次與重複。實際映射決策升級為
`.work/CARD-SSP308-RUNTIME-PROBE-BACKLOG-20260914.md` 的**硬性前置**（不
再是選配強化）。

**F-03**：完整性檢查改為對照獨立凍結檔（帶出處），不再是同一份 YAML 裡
兩張清單互比。

## 3. 死碼清理（F-02 的直接後果，主動處理）

`lifecycle_map` 清空後，evaluator 裡「`mapped_to` 是否等於 declared map
entry」的分支永遠不可達（空 Hash 的 `key?` 恆 false，前一行永遠先回傳）。
移除該段與 `CLAUDE_CODE_MAPPING_TARGET_MISMATCH`。因為 `error_contract`
綁定走 AST 模組，宣告集合自動同步縮小，不需要手動調整清單。

## 4. 請重播

**A. Guard parity（兩個 evaluator，回歸）**

| evaluator | 結果 |
| --- | --- |
| `claude_code_mapping_failure`（14 條，原 15，少了移除的死碼） | 14 RED / 0 GREEN |
| `claude_code_rollback_failure`（6 條，未變動） | 6 RED / 0 GREEN（assertion 5 / exception 1） |

**B. 結構／跨契約 probe（4 條，針對本輪修法）**

| # | 動作 | 我的結果 |
| --- | --- | --- |
| 1 | 凍結快照（獨立檔）多一個契約未分類的事件 | RED |
| 2 | 凍結快照少一個契約仍分類著的事件（反向） | RED |
| 3 | 快照缺 `source_url` | RED |
| 4 | `lifecycle_event_map` 重新填一條與 non_lifecycle 重疊的事件 | RED |

probe 1/2 是 F-03 修法的核心——完整性現在是對照**跨檔案**獨立來源。

還原請用 `cp` 備份，不要用 `git checkout --`。

## 5. Gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

validator **267 行**、契約 **269 行**（< 400 硬上限）。

## 6. 主動揭露（不在本卡修，已回報 Owner）

research SSP308-F-02 時發現：已合併的 `SSP-307`
（`task_started → start`／`task_complete → submit_review`）用真實資料
換算，`task_started`／`task_complete` 平均每 session 出現約 11.6 次
（9529／9392 除以 818），強烈暗示同一類 per-turn cadence 問題。**未在
本卡處理**——那是獨立、已 Owner 接受的 review line，已在對話中直接回報
Owner 裁決是否開新卡。若你認為這也在本輪審查範圍內，請明說。

## 7. 邊界（未變）

沒有修改已合併的 `codex-native-adapter.yaml`；沒有做即時 hook 觸發；
沒有改任何上游契約；`error_contract` AST 綁定／authority boundary／
rollback evaluator 未重開（你未列 finding）。

請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
