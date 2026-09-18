---
id: SSP323-SLICE3-PERSONAL-STORE-PORTABILITY-20260918
status: READY
jira: SSP-323
parent_jira: SSP-286
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-323｜EMEM-09 切片 3：Personal Store Portability ／ Local-First Export Surface

## 目標

沿用 `.work/CARD-SSP323-WEEKLY-PERSONAL-HARNESS-20260917.md` 第 1 節
「Platform-neutral / portable Personal truth」與第 2 節「Local-first
boundary」，做成可機器驗的契約 + evaluator。

延伸（不重造）`規格/v0.1/personal-harness-integration.yaml` 已存在、且已被
`validate_ai_work_record_boundary_contract.rb` 的 `cross_reference` 強制
的 `runtime_policy.executor_authority_over_memory`／`optional_executors`
宣告——這兩個既有宣告本次不動，只在同一個 `runtime_policy` 底下新增具體
機制。

## Scope

1. `規格/v0.1/personal-harness-integration.yaml` 的 `runtime_policy` 新增：
   - `portable_record_contract`：`portable_fields`（換 executor 不得變的
     核心欄位）與 `executor_provenance_fields`（可以隨 executor 改變的
     補充 metadata），兩者結構性不相交。
   - `local_first_export_surface`：封閉列舉，只有
     `minimal_evidence_package`／`weekly_closeout_receipt` 兩項。
2. `scripts/validate_personal_store_portability_contract.rb`：
   - Acceptance #1（同一份 Personal Store 可由至少兩種 executor fixture
     處理，核心語意不變）：兩個不同 `optional_executors` 對同一筆 record
     的本機投影，`portable_fields` 逐項比對相等（`evidence_refs` 以集合
     比對，不因序列化順序不同而誤判）。
   - Acceptance #2（換 executor 不需 migration）：`portable_fields` 與
     `executor_provenance_fields` 不相交的結構斷言。
   - `local_first_export_surface` 恰好是封閉的兩項列舉。
3. 接回 `scripts/validate_personal_memory_contract.rb` 聚合器。

## 承接前兩片的兩項硬要求

1. **聚合器接回實測**：新增 guard 至少一個要證明不只直接呼叫這支會紅，
   呼叫聚合器也同步轉紅。
2. **機器可查訊號 vs 判斷型訊號分離**：本片全部斷言都是結構性事實
   （欄位相等、集合不相交、executor 屬於既有清單、export surface 恰好
   兩項）——不像切片 2 有需要人類判斷的維度，這裡沒有「自報」的空間可驗，
   自然滿足這條要求，不需要額外設計。

## 不屬本卡

- 切片 2（Organizational Value Assessment）已完工，不重做。
- 切片 4（weekly grill／batch UX／收尾）。
- 本機持久層的實際儲存實作（檔案格式、資料庫選型等）——本卡只鎖「哪些
  欄位必須 executor-neutral」與「公司端只收到什麼」，不規定本機怎麼存。
- `SSP-324` 的 Minimal Evidence Package 實作（沿用本卡的
  `local_first_export_surface` 列舉，另卡）。
