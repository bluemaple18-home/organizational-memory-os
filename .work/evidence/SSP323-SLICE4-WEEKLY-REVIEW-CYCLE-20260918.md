# SSP-323 切片 4 — evidence

日期：2026-09-18　branch：`cc/ssp323-weekly-review-cycle`　base：`b1d40d7`

## 交付

```
規格/v0.1/personal-harness-integration.yaml   +weekly_review_cycle 區塊
scripts/validate_weekly_review_cycle_contract.rb   228 行（< 400）
規格/v0.1/fixtures/weekly-review-cycle-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
```

## 設計回應

### `review_period_id` 是核心 identity

驗證單位是**一個 `review_period_id` 底下的整段 closeout 歷史**（陣列），
不是單筆 receipt。每筆 closeout 嘗試都必須宣告同一個 `review_period_id`
（`WRC_REVIEW_PERIOD_ID_MISMATCH`）與同一個 `scheduled_review_period_
start`（`WRC_PERIOD_START_INCONSISTENT`）——catch-up／retry 不能因為
「實際發生在哪一天」而漂移到不同的 identity 或不同的排定週期。

### 同一 review period 最多一個有效 closeout

`terminal_statuses`（`COMPLETE`／`SKIPPED`／`NO_PROMOTION`）在整段歷史裡
最多出現一次（`WRC_DUPLICATE_TERMINAL_CLOSEOUT`），且必須是歷史裡的
最後一筆（`WRC_CLOSEOUT_AFTER_TERMINAL`）——一旦某次嘗試落地為 terminal
狀態，後面不會再有任何嘗試。`FAILED` 不是 terminal，可以被 retry。

### catch-up 不會被算成下一週新 closeout

catch-up 嘗試必須沿用原本排定週期的 `review_period_id` 與
`scheduled_review_period_start`（同一組一致性檢查），不是依實際發生日
另外重新推導。

### retry 不會重複產生 Promotion

`promotion_idempotency_key` 在同一個 `review_period_id` 底下，對同一個
item 的多次出現（跨多次 closeout 嘗試）必須完全相同
（`WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT`）——這不是「禁止重複出現」（同一
item 在 retry 時本來就該再出現同一個 key），而是「禁止漂移」：key 一旦
變了，就等於悄悄產生了第二個 identity，下游 Promotion 的 idempotency
機制就會失效。

### 尚待 catch-up 不會先被標成 SKIPPED

`final_status == "SKIPPED"` 必須同時 `catch_up_deadline_passed == true`
（`WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED`）——SKIPPED 是明確的最終處置，
不是「今天沒做、之後再說」的預設狀態。

### batch confirmation 不會讓所有 Candidate 自動 ACCEPTED

closeout receipt 的 `forbidden_fields` 重用切片 1 的 FORBIDDEN_LIFECYCLE_
FIELDS 概念（`candidate_status`／`record_status`／`verification_status`／
`acceptance_status`／`conflict_resolution_status`）：receipt 本身結構性
不能碰這些欄位。`selected_item_refs`／`item_dispositions` 只是有界的
refs 與分類 enum，不是 inline 內容——沒有一個「整份 bundle 一次接受」的
欄位存在，唯一的 acceptance authority 仍在每個 `PersonalMemoryCandidate`
自己既有的 verification／acceptance gate。因為沒有另外建立一個
WeeklyReviewBundle 資源型別，`WeeklyReviewBundle != PersonalMemoryRecord`
是靠「這個資源根本不存在」滿足，不是靠額外驗證。

### 可回答的 item 不會被留到下週

`selected_item_refs` 與 `item_dispositions` 的 key 集合必須完全相同
（`WRC_ITEM_DISPOSITION_INCOMPLETE`）——本週選進來的每一項，本次 review
session 就要有明確處置。`NEEDS_ORG_FOLLOWUP` 是唯一合法的「留白」方式，
不是沉默地不處理。

### `NEEDS_ORG_FOLLOWUP` 不會被當成 Knowledge

`item_dispositions` 裡 category 為 `NEEDS_ORG_FOLLOWUP` 的項目不得帶
`record_ref` 或 `promotion_ref`（`WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_
PROMOTION_REF`）——它永遠是 follow-up signal，不會意外變成一筆
Canonical Knowledge 的建立依據。

### 不讓固定問卷冒充 dynamic grill

`item_dispositions[].category` 的合法值直接讀 `historical_comparison.
categories`（評估當下從上游取得，不重述）加上 `NEEDS_ORG_FOLLOWUP`
（`WRC_UNKNOWN_DISPOSITION_CATEGORY`）——本片完全沒有自己的分類詞彙可以
另立山頭，任何處置都必須落在切片 1／2 已經驗過的真實機制裡。

### Tenant 改 weekly anchor 不會 fork core schema

`closeout_statuses`／`attempt_kinds`／`closeout_receipt.required_fields`
在契約裡只宣告一次（不是 per-tenant 的 map），`cadence_policy.default_
anchor` 只是一個可被 tenant 覆寫的資料值，不參與 receipt schema 或
enum 的定義——anchor 改變不可能連動改到這些結構本身。

## 接回總入口的實測

```
中和 WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT 的 guard（你特別點名要盯的
review_period_id/idempotency 機制）：

直接呼叫新片   → FAIL WRC_NEG_PROMOTION_IDEMPOTENCY_KEY_DRIFT 預期 deny，
                 實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_weekly_review_cycle_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## 逐 return site parity（非逐 code）

17 個 return site → 17/17 全紅，未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（34 支，含新增這支）  → PASS
四支 Python schema engine                         → 環境缺 jsonschema 模組
                                                     （pre-existing，未安裝
                                                     venv，本卡未改動其涵蓋
                                                     範圍）
git diff --check                                   → clean
```

## 明確不在本卡範圍

- Weekly Grill 動態提問演算法本身（本卡只鎖處置詞彙必須落在切片 1/2）。
- `SSP-324` Minimal Evidence Package 實作（另卡）。
- 排程觸發 runtime（cron/提醒機制）——本卡只鎖 cadence 的語意。
