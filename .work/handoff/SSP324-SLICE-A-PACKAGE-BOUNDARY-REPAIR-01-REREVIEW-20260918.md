# SSP-324 切片 A — repair-01 定點複審交付包

## 鎖定

```
base             faf6822
original_review  ebd2dd3（審的是 faf6822..3cecb25）
repair_commit    7879330
branch           cc/ssp324-package-boundary
```

## 三筆 P1 全收

1. **F-01 closed shape**：`package_required_fields` 同時是完整 allowlist
   （`MEP_PACKAGE_UNKNOWN_FIELD`），forbidden 清單保留在它之前以維持
   明確錯誤碼；`organizational_value_reasons` 從 `any?` 改為
   「非空 ＋ 全元素非空字串」。
2. **F-02 ref 綁上游形狀**：canonical matcher 由
   `common-vocabulary` 的 `ref_template` ＋ `resource_kinds` 組出；
   `evidence_refs` pin `EVIDENCE_RECORD`、`source_anchor_refs` pin
   `SOURCE_ANCHOR`；`source_acl_snapshot_ref` 綁 STD-01 schema 的
   `acl_snapshot_ref.pattern`（與 permission-retention-deletion 同源，
   從 schema 讀不手抄）。
3. **F-03 bounded integrity**：`content_bound.max_bytes` 宣告在契約、
   evaluator 量 `bytesize`；`content_hash` 驗 SHA-256 形狀 **且** 依
   `content_hash_basis` 重算比對。

誠實邊界（寫進契約 `ref_binding.known_gap`，不假裝同等強度）：上游沒有
PROVENANCE kind，`provenance_chain_refs` 只能綁到「kind 屬於上游
resource_kinds」；`package_id`／`employee_owner_ref`／`consent_ref`／
`redaction_ref` 是 org 端 identity，維持 generic omos-URN。

## 請重播

```bash
ruby scripts/validate_minimal_evidence_package_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb             # 應 PASS（聚合器）

grep -A6 "MEP_NEG_PACKAGE_UNKNOWN_FIELD" 規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
grep -A6 "MEP_NEG_EVIDENCE_REF_NOT_CANONICAL" 規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
grep -A6 "MEP_NEG_CONTENT_HASH_MISMATCH" 規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
```

你的九個 exploit 變體重播結果全部關閉（含 baseline 仍 `nil`，證明不是
一律擋掉了事）；逐 return site parity 26/26 全紅；中和
`MEP_PACKAGE_UNKNOWN_FIELD`（你的 `private_blob` repro）驗證聚合器同步
轉紅。

## 請特別判斷

1. **`content_bound.max_bytes = 4096` 這個數字**：我把它放在契約當
   policy（evaluator 只讀不寫死），但 4096 仍是我選的。請判斷這個量級對
   「bounded excerpt」是否合理，或該由 Owner 定。
2. **`provenance_chain_refs` 的弱綁定**：上游確實沒有 PROVENANCE
   resource kind。目前綁到「任一宣告過的 resource kind」。請判斷這是否
   足夠，或該在 `common-vocabulary` 補一個 kind（那會動到 `LOCKED` 的
   共用詞彙，屬於另一張卡）。
3. **切片 3 P2 改標 `CLEARED_CONTRACT_LEVEL`**（非 `CLEARED`），並在該列
   明寫 runtime 證明仍屬 `SSP-295`。請確認這個措辭符合你的裁決。

## Gate

```
ruby scripts/validate_*.rb（35 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
