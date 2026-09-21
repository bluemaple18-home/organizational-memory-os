---
id: PERSONAL-INBOX-SLICE-B-RESEARCH-20260921
status: B1_DONE_D1_D2_D3_D4_D5_RESOLVED
type: research
parent_card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
scope: Slice B（review due ＋ Friday trigger ＋ 提醒）
blocked_by: Slice A review（產品碼待 Slice A GO 才動）
authority: organizational-memory-os
---

# Slice B 研究｜Weekly Review Queue ＋ Friday Trigger

👉 [假設與目標確認]
- **目標**：在寫任何 Slice B 產品碼之前，先把**契約已經決定好的東西**查清楚，
  避免實作時自己發明一套平行語意。
- **邊界**：本卡只做研究與決策點盤點，**不含產品碼**（Owner 指示：等
  Slice A GO）。
- **範圍**：`review due`、launchd、提醒三者。

## 1. 契約已經決定的（不得重新發明）

來源：`governance/規格/v0.1/personal-harness-integration.yaml` §`weekly_review_cycle`。

| 事項 | 契約怎麼說 |
|---|---|
| 身分 | `review_period_id` 是核心身分。**同一個排定週期的每一次嘗試**——準時、隔日 catch-up、失敗後 retry——都必須帶**同一個** id |
| 身分不得重推 | 明文禁止「用工作實際發生在哪一天去重新推導身分」 |
| catch-up | 錯過的週期滾到**下一個工作日**；catch-up 保留**原本的** `review_period_id` 與 `scheduled_review_period_start`，**絕不**併入下一期 |
| 下一期的證據 | **絕不**混進這一期的 review |
| SKIPPED | 是終局且明確的處置。**還在等 catch-up 窗口的週期不是 SKIPPED**；在 catch-up deadline 之前宣告 SKIPPED 會被**直接拒絕**，不是「不建議」 |
| anchor | `default_anchor: FRIDAY_AFTERNOON`，`anchor_is_tenant_configurable: true`；改 anchor **不得**連帶改 `closeout_statuses`／`attempt_kinds`／receipt schema |
| receipt | 是 **lightweight pointer record**：`selected_item_refs`／`item_dispositions` 只能是 bounded refs 與 enum 分類，**絕不**內嵌內容 |
| receipt 禁用欄位 | `full_personal_store_ref`／`weekly_work_summary`／`personal_store_snapshot`／`candidate_status`／`record_status`／`verification_status`／`acceptance_status`／`conflict_resolution_status` |
| 批次確認 | **本身不能接受任何東西**。唯一的 acceptance authority 仍是每個 Candidate 自己既有的 verification／acceptance gate |
| disposition | `selected_item_refs` 與 `item_dispositions` 的鍵集合必須完全相同；`NEEDS_ORG_FOLLOWUP` 是唯一合法的「延後但不回答」，且**不得**帶 `record_ref`／`promotion_ref` |

**結論**：Slice B 的 `review due` 只負責**準備 queue 與提醒**。它碰不到
closeout、acceptance、Promotion——這不是本片的自我克制，是契約已經封死的。

## 2. 產品現況（實查）

- `review_period_id` 目前**完全由呼叫端提供**：`closeout --file FILE` 讀一份
  JSON，`Runtime#commit_closeout` 直接取 `closeout["review_period_id"]`。
  產品**沒有任何地方**推導過週期身分。
- `closeouts` table 已存在，doctor 已檢查「同一 `review_period_id` 至多一次
  terminal closeout」。
- macOS 兩個原生工具都在：`/bin/launchctl`、`/usr/bin/osascript`
  （`display notification` 不需要額外相依）。
- `~/Library/LaunchAgents/` 已有其他第三方 plist——**install／remove 必須
  只認自己那一支**，與 Slice A 的 Host hook 是同一類風險（collision-adjacent）。

## 3. 待裁決的決策點（實作前必須定）

### D1｜`review_period_id` 從哪裡來（**最關鍵**）

契約禁止用「工作實際發生在哪一天」推導。因此只有兩條路：

| 選項 | 說明 | 風險 |
|---|---|---|
| **D1-a 由 `scheduled_review_period_start` 決定** | id 是排定週期起始日的函數（例如該週五的日期），catch-up 當天算出來仍是同一個 | 需要定義「週期起始日」的推導規則，且要與既有已存在的 closeout 資料相容 |
| D1-b 由呼叫端繼續提供 | 維持現狀，`review due` 只列 queue 不提身分 | scheduler 無法自動 catch-up，等於沒解決問題 |

交付方傾向 **D1-a**，但**不自行決定**：既有 store 裡可能已有以其他規則產生的
`review_period_id`，推導規則一旦定下就會影響既有資料的對齊。

### D1／D3 已解（B1 實作時，2026-09-21）

**D1 由既有資料回答，不需要新裁決。** store 與 fixture 裡的既有形狀是
`urn:omos:personal-memory:review-period:2026-W38` 配
`scheduled_review_period_start: 2026-09-18`（週五）——就是 **anchor 那個週五
的 ISO 年週**。因此採 D1-a，且推導規則沿用既有形狀而不是新造，既有資料自然
對齊。

關鍵是**用 anchor 那天算，不是用今天算**：週五排定的週期，下週一 catch-up
時今天的 ISO 週已經是 W39。實作與測試都把這一條當成主要不變式
（「週一本身確實已是 W39」另有一條檢查，證明前一條不是巧合）。

**D3 的選取條件**收斂成兩條，都由契約直接推得：Candidate 仍停在 `PROPOSED`；
`chronology.created_at` 不晚於本期 anchor（契約明寫下一期證據不得混入）。
另外排除已在本期 closeout 被處置過的項目。

### D2｜「下一個工作日」怎麼定義

產品目前沒有任何行事曆概念。契約只說 "next business day"，沒有給演算法。

**B1 暫採**：跳過週六、週日，**不含國定假日**——產品沒有行事曆，而假造一份
比沒有更糟（它會在不同地區悄悄算錯）。這個限制寫在
`ReviewQueue.catch_up_deadline` 的註解裡，不是藏在某個常數。
**若要支援國定假日，需要 Owner 指定來源**，交付方不自行引入行事曆相依。

### D3｜queue 的選取條件

「本週 N 筆待 review」的 N 是什麼？候選：所有 `PROPOSED` 的 Candidate／
本週期內新增的／加上 `NEEDS_ORG_FOLLOWUP` 延後的。契約規定「下一期的證據
絕不混進這一期」，所以選取必須以**時間窗**為界，而時間窗又依賴 D1。

### B1 repair（2026-09-21）：週期推導的時區

reviewer 實測：台北週五 **16:00 local = 08:00 UTC**，原本會算成 **W37**，
正確是 W38。原因是 `period_for` 直接看傳進來的 `Time` 的 `hour`，混著 UTC 與
local 語意。launchd 在週五 16:00 叫醒時會拿到**錯的** review period。

修法：週期推導全程以 **Mac 系統 local timezone** 為準，與 launchd 的
Friday 16:00 同一個時鐘來源；caller 傳進來的任何 `Time` 進計算前一律
`getlocal`。anchor 與 catch-up deadline 改用 `Time.new`（系統時區），
序列化帶偏移。

測試側同一個教訓：fixture 原本用 `Time.utc(...)` 表達「週五 16:00」，在
UTC+8 的機器上那其實是另一個時刻——與 P1 是同一種混淆。改用 `Time.new`，
並新增三個時區（Asia/Taipei／UTC／America/Los_Angeles）的子行程回歸。

### D4｜launchd 的 `RunAtLoad` 與 catch-up 的關係

**Owner 裁決（2026-09-21）**：`StartCalendarInterval` Friday 16:00
**＋** `RunAtLoad`。`RunAtLoad` 只負責補喚醒，真正的 period identity 仍由原
Friday anchor 算，所以週一登入也必須拿到原本的 W38。

**超過 catch-up deadline 也不得自動 SKIPPED**，只能呈現逾期——terminal
disposition 仍然是人的 closeout。

### D5｜提醒失敗的語意

**Owner 裁決（2026-09-21）**：通知失敗不影響 queue，但**不可完全靜默**。
寫 stderr ／ 明確的 `schedule status` 即可。

**不**為 notification 另開 ledger，也**不**硬塞進現有 `operation_journal`
——那份目前是 Store operation evidence，擴它的 kind 會碰到既有 runtime
contract。

## 4. 實作順序（Slice A GO 後）

```text
B1 review queue projection（純讀，不碰 schedule）
   └ 先解 D1／D3，因為 queue 的正確性完全依賴週期身分
→ B2 launchd schedule install/status/remove ＋ 通知
   └ 解 D4／D5
→ upgrade regression（含 Slice A 的 identity 保留）
→ zip 覆蓋解壓的實際交付路徑 upgrade（主卡驗收 13）
→ 帶 quarantine 的交付路徑驗收（主卡驗收 14）
→ targeted review
```

## 5. 本卡不做

不寫任何 Slice B 產品碼（Owner 指示）、不改 `weekly_review_cycle` 契約、
不新增 queue table、不碰 Slice A 已送 review 的檔案。

## 6. Minimum Sufficient

- **why_not_less**：D1 沒定就寫 queue，等於自己發明一套週期身分，而契約對
  這件事有明文；寫完才發現對不上是最貴的返工。
- **why_not_more**：本卡只盤點契約與決策點，不預先設計 API、不畫 schema。
- **do_not_absorb**：不吸收 closeout／acceptance／Promotion——契約已封死；
  不吸收 Slice A 的 identity 議題（已在證據包 §5 交給 reviewer）。
