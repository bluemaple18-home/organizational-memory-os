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

## 不做

不改 cadence 的傳遞結構（`repair-02` 已凍結：period 自帶 cadence、
`due_for` 不收 cadence 參數），不碰公司端匯總。
