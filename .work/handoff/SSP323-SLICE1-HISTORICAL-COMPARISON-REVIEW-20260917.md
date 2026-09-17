# SSP-323 切片 1 — 大 review 交付包

## 鎖定

```
base    63464c3
review  0205d7b
branch  cc/ssp323-historical-comparison
```

新增三個檔案 + 修改既有 aggregator 一行：

```
規格/v0.1/personal-harness-integration.yaml         +historical_comparison
scripts/validate_historical_comparison_contract.rb  225 行
規格/v0.1/fixtures/historical-comparison-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
```

**未修改任何既有契約區塊或既有 validator 的判斷邏輯**——唯一動到既有檔案的
地方是把新 slice 名稱加進 aggregator 的清單。

## 這張卡

`SSP-323`（EMEM-09）切片 1：五態比較結果分類，供 `SSP-324` 的 dedup 規則
綁定。派工前的 review 指出兩個要點，已落實：

1. category／disposition 不能自報——本卡的 run schema 裡根本沒有讓呼叫端
   宣告這兩者的欄位，全部由 evaluator 從原始訊號推導。
2. 五態可能同時成立，用明確優先序（`CONTRADICTED` > `NEW_EVIDENCE` >
   `MATERIALLY_CHANGED` > `UNCHANGED`，`UNSEEN` 最優先）解決，不是列五個
   名稱就算完事。

## 請重播

```bash
ruby scripts/validate_historical_comparison_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb          # 應 PASS（接回總入口）

# 接回總入口的證明：中和 COMPARISON_FORBIDDEN_LIFECYCLE_FIELD 的 guard，
# 不只直接呼叫新片會紅，呼叫總入口也應該紅
# 逐 return site parity（非逐 code）→ 我的結果 10/10 全紅
```

## 請特別判斷

1. **優先序本身是否合理**：`CONTRADICTED` 永遠優先於 `NEW_EVIDENCE`，即使
   新證據才是矛盾的來源。請判斷這個排序是否符合直覺，或該不該讓
   「新證據導致的矛盾」與「既有材料重新評估後的矛盾」分成不同 disposition。
2. **`material_effect_dimensions` 是否足夠**：目前六項（evidence_strength_
   tier／applicability／risk／conflict_determination／
   redaction_or_sensitivity_requirement／conclusion）直接取自 `SSP-324`
   卡片列出的 material effect 定義。
3. **`UNSEEN` 的 disposition 是否該在本卡定義**：目前給 `INITIAL_SUBMISSION`
   （沒有 resend 語意，因為沒有東西可以 resend）。請判斷這個處置是否恰當，
   或應該留給既有的候選送出流程處理、本卡不需要碰。
4. **判斷型訊號的「不可推翻先前」規則**：`no_prior_record` 為 true 時，
   `material_effect`／`contradicts_prior` 一律拒絕宣告為 true。請判斷這個
   一致性檢查是否足夠，或需要對稱地檢查其他組合。

## Gate

```
ruby scripts/validate_*.rb（31 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
