# SSP-323 切片 4 — repair-01 定點複審交付包

## 鎖定

```
base             b1d40d7
original_review  6fc781a（審的是 b1d40d7..ca3b42e）
repair_commit    （本次 commit，程式碼修法本身，待 push 後補上）
branch           cc/ssp323-weekly-review-cycle
```

## 這輪收 3 個 P1 + 1 個 P2

你這輪沒有明確授權把 P2 留 backlog，且修法成本低，一併收掉：

1. **F-01**：`item_dispositions` 的 key 必須符合既有
   `personal_memory_resource_contracts...id_templates.
   PersonalMemoryCandidate` 前綴（讀既有模板，不自建規則）；disposition
   物件本身只能帶 `category`／`record_ref`／`promotion_ref`／
   `promotion_idempotency_key` 四個 allowlist 欄位。
2. **F-02**：`promotion_ref` 出現時 `promotion_idempotency_key` 不得
   省略；追蹤對象從單純 key 改成 `(promotion_ref, promotion_
   idempotency_key)` 整組，任一個漂移都拒絕。
3. **F-03**：`closeouts` 迴圈一開始先確認 `entry.is_a?(Hash)`，不會再
   對非 Hash 的 entry 直接呼叫 `.key?` 而當掉。
4. **P2**：`scheduled_review_period_start`／`scheduled_anchor_at`／
   `actual_closeout_at` 必須是非空字串，不再只驗 key 存在。

## 請重播

```bash
ruby scripts/validate_weekly_review_cycle_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb         # 應 PASS（聚合器）

# 你的三個具體 repro 現在都被擋下：
grep -A8 "WRC_NEG_ITEM_DISPOSITION_UNKNOWN_FIELD" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
grep -A8 "WRC_NEG_ITEM_REF_NOT_CANDIDATE" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
grep -A20 "WRC_NEG_PROMOTION_IDENTITY_DRIFT" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
grep -A8 "WRC_NEG_CLOSEOUT_ENTRY_NOT_MAP" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
```

## 逐 return site parity

22 個 return site（原 17 個，新增 5 個，1 個改名）逐一中和 → 22/22 全紅。
額外驗證：中和本輪新增的 `WRC_ITEM_REF_NOT_CANDIDATE` guard（對應你指出
的「selected_item_refs 改成 PersonalMemoryRecord URN」repro），不只直接
呼叫新片會紅，呼叫聚合器 `validate_personal_memory_contract.rb` 也會
轉紅。還原後兩個入口都回到 PASS，diff 對備份逐位元相同。

## 請特別判斷

1. **`ALLOWED_DISPOSITION_FIELDS` 是否窮舉了合理需要的欄位**：目前是
   `category`／`record_ref`／`promotion_ref`／`promotion_idempotency_
   key` 四個。請判斷未來是否會需要更多合法欄位（例如某種備註/理由），
   或這四個已經足夠表達「bounded refs + enum」的意圖。
2. **`record_ref` 目前沒有跟 `promotion_ref` 一樣要求對應的 identity
   binding**：只在 `NEEDS_ORG_FOLLOWUP` 分類時檢查它不得出現，其餘情況
   完全不驗證它的格式或是否真的指向一筆 PersonalMemoryRecord。請判斷是
   否也該比照 `WRC_ITEM_REF_NOT_CANDIDATE` 的做法，綁 `PersonalMemory
   Record` 的 id_template。
3. **`WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY` 沒有反向檢查**：
   `promotion_idempotency_key` 存在但 `promotion_ref` 缺席目前不會被
   擋（只檢查 `promotion_ref && !promotion_key` 這個方向）。請判斷這個
   不對稱是否合理，或也該對稱擋下。

## Gate

```
ruby scripts/validate_*.rb（34 支）  → PASS
4 支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本輪未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。

若 `GO`，`SSP-323`（EMEM-09）四片全數收完。
