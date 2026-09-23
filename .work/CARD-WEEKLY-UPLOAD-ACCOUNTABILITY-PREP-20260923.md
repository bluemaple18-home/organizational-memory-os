---
id: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923
status: SPEC_FROZEN_READY_TO_IMPLEMENT
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
14. 每項附鑑別力反證。

## 7. Minimum Sufficient

- **why_not_less**：少了預期序列就算不出差集，漏掉的週仍是空白；少了
  `review skip`／`review done`，實務上不會有人留紀錄，可管理性是空談。
- **why_not_more**：不做跨人、不做公司端、不做 dashboard、不建第二個 DB、
  不改 SSP-323 的 catch-up 語意。
- **do_not_absorb**：不吸收 SSP-324 的提交面與隱私裁決；不吸收國定假日
  行事曆（每個人放假不同，產品不該內建一份）。
