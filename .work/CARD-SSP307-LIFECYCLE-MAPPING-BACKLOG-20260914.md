---
id: SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914
status: SUPERSEDED_BY_TASK_REF_FIX
type: implementation
tier: T1
jira: SSP-307（AIWR-09，後續強化）
origin: "SSP-307 POST_MERGE_FIX_01：lifecycle_event_map 清空後，映射決策延後"
---

# SSP-307 Lifecycle Mapping（現為硬性前置，等真實發生頻率資料）

## SUPERSEDED（2026-09-14）

`task_started`／`task_complete` 都已透過 `task_ref`（`turn_id`）機制重新映射，
見 `.work/CARD-NATIVE-ADAPTERS-TASK-REF-CORRELATION-20260914.md`。這張卡
不再是這兩個事件的待辦。如果未來又找到別的候選事件要映射，開新卡，不要
重新打開這張。

## 現況（POST_MERGE_FIX_01 之後，歷史記錄）

`codex-native-adapter.yaml` 的 `lifecycle_event_map` 目前清空。
`task_started`／`task_complete` 都已改列 `non_lifecycle_event_types`——
實測（830 個真實 session，逐一計算每個 session 的出現次數，非只看總數）
確認兩者在 **73~75% 的真實 session 中出現 2 次以上**，不是罕見情況。

依 `hard_stops` 新增的一條：**在有真實發生頻率證據之前，
`lifecycle_event_map` 不得新增任何條目**。

## 修法（等有 runtime probe 或其他證據時）

1. 找出是否有任何 Codex 原生事件（或事件的某個欄位組合）具有「每個
   Work Record 最多一次」的可證實保證。候選方向：
   - 是否有更高層級的事件（例如 session 本身的開始／結束，而非
     task/turn 層級）？
   - `task_started`／`task_complete` 的 payload 是否帶有可以區分
     「第一個 turn」與「後續 turn」的欄位？
   - 是否該改變設計：不追求「單一原生事件對應一個生命週期轉換」，
     而是在更高層（Hook／Harness）做狀態感知的聚合，而非要求這個
     無狀態 Adapter 自己解決？
2. 若確認某個事件安全，比照 `SSP-308` 的姊妹卡：更新
   `lifecycle_event_map.map`、移出 `non_lifecycle_event_types`，
   補上對應正例，跑完整 guard parity + 結構 probe。
3. 若決定「單一事件無法安全對應」是這個 Adapter 架構的根本限制，
   考慮是否需要回頭跟 Owner 討論放寬 `hard_stops` 的「無狀態純函式」
   限制——但那是 T2 等級的規格決策，不是這張卡能單方面決定的。

## 不做

不在本卡猜測任何映射；不改變 Adapter 的無狀態架構假設（除非明確
回到 Owner 討論）。
