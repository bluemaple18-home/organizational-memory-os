---
id: SSP307-PER-TURN-CADENCE-FIX-20260914
status: AWAITING_BIG_REVIEW
type: post_merge_fix
tier: T1
jira: SSP-307（AIWR-09，已 ACCEPTED_GO + merged @ 32b3f82，本卡是後續修正）
sibling_of: SSP-308（AIWR-10，已修過同一類問題，repair-01 @ 081d960）
origin: "研究 SSP-308 repair-01 時發現的疑慮，見 .work/CARD-SSP307-PER-TURN-CADENCE-CONCERN-20260914.md"
---

# SSP-307 已合併程式碼的正確性修正（POST_MERGE_FIX_01）

👉 [假設與目標確認]
- 目標：修正已合併的 `codex-native-adapter.yaml` 裡
  `task_started → start`／`task_complete → submit_review` 的粒度錯誤。
- 邊界：這**不是**重開已關閉的 big review（那條 review line 已經
  `ACCEPTED_GO` 並 merge，是不可變的歷史）。這是對已出貨程式碼的新一輪
  修正，走全新的 worktree／branch／big review 流程，base 是目前的
  `main`（`536f110`），不是舊的 review base。
- 驗收：見 Acceptance。

## 為什麼要修

`SSP-308`（Claude Code 手足卡）repair-01 發現 `Stop → submit_review`
在多 turn session 會產生非法 transition（`IN_REVIEW → IN_REVIEW` 不存在）。
研究這個問題時，注意到 `SSP-307` 的 `task_complete → submit_review` 是
同一種設計形狀，只是當時沒有文件可查發生頻率，只能靠量測數據回推。

## 驗證（實測，非推測）

對本機全部 830 個真實 Codex session，逐一計算每個 session 的出現次數
（不是只看總數平均，避免離群值誤導）：

```
task_started：0或1次 206 個（24.8%）　2次以上 624 個（75.2%，最大 376 次）
task_complete：0或1次 219 個（26.4%）　2次以上 611 個（73.6%，最大 375 次）
```

**73~75% 是絕大多數的常態，不是離群值。** 確認第二個 turn 的
`task_complete → submit_review` 會嘗試 `IN_REVIEW → IN_REVIEW`——
`ai-task-card-record.yaml` 的 `allowed_status_transitions` 沒有這條邊。

## 修法（完全比照 SSP-308 repair-01 的形狀）

1. `lifecycle_event_map.map` 清空。`task_started`／`task_complete` 移入
   `non_lifecycle_event_types`，各自留下 `_note` 記錄實測依據。
2. `hard_stops` 新增一條：沒有真實發生頻率證據前，`lifecycle_event_map`
   不得新增條目。
3. Evaluator 裡「`mapped_to` 是否等於 declared map entry」的分支因
   map 清空而不可達，主動移除，`error_contract` 綁定沿用既有 AST 模組
   自動同步縮小。
4. 新開 `.work/CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG-20260914.md`：
   把「哪個事件安全」的決策延後，等有更多證據。

## Traces to

- `.work/CARD-SSP307-PER-TURN-CADENCE-CONCERN-20260914.md`（疑慮記錄）
- `.work/CARD-SSP308-REPAIR-01`（`081d960`，同一類問題的先例）
- `規格/v0.1/ai-task-card-record.yaml`（`allowed_status_transitions`）

## Constraints

- 不改上游 `ai-task-card-record.yaml`／`ai-work-record-hook.yaml`。
- 不做 runtime probe／即時訂閱。
- validator `< 400` 行。

## Acceptance

1. `lifecycle_event_map` 為空；`task_started`／`task_complete` 皆在
   `non_lifecycle_event_types` 裡，且分類與真實觀測到的 10 個事件類型
   聯集逐字相符。
2. 三個 evaluator（mapping／rollback／runtime sample）guard parity 全紅。
3. `error_contract` 與三個 evaluator 實際可回傳集合機器綁定不變。
4. 既有 fixture（除了因設計改變而必然調整的兩個 MAPPED 案例）判定不變。
5. 全部既有 validator + schema engine + cross-layer + `git diff --check`
   全 PASS。

## Stop conditions

- 若發現除了 `task_started`／`task_complete` 之外，其他已分類的事件
   （`turn_aborted` 等）也有類似問題，停，回 Owner——那超出本卡範圍。

## Evidence

`.work/evidence/SSP307-POST-MERGE-FIX-01-20260914.md`
