# SSP-323 切片 4 — repair-02 定點複審交付包

## 鎖定

```
base             b1d40d7
repair-01        f945486
original_review  965c111（審的是 ca3b42e..f945486）
repair_commit    f5e5975
branch           cc/ssp323-weekly-review-cycle
```

## 這輪收 1 個 P1；P2 留 backlog（你明示未證明會造成 duplicate Promotion）

repair-01 的 allowlist 只鎖了 disposition 的欄位「名稱」，沒有鎖
`record_ref`／`promotion_ref` 這兩個 ref 欄位的「值形狀」——修法：

- `record_ref` 改綁既有 `personal_memory_resource_contracts...id_
  templates.PersonalMemoryRecord`（跟 repair-01 綁 Candidate 同樣的
  做法），值必須是這個前綴開頭的字串。
- `promotion_ref` 沒有對應上游 id_template，退而求其次要求合法的
  omos URN。
- `promotion_idempotency_key` 要求非空字串（同一類防禦，對稱補上，
  雖然你沒有直接示範這個變體）。

三者都不再接受 Hash／Array 等任意 payload。

## 請重播

```bash
ruby scripts/validate_weekly_review_cycle_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb         # 應 PASS（聚合器）

# 你的三個具體 repro 現在都被擋下：
grep -A10 "WRC_NEG_RECORD_REF_HASH_PAYLOAD" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
grep -A10 "WRC_NEG_RECORD_REF_NOT_URN_STRING" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
grep -A30 "WRC_NEG_PROMOTION_REF_HASH_PAYLOAD" 規格/v0.1/fixtures/weekly-review-cycle-negative-fixtures.json
```

## 逐 return site parity

25 個 return site（repair-01 後 22 個，本輪新增 3 個）逐一中和 → 25/25
全紅。額外驗證：中和本輪新增的 `WRC_RECORD_REF_NOT_RECORD` guard（對應
你的 Exploit A/B repro），不只直接呼叫新片會紅，呼叫聚合器也會轉紅。
還原後兩個入口都回到 PASS，diff 對備份逐位元相同。

## 請特別判斷

1. **`promotion_ref` 沒有上游 id_template 可綁，只能退而求其次要求合法
   omos URN**——這比 `record_ref`／`item_ref` 弱（後兩者綁定了具體的
   resource kind 前綴）。請判斷這個不對稱（一個綁具體 template、一個只
   驗通用 URN 形狀）是否可接受，或該在
   `personal_memory_resource_contracts` 補一個 Promotion 相關的
   id_template（那會是切片 4 以外的範圍）。
2. **三個 shape 檢查的順序**：目前是 record_ref → promotion_ref →
   promotion_idempotency_key → NEEDS_FOLLOWUP 檢查 →
   PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY 檢查 → drift 檢查。請確認這個
   順序沒有製造出新的「先被更早的檢查擋住、導致後面的檢查變成打不到的
   dead code」問題（我方的 return-site sweep 顯示 25/25 全部可達，但
   麻煩你獨立確認一次)。

## Gate

```
ruby scripts/validate_*.rb（34 支）  → PASS
4 支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本輪未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。

若 `GO`，`SSP-323`（EMEM-09）四片全數收完。
