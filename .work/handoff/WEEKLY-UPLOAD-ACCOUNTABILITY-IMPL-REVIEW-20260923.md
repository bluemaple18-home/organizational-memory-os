# 週期帳（weekly upload accountability）— implementation review 交付包

## 鎖定

```
base    72d87ec   Freeze C 規格（已 GO，immutable）
review  e12ab90   實作
branch  main
```

定點 diff：`git diff 72d87ec..e12ab90`

Jira：**目前沒有對應 ticket**。這張卡是 Owner 在對話中直接提出的管理需求
（「以後到公司端要可以記錄每個人這禮拜有沒有上傳」），還沒開 Jira 單，
需要補開一張並回填 `id: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923`。

## 這一輪要審什麼

規格已在 `72d87ec` 凍結並 GO，**不要重開規格**。這輪唯一的判準是：

> **實作有沒有照簽下去的規格做？**

具體是三件事：

1. §3.3.1 的 T-1..T-10，每一條是否真的有 guard，而且 guard 就在規格指定的
   authority 位置（不是散在別處的第二份規則）。
2. §3.3.2 的決策函式與 reducer，實作是否與規格逐格一致。
3. §6.0 的兩條結構規則（R-1 生成式 coverage、R-2 反證必須能轉紅）
   是否真的落在測試裡，而不是只寫在卡片散文。

不必重開的：`WeeklyCloseoutHistory` 這支既有 evaluator（本卡沒有改它，
只是呼叫它）、Slice B 的 launchd lifecycle、交付包 zip 的 acceptance 13/14。

## 交付內容

```
lib/omos/review_ledger.rb    新增，+268   phase classifier / reducer / 決策函式 / builder
lib/omos/cli.rb                     +117   review due|history|done|skip、import、inbox list
lib/omos/review_queue.rb             +40   --anchor-weekday（限週一～五）
lib/omos/schedule.rb                 +40   anchor_weekday 貫通 install/plist/status
lib/omos/installer.rb                +17   weekly_review_origin_at（跨升級穩定的起點）
test/conformance_3c.rb              +294   本卡新增 38 條
```

卡片 §8 有完整的 `T-ID → 規則位置 → guard → 測試 → 反證` 對照表：
`.work/CARD-WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923.md`

## 交付方已知的弱點（請優先攻這幾點）

寫在這裡不是為了先擋掉 finding，是為了讓 reviewer 不必重新發現同樣的東西。

1. **M7 我判定為等價變異，這個判定可能是錯的。**
   `period_from_iso_week` 把 `Date.commercial(y, w, anchor_weekday)` 的最後一個
   參數寫死成 `5`，全套測試仍然全綠。我的論證是：`period_for` 會從給定時刻
   **往回走**到 anchor 星期，而 `5` 是允許範圍 `1..5` 的最大值，往回走不會跨出
   該 ISO 週；寫死成 `1` 就會跨到上一週並轉紅（M7b）。
   **如果這個論證有洞，那就是一個沒被測到的位置。**

2. **`expected_periods` 只有 4 個期別的序列測試。**
   跨年（W52→W01）、ISO 53 週年、以及 DST 轉換那一週都沒有測。
   `Date.commercial` 對 53 週年的行為與我假設的是否一致，沒有驗過。

3. **`reduce_history` 依賴 `closeouts_for` 的回傳順序。**
   實作寫的是 `closeouts.reverse.find`，也就是假設 store 依插入順序回傳。
   規格 §3.3.2(a) 說的是「取 `attempt_seq` 最後一筆」——實作用的是**陣列順序**
   而不是顯式的 `attempt_seq` 欄位。如果 store 的排序沒有保證，這是一個
   silent 錯誤。

4. **T-3 的「整個 queue」是以 `anchor` 時刻去算的。**
   `build_done` 用 `ReviewQueue.due(runtime, now: Time.parse(period[:scheduled_anchor_at]))`。
   補做時（catch-up）算出來的 due 集合是 anchor 當下那一份，不是現在那一份。
   這是刻意的（不然補做會被下一期的項目污染），但我沒有把它寫進規格，
   也沒有對「anchor 之後才匯入的項目在補做時是否應該出現」下過裁決。

5. **`assert_started!` 在三個地方被呼叫**（`build_done`、`build_skip`、`base`）。
   我的理由是 `base` 是共用出口、兩個 builder 各自要在算 due／算 catch-up
   期限**之前**先擋，否則錯誤訊息會指向錯的原因（這是實作時抓到的真 bug）。
   但三次呼叫同一個 guard 也可能是我沒找到對的接縫。

## 要求的驗證方式

- **不接受只讀程式碼的結論。** 每一條 P0/P1 都要附一個可重現的變異：
  說明改哪一行、改成什麼、哪一條測試會轉紅（或證明**沒有**測試會轉紅）。
- 只有 P0/P1 擋卡。P2 記錄但不擋。
- 唯讀，針對 `e12ab90` 這個 commit。不要重寫架構。

## 交付方自己跑過的結果

```
3a conformance：26/26 PASS
3b conformance：34/34 PASS
3c conformance：391/391 PASS
六支 validate_personal_memory_* / validate_weekly_review_cycle_contract.rb  全 PASS
git diff --check  乾淨
launchctl print gui/501  omos 殘留 0
```

反證 18 個，17 個轉紅，未轉紅的 M7 見上面第 1 點。
