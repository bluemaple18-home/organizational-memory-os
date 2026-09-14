---
id: SSP308-RUNTIME-PROBE-BACKLOG-20260914
status: PARTIALLY_SUPERSEDED_BY_TASK_REF_FIX
type: implementation
tier: T1
jira: SSP-308（AIWR-10，後續強化）
origin: "SSP-308 kickoff：Owner 選定本輪不做 runtime probe，先寫靜態分類契約"
escalated: >-
  repair-01（2026-09-14）：SSP308-F-02 證明沒有任何 hook 名稱有文件確認的
  「每個 Work Record 最多發生一次」保證，本卡從「選配強化」升級為
  「lifecycle_event_map 要新增任何條目前的硬性前置」——見
  規格/v0.1/claude-code-native-adapter.yaml 的 hard_stops 與
  lifecycle_event_map.design_note。
---

# SSP-308 Runtime Probe（現為 lifecycle_event_map 的硬性前置）

## PARTIALLY SUPERSEDED（2026-09-14）

`UserPromptSubmit`／`Stop` 都已透過 `task_ref`（`prompt_id`）機制重新映射，
見 `.work/CARD-NATIVE-ADAPTERS-TASK-REF-CORRELATION-20260914.md`。這張卡
對這兩個事件不再是待辦，但 `SessionEnd`（`reason` 分布未知）與其他 31 個
事件仍然沒有 lifecycle 映射，這張卡對它們仍然有效。

## 現況（repair-01 之後，歷史記錄）

`claude-code-native-adapter.yaml` 對真實文件（33 個 hook 事件，凍結於
`規格/v0.1/fixtures/claude-code-hook-events-doc-snapshot.json`，帶
`source_url`／`captured_at` 出處）已經做到完整分類，但
**`lifecycle_event_map` 本輪刻意留空**——33 個事件全部分類為
`non_lifecycle_event_types`。

原因：big review 第一輪指出 `SessionStart → start` 與 `Stop → submit_review`
的粒度不對。實測確認（透過官方文件）：

- `Stop` 是 per-turn cadence，每個 turn 結束都會發，不是每個 Work Record
  一次。第二個 turn 的 `Stop` 會嘗試 `IN_REVIEW → IN_REVIEW`（不存在的邊）。
- `SessionStart` 是 per-session cadence，但**文件明講**「`/clear` 或 compaction
  之後，`SessionStart` 會再次觸發」——同一個 session 內可能發生第二次，
  若發生在第一個 `Stop` 之前，會嘗試 `OPEN → OPEN`（同樣不存在）。
- `TaskCreated`／`TaskCompleted` 名稱上像是任務邊界，但文件只寫「透過
  `TaskCreate` 建立」，沒有確認是否對應到 AIWR 的頂層 Work Record 邊界，
  還是 Claude Code 自己內部的任務／佇列機制。

這個 Adapter 依 `hard_stops` 是無狀態的純函式（不做狀態機），沒辦法單靠
事件名稱分辨「這是這個 Work Record 的第一次 SessionStart」還是「這是
compaction 造成的第二次」。

## 修法（等有真實觸發環境時）

1. 實際配置一組 hook（`SessionStart`／`Stop`／`TaskCreated`／`TaskCompleted`
   至少各觸發幾次，含跨 compaction 的情境），在真實 Claude Code session 中
   取得真實 payload 與**發生頻率**。
2. 只萃取受控欄位（hook 名稱、任何 discriminator 欄位如 `reason`），不擷取
   任何訊息內容、工具輸出、檔案內容——比照 SSP-307 的做法，先問過 Owner
   再讀。
3. 具體要回答的問題：
   - `TaskCreated`／`TaskCompleted` 是否真的對應到一個穩定、每 Work Record
     恰好一次的邊界？如果是，這可能是比 `SessionStart`／`Stop`更安全的
     映射對象。
   - 是否有 payload 欄位能區分「Work Record 的第一次 SessionStart」與
     「compaction 造成的重複」？
4. 只有在能確定某個 native event 有「每個 Work Record 最多一次」的保證後，
   才能讓 `lifecycle_event_map` 新增條目——這是 repair-01 寫進
   `hard_stops` 的硬性要求，不是建議。
5. 屆時同步比照 `codex-native-adapter.yaml` 的
   `codex_runtime_sample_failure`-style 雙向相等 evaluator，從一開始就用
   雙向比對（記取 SSP307-F-04 的教訓，不要重演單向漏洞）。

## 不做

不在本卡實際配置或觸發任何 hook；不讀取任何真實 session 內容。
