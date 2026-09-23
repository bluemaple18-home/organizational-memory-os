---
id: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923
status: SPEC_FROZEN_AWAITING_FREEZE_C_REVIEW
freeze_c_review_round_1: NO_GO（2026-09-23，P1×2：驗收 14 誤稱 evaluator 會擋合法 ref 欄位／attempt_kind 只看歷史會標錯；P2×2：C-2 應消費既有 seam／C-3 的 COMPLETE 語意是新政策非契約）→ 已補
freeze_c_review_round_2: NO_GO（2026-09-23，P1×1：C-7 四格與自身散文衝突且未列未到期週期；P2×1：§3.3 開頭過度宣稱「全部來自既有契約」）→ 已補
freeze_c_review_round_3: NO_GO（2026-09-23，P1×1：驗收 14 未鎖 LATE 分叉；P2×1：C-7 整個 phase classifier 未標為產品推導）→ 本版已補
type: bounded-product-capability
priority: MVP
parent_card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
related:
  - CARD-SSP295-FULL-PRODUCT-PILOT-20260921（跨人可見度屬 pilot 之後）
  - CARD-SSP324-MINIMAL-EVIDENCE-PACKAGE-20260917（公司端只收 submission package）
authority: organizational-memory-os
---

# 每週上傳的可管理性 — 本機端準備

👉 [假設與目標確認]
- **目標**：從本功能的穩定 history origin 起，讓**每一個週期都有一筆明確結果**，
  沒有無法解釋的空白。這樣日後公司端才能
  回答「這禮拜有沒有上傳／是不是本週的版本／少了哪週」。
- **邊界**：**只做本機端**。不做跨人可見度、不做公司端提交、不碰隱私契約。
- **不是**：不建 dashboard、不建第二個 DB、不改 SSP-323 的 weekly semantics。

## 1. Owner 的管理需求（原話）

> 以後到公司端要可以記錄每個人這禮拜有沒有上傳、是不是上傳本週的版本、
> 不是的話是少了哪週。我要為這個管理做準備。

以及大原則：

> 一個禮拜一定要一次，不管哪天。如果設定日期沒做，就是遞延，或者下禮拜做兩次。

## 2. 契約已經給了對的形狀（不需要新發明）

`closeout_receipt` 是 **content-free 的 pointer record**，必填欄位裡已經有
`review_period_id`、`scheduled_review_period_start`、`actual_closeout_at`、
`attempt_kind`、`final_status`、`catch_up_deadline_passed`；
而 `forbidden_fields` 明文禁止夾帶 `personal_store_snapshot`、
`weekly_work_summary` 等內容。

因此那三個管理問題**不需要看任何人的知識內容**就能回答——這正是它被設計成
pointer record 的原因。

`SKIPPED` 也已經是契約定義的終局狀態，且明文規定必須**等 catch-up 期限過了**
才能宣告，不得提前認賠。所以「怕一直遞延」的答案不是延長期限，是**讓沒做的
那一週也留下一筆明確的結果**。

## 3. 真正缺的只有一件：預期序列

目前漏掉的週是**空白**，不是「有紀錄的沒做」。沒有預期序列就算不出差集，
空白無法管理。

預期序列可由既有事實推導，**不需要新資料表**。但歷史起點不能直接用
`receipt.installed_at`：現行 installer 每次 install／upgrade 都會重寫它，若把它
當起點，升級後舊的 MISSING 週期會被靜默洗掉。

本卡凍結以下兩個實作前提：

### 3.1 Freeze A — history origin 必須跨升級穩定

- 在**既有 install receipt** 增加一個穩定欄位 `weekly_review_origin_at`；不新增
  registry／DB／ledger。
- fresh install 第一次建立時寫入當下時間；之後 reinstall／upgrade 必須原樣保留，
  不得用新的 `installed_at` 覆蓋。
- 舊版 receipt 尚無此欄位時，第一次升級採用該 receipt 現有的
  `installed_at` 作 migration origin。這只是「目前仍可證明的最早起點」，
  **origin 之前的週期視為 unknown，不得倒推成 MISSING**。
- rollback／再次 upgrade 不得讓 origin 往後移；驗收必須鎖住這件事。

因此預期序列改為：

```text
穩定起點（receipt.weekly_review_origin_at）
  → 每個 ISO 週一個 period（anchor 由使用者設定）
  → 對照 closeouts 實際有的 review_period_id
  → 差集 ＝「少了哪週」
```

與 `review due` 同一個做法：projection，不落地。

### 3.2 Freeze B — done／skip 必須明確指定週期

`review done` 與 `review skip` **不得靠「今天」猜要關哪一週**。missed period 可以
在下一週補做，而同一週也可能同時處理「上一週 catch-up + 本週 current」；若沒有
明確 target，兩筆 closeout 會無法區分。

CLI 固定採人類可輸入的 ISO week：

```text
review done --period 2026-W38
review skip --period 2026-W38
```

CLI 只負責把 `2026-W38` 正規化成既有
`urn:omos:personal-memory:review-period:2026-W38`，並依該週的 anchor 產生既有
closeout 所需 cadence 欄位；**最後仍必須走 `Runtime.commit_closeout` 與既有
`weekly_closeout_history` evaluator**。CLI 不得重寫第二份 SKIPPED／terminal／
idempotency 規則。

缺 `--period` 必須 fail closed，不提供會在有多個 open period 時改變含義的
「自動猜本週」捷徑。`review history` 要直接顯示可複製的 `YYYY-Www`。

### 3.3 Freeze C — `review done` 收什麼（本輪新增）

`review done` **不可能是一個字的指令**。既有 evaluator
（`weekly_closeout_history.rb`）對 receipt 的要求已經很硬，實作若不先釘死，
最可能的結果是自己發明一套簡化的處置語彙——**那就是第二份規則**，正是驗收
第 12 項明文禁止的。

以下**沿用既有詞彙與 evaluator**。凡是產品／Owner 的收緊，一律登記在
**§3.4 的集中清單**——不散落在各條之中。

> **為什麼要集中列。** 「把產品收緊寫成契約既有」這個毛病在 Freeze C 的
> 三輪 review 裡出現了**三次**（誤稱 evaluator 會擋合法 ref 欄位、開頭的
> 全稱宣告、phase classifier 沒標）。三次的修法形狀都一樣：補一句
> 「這是產品收緊」。補句子治不了它，因為下一條新增的收緊還是會忘。
> 改成**單一清單**：任何收緊都必須出現在 §3.4，沒出現就是沒凍。

#### C-1 evaluator 允許四個欄位；本片**自己**只產一個

evaluator 的 allowlist 是
`category / record_ref / promotion_ref / promotion_idempotency_key`，
**第五種**未知欄位才會被擋（`WRC_ITEM_DISPOSITION_UNKNOWN_FIELD`）。

因此必須講清楚：本片的 disposition 只帶 `category`，這是
**`review done` builder 自己保證的產品收緊，不是 evaluator 幫我們守**。
`record_ref`／`promotion_ref` 對 evaluator 而言完全合法——寫成「多一個欄位
就被擋」是錯的，會讓人以為有一道實際上不存在的防線。

#### C-2 分類詞彙必須消費既有的 `Contract.disposition_categories`

產品**已經有**這個 seam，而共用 evaluator 吃的就是這一份：

```ruby
OMOS::Contract.disposition_categories
# => #<Set: {"UNSEEN", "UNCHANGED", "NEW_EVIDENCE",
#            "MATERIALLY_CHANGED", "CONTRADICTED", "NEEDS_ORG_FOLLOWUP"}>
```

**必須直接消費它**，不得自己再讀一次 spec。「自己讀 spec」看起來也會跟著
規格動，但 `NEEDS_ORG_FOLLOWUP` 不在 `historical_comparison.categories` 裡
——它是在這個 seam 裡被併進去的。自己讀就會把它手抄一次，**那就是第二份詞彙**。

#### C-3 本片固定產 `NO_PROMOTION`——這是 **Owner scope decision**，不是契約語意

`COMPLETE` 與 `NO_PROMOTION` **都只是既有的 terminal status**，契約**沒有**
把 `COMPLETE` 保留給「有 promotion」的情境。先前卡上那樣寫是**新發明的產品
政策**被誤述成契約語意，已更正。

本片的決定與它精確的意思：

- `review done` 產生的 disposition **只帶 `category`**（C-1：builder 自己
  保證，不是 evaluator 擋）；
- `final_status` 固定為 **`NO_PROMOTION`**，意思是
  **「這次 closeout 當下沒有產生 Promotion」**——不是「這週沒做完」，
  也不是「以後永遠不會有 promotion」。

**凍結的推論**：日後 SSP-324 另外產生 submission／promotion record 時，
**不得回頭改寫這筆 terminal closeout**。terminal 已經是 terminal
（`WRC_CLOSEOUT_AFTER_TERMINAL` 也會擋）。這樣才真的不需要 migration。

#### C-4 選取範圍預設是「該週期的全部待辦」，缺一不可

evaluator 只要求 `selected_item_refs` 與 `item_dispositions` 鍵集合相同，
沒有要求涵蓋整個 queue。但契約明寫 `NEEDS_ORG_FOLLOWUP` 是**唯一**合法的
「延後但不回答」，**不是 silent carry-over**。

因此本片在產品層收緊：

> `review done --period W` 的 selected 預設**等於該週期 `review due` 的全部
> 項目**；任何一項沒有 disposition 就 **fail closed**，不得產生部分 closeout。

要延後某一項，必須明確給它 `NEEDS_ORG_FOLLOWUP`，不能靠「不選它」。

#### C-5 輸入形狀

```text
review done --period 2026-W38 --item <candidate-urn>=<CATEGORY> [--item ...]
review done --period 2026-W38 --dispositions FILE.json      # 項目多時
```

`--item` 的 key 必須是 **PersonalMemoryCandidate 的 URN**——evaluator 會擋
（`WRC_ITEM_REF_NOT_CANDIDATE`），CLI 不得另立字串規則。

#### C-6 `review skip` 的 receipt 形狀

`selected_item_refs: []` ＋ `item_dispositions: {}`（鍵集合相同，合法），
`final_status: SKIPPED`，`catch_up_deadline_passed: true`——後者為 false 時
evaluator 直接回 `WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED`。

#### C-7 attempt_kind 與 cadence 欄位由**週期**推導，不由「今天」推導

evaluator 另有四條跨 attempt 的規則：`WRC_MULTIPLE_SCHEDULED_ATTEMPTS`
（一個 period 至多一次 `SCHEDULED`）、`WRC_PERIOD_START_INCONSISTENT`
（所有 attempt 的 `scheduled_review_period_start` 必須一致）、
`WRC_DUPLICATE_TERMINAL_CLOSEOUT`、`WRC_CLOSEOUT_AFTER_TERMINAL`。

因此：

- `scheduled_review_period_start` 與 `scheduled_anchor_at` **一律由 `--period`
  的 anchor 推導**，不得用當下時間——否則跨週補做會觸發
  `WRC_PERIOD_START_INCONSISTENT`；
- `attempt_kind` **不能只看「有沒有既有 closeout」**，也**不能只分「窗口內／
  逾窗口」**。前一版的兩格表與自己的散文衝突：它會把「已在 catch-up 階段、
  前次 `FAILED`、同階段再試」標成 `CATCH_UP`，但散文說同一窗口內的再試是
  `RETRY`。

  **整個 phase classifier 都是產品層推導**（§3.4 T-5）：階段切法、
  「anchor 當日結束」的界線、週末歸 `CATCH_UP`、`LATE` 仍映成 `CATCH_UP`、
  「同 phase 才是 `RETRY`」——**evaluator 一條都不會替我們守**。
  它只檢查最後送進去的 `attempt_kind` 是否在
  `SCHEDULED/CATCH_UP/RETRY` 之內，以及跨 attempt 的四條一致性規則。

  改以**階段**為準。每個 period 由 anchor 與 catch-up 截止切成四段：

  | 階段 | 範圍 |
  |---|---|
  | `BEFORE` | `now < scheduled_anchor_at` |
  | `SCHEDULED` | anchor 起，至**該 anchor 當日結束** |
  | `CATCH_UP` | anchor 當日之後，至 `catch_up_deadline_at`（下一個工作日的同一時刻）前 |
  | `LATE` | `now >= catch_up_deadline_at` |

  （週六日落在 `CATCH_UP`——契約說 catch-up 是「滾到下一個工作日」，
  週末屬於等待期。）

  推導規則：

  1. **`BEFORE` → 拒絕**。不得提前 closeout 一個還沒到 anchor 的週期。
  2. `SCHEDULED` 階段、該階段尚無 attempt → **`SCHEDULED`**
  3. `CATCH_UP` 或 `LATE` 階段、該階段尚無 attempt → **`CATCH_UP`**
  4. **同一階段**內前次 `FAILED` → **`RETRY`**
     （涵蓋 `SCHEDULED FAILED → RETRY → FAILED → RETRY`，
     以及 `CATCH_UP FAILED → RETRY`）
  5. 前次 `FAILED` 但**階段已改變** → 依第 2／3 條，即
     `SCHEDULED FAILED` 跨進 catch-up 後是 **`CATCH_UP`**，不是 `RETRY`
  6. 該 period 已有 terminal → 由既有 evaluator
     （`WRC_DUPLICATE_TERMINAL_CLOSEOUT`／`WRC_CLOSEOUT_AFTER_TERMINAL`）
     與 unique index 拒絕，**產品不另寫一份**

  一句話：**`RETRY` 只在同一階段內成立；跨階段一律回到該階段的首次種類。**

  `catch_up_deadline_passed` 亦由階段決定：`LATE` 為 `true`，其餘為 `false`。
  `WRC_MULTIPLE_SCHEDULED_ATTEMPTS` 會擋住同一 period 出現第二次 `SCHEDULED`。

### 3.4 產品／Owner 收緊的集中清單

**本卡所有超出上游契約的收緊都必須登記在這裡。** 新增收緊時若沒有加進這張
表，視為沒有凍結。

| # | 收緊 | 上游實際怎樣 | 為什麼還是要收 |
|---|---|---|---|
| T-1 | `review done` 的 disposition 形狀恰為 `{category}` | evaluator 允許 `category`／`record_ref`／`promotion_ref`／`promotion_idempotency_key` 四欄，**只擋第五種** | promotion 屬 SSP-324，本片不產生；由 **builder 自己保證**，沒有任何 evaluator 規則在守這件事 |
| T-2 | `final_status` 固定 `NO_PROMOTION` | `COMPLETE` 與 `NO_PROMOTION` **都是**合法 terminal，契約沒有保留 `COMPLETE` 給 promotion | Owner scope decision。意思是「這次 closeout 當下沒有產生 Promotion」，**不是**「這週沒做完」 |
| T-3 | `review done` 的 selected 預設＝該週期全部 due items，缺一即 fail closed | evaluator 只要求 selected 與 dispositions **鍵集合相同**，不要求涵蓋整個 queue | 否則漏掉的項目可以靠「不選它」靜默消失，本卡的目的就破了。延後必須明確給 `NEEDS_ORG_FOLLOWUP` |
| T-4 | `BEFORE` 階段拒絕 closeout | evaluator **不擋**提前 closeout 未到期的週期 | 提前關帳會讓週期帳失真 |
| T-5 | 整個 phase classifier（四階段切法、anchor 當日界線、週末歸 `CATCH_UP`、`LATE` 映 `CATCH_UP`、同 phase 才 `RETRY`） | evaluator 只檢查 `attempt_kind` 在三個值之內，以及跨 attempt 的四條一致性；**不驗階段推導** | 沒有這套推導，`attempt_kind` 等於使用者隨便填 |
| T-6 | `weekly_review_origin_at` 與「origin 以前視為 unknown」 | 上游沒有這個欄位，也沒有歷史起點的概念 | 見 Freeze A：`installed_at` 每次升級被重寫 |
| T-7 | `--period` 必填、`--anchor-weekday` 限週一～五 | 上游對 CLI 形狀沒有規定 | 見 Freeze B 與範圍第 1 項 |

## 4. 範圍

1. **`--anchor-weekday`**（限週一～週五）。每個人自己選哪一天上傳——放假時間
   每個人不同，產品不內建行事曆。選到的那天遇到假日，既有 catch-up 會順延到
   下一個工作日。
2. **`review history`**：本機週期帳。每個 ISO 週一列，狀態為
   `COMPLETE`／`NO_PROMOTION`／`SKIPPED`／**MISSING**（從未 closeout）。
   MISSING 就是「少了哪週」的答案。
3. **`review skip`**：在 catch-up 期限過後，把該週明確記成 `SKIPPED`。
   期限未到就宣告必須**直接拒絕**（契約明文）；呼叫端必須明確給 `--period`。
4. **`review done`**：把手寫 closeout JSON 這件事變成一般人做得到的操作。
   現況是 `closeout --file FILE` 要餵一份組好的 JSON——實際上等於沒人會留紀錄，
   而沒紀錄就沒有可管理性。呼叫端同樣必須明確給 `--period`。

## 5. 明確不做（需要 Owner／契約裁決才能碰）

- **跨人可見度**：看不到別人的 Personal store 是**核心隱私邊界**
  （`EMPLOYEE_PRIVATE` / `visibility_scope: SELF_ONLY`），不是尚未實作。
- **公司端提交管道**：SSP-324 明訂「公司只收到明確 submission package，
  且不存在 reverse-access path」。要送什麼、誰能看，是那條線的決定。
- **沒做的人怎麼處置**：管理政策，不是產品行為。

本卡只保證一件事：**從 `weekly_review_origin_at` 起，每一週都能被判成 terminal
結果或 MISSING**。origin 以前沒有可證明的資料，不偽造歷史。有了這個，日後要把
週期帳做成可提交的內容，才有東西可送。

## 6. Acceptance

1. `--anchor-weekday` 可設 Mon–Fri；週末一律拒絕（catch-up 以工作日定義）。
2. 改變 anchor 的那一天**不得**造成週期重複或消失——period 身分綁 ISO 週，
   需有測試鎖住，不得只靠推論。
3. anchor weekday 與 hour 同樣從已安裝 plist 讀回；兩個來源不一致即退回預設
   並顯示。
4. `review history` 由既有事實重算，**不新增資料表**；MISSING 的判定來自
   「預期序列 vs 實際 closeouts」的差集。
5. `weekly_review_origin_at` 在 reinstall／upgrade 後 byte-for-byte 維持原值；
   upgrade 前已是 MISSING 的週期，upgrade 後仍必須是 MISSING。
6. 舊版 receipt 首次遷移只從仍可證明的 `installed_at` 起算；origin 以前不得
   被 `review history` 誤報為 MISSING。
7. `review done`／`review skip` 缺 `--period` 必須拒絕；同一個自然週內要能分別
   對上一期與本期各提交一次，且兩筆 `review_period_id` 不得混淆。
8. `review skip` 在 catch-up 期限**未到**時必須被拒絕，錯誤碼明確。
9. 期限已過時 `review skip` 產生的 receipt 必須通過既有 closeout evaluator，
   `catch_up_deadline_passed` 為 true。
10. `review done` 產生的 receipt 同樣通過既有 evaluator；**不得**夾帶
   `forbidden_fields` 任何一欄。
11. 一個 `review_period_id` 至多一次 terminal closeout——沿用既有 unique index，
   需有測試證明重複提交被擋。
12. done／skip 只組 payload 並呼叫既有 `Runtime.commit_closeout`；不得在 CLI 或
    新 helper 複製 `weekly_closeout_history` 的 terminal／SKIPPED 規則。
13. 3a／3b／3c 全綠；validators 全綠；`git diff --check` clean。
14. **Freeze C**：
    - **builder 自己保證** disposition 的形狀恰為 `{category}`。
      **不得**宣稱「evaluator 會擋多出來的欄位」——`record_ref`／
      `promotion_ref` 對 evaluator 完全合法，只有第五種未知欄位才被擋；
    - 產品直接消費 `Contract.disposition_categories`；改動 upstream 的
      category 集合後，產品接受的集合必須**跟著變**（此為證明沒有第二份
      詞彙的鑑別力反證）；
    - `review done` 漏掉任一待辦項目 → fail closed，不得產生部分 closeout；
    - `review skip` 的空 selected／dispositions 能通過 evaluator；
    - 跨週補做時 `scheduled_review_period_start` 取自 `--period` 的 anchor，
      不得觸發 `WRC_PERIOD_START_INCONSISTENT`；
    - **`attempt_kind` 八條各有測試**：
      (a) 準時首次＝`SCHEDULED`；
      (b) 無歷史但逾期補做＝`CATCH_UP`；
      (c) `SCHEDULED FAILED` 同階段再試＝`RETRY`；
      (d) `SCHEDULED FAILED` 跨進 `CATCH_UP`＝`CATCH_UP`；
      (e) `CATCH_UP FAILED` 同階段再試＝`RETRY`；
      (f) **`CATCH_UP FAILED` 跨進 `LATE`＝`CATCH_UP`**；
      (g) **`LATE FAILED` 同一 `LATE` 再試＝`RETRY`**；
      (h) **連續失敗 `FAILED → RETRY → FAILED → RETRY`**——只處理第一次
          retry 的實作必須在這條轉紅；
      已 terminal 由既有 evaluator／unique index 拒絕。
      同一 period 不得出現第二次 `SCHEDULED`；
    - **`LATE` 階段仍可 `review done`**（Owner 裁決）。逾期不自動判死——
      `SKIPPED` 是明確放棄這一期，不是逾期的自動結果；否則「下週補上週、
      同週做兩次」這個原始需求會被打掉；
    - **尚未到 anchor 的 period → `review done`／`review skip` 必須拒絕**
      （T-4，evaluator 不會擋），錯誤碼明確；
    - **§3.4 的每一條收緊都必須有對應測試**——沒有測試的收緊等於沒凍。
15. 每項附鑑別力反證。

## 7. Minimum Sufficient

- **why_not_less**：少了預期序列就算不出差集，漏掉的週仍是空白；少了
  `review skip`／`review done`，實務上不會有人留紀錄，可管理性是空談。
- **why_not_more**：不做跨人、不做公司端、不做 dashboard、不建第二個 DB、
  不改 SSP-323 的 catch-up 語意。
- **do_not_absorb**：不吸收 SSP-324 的提交面與隱私裁決；不吸收國定假日
  行事曆（每個人放假不同，產品不該內建一份）。
