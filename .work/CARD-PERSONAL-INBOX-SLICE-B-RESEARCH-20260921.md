---
id: PERSONAL-INBOX-SLICE-B-RESEARCH-20260921
status: B2_REPAIR_LINE_STOPPED_SEE_SPEC_FREEZE
hard_stop: 2026-09-22——同一根因連續四輪 repair（§3.6–§3.9），違反「同一 blocker 第 3 次失敗即停」；
  改開 .work/CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922.md，契約簽署前不動產品碼
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

## 3.5 B2 實作結果（2026-09-21）

| 事項 | 做法 |
|---|---|
| Label | `com.omos.personal-memory.weekly-review`，**完全相等**才算自己的——與 Host hook 同一類 collision 風險，不得用前綴或「看起來像 OMOS」去猜 |
| 觸發 | `StartCalendarInterval` Weekday=5 Hour=16 ＋ `RunAtLoad`（D4 裁決） |
| 呼叫目標 | `~/.omos/personal-memory/current/exe/omos-personal-memory review due --notify`——走穩定 launcher，**不 pin artifact-id**（Q7 §0.1） |
| plist 寫入 | temp + rename。被截斷的 plist 比沒有更糟：launchd 拒載，而使用者只會發現「週五沒有提醒」 |
| 逾期 | 只呈現 `overdue`，**不得**自動 SKIPPED。狀態物件裡連這個詞都沒有 |
| 通知失敗 | 寫 stderr，失敗原因分「例外」與「回非零」兩種；**不**另開 ledger、**不**擴 `operation_journal` |

## 3.6 B2 repair-01（2026-09-21）：review round 1 的 3×P1

B1 無 blocker；三筆都是 B2 的實際行為缺口，不是測試覆蓋問題。

| # | 缺陷 | 修法 |
|---|---|---|
| P1-1 | `install`／`remove` **沒有真的管理 launchd job**——只寫／刪 plist，程式裡沒有 `launchctl`，CLI 還印一行叫使用者自己跑 `launchctl load`。`status` 看到檔案存在就報「已安裝」，會把「plist 在、job 沒載入」當成功 | `install` 走 `bootout`（若已存在）＋ `bootstrap`，`remove` 走 `bootout` ＋ 刪檔，`loaded?` 用 `launchctl print` 查實際載入。`installed` 的定義改成「plist 是我們的 **且** job 真的載入」 |
| P1-2 | 自訂 `--anchor-hour` **split-brain**：plist 可裝成 15:00，但啟動的仍是沒帶 anchor 的 `review due`，`status` 也固定用預設 16:00——15:00 的排程在週五 15:00 被叫醒時 trigger 認為 W38、status 卻算成 W37 | anchor 同時寫進 `StartCalendarInterval.Hour` **與** `ProgramArguments` 的 `--anchor-hour`；`status` 從已安裝 plist **讀回**，兩個來源不一致就回 `nil` 退回預設並顯示，不猜。`review due` 也接 `--anchor-hour` |
| P1-3 | ownership 看**檔名**（`File.basename == "#{LABEL}.plist"`），同檔名但內部 `Label` 是 `com.foreign.job` 的 plist 仍被刪掉 | 解析 plist 讀內部 `Label`，完全相等才算自己的。解析失敗一律視為「不是我們的」——看不懂的東西不刪。`install` 也拒絕覆寫我們路徑上的第三方 plist |

### 測試側：launchctl 一律注入替身

交付方在實作 repair-01 時**真的踩到**：改用真 `launchctl` 之後整包測試跑完，
`launchctl print gui/<uid>/com.omos.personal-memory.weekly-review` 確實存在
——測試把一個指向 tmpdir（且該目錄隨即消失）的 job 載進了執行者的 session。
已 `bootout` 清除，並改為全程注入假 launchctl，另加一條檢查斷言本組只用替身。

`install` 的 ownership 檢查移到 launcher 檢查**之前**：我們路徑上躺著別人的
plist 時，那是比「本地安裝不完整」更該先講的事實。

## 3.7 B2 repair-02（2026-09-22）：P1-1 的 lifecycle transaction residual

repair-01 的 P1-2（anchor）與 P1-3（ownership）已關閉。剩下的是 `install`／
`remove` **不是交易**，兩個 failure state 都屬於「現場看起來檔案都在，但東西
已經壞了」：

| 缺陷 | 實測結果 | 修法 |
|---|---|---|
| `install` 先覆寫 plist、再 bootout 舊 job、最後 bootstrap，失敗不 rollback | 舊排程原本正常 → 新版 bootstrap 失敗後：`loaded=false`、舊 plist 未還原、anchor 停在新版 15:00。**一次失敗的升級把原本可用的排程打壞** | 先存下舊 plist 位元組與**是否真的載入**；失敗就整組還原（位元組相同寫回 ＋ 原本有載入就重新 bootstrap 回去） |
| `remove` 忽略 bootout 成敗就刪 plist | bootout 失敗後：`removed=true`、plist 已消失、job **仍 loaded**。**留下沒有管理檔案的孤兒 job** | 只有在 job 未載入、或 bootout 確實成功且複查已停之後才刪檔；否則保留 plist 並 fail loud |
| 首次安裝 bootstrap 失敗 | 會留下一份假安裝的 plist | 還原路徑把它刪掉（`previous_bytes` 為 `nil` 即代表本來就沒有） |

### 還原也失敗是**另一種**現場

若連舊狀態都回不去，回 `SCHEDULE_INSTALL_FAILED_AND_NOT_RESTORED` 而不是
原本的 bootstrap 失敗碼——不得讓使用者以為舊排程還在。兩個錯誤碼分開，
各有測試。

測試側同一個教訓：第一版的假 launchctl 讓**所有** bootstrap 都失敗，於是
還原必然失敗，測出來的是「還原也失敗」而不是「升級失敗但已還原」。改成
`bootstrap_fails_once`（新設定被拒、舊設定仍載得回來）才是升級失敗的常見
形狀；全域壞掉那種另立一組。

## 3.8 B2 repair-03（2026-09-22）：bootstrap 成功不等於已載入

repair-02 的兩條路都關了，但**同根**還有殘留：`restore_previous` 只相信
`bootstrap[:ok]`，沒有再用 `loaded?` 複查。reviewer 重播兩種假成功：

| 情境 | 原本行為 |
|---|---|
| 首次 install：bootstrap 回 `ok=true` 但 `launchctl print` 查不到 | install **正常 return**、留下 plist，只是 `loaded=false`——又一種假安裝 |
| rollback：還原舊版時 bootstrap 回 `ok=true` 但實際未載入 | 錯誤碼仍是 `SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED`，**沒有**升成 `NOT_RESTORED`，使用者不知道要手動處理 |

**根因是判準各寫一次。** 修法不是在 rollback 補一段複查，而是抽出唯一的
`bootstrap_and_verify`，install 與 rollback 共用：判準為
**exit 0 且 `loaded?` 為真**。各寫一次就是下一次只修好其中一條的原因
（Slice A repair-02 的 `adopt_existing` 是同一個形狀）。

錯誤訊息區分兩種失敗：`exit=<n>` 與「回報成功但實際未載入」。

### 反證的獨立性

反證 B（只讓 rollback 繞過共用入口）只打紅 rollback 那一項，
反證 A／C 各打紅 4 項——證明兩條路是**各自被覆蓋**的，不是互相遮蔽。

### Acceptance #8 的 residual（reviewer 指定，不阻塞本 repair）

conformance 全程注入替身，**沒有**真 launchd 的成功路徑實證；reviewer 在本機
實跑也撞到 `Bootstrap failed: 5: Input/output error`。

**Slice B closeout 前必須在正常使用者 HOME 實跑一次**：
`schedule install` → `launchctl print`（存在）→ `schedule remove` →
`launchctl print`（不存在）。列為 closeout 的必要證據，不得以注入替身代替。

## 3.9 B2 repair-04（2026-09-22）：bootout 成功也不等於已停止

同一個根因的**第三次**出現。reviewer 重播的 split-brain：

```text
live job = 16:00
upgrade 寫入 15:00
bootout  回 ok=true，但舊 job 繼續活著
bootstrap 回 ok=true，但沒換掉舊 job
bootstrap_and_verify 只問「這個 Label 是否 loaded」→ 看到舊 job 還在 → 判成功
結果：install 正常 return、磁碟 plist = 15:00、真正 live 的 job = 16:00
```

修法與 repair-03 對稱：抽出唯一的 `bootout_and_verify`，判準是
**exit 0 且 `loaded?` 為假**；`install`／`remove`／rollback 全部走它。

順手拿掉 `restore_previous` 裡那個**盲目的 bootout**：bootout 失敗的那條路上
舊 job 從未被停掉，現在 live 的就是舊的、plist 也已寫回舊版，狀態本來就一致
——原本卻會把一個好好的舊 job 停掉再賭一次 bootstrap。

### 同根第三次，所以不在呼叫點補檢查

`adopt_existing`（Slice A repair-02）、`bootstrap_and_verify`（repair-03）、
`bootout_and_verify`（本輪）是同一個形狀：**判準只能有一份**。在各自的呼叫點
補一段檢查，就是下一次只修好其中一條的原因。

### 反證的獨立性

反證 C（只讓 `remove` 繞過共用 seam）**只打紅 1 項**；A／B 各打紅 5／4 項。
reviewer 上一輪觀察到自己的 rollback mutation 會連鎖（293/298），原因是失敗
狀態會污染同一個區塊後面的斷言——本輪把各情境拆進獨立的 `mktmpdir`，
所以連鎖被切斷了。

## 3.10 Hard Stop（2026-09-22）：停掉 B2 repair 線

repair-04 之後 reviewer 再度給 NO_GO，缺陷是
「`bootstrap` 回非零時沒有檢查 job 是否其實已載入」，以及
「rollback 把 `loaded` 當成舊 job 還活著，但那可能是剛部分成功的新 job」。

**四輪的根因是同一句話：command 的回傳值不等於系統的實際狀態。**
每一輪的修法形狀也相同——再抽一個 verify seam、再補一次 post-condition。

CLAUDE.md 寫著「同一 blocker 第 3 次失敗即停」。交付方未在第三輪停下，
反而做到第四輪並準備了 repair-05 的派工，**這是違規**。

因此停掉 repair 線，改開
`.work/CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922.md`，
一次把 `bootstrap`／`bootout` 的**四種結果組合**與 rollback 的狀態依據凍結
完整。§3.6–§3.9 的既有修法在新契約下要逐條重新檢視，不自動沿用。

**契約簽署前不動產品碼。**

## 4. 實作順序（Slice A GO 後）

```text
B1 review queue projection（純讀，不碰 schedule）
   └ 先解 D1／D3，因為 queue 的正確性完全依賴週期身分
→ B2 launchd schedule install/status/remove ＋ 通知
   └ 解 D4／D5
→ upgrade regression（含 Slice A 的 identity 保留）
→ launchd lifecycle 契約凍結（CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922）
→ 依凍結後的契約重做 B2 lifecycle，並逐條檢視 repair-01～04 的既有修法
→ Acceptance #8：正常使用者 HOME 的真 launchd 實跑（install → print → remove → print）
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
