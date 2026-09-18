# SSP-323 切片 4 — 大 review 交付包

## 鎖定

```
base    b1d40d7
review  （本次 commit，待 push 後補上）
branch  cc/ssp323-weekly-review-cycle
```

新增三個檔案 + 修改既有 aggregator/spec 各一處：

```
規格/v0.1/personal-harness-integration.yaml         +weekly_review_cycle
scripts/validate_weekly_review_cycle_contract.rb    228 行
規格/v0.1/fixtures/weekly-review-cycle-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
```

**未修改切片 1／2／3 的任何既有契約區塊**——只透過 pointer／binding 讀取
`historical_comparison.categories`、`personal_memory_resource_contracts.
resources.PersonalMemoryCandidate`、`runtime_policy.local_first_export_
surface`，不重述、不改動。

## 這張卡

`SSP-323`（EMEM-09）切片 4：把切片 1～3 串成真正可執行的 Weekly Grill
closeout 迴圈，同時納入 Owner 已直接推 `main` 鎖定的 cadence policy
（`d903c00`／`66ad51e`：週五下午預設 anchor、可調整但不得 fork core
schema、catch-up 沿用原 identity、同一 review period 最多一個有效
closeout、`SKIPPED` 須明確處置）。

**核心設計**：`review_period_id` 是這片的核心 identity。驗證單位是**一個
review_period_id 底下的整段 closeout 歷史**（陣列），不是單筆 receipt——
重複 closeout、idempotency key drift 這類問題本質上只在跨多筆記錄比對
時才看得出來，單筆檢查看不到。

## 請重播

```bash
ruby scripts/validate_weekly_review_cycle_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb         # 應 PASS（接回總入口）

# 接回總入口的證明：中和 WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT 的 guard，
# 不只直接呼叫新片會紅，呼叫總入口也應該紅
# 逐 return site parity（非逐 code）→ 我的結果 17/17 全紅
```

## 請特別檢查（對應你點名要防的 11 個 failure case）

```
同一 review period 第二次成功 closeout       → WRC_DUPLICATE_TERMINAL_CLOSEOUT
catch-up 被算成下一週新 closeout             → WRC_PERIOD_START_INCONSISTENT / WRC_REVIEW_PERIOD_ID_MISMATCH
retry 重複產生 Promotion                     → WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT
尚待 catch-up 卻先被標成 SKIPPED              → WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED
batch confirmation 讓所有 Candidate 變 ACCEPTED → 結構上不存在這種欄位（forbidden_fields + 沒有 bundle 資源型別）
Weekly Bundle 被存成單一 PersonalMemoryRecord  → 同上，沒有 Bundle 資源型別可被存成 Record
closeout receipt 偷帶完整 Personal Store/摘要   → WRC_FORBIDDEN_FIELD_PRESENT
Tenant 改 weekly anchor 導致 core lifecycle fork → 契約結構斷言：enum/required_fields 只宣告一次，非 per-tenant
固定問卷冒充 dynamic Grill                    → WRC_UNKNOWN_DISPOSITION_CATEGORY（分類詞彙綁定切片1/2真實輸出）
可回答的 selected item 被留到下週              → WRC_ITEM_DISPOSITION_INCOMPLETE
NEEDS_ORG_FOLLOWUP 被當成 Knowledge/Canonical  → WRC_NEEDS_FOLLOWUP_WITH_RECORD_OR_PROMOTION_REF
```

## 請特別判斷

1. **`WRC_CLOSEOUT_AFTER_TERMINAL` 與 `WRC_DUPLICATE_TERMINAL_CLOSEOUT`
   是否窮盡了「terminal 之後不該再有動作」的所有情境**：目前邏輯是先
   擋「terminal 出現超過一次」，再擋「terminal 沒有在歷史的最後一筆」。
   請確認這兩條合起來是否真的等價於「terminal 一旦出現，後面必須什麼都
   沒有」，有沒有邊界情況漏掉。
2. **`item_dispositions` 的 disposition 子物件本身沒有 required_fields
   檢查**（只檢查 `category` 合法、`NEEDS_ORG_FOLLOWUP` 不得帶
   record_ref/promotion_ref）：`record_ref`／`promotion_ref`／
   `promotion_idempotency_key` 都是選填。請判斷是否該對非
   `NEEDS_ORG_FOLLOWUP` 的分類（尤其是導致 Promotion 的分類）要求更明確
   的欄位存在性。
3. **`scheduled_review_period_start` 只是自由字串（未強制日期格式或
   跟 `default_anchor: FRIDAY_AFTERNOON` 的星期幾對齊）**：目前只做
   「同一段歷史裡必須一致」的內部一致性檢查，不驗證它本身是不是真的
   星期五（或 tenant 設定的 anchor 日）。請判斷這是否是本卡職責範圍，
   或該留到排程 runtime 層驗證。
4. **`WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT` 只檢查「出現了才比對」**：
   如果 retry 時完全不帶 `promotion_idempotency_key`（而不是帶一個不同
   的 key），目前不會被擋。請判斷這是否是需要補的漏洞，或屬於下游
   Promotion 機制（不在本卡）的責任。

## Gate

```
ruby scripts/validate_*.rb（34 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本卡未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。

若 `GO`，`SSP-323`（EMEM-09）四片全數收完。
