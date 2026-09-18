---
id: SSP323-SLICE4-WEEKLY-REVIEW-CYCLE-20260918
status: READY
jira: SSP-323
parent_jira: SSP-286
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-323｜EMEM-09 切片 4：Weekly Grill Closeout Loop

## 目標

把切片 1（historical comparison）、切片 2（Organizational Value
Assessment／`NEEDS_ORG_FOLLOWUP`）、切片 3（Personal Store
Portability／Local-First export surface）串成真正可執行的 Weekly Grill
closeout 迴圈，並納入 Owner 已直接推 `main` 鎖定的 cadence／schedule
policy（`d903c00`／`66ad51e`）。

`review_period_id` 是本片的核心 identity：同一個排定週期的每一次
closeout 嘗試（準時／catch-up／retry）都必須共用同一個
`review_period_id`，否則「週五 → 補做 → retry」只能靠日期字串猜是不是
同一週，最後一定長出重複 closeout／重複 Promotion。

## Scope

1. `規格/v0.1/personal-harness-integration.yaml` 新增 `weekly_review_
   cycle` 區塊：cadence policy（週五下午預設 anchor、tenant 可調整但不得
   fork core schema、catch-up 沿用原 `review_period_id`）、`closeout_
   statuses`（COMPLETE／FAILED／SKIPPED／NO_PROMOTION）、`terminal_
   statuses`、`attempt_kinds`（SCHEDULED／CATCH_UP／RETRY）、closeout
   receipt 的 required/forbidden fields、item disposition 規則、
   promotion idempotency 規則。
2. `scripts/validate_weekly_review_cycle_contract.rb`：驗證單位是**一個
   review_period_id 底下的整段 closeout 歷史**（不是單筆 receipt）——
   重複 closeout、idempotency key drift 這類問題本質上只在跨多筆記錄
   比對時才看得出來。
3. 接回 `scripts/validate_personal_memory_contract.rb` 聚合器。

## 不重述切片 1／2／3

- `item_dispositions` 的分類詞彙直接讀 `historical_comparison.
  categories`（5 個）＋ `NEEDS_ORG_FOLLOWUP`（切片 2 的推導結果），不
  自己另立一套——這同時是「不讓固定問卷冒充 dynamic grill」的機器邊界。
- Closeout receipt 正是切片 3 `runtime_policy.local_first_export_
  surface` 封閉列舉的第二項，不重新定義公司端能拿到什麼。
- `item_dispositions` 只能引用既有 `PersonalMemoryCandidate` 的生命
  週期（透過 forbidden_fields 結構性禁止 receipt 自己夾帶
  `candidate_status` 等欄位），批次確認本身不授予任何 acceptance
  authority——那仍完全在既有 candidate 的 verification／acceptance
  gate。

## 承接前三片的兩項硬要求

1. **聚合器接回實測**：新增 guard 至少一個要證明不只直接呼叫這支會紅，
   呼叫聚合器也同步轉紅。
2. **機器可查訊號 vs 判斷型訊號分離**：本片沒有需要人類判斷的維度——
   全部斷言都是同一個 `review_period_id` 底下、跨多次 closeout 嘗試的
   內部一致性（identity 一致、terminal 只能有一次、idempotency key 不能
   漂移），結構性事實，不是自報。

## 不屬本卡

- Weekly Grill 的實際動態提問機制（怎麼決定該問什麼）——本卡只鎖「問完
  之後的處置必須落在切片 1/2 的真實詞彙裡」，不規定提問演算法本身。
- `SSP-324` Minimal Evidence Package 的實作——沿用本卡的 closeout
  receipt 概念，另卡。
- 排程觸發本身（真正在週五下午發提醒的 cron/排程機制）——本卡只鎖
  cadence 的**語意**（anchor 可調整、catch-up 規則、idempotency），不是
  排程 runtime 實作。
