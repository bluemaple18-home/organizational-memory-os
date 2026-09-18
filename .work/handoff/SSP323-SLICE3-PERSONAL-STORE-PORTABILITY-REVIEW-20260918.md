# SSP-323 切片 3 — 大 review 交付包

## 鎖定

```
base    b1885e7
review  （本次 commit，待 push 後補上）
branch  cc/ssp323-personal-store-portability
```

新增三個檔案 + 修改既有 aggregator/spec 各一處：

```
規格/v0.1/personal-harness-integration.yaml         runtime_policy +portable_record_contract +local_first_export_surface
scripts/validate_personal_store_portability_contract.rb  148 行
規格/v0.1/fixtures/personal-store-portability-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
```

**未修改 `runtime_policy` 的任何既有欄位**——`executor_authority_over_
memory`／`optional_executors` 逐字保留，只新增兩個子欄位在同一個 block
底下。

## 這張卡

`SSP-323`（EMEM-09）切片 3：Personal Store Portability ／ Local-First
export surface。延伸（不重造）已存在、且已被
`validate_ai_work_record_boundary_contract.rb` 的 `cross_reference` 強制
的 `executor_authority_over_memory`／`optional_executors`。

## 請重播

```bash
ruby scripts/validate_personal_store_portability_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb                # 應 PASS（接回總入口）

# 接回總入口的證明：中和 PORTABILITY_FIELD_MISMATCH 的 guard，
# 不只直接呼叫新片會紅，呼叫總入口也應該紅
# 逐 return site parity（非逐 code）→ 我的結果 5/5 全紅
```

## 請特別判斷

1. **`portable_fields` 這四個欄位是否足夠代表「核心語意」**：目前是
   `record_id`／`content_digest`／`evidence_refs`／`created_at`。請判斷
   是否遺漏了會因 executor 不同而合理改變、卻不該被忽略的欄位，或反過來
   是否有欄位不該被要求跨 executor 完全相等（例如時間精度）。
2. **`local_first_export_surface` 封閉列舉是否過早鎖死**：目前只有
   `minimal_evidence_package`／`weekly_closeout_receipt` 兩項。如果
   `SSP-324` 未來需要第三種匯出型態（例如純粹的稽核備查匯出），這裡會先
   紅——請判斷這個「先紅、逼著明確擴充契約」的設計是否恰當，或應該留一個
   可擴充但仍受控的機制。
3. **`content_digest` 相等是否足以代表「核心內容未變」**：本片沒有驗證
   `content_digest` 本身是怎麼算出來的（不像 SSP-309 的 adapter mapping
   contract 有 `determinism.inputs` 可重算）。請判斷這裡是否需要比照
   SSP-309 的模式，或目前只驗「兩邊宣稱的 digest 相等」已足夠回答
   Acceptance #1。
4. **`evidence_refs` 用集合比對（忽略順序）是否會掩蓋真正的差異**：如果
   兩個 executor 對同一筆 evidence 給出重複或近似但不完全相同的 URN，
   集合比對可能各算各的、剛好數量相同但內容不同時才會抓到。請判斷這個
   比對粒度是否足夠。

## Gate

```
ruby scripts/validate_*.rb（33 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本卡未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
