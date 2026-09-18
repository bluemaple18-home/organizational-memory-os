# SSP-323 切片 3 — evidence

日期：2026-09-18　branch：`cc/ssp323-personal-store-portability`　base：`b1885e7`

## 交付

```
規格/v0.1/personal-harness-integration.yaml   runtime_policy +portable_record_contract +local_first_export_surface
scripts/validate_personal_store_portability_contract.rb   148 行（< 400）
規格/v0.1/fixtures/personal-store-portability-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
```

**未修改任何既有 `runtime_policy` 欄位**——`executor_authority_over_
memory`／`optional_executors` 逐字保留，只在同一個 block 底下新增兩個
子欄位。

## 設計回應

### 延伸既有宣告，不重造

`optional_executors`（deterministic_worker／bounded_model_worker／
Codex／Claude Code／Hermes／DeepSeek Harness）與 `executor_authority_
over_memory: false` 直接沿用；`portability_failure` 檢查每個
`executor_ref` 都必須屬於這份既有清單（`PORTABILITY_UNKNOWN_EXECUTOR`），
不是自己另立一套 executor 名單。

### Acceptance #1：跨 executor 核心語意不變

`portable_fields`（`record_id`／`content_digest`／`evidence_refs`／
`created_at`）逐項比對兩個不同 executor 的投影是否相等。`evidence_refs`
用集合比對（`to_set`），不因序列化順序不同誤判——正例
`PORTABILITY_POS_CLAUDE_CODE_VS_CODEX` 刻意讓兩個投影的 `evidence_refs`
順序相反，證明比對邏輯不受順序影響。

### Acceptance #2：換 executor 不需 migration

契約結構斷言 `portable_fields.to_set & executor_provenance_fields.to_set`
必須為空——`executor_ref`／`executor_session_ref` 只能是補充 provenance，
不得同時是判定「這是同一份 Personal truth」的依據。

### Local-first export surface 封閉列舉

`local_first_export_surface` 必須恰好是
`{minimal_evidence_package, weekly_closeout_receipt}`——這是「公司端只
得到明確送出的 package 與 receipt」在契約層的機器邊界：不是開放集合，
未來如果有人想加第三個匯出管道，這裡會先紅。

### 機器可查訊號 vs 判斷型訊號分離

本片全部斷言都是結構性事實：欄位相等、集合不相交、executor 屬於既有
清單、export surface 恰好兩項。跟切片 1／2 不同，這裡沒有任何需要人類
判斷的維度（不像切片 2 的九構面評分），所以不存在「自報」的空間需要
特別設計佐證機制——結構本身就是唯一的真相來源。

## 接回總入口的實測

```
中和 PORTABILITY_FIELD_MISMATCH 的 guard：

直接呼叫新片   → FAIL PORTABILITY_NEG_FIELD_MISMATCH 預期 deny，實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_personal_store_portability_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## 逐 return site parity（非逐 code）

5 個 return site → 5/5 全紅，未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（33 支，含新增這支）  → PASS
四支 Python schema engine                         → 環境缺 jsonschema 模組
                                                     （pre-existing，未安裝
                                                     venv，本卡未改動其涵蓋
                                                     範圍）
git diff --check                                   → clean
```

## 明確不在本卡範圍

- 本機持久層的實際儲存實作（檔案格式、資料庫選型）——本卡只鎖欄位層級
  的 executor-neutral 邊界，不規定實作細節。
- 切片 4（weekly grill／batch UX／收尾）。
- `SSP-324` 綁定本卡 `local_first_export_surface` 的實作（另卡）。
