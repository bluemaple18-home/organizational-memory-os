# SSP-324 切片 B — repair-03 evidence

日期：2026-09-18　branch：`cc/ssp324-revision-dedup`

```
base            72ac78d
repair-02       5db98e0（delivery fb4bc51）
repair_commit   80d3c17
```

## Reviewer NO_GO（對 `fb4bc51`）

```
P0=0 / P1=1 / P2=0 / P3=0
```

repair-02 的自報 classification P1 確認關閉；切片 1 的 refactor 獲接受
（27/27 逐字相同），不需另開 refactor 卡。

**新 P1 — 我自己揭露、但判斷錯誤的那個半套。** 我當時說
「`prior_evidence_refs` 仍無從驗證」，**這是錯的**：這條 submission chain
本身就保存 predecessor package，因此 prior evidence refs 有權威對照物。
後果不是「provenance 不完美」，而是可以偽造分類：

```
原始：MATERIALLY_CHANGED → CORRECTION_SUPERSESSION_PROPOSAL
只在 comparison.current_evidence_refs 塞一筆 package 沒有的 evidence：
      NEW_EVIDENCE → EVIDENCE_UPDATE_REVISION → PASS
或把 comparison.prior_evidence_refs 偽造成 []：
      NEW_EVIDENCE → EVIDENCE_UPDATE_REVISION → PASS
```

也就是把本來需要 correction metadata 的路徑，偽造成不需要的那一條。

## 修法（依裁決一次收乾淨）

- `comparison.current_evidence_refs` 必須與**本筆 package.evidence_refs**
  集合一致（`PKGREV_COMPARISON_CURRENT_EVIDENCE_NOT_BOUND_TO_PACKAGE`）。
- 後續 submission 的 `comparison.prior_evidence_refs` 必須與
  `supersedes_package_ref` 指到的 **predecessor package.evidence_refs**
  集合一致（`PKGREV_COMPARISON_PRIOR_EVIDENCE_NOT_BOUND_TO_CHAIN`）。
- 第一筆維持 no-prior 語意：權威的 prior evidence 就是**空集合**，所以
  同一條規則直接涵蓋，不需要特例分支，也不會多出一個驗不到的 code。
- **set equality**，不綁 array order。
- 補兩個 exploit 負例：`PKGREV_NEG_FAKE_CURRENT_EVIDENCE`、
  `PKGREV_NEG_FAKE_PRIOR_EVIDENCE`。

## 重播

```
原始正例                         推導 MATERIALLY_CHANGED/CORRECTION_SUPERSESSION_PROPOSAL → nil
exploit 1（塞封包沒有的 evidence）推導被偽造成 NEW_EVIDENCE/EVIDENCE_UPDATE_REVISION
                                 PACKAGE_HAS_FAKE_CURRENT=false
                                 → PKGREV_COMPARISON_CURRENT_EVIDENCE_NOT_BOUND_TO_PACKAGE
exploit 2（prior 偽造成 []）      推導被偽造成 NEW_EVIDENCE/EVIDENCE_UPDATE_REVISION
                                 PREDECESSOR_EVIDENCE=[…801] / DECLARED=[]
                                 → PKGREV_COMPARISON_PRIOR_EVIDENCE_NOT_BOUND_TO_CHAIN
順序不同、集合相同                → nil（沒有誤殺）
第一筆宣稱有 prior evidence       → PKGREV_COMPARISON_PRIOR_EVIDENCE_NOT_BOUND_TO_CHAIN
```

推導那一行是重點：偽造**確實**會讓 `classify` 算出 NEW_EVIDENCE——所以擋
下來的不是「分類錯了」，而是「你餵給推導的輸入沒有綁回鏈上的事實」。

## 逐 return site parity（非逐 code）

```
共用推導 helper（COMPARISON_）  14 sites → 14/14 全紅
共用封包 helper（MEP_）          22 sites → 22/22 全紅
切片 A（access_request）          4 sites → 4/4 全紅
切片 B（PKGREV_）                27 sites → 27/27 全紅
```

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
golden：切片 1 → 27/27；切片 A → 42/42（本輪未再動這兩片的邏輯）
```

## Fixture

```
切片 B：4 positive + 29 negative = 33
```
