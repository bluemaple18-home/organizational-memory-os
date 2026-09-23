---
id: WEEKLY-ACCOUNTABILITY-P2-CLEANUP-20260923
jira: 尚無對應 ticket，需補開一張並回填此欄
status: BACKLOG
tier: T0
parent: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923
---

# 週期帳 P2 清理

外部 review 在第 2 輪（`44f4f8b`）列出、並明示不擋卡的兩筆 P2。
本卡是 bounded fix，不加 form／model／Reviewer。

## P2-1 `ReviewLedger::TERMINAL_STATUSES` 是第二份抄本

`lib/omos/review_ledger.rb` 自己列了一份 terminal status 詞彙，
而 `WeeklyCloseoutHistory::TERMINAL_STATUSES` 已經是那份 authority。

同一份詞彙寫兩處就會漂移——這正是 EMEM-11 切片 1 repair-01 的 P1-2
（runtime 自列 status／attempt 詞彙）已經踩過一次的形狀。

**修法**：改為消費 `Contract::CloseoutHistory::TERMINAL_STATUSES`，刪掉本地常數。

**驗收**：`rg 'TERMINAL_STATUSES\s*=' lib/` 只剩上游那一處；
反證——把上游常數改掉一個值，`reduce_history` 的 terminal 出口測試必須轉紅。

## P2-2 `schedule status` 的「採預設」只看 `anchor_hour`

`lib/omos/schedule.rb` 的 `status` 判斷是否採用預設時只檢查 `anchor_hour.nil?`，
但 `anchor_weekday` 也可能因為 plist 兩處寫的值不一致而回 `nil` 並退回 Friday。
使用者看到的是「已安裝，週五 16:00」，實際上 plist 裡的 weekday 是壞的。

**修法**：`anchor_hour` 與 `anchor_weekday` 各自揭露來源（installed／default），
任一退回預設時明確顯示，不合併成一個布林。

**驗收**：造一份 `StartCalendarInterval.Weekday` 與 `--anchor-weekday` 不一致的
plist，`schedule status` 必須指出 weekday 來源不可信；
反證——把揭露拿掉，該測試必須轉紅。

## P2-3 剛安裝完 `review history` 的空輸出沒有解釋

（2026-09-23 隔離試跑時發現，非 reviewer 提出。）

安裝當下還沒有任何一期的 anchor 落在 origin 之後，`review history` 印的是
「共 0 週，其中 0 週未完成」。這個結果是**對的**（origin 以前不倒推），
但看的人不知道是「還沒開始算」還是「壞了」。

實測：週三安裝 → 今天 0 週；同一個 store 模擬到 10/14 → 正確列出
W39／W40／W41 三週 MISSING。

**修法**：rows 為空時改印「尚未進入第一個週期，第一次 review 是 <日期>」，
日期取 `expected_periods` 的下一期 anchor。

**驗收**：origin 在下一個 anchor 之前時，輸出必須含下一次 review 的日期；
反證——把該分支拿掉，測試必須轉紅。

## 不做

不改 cadence 的傳遞結構（`repair-02` 已凍結：period 自帶 cadence、
`due_for` 不收 cadence 參數），不碰公司端匯總。
