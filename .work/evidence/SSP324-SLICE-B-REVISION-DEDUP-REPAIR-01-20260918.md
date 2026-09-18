# SSP-324 切片 B — repair-01 evidence

日期：2026-09-18　branch：`cc/ssp324-revision-dedup`

```
base            72ac78d
original_review 2b7dcef（審的是 72ac78d..3119fa1）
repair_commit   （本次 commit，待 push 後補上）
```

## Reviewer NO_GO（對 `3119fa1`）

```
P0=0 / P1=3 / P2=1 / P3=0
```

1. **P1**：A/B layering 只是宣稱，沒有組合 enforcement——B 正例的 package
   只有 3/20 欄仍 PASS，額外塞 `extra_secret` 也 PASS。aggregator 只是
   分別跑兩組 fixtures。
2. **P1**：「`content_hash` 必須改」這條規則是錯的——A 的 hash 只 hash
   `content_snapshot`，而父卡明確允許 new evidence／redaction／policy／
   applicability／risk 變化形成 revision，內容本身可以沒改。這條會誤殺
   合法 revision。
3. **P1**：第二筆以後仍可再次宣稱 `UNSEEN / INITIAL_SUBMISSION`——只要求
   「第一筆必須 UNSEEN」，沒有反向要求「UNSEEN 只能是第一筆」。
4. **P2**：`submission_id` 沒有 uniqueness。

裁決同輪確認：`NO_RESEND`／`LOCAL_RECURRENCE_ONLY` 不需 Owner freeze；
「信封、不動封包」架構正確；陣列順序不判 blocker，`submitted_at` 單調性
需先明定 timestamp 格式／clock 語意，現在不加武斷比較。

## 修法

### F-01：真的共用 evaluator，不是「同掛 aggregator」

把切片 A 的封包 evaluator 抽成
`scripts/lib/minimal_evidence_package_shape.rb`，A 與 B 都呼叫同一支
`MEPShape.package_failure`。B 在每筆 submission 上呼叫它，失敗即
`PKGREV_PACKAGE_FAILS_SLICE_A_CONTRACT`。上游綁定也改用同一支
`build_bindings`，兩片不可能各自讀出不同版本的上游。

**抽取是行為逐字不變的**，並且有證據：

```
golden harness（A 的 39 筆 fixtures + 5 組多重違規順序敏感度組合）
repair 前 vs repair 後：42/42 逐字相同，diff 無輸出
```

多重違規組合是關鍵——它證明 refactor 沒有改動檢查順序（例如
`mismatch+bad_evidence_ref` 前後都回 `MEP_PACKAGE_REF_MISMATCH`，
而不是變成 evidence-ref 的錯誤）。

A 的 `transmission_failure` 拆成 `access_request_failure`（取得路徑，
留在 A）＋ 共用的 `package_failure`，兩支各自受 `LoopReturnContract` 出口
形狀凍結約束，A 的 `ERROR_CONTRACT` 斷言改成兩者可達 code 的聯集。

**組合證明**（這是 review 要的東西）：

```
在共用 helper 裡中和 MEP_PACKAGE_UNKNOWN_FIELD 一個 guard：
  切片 A      → FAIL MEP_NEG_PACKAGE_UNKNOWN_FIELD
  切片 B      → FAIL PKGREV_NEG_PACKAGE_EXTRA_FIELD
  aggregator  → FAIL ... slice validate_evidence_package_revision_contract exited 1
一個 guard 同時讓兩片轉紅——舊架構下不可能。
```

### F-02：刪掉「content_hash 必須改」

整條移除，連同 `PKGREV_CONTENT_HASH_UNCHANGED` 錯誤碼與其 fixture。是否
可送完全由上游 disposition 決定，不以 hash 有沒有動當必要條件。新增正例
`PKGREV_POS_REVISION_WITH_UNCHANGED_CONTENT_HASH`：內容未變、
`redaction_ref` 與 `sensitivity` 改變的 `CORRECTION_SUPERSESSION_PROPOSAL`
——repair 前會被誤殺，現在正確放行。

### F-03：UNSEEN 只能是第一筆

補上反向檢查 `PKGREV_REPEATED_INITIAL_SUBMISSION`。這是這條線一再出現的
同一種洞（只檢查單向），所以我順手把同族的對稱性全掃了一遍：
「第一筆不得 supersede／後續必須 supersede」✅ 已對稱、
「correction disposition 必須帶 correction 欄位／非 correction 不得帶」✅
已對稱、「package_id 唯一／submission_id 唯一」← 由 P2 補齊後對稱。

### P2：`submission_id` 唯一

新增 `PKGREV_DUPLICATE_SUBMISSION_ID`。

### 契約文字同步

`layering_boundary` 改寫成實際 enforcement（含「aggregator 不是
composition」這個教訓）；`chain_rules` 移除 content_hash 那句、補上
UNSEEN 單向檢查的說明；新增
`package_evaluator_shared_with: scripts/lib/minimal_evidence_package_shape.rb`
指回共用實作。

## 重播 reviewer 的 repro

```
baseline（完整封包的兩筆鏈）                      → nil
package 只有 3/20 欄                              → PKGREV_PACKAGE_FAILS_SLICE_A_CONTRACT
package 額外塞 extra_secret                       → PKGREV_PACKAGE_FAILS_SLICE_A_CONTRACT
內容未變但 redaction/sensitivity 改的合法 revision → nil（repair 前被誤殺）
第二筆再宣稱 UNSEEN/INITIAL_SUBMISSION            → PKGREV_REPEATED_INITIAL_SUBMISSION
兩筆共用同一個 submission_id                      → PKGREV_DUPLICATE_SUBMISSION_ID
```

## 逐 return site parity（非逐 code）

```
共用 helper（MEP_，A 與 B 任一轉紅即算守住）  22 sites → 22/22 全紅
切片 A 自身（access_request）                  4 sites → 4/4 全紅
切片 B（PKGREV_）                             22 sites → 22/22 全紅
```

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
golden（切片 A 行為逐字不變）          → 42/42 相同
```
