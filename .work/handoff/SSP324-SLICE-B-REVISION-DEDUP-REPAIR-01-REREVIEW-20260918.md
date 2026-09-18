# SSP-324 切片 B — repair-01 定點複審交付包

## 鎖定

```
base             72ac78d
original_review  2b7dcef（審的是 72ac78d..3119fa1）
repair_commit    （本次 commit，待 push 後補上）
branch           cc/ssp324-revision-dedup
```

## 三筆 P1 + 一筆 P2 全收

1. **F-01 真的共用 evaluator**：A 的封包 evaluator 抽成
   `scripts/lib/minimal_evidence_package_shape.rb`，A 與 B 呼叫同一支
   `package_failure`，上游綁定也用同一支 `build_bindings`。
2. **F-02 刪掉「content_hash 必須改」**：那條會誤殺「內容沒改、但
   redaction／sensitivity／applicability 改了」的合法 revision。是否可送
   完全由上游 disposition 決定。
3. **F-03 UNSEEN 只能是第一筆**：補反向檢查。
4. **P2 `submission_id` 唯一**。

## ⚠️ 本輪動到了已 `ACCEPTED_GO` 的切片 A，請重點覆核

抽取共用 evaluator 必然要改 A。我的立場是**行為逐字不變**，證據：

```
golden harness：A 的 39 筆 fixtures + 5 組多重違規順序敏感度組合
repair 前 vs 後 → 42/42 逐字相同（diff 無輸出）
```

多重違規組合是重點，它證明檢查順序沒被 refactor 改掉，例如
`mismatch+bad_evidence_ref` 前後都回 `MEP_PACKAGE_REF_MISMATCH`。

A 的 `transmission_failure` 拆成 `access_request_failure`（留在 A）＋
共用 `package_failure`，兩支各自受出口形狀凍結約束，A 的 `ERROR_CONTRACT`
斷言改為兩者可達 code 的聯集（`MEP_*` 一個不多一個不少）。

**請獨立驗這件事**——若你認為抽取本身需要另開 refactor 卡或回 Owner
簽核，我照辦。

## 組合證明（review 明確要的東西）

```
在共用 helper 裡中和 MEP_PACKAGE_UNKNOWN_FIELD 一個 guard：
  切片 A      → FAIL MEP_NEG_PACKAGE_UNKNOWN_FIELD
  切片 B      → FAIL PKGREV_NEG_PACKAGE_EXTRA_FIELD
  aggregator  → FAIL ... validate_evidence_package_revision_contract exited 1
```

一個 guard 同時讓兩片轉紅——這在「只是同掛 aggregator」的舊架構下不可能。

## 請重播

```bash
ruby scripts/validate_minimal_evidence_package_contract.rb   # 應 PASS
ruby scripts/validate_evidence_package_revision_contract.rb  # 應 PASS
ruby scripts/validate_personal_memory_contract.rb            # 應 PASS

# 你的四個 repro
grep -A4 "PKGREV_NEG_PACKAGE_ONLY_THREE_FIELDS"        規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A4 "PKGREV_NEG_PACKAGE_EXTRA_FIELD"              規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A4 "PKGREV_NEG_REPEATED_INITIAL_SUBMISSION"      規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A4 "PKGREV_NEG_DUPLICATE_SUBMISSION_ID"          規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
# F-02 的反向證據（repair 前會被誤殺的合法 revision）
grep -A4 "PKGREV_POS_REVISION_WITH_UNCHANGED_CONTENT_HASH" 規格/v0.1/fixtures/evidence-package-revision-positive-fixtures.json
```

## 逐 return site parity

```
共用 helper（MEP_）  22 sites → 22/22 全紅（A 或 B 任一轉紅即算守住）
切片 A（access_request）4 sites → 4/4 全紅
切片 B（PKGREV_）      22 sites → 22/22 全紅
```

## 我主動掃的同族對稱性

F-03 是「只檢查單向」這一族的洞，所以我把同族全掃了一遍：
「第一筆不得 supersede／後續必須 supersede」已對稱、
「correction disposition 必須帶欄位／非 correction 不得帶」已對稱、
「package_id 唯一／submission_id 唯一」由 P2 補齊後對稱。

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
golden（切片 A 行為逐字不變）          → 42/42 相同
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
