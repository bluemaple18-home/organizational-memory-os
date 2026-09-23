---
id: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923
status: READY_TO_IMPLEMENT
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
- **目標**：讓**每一個週期都有一筆明確結果**，沒有空白。這樣日後公司端才能
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

預期序列可由既有事實推導，**不需要新資料表**：

```text
安裝時間（receipt.installed_at）
  → 每個 ISO 週一個 period（anchor 由使用者設定）
  → 對照 closeouts 實際有的 review_period_id
  → 差集 ＝「少了哪週」
```

與 `review due` 同一個做法：projection，不落地。

## 4. 範圍

1. **`--anchor-weekday`**（限週一～週五）。每個人自己選哪一天上傳——放假時間
   每個人不同，產品不內建行事曆。選到的那天遇到假日，既有 catch-up 會順延到
   下一個工作日。
2. **`review history`**：本機週期帳。每個 ISO 週一列，狀態為
   `COMPLETE`／`NO_PROMOTION`／`SKIPPED`／**MISSING**（從未 closeout）。
   MISSING 就是「少了哪週」的答案。
3. **`review skip`**：在 catch-up 期限過後，把該週明確記成 `SKIPPED`。
   期限未到就宣告必須**直接拒絕**（契約明文）。
4. **`review done`**：把手寫 closeout JSON 這件事變成一般人做得到的操作。
   現況是 `closeout --file FILE` 要餵一份組好的 JSON——實際上等於沒人會留紀錄，
   而沒紀錄就沒有可管理性。

## 5. 明確不做（需要 Owner／契約裁決才能碰）

- **跨人可見度**：看不到別人的 Personal store 是**核心隱私邊界**
  （`EMPLOYEE_PRIVATE` / `visibility_scope: SELF_ONLY`），不是尚未實作。
- **公司端提交管道**：SSP-324 明訂「公司只收到明確 submission package，
  且不存在 reverse-access path」。要送什麼、誰能看，是那條線的決定。
- **沒做的人怎麼處置**：管理政策，不是產品行為。

本卡只保證一件事：**本機端不會有空白的週**。有了這個，日後要把週期帳做成
可提交的內容，才有東西可送。

## 6. Acceptance

1. `--anchor-weekday` 可設 Mon–Fri；週末一律拒絕（catch-up 以工作日定義）。
2. 改變 anchor 的那一天**不得**造成週期重複或消失——period 身分綁 ISO 週，
   需有測試鎖住，不得只靠推論。
3. anchor weekday 與 hour 同樣從已安裝 plist 讀回；兩個來源不一致即退回預設
   並顯示。
4. `review history` 由既有事實重算，**不新增資料表**；MISSING 的判定來自
   「預期序列 vs 實際 closeouts」的差集。
5. `review skip` 在 catch-up 期限**未到**時必須被拒絕，錯誤碼明確。
6. 期限已過時 `review skip` 產生的 receipt 必須通過既有 closeout evaluator，
   `catch_up_deadline_passed` 為 true。
7. `review done` 產生的 receipt 同樣通過既有 evaluator；**不得**夾帶
   `forbidden_fields` 任何一欄。
8. 一個 `review_period_id` 至多一次 terminal closeout——沿用既有 unique index，
   需有測試證明重複提交被擋。
9. 3a／3b／3c 全綠；validators 全綠；`git diff --check` clean。
10. 每項附鑑別力反證。

## 7. Minimum Sufficient

- **why_not_less**：少了預期序列就算不出差集，漏掉的週仍是空白；少了
  `review skip`／`review done`，實務上不會有人留紀錄，可管理性是空談。
- **why_not_more**：不做跨人、不做公司端、不做 dashboard、不建第二個 DB、
  不改 SSP-323 的 catch-up 語意。
- **do_not_absorb**：不吸收 SSP-324 的提交面與隱私裁決；不吸收國定假日
  行事曆（每個人放假不同，產品不該內建一份）。
