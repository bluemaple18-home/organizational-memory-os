---
id: PERSONAL-INBOX-SLICE-B-B1B2-EVIDENCE-20260921
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
research: CARD-PERSONAL-INBOX-SLICE-B-RESEARCH-20260921
slice: B（B1 ＋ B2）
type: evidence
status: READY_FOR_REVIEW
commits: d6fce24（B1）、86a5103（B1 repair：時區）、22c8ab9（B2）
scope_note: 這是 targeted review，只審 B1+B2 的行為；delivery-path 驗收（upgrade／zip／quarantine）尚未開始
---

# Slice B1＋B2 證據包｜Weekly review queue ＋ Friday trigger

只記錄**本 session 實際跑出來**的結果。每一項都附鑑別力反證。

## 1. 交付內容與行數

| 檔案 | +/- |
|---|---|
| `lib/omos/review_queue.rb`（新） | +144 |
| `lib/omos/schedule.rb`（新） | +170 |
| `lib/omos/cli.rb` | +78 |
| `test/conformance_3c.rb` | +271 |
| 研究卡 | +61 / −8 |
| 合計 | **+724 / −8** |

產品碼 392 行中：**程式 245、註解 107、空白 40**。3c 總檢查數 **270**。

## 2. B1｜queue 是 projection

不新增 table，每次由既有事實重算（Candidate ＋ closeouts）。
**這一層只準備 queue 與回報，沒有任何寫入路徑。**

### review_period_id：D1 由既有資料回答

store 與 fixture 裡的既有形狀就是
`urn:omos:personal-memory:review-period:2026-W38` 配
`scheduled_review_period_start: 2026-09-18`（週五）——**anchor 那個週五的
ISO 年週**。沿用而不是新造，既有資料自然對齊。

關鍵陷阱：**必須用 anchor 那天算，不是用今天算**。契約明文禁止
「用工作實際發生在哪一天重新推導身分」；週五排定的週期，下週一 catch-up 時
今天的 ISO 週已經是 **W39**。測試把這條當主要不變式，並另有一條檢查斷言
「週一本身確實是 W39」，避免前一條是巧合。

### 時區（repair，reviewer 前一輪實測）

台北週五 **16:00 local = 08:00 UTC**，原本 `period_for` 直接看傳入 `Time`
的 `hour`，8 < 16 於是退一週算成 **W37**——launchd 在週五 16:00 叫醒時會拿到
錯的 period。修法：全程 `getlocal`，與 launchd 同一個時鐘；anchor 與
catch-up deadline 用 `Time.new`（系統時區），序列化帶偏移。

**測試側犯了同一種混淆**：fixture 原本用 `Time.utc(...)` 表達「週五 16:00」，
在 UTC+8 機器上那是另一個時刻。改用 `Time.new`，並加三個時區的子行程回歸。

### 選取條件（D3）

只有兩條，都由契約直接推得：Candidate 仍停在 `PROPOSED`；
`chronology.created_at` **不晚於本期 anchor**（契約明寫下一期證據不得混入）。
另排除已在本期 closeout 被處置過的項目。

## 3. B2｜launchd Friday trigger

| 事項 | 做法 |
|---|---|
| Label | `com.omos.personal-memory.weekly-review`，**完全相等**才算自己的 |
| 觸發 | `StartCalendarInterval` Weekday=5 Hour=16 ＋ `RunAtLoad`（D4） |
| 呼叫 | `~/.omos/personal-memory/current/exe/omos-personal-memory review due --notify`，**不 pin artifact-id** |
| plist 寫入 | temp + rename——被截斷的 plist 比沒有更糟：launchd 拒載，使用者只會發現「週五沒有提醒」 |
| 逾期 | 只呈現 `overdue`，**不得**自動 SKIPPED；狀態物件裡連這個詞都沒有 |
| 通知失敗 | 寫 stderr，區分「例外」與「osascript 回非零」；不另開 ledger、不擴 `operation_journal` |

## 4. 驗證結果

| suite | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | **270/270 PASS** |
| 3c（`TZ=America/Los_Angeles`） | **270/270 PASS** |
| validator（40 支） | 40 PASS / 0 FAIL |
| `git diff --check` | clean |

### 鑑別力反證（單點反轉，還原後全綠）

| 反轉 | 結果 |
|---|---|
| 週期身分改用「今天」推導 | 3c **235/242**（7 項，catch-up 四條全紅） |
| 拿掉 anchor 時間窗 | 3c **240/242** |
| 不排除已處置項目 | 3c **241/242** |
| `period_for` 不做 `getlocal` | 台北下 **247/248**，重現 W37 |
| anchor 改回 `Time.utc` | 3c **244/248**（4 項） |
| `remove` 改用前綴比對 | 3c **268/270**（誤刪第三方） |
| LaunchAgent 綁 versioned path | 3c **262/270**（8 項） |
| 通知失敗靜默吞掉 | 3c **268/270** |
| 逾期自動判成 SKIPPED | 3c **269/270** |

## 5. 交付方主動揭露

### 5.1 `notify` 原本有**兩處**失敗輸出

反證「通知失敗靜默吞掉」**第一次沒抓到**——拿掉其中一處，另一處照印。
保護看起來還在，其實已經少了一半。收斂成單一回報點後才真的鎖住。
**請 reviewer 確認現在確實只有一個出口。**

### 5.2 反證炸掉三次才轉紅

`install`（三處）、`plutil` 解析、`ProgramArguments` 取值，在保護被拿掉時
都會丟例外而不是轉紅。全部改 nil-safe 並走同一個 `try_install` helper。
這是 Slice A repair-01 之後**第三次**踩同一件事：反證會炸掉就等於沒有鑑別力。
**請 reviewer 檢查是否還有第四處。**

### 5.3 D2 的限制

business day ＝ Mon–Fri，**不處理國定假日**。產品沒有行事曆，假造一份比
沒有更糟（不同地區會悄悄算錯）。限制寫在
`ReviewQueue.catch_up_deadline` 的註解裡。

## 6. 沒有驗到的東西

- **真實的 launchd 觸發**：測試驗的是 plist 的內容與 `plutil -lint`，
  **沒有**真的 `launchctl load` 等到週五 16:00。本機無法在測試裡等一週。
- **真實的 macOS 通知**：`notify` 的 runner 在測試裡是注入的，沒有真的跳
  通知中心。
- **delivery-path 驗收**（upgrade／zip 覆蓋解壓／quarantine）**尚未開始**，
  不在本包範圍。
