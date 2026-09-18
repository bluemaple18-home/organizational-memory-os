# SSP-324 切片 B — evidence

日期：2026-09-18　branch：`cc/ssp324-revision-dedup`　base：`72ac78d`

## 交付

```
規格/v0.1/personal-harness-integration.yaml   +evidence_package_revision 區塊
scripts/validate_evidence_package_revision_contract.rb   262 行（< 400）
規格/v0.1/fixtures/evidence-package-revision-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
```

**未修改切片 A 的封包契約、`historical_comparison`、`correction_flow` 任何
一行**——全部 pointer-bind。

## 設計回應

### 驗證單位是提交鏈，不是單筆封包

「不得每週重送 duplicate package」與「previous package 必須可追溯」都只在
跨筆比對時才看得見。這跟 `weekly_review_cycle` 對 closeout 歷史學到的是
同一課，所以直接沿用同樣的形狀：run = 一個 candidate 的整段 submissions。

### 信封而非加欄位（避免重開切片 A）

切片 A 的 `package_required_fields` 是封閉 allowlist；把 revision 欄位塞
進封包會逼著改 A 的 YAML 清單、Ruby 常數與全部正例。改用外層信封後，A 的
封閉 shape 一字未動。契約裡以 `layering_boundary` 明寫這個分層，並說明 B
仍對自己讀的三個封包欄位做值形狀鎖（`package_id` URN、`content_hash`
sha256、`candidate_ref` 與鏈一致），不盲信也不重做 A 的驗證。

### dedup／resend 完全綁上游

`disposition` 必須是上游對該 `comparison_category` 宣告的那一個
（`PKGREV_DISPOSITION_NOT_DECLARED_FOR_CATEGORY`）。`NEW_EVIDENCE` 在上游
本來就分兩支（有／無 material effect），所以判定用「屬於該 category 的合法
集合」，不是寫死單一值——上游哪天再分支，這裡自動跟上。

卡片 Acceptance #7（`UNCHANGED` 不重送）的機器邊界：
`non_transmittable_dispositions`（`NO_RESEND`／`LOCAL_RECURRENCE_ONLY`）
授權的是「不要送」，所以帶著這種 disposition 出現在提交鏈裡本身就是矛盾
（`PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE`）。這兩個值是本片唯一新增的
決定，因此明寫在契約，但**每個值都必須存在於上游 dispositions**，由斷言
強制，不得自創；validator 另有斷言要求每個 non-transmittable disposition
都被負例實際打過。

### immutable / 可追溯

- 第一筆必須 supersede 空、且必須是 `UNSEEN`／`INITIAL_SUBMISSION`
- 之後每一筆必須指向**鏈中更早出現過**的 predecessor（可追溯）
- `package_id` 不得在鏈中重複（原地改寫偽裝成重新提交）
- 兩筆不得指向同一個 predecessor（鏈分叉，同樣是變相原地改寫——
  `correction_flow` 本來就禁 `in_place_record_overwrite`）
- revision 的 `content_hash` 必須與 predecessor 不同；相同內容就是
  `UNCHANGED`，而 `UNCHANGED` 不可傳輸

### correction 走既有 lifecycle

`CORRECTION_SUPERSESSION_PROPOSAL`／`CORRECTION_CONFLICT_PROPOSAL` 必須帶
`correction_proposal_ref`（URN）且 `correction_kind` ∈ 上游
`correction_flow.contract.correction_kinds`（`AMEND`／`INVALIDATE`／
`SUPERSEDE`）。非 correction 的 disposition 則**不得**夾帶這兩個欄位。

## 先套用切片 A 兩輪 NO_GO 的教訓（不等 review 抓）

1. **欄位名 allowlist ≠ 值被鎖**：`submission_allowed_fields` 是封閉
   allowlist，且每個讀到的值都另有形狀檢查（URN／sha256／map）。
2. **綁上游要綁到 identity 那層**：`content_hash` 直接用既有共用的
   `SHA256_LOCKED_PATTERN`，不自寫 regex。

## 接回總入口的實測

```
中和 PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE（卡片 Acceptance #7 的 guard）：

直接呼叫新片   → FAIL PKGREV_NEG_RESEND_UNCHANGED／_LOCAL_RECURRENCE
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣的 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_evidence_package_revision_contract exited 1

還原後 diff 逐位元相同，兩個入口都回到 PASS。
```

## 逐 return site parity（非逐 code）

22 個 return site → 22/22 全紅（第一輪就全紅），未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（36 支，含新增這支）→ PASS
四支 Python schema engine                       → 環境缺 jsonschema（pre-existing）
git diff --check                                 → clean
```

## 明確不在本卡範圍

- 切片 C（公司端使用邊界、`NEEDS_ORG_FOLLOWUP` 無 canonical identity）。
- 真人 runtime 證明 → `SSP-295`。
