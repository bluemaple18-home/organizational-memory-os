# SSP-323 切片 1 — evidence

日期：2026-09-17　branch：`cc/ssp323-historical-comparison`　base：`63464c3`

## 開工前的兩個查證（你指出的現況修正）

1. `runtime_policy.optional_executors`（Codex／Claude Code／Hermes／
   DeepSeek Harness）與 `executor_authority_over_memory: false` 已存在，
   且**已被** `validate_ai_work_record_boundary_contract.rb:258-262` 強制
   ——platform-neutral 不是零基礎，是「宣告與部分強制已存在，具體機制
   （本機保存、可攜、跨平台操作）未落成」。這是切片 3 的範圍，不是本卡。
2. `validate_personal_evidence_profile_contract.rb` 實際讀
   `personal-evidence-profile.yaml` ＋ `personal-harness-integration.yaml`
   ＋ fixtures，不是只讀一份檔案——「共用語意單一權威、各契約引用承接」
   比「六支全讀同一檔」更準確。

## 交付

```
規格/v0.1/personal-harness-integration.yaml   +historical_comparison 區塊
scripts/validate_historical_comparison_contract.rb   225 行（< 400）
規格/v0.1/fixtures/historical-comparison-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
```

## 設計回應

### 不是第二套生命週期

`FORBIDDEN_LIFECYCLE_FIELDS`（`candidate_status`／`record_status`／
`verification_status`／`acceptance_status`／`conflict_resolution_status`）
結構性禁止出現在 comparison run 裡。

### category／disposition 純推導，不接受自報

`compute_signals` 從 `prior_record_ref`（存在與否）、content hash（相等
與否）、`evidence_refs` 集合差算出三個機器可查訊號；`classify` 用明確
優先序推導 category／disposition。run 的欄位裡**沒有**讓呼叫端宣告
`category`／`disposition` 的欄位——不是「驗證了自報與事實一致」，是
「自報這個概念根本不存在」。

`material_effect`／`contradicts_prior` 無法機器判定，允許呼叫端宣告，
但 `true` 必須附非空 `reasons`（限定 `material_effect_dimensions`）與至少
一個 URN `evidence_refs`。

### 優先序解決同時成立

```
HC_POS_CONTRADICTION_PRECEDENCE_OVER_NEW_EVIDENCE：
  has_new_evidence=true 且 material_effect=true 且 contradicts_prior=true
  → 推導結果：CONTRADICTED（不是 NEW_EVIDENCE）
```

## 接回總入口的實測（不是只加檔案）

```
把 COMPARISON_FORBIDDEN_LIFECYCLE_FIELD 的 guard 中和掉：

直接呼叫新片   → FAIL HC_NEG_FORBIDDEN_LIFECYCLE_FIELD 預期 deny，實際通過
呼叫總入口     → FAIL HC_NEG_FORBIDDEN_LIFECYCLE_FIELD 預期 deny，實際通過
               （並連帶觸發 HC_NEG_PRIOR_RECORD_INCONSISTENT 的後續失敗）
```

還原後 `diff` 確認逐位元相同，總入口回到 `PASS personal memory contract
validation`。

## 逐 return site parity

10 個 return site → 10/10 全紅，未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（31 支，含新增這支）  → PASS
四支 Python schema engine                         → PASS
git diff --check                                   → clean
```

## 明確不在本卡範圍

- 平台中立本機邊界的具體機制（切片 3）。
- Organizational Value Assessment／`NEEDS_ORG_FOLLOWUP`（切片 2）。
- `SSP-324` 綁定本卡 disposition 的實作（另卡，待本片與切片 2 完成）。
