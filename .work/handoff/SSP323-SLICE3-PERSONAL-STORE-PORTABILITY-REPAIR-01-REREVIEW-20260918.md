# SSP-323 切片 3 — repair-01 定點複審交付包

## 鎖定

```
base             b1885e7
original_review  bfd97b7
repair_commit    08633ee
branch           cc/ssp323-personal-store-portability
```

## 這輪只收一筆 P1

依你的判斷「repair-01 只要收 P1：把 portability comparison 綁回既有
Candidate/Record authority」，本輪：

不再維護第二份四欄「portable_fields」清單。`portability_failure` 改成
讀取呼叫端宣告的 `resource_kind`（`PersonalMemoryCandidate` 或
`PersonalMemoryRecord`），在**評估當下**向
`personal_memory_resource_contracts.resources.<kind>` 這個既有權威
schema 要真正的 `required_fields`／`forbidden`，逐項比對兩個 executor
投影的 `resource` 物件：

- 每個 `required_fields`（點號路徑）必須兩邊都存在（key 存在即可，legit
  null 值如 `governance.supersedes` 不算缺席）且相等（陣列用集合比對）。
- `forbidden` 清單裡真的是欄位名的條目（過濾掉
  `resource_kind=PERSONAL_MEMORY_RECORD` 這種複合語意宣告），出現在任一
  邊就直接拒絕——這條直接關閉你點名的 `record_id` 混進 Candidate 投影
  這個具體 repro。
- `executor_provenance_fields`（`executor_ref`／`executor_session_ref`）
  的契約層斷言也改綁真實 `required_fields` 聯集，不再跟自己另一份清單
  比對。

P2（`local_first_export_surface` 宣稱比 enforcement 大）已登
`文件/待辦重整.md`，本輪未動。

## 請重播

```bash
ruby scripts/validate_personal_store_portability_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb                # 應 PASS（聚合器）

# 你點名的三個 drift 現在都被擋下：
# 1. ownership/visibility drift
grep -A6 "PORTABILITY_NEG_OWNERSHIP_MISMATCH" 規格/v0.1/fixtures/personal-store-portability-negative-fixtures.json

# 2. content drift（不再靠自報 content_digest）
grep -A6 "PORTABILITY_NEG_CONTENT_MISMATCH" 規格/v0.1/fixtures/personal-store-portability-negative-fixtures.json

# 3. record_id 混進 Candidate 投影（原始 P1 具體 repro）
grep -A6 "PORTABILITY_NEG_FORBIDDEN_FIELD_PRESENT" 規格/v0.1/fixtures/personal-store-portability-negative-fixtures.json
```

## 逐 return site parity

9 個 return site（原 5 個，拿掉舊的四欄比對邏輯、新增 4 個綁定真實
resource schema 的 guard）逐一中和 → 9/9 全紅。額外驗證：中和本輪新增的
`PORTABILITY_FORBIDDEN_FIELD_PRESENT` guard（直接對應你的原始 repro），
不只直接呼叫新片會紅，呼叫聚合器 `validate_personal_memory_contract.rb`
也會轉紅（並印出 `slice validate_personal_store_portability_contract
exited 1`）。還原後兩個入口都回到 PASS，diff 對備份逐位元相同。

## 請特別判斷

1. **`required_fields` 用「key 存在」而非「值非 null」判定完整性是否
   恰當**：`governance.supersedes`／`superseded_by` 這類欄位對一筆全新、
   尚未被取代的 record 合法為 `null`；如果改成「值不得為 null」會誤殺這
   個合法狀態。目前的設計是 key 必須存在（兩邊都要有這個 key），值可以
   是 null，但兩邊的值仍必須相等（null == null 算相等；一邊 null 一邊
   非 null 仍會被 `PORTABILITY_FIELD_MISMATCH` 抓到）。請判斷這個「存在
   性用 key、相等性用值」的兩層設計是否合理。
2. **`literal_forbidden_fields` 用「是否出現在任一 resource kind 的
   required_fields 聯集」篩選 forbidden 清單，是否會漏掉真正該擋的欄位
   名**：`model_confidence_only`／`missing evidence support` 這類複合
   語意宣告被跳過，因為它們不是任何 resource 的欄位名，本片也不打算重做
   既有 `validate_personal_memory_resource_contract.rb` 已經在做的完整
   Candidate/Record 驗證。請確認這個範圍切分是否恰當。
3. **`resource_kind` 目前允許 `personal_memory_resource_contracts.
   resources` 底下全部 4 種 kind**（`PersonalMemoryCandidate`／
   `PersonalMemoryRecord`／`MemorySupportLink`／`MemoryConflictSet`），
   不是只限定前兩種。請判斷是否應該收窄到只允許 Candidate/Record（因為
   「Personal Store record」概念上指的是這兩種），或維持通用機制不特別
   限制。

## Gate

```
ruby scripts/validate_*.rb（33 支）  → PASS
4 支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本輪未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
