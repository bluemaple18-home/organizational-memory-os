# SSP-309／AIWR-11 Native Adapter Conformance — 大 review 交付包

## 鎖定

```
base    5e511c4
review  <此次 push 的 HEAD，見下方 commit>
branch  cc/ssp309-native-adapter-conformance
```

`git diff 5e511c4..<review>` 為唯讀 diff：只新增
`scripts/validate_ssp309_native_adapter_conformance.rb`（148 行）、
`.work/CARD-SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915.md`、
`.work/evidence/SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915.md`、本交付包。
**沒有修改任何既有契約檔案或既有 validator。**

## 範圍

依 `SSP-307`／`SSP-308`／Native Adapters Correlation Closeout（皆已
`ACCEPTED_GO` + merged）之後，兩份 Adapter 契約現在都有真實的
`lifecycle_event_map` 與 `native_correlation_ref`，本卡把兩邊已宣告但
沒人驗證過的一致性變成可重播的真實斷言：

- **C-01**：`mapping_run` 核心欄位集合／`outcomes` 列舉相等，平台專屬
  欄位（有單邊 `<field>_rule` 說明）例外。
- **C-02**：`error_contract` 語意碼（去前綴後）互相對應，有差集的碼須
  能在契約文字裡找到 `error_contract` 之外的至少一次引用。

原計畫第三條「`lifecycle_event_map` 綁 `ai-task-card-record.yaml`」研究
後**不做**——兩支既有 validator（`validate_codex_native_adapter_contract.rb:148-170`／
`validate_claude_code_native_adapter_contract.rb:144-163`）各自已經 fail-closed
綁定同一份上游檔案，重做會是「兩份手寫清單互相比對」的重複模式。詳見
`.work/evidence/SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915.md`。

## 請重播

正例（目前狀態應 PASS）：

```
ruby scripts/validate_ssp309_native_adapter_conformance.rb
```

Mutation／enforcement-parity（我已做過，見 evidence 檔的完整記錄；歡迎
重放）：中和 `mapping_run_conformance_failures` 或
`error_contract_conformance_failures` 裡任一 `assert(...)` 的條件，
確認 self-test 區塊會讓整支腳本 `FAIL`；還原後應回到 `PASS`。

## Gate

```
ruby scripts/validate_*.rb（全部 24 支，含新增這支）  → PASS
四支 Python schema engine                             → PASS
git diff --check                                       → clean
```

## 請只判斷

這支新 validator 的兩條斷言是否真的對應到兩份契約已經宣告要遵守的東西、
是否會被 mutation 真的抓到、是否有引入本卡範圍外的新一致性要求（沒有
——`non_lifecycle_event_types` 清單長度不同、runtime probe 有無，本卡
明確排除，見卡片「明確排除」段）。最後以 `P0 / P1 / P2 / P3` 分級給
`GO` 或 `NO_GO`。
