# SSP-324 切片 B — repair-03 定點複審交付包

## 鎖定

```
base             72ac78d
repair-02        5db98e0（delivery fb4bc51）
repair_commit    （本次 commit，待 push 後補上）
branch           cc/ssp324-revision-dedup
```

## 這輪只收那一筆 P1：evidence refs 綁回鏈上的權威對照物

**先承認判斷錯誤**：我上一輪說「`prior_evidence_refs` 仍無從驗證」是錯的。
你指出的對——submission chain 本身就保存 predecessor package，權威對照物
一直都在。這不是 provenance 不完美，而是可以把需要 correction metadata
的路徑偽造成不需要的那一條。

依裁決一次收乾淨：

- `comparison.current_evidence_refs` 必須與本筆 `package.evidence_refs`
  **集合一致**
- 後續 submission 的 `comparison.prior_evidence_refs` 必須與
  `supersedes_package_ref` 指到的 predecessor `package.evidence_refs`
  **集合一致**
- 第一筆維持 no-prior 語意：權威 prior evidence 就是空集合，所以同一條
  規則直接涵蓋，不需要特例分支，也不會多出驗不到的 code
- set equality，不綁 array order
- 兩個 exploit 負例已補

## 請重播

```bash
ruby scripts/validate_evidence_package_revision_contract.rb  # 應 PASS
ruby scripts/validate_personal_memory_contract.rb            # 應 PASS

grep -A8 "PKGREV_NEG_FAKE_CURRENT_EVIDENCE" 規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A8 "PKGREV_NEG_FAKE_PRIOR_EVIDENCE"   規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
```

我的重播（含推導值，證明擋的是輸入綁定而不是分類本身）：

```
原始正例                          推導 MATERIALLY_CHANGED/CORRECTION_SUPERSESSION_PROPOSAL → nil
exploit 1（塞封包沒有的 evidence） 推導被偽造成 NEW_EVIDENCE/EVIDENCE_UPDATE_REVISION
                                  PACKAGE_HAS_FAKE_CURRENT=false
                                  → PKGREV_COMPARISON_CURRENT_EVIDENCE_NOT_BOUND_TO_PACKAGE
exploit 2（prior 偽造成 []）       推導被偽造成 NEW_EVIDENCE/EVIDENCE_UPDATE_REVISION
                                  PREDECESSOR_EVIDENCE=[…801] / DECLARED=[]
                                  → PKGREV_COMPARISON_PRIOR_EVIDENCE_NOT_BOUND_TO_CHAIN
順序不同、集合相同                 → nil（沒有誤殺）
第一筆宣稱有 prior evidence        → PKGREV_COMPARISON_PRIOR_EVIDENCE_NOT_BOUND_TO_CHAIN
```

## 逐 return site parity

```
共用推導 helper（COMPARISON_）  14 sites → 14/14 全紅
共用封包 helper（MEP_）          22 sites → 22/22 全紅
切片 A（access_request）          4 sites → 4/4 全紅
切片 B（PKGREV_）                27 sites → 27/27 全紅
```

本輪未再動切片 1 與切片 A 的邏輯；兩者 golden 仍為 27/27 與 42/42。

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
切片 B fixtures：4 positive + 29 negative = 33
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
