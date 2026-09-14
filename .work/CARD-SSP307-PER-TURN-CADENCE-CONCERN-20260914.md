---
id: SSP307-PER-TURN-CADENCE-CONCERN-20260914
status: AWAITING_OWNER_ROUTING_DECISION
type: concern
tier: n/a
jira: SSP-307（已 ACCEPTED_GO + merged @ 32b3f82，本卡不是 repair）
origin: "SSP-308 repair-01 research 過程中發現，未在該卡修復，回報 Owner 裁決"
---

# SSP-307 疑似有 SSP308-F-02 同一類 per-turn cadence 問題

👉 [假設與目標確認]
- 目標：把研究過程中發現的疑慮完整記錄下來，交給 Owner 裁決要不要開修復卡。
- 邊界：**本卡不修改任何 `codex-native-adapter.yaml` 或其 validator**。
  `SSP-307` 是已經 `ACCEPTED_GO` 並合併進 `main` 的獨立 review line，
  不因為研究另一張卡時的旁及發現就擅自回頭改。
- 驗收：Owner 裁決是否開修復卡；若開，另立新卡走完整 review 流程。

## 疑慮

`規格/v0.1/codex-native-adapter.yaml`（`SSP-307`，`ACCEPTED_GO @ 32b3f82`）
的映射：

```
task_started → start
task_complete → submit_review
```

`SSP-307` 實作時做過全量掃描（818 個真實 Codex session），量出：

```
task_started: 9529 次
task_complete: 9392 次
```

平均每個 session ≈ **11.6 次**。這個比例強烈暗示 `task_started`／
`task_complete` 是 **per-turn cadence**（每個 turn 一次），不是
per-Work-Record 一次——跟 `SSP308-F-02` 抓到的 `Stop`（Claude Code）
是同一種形狀。

若屬實：第二個 turn 的 `task_complete → submit_review` 會嘗試對已經在
`IN_REVIEW` 的卡再送一次 `IN_REVIEW`，而 `ai-task-card-record.yaml` 的
`allowed_status_transitions` 沒有 `IN_REVIEW → IN_REVIEW` 這條邊——跟
Claude Code 那邊完全同一個 bug 形狀。

## 為什麼這次沒被抓到（值得記錄的落差）

`SSP-307` 大 review 的兩輪 finding（`F-01`／`F-02`）都聚焦在「映射目標
是否合法」（`complete` 沒有 `OPEN→DONE` 邊、`turn_aborted` 不該映射到
終態），沒有人（包含 reviewer 與我）去檢查「同一個映射目標被同一個
Work Record 內的多次事件重複命中，是否還合法」。`SSP-308` 這輪能抓到，
是因為 reviewer 直接去查了官方文件裡 `Stop` 的觸發頻率語意；`SSP-307`
沒有對應的「頻率語意」文件可查（Codex 原生事件沒有公開規格），只能靠
量測數據**回推**，而回推需要有人主動去做這個除法——這次是在處理
`SSP-308` 時才自然浮現。

## 建議（不代替 Owner 裁決，僅供參考）

若要修，形狀會跟 `SSP-308 repair-01` 一樣：`lifecycle_event_map` 清空
`task_started`／`task_complete` 這兩條，全部改列
`non_lifecycle_event_types`，把映射決策交回
`.work/CARD-SSP291-EXIT-SHAPE-BACKLOG-20260911.md`（若適用）或另開一張
runtime probe 延伸卡，等能區分「這個 Work Record 的第一次」與「同一
session 內的重複」再決定映射。

## 不做

不修改 `codex-native-adapter.yaml`、其 validator、任何 fixture。
不假設這個疑慮一定成立——`task_started`／`task_complete` 也可能有本卡
沒考慮到的、讓重複觸發安全的機制（例如下游是否已經對同一 Work Record
做去重）。這需要 Owner 或下一位施工者實際查證。
