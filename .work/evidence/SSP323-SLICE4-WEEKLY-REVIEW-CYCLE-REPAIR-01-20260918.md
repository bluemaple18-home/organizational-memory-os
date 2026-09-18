# SSP-323 切片 4 — repair-01 evidence

日期：2026-09-18　branch：`cc/ssp323-weekly-review-cycle`

```
base            b1d40d7
original_review 6fc781a（審的是 b1d40d7..ca3b42e；6fc781a 只是 handoff SHA 補正）
repair_commit   （本次 commit，待 push 後補上）
```

## Reviewer NO_GO（2026-09-18，對 `ca3b42e`）

```
P0=0 / P1=3 / P2=1 / P3=0
```

1. **P1**：`item_dispositions` 沒鎖 shape，直接打穿 Candidate/receipt
   邊界——disposition 塞 `candidate_status=ACCEPTED_FOR_RECORD` → `nil`；
   塞 `weekly_work_summary` → `nil`；`selected_item_refs` 改成
   `PersonalMemoryRecord` URN → `nil`。
2. **P1**：Promotion idempotency 可整條省略——`next unless key` 讓 retry
   把 `promotion_idempotency_key` 整個刪掉就通過；保持同一 key、把
   `promotion_ref` 從 `p-1` 改 `p-2` 仍然通過。
3. **P1**：malformed closeout entry 不是 fail-closed error code，而是
   直接 `NoMethodError`——第一筆 closeout 換成 `"oops"` 就讓 evaluator
   當掉。
4. **P2**：cadence 欄位（`scheduled_review_period_start`／
   `scheduled_anchor_at`／`actual_closeout_at`）只驗 key 存在、值可以是
   `nil` 仍 PASS。

Reviewer 對交付包四點的判定：terminal 邏輯（duplicate + after-terminal）
完整；disposition shape 不足且是 P1；Friday/tenant anchor 真實排程對齊
可留 runtime，但基本欄位 shape 是 P2；retry 缺 idempotency key 是 P1，
不應留給下游。

本輪未明確授權把 P2 留 backlog，且修法成本低，一併收掉，不分兩輪。

## 修法

### F-01：item ref 綁 Candidate identity + disposition 欄位 allowlist

- 讀既有 `personal_memory_resource_contracts.shared_constraints.
  id_templates.PersonalMemoryCandidate`（`urn:omos:personal-memory:
  candidate:{uuidv7}`），取 `{` 前的字面前綴，作為 `item_dispositions`
  每個 key 必須符合的前綴——不自己另立字串規則，直接讀既有模板。
  `selected_item_refs` 用 Record URN 的攻擊會在同一個檢查被擋下（因為
  completeness 檢查已強制兩者的 key 集合相同）。新錯誤碼
  `WRC_ITEM_REF_NOT_CANDIDATE`。
- 新增 `ALLOWED_DISPOSITION_FIELDS = %w[category record_ref promotion_ref
  promotion_idempotency_key]`，disposition 物件裡任何不在這份 allowlist
  的 key 一律拒絕。新錯誤碼 `WRC_ITEM_DISPOSITION_UNKNOWN_FIELD`。

### F-02：Promotion identity 不能省略也不能漂移

- `promotion_ref` 出現時 `promotion_idempotency_key` 不得省略。新錯誤碼
  `WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY`。
- 追蹤對象從單純的 key 改成 `(promotion_ref, promotion_idempotency_
  key)` 整組 tuple——同一 item 在同一 `review_period_id` 底下重複出現時，
  ref 與 key 都必須跟前一次完全相同，任一個漂移都拒絕。錯誤碼從
  `WRC_PROMOTION_IDEMPOTENCY_KEY_DRIFT` 改名為 `WRC_PROMOTION_IDENTITY_
  DRIFT`（涵蓋範圍變大，改名反映實際語意）。

### F-03：closeout entry 形狀先鎖

`closeouts.each_with_index` 迴圈一開始就檢查
`entry.is_a?(Hash)`，才呼叫任何 `entry.key?`／`entry[...]`。新錯誤碼
`WRC_CLOSEOUT_ENTRY_NOT_MAP`。

### P2：cadence 欄位值必須是非空字串

新增 `CADENCE_STRING_FIELDS` 檢查：`scheduled_review_period_start`／
`scheduled_anchor_at`／`actual_closeout_at` 必須是非空字串（不是單純
key 存在即可）。真正是不是星期五／對齊 tenant anchor 仍留給排程
runtime——這裡只鎖「有一個可驗的值」。新錯誤碼
`WRC_CADENCE_FIELD_NOT_STRING`。

## 重播 reviewer 的具體 exploit（對修好的程式碼）

```
Exploit 1a（disposition 塞 candidate_status）：
  → WRC_ITEM_DISPOSITION_UNKNOWN_FIELD（不再是 nil）
Exploit 1b（disposition 塞 weekly_work_summary）：
  → WRC_ITEM_DISPOSITION_UNKNOWN_FIELD（不再是 nil）
Exploit 1c（selected_item_refs 改用 Record URN）：
  → WRC_ITEM_REF_NOT_CANDIDATE（不再是 nil）

Exploit 2a（retry 整個刪掉 promotion_idempotency_key）：
  → WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY（不再是 nil）
Exploit 2b（同一個 key、promotion_ref 從 p-1 改 p-2）：
  → WRC_PROMOTION_IDENTITY_DRIFT（不再是 nil）

Exploit 3（第一筆 closeout 換成 "oops"）：
  → WRC_CLOSEOUT_ENTRY_NOT_MAP，無例外（原本是 NoMethodError）
```

六個變體全數確認關閉、無例外。

## 逐 return site parity（非逐 code）

`weekly_review_cycle_failure` 目前 22 個 return site（repair 前 17 個：
新增 `WRC_CLOSEOUT_ENTRY_NOT_MAP`／`WRC_CADENCE_FIELD_NOT_STRING`／
`WRC_ITEM_REF_NOT_CANDIDATE`／`WRC_ITEM_DISPOSITION_UNKNOWN_FIELD`／
`WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY` 五個，`WRC_PROMOTION_
IDEMPOTENCY_KEY_DRIFT` 改名為 `WRC_PROMOTION_IDENTITY_DRIFT`）。逐一
中和、確認 RED、還原、確認逐位元相同：22/22 全紅，未被測到：無。

## 接回總入口的實測

```
中和 WRC_ITEM_REF_NOT_CANDIDATE 的 guard（本輪關鍵新增，對應原始 P1
「selected_item_refs 改成 PersonalMemoryRecord URN」repro）：

直接呼叫新片   → FAIL WRC_NEG_ITEM_REF_NOT_CANDIDATE 預期 deny，實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_weekly_review_cycle_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## Fixture 變更

- 新增 6 筆負例：`WRC_NEG_CLOSEOUT_ENTRY_NOT_MAP`／`WRC_NEG_CADENCE_
  FIELD_BLANK`／`WRC_NEG_ITEM_REF_NOT_CANDIDATE`／`WRC_NEG_ITEM_
  DISPOSITION_UNKNOWN_FIELD`／`WRC_NEG_PROMOTION_REF_WITHOUT_KEY`。
- 改寫既有 `WRC_NEG_PROMOTION_IDEMPOTENCY_KEY_DRIFT` 為
  `WRC_NEG_PROMOTION_IDENTITY_DRIFT`：兩筆 closeout 對同一 item 使用
  **相同** `promotion_idempotency_key` 但**不同** `promotion_ref`
  （`p-1` → `p-2`）——直接對應 reviewer 指出的具體繞過方式，而不是原本
  「key 本身改變」這個較弱的版本。
- `EXPECTED_NEGATIVE_LABELS` 同步增補/改寫對應 6 個 label。

## Gate

```
ruby scripts/validate_*.rb（34 支，含本片）→ 全部 PASS
4 支 Python schema engine                    → 環境缺 jsonschema 模組
                                                （pre-existing，未安裝
                                                venv，本輪未改動其涵蓋
                                                範圍）
git diff --check                              → clean
```

## 明確不在本輪範圍

- 「`scheduled_review_period_start` 是不是真的星期五／對齊 tenant
  anchor」——維持留給排程 runtime，不在本卡職責。
- 切片 1／2／3 的既有契約——完全未動。
