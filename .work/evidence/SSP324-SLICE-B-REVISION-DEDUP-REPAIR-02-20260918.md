# SSP-324 切片 B — repair-02 evidence

日期：2026-09-18　branch：`cc/ssp324-revision-dedup`

```
base            72ac78d
repair-01       15074ce（delivery f250451）
repair_commit   5db98e0
```

## Reviewer NO_GO（對 `f250451`）

```
P0=0 / P1=1 / P2=0 / P3=1
```

**P1 — dedup／resend 仍可被自報 classification 繞過。** 上游明訂
`category`／`disposition` 不得由 caller 宣告、必須從 primitive signals
推導，但切片 B 直接讀 `submission["comparison_category"]` 與
`submission["disposition"]`，只驗兩者是不是合法配對。reviewer 的 repro：
content_hash／evidence_refs／redaction_ref／sensitivity 全部與前一份相同，
只有新的 identity 與 timestamp，自報 `MATERIALLY_CHANGED` ＋ 合法的
`CORRECTION_SUPERSESSION_PROPOSAL` ＋ 合法 correction metadata → **通過**。
等於沒有證明任何 material effect 就送出 revision，直接穿過父卡
Acceptance #7。

裁決：「不要再複製規則，讓 B 實際消費 historical-comparison evaluator 的
推導結果。現在這版只有『詞彙綁定』，沒有『結果綁定』。」

**P3** — 前一份 handoff 把切片 A 的 fixture 數寫成 39，實際是
3 positive + 34 negative = 37。

repair-01 的四筆 finding 經 reviewer 重播確認全數關閉；切片 A 的 refactor
獲接受，不需另開 refactor 卡。

## 修法：結果綁定，不是詞彙綁定

### 1. 把切片 1 的推導抽成共用 helper

`scripts/lib/historical_comparison_derivation.rb`（`compute_signals`／
`historical_comparison_failure`／`classify`）。切片 1 改為呼叫它，
**行為逐字不變**：golden harness（切片 1 的 22 筆 fixtures ＋ 5 組多重違規
順序敏感度）27/27 相同。切片 1 的 `LoopReturnContract` 綁定改指向 helper。

### 2. 切片 B 不再接受自報分類

`comparison_category`／`disposition` 從 `submission_allowed_fields`
移除，改列入 `forbidden_self_declared_fields`：夾帶即
`PKGREV_SELF_DECLARED_CLASSIFICATION`（與切片 1／2 對自報分類的處理
一致）。契約另有斷言確保這兩份清單不重疊。

### 3. 改送 primitive signals，由共用 evaluator 推導

submission 改帶 `comparison`（prior/current identity、content hash、
evidence_refs 集合、以及**有實證的** material_effect／contradicts_prior）。
B 先呼叫 `HCD.historical_comparison_failure`（失敗即
`PKGREV_COMPARISON_FAILS_SLICE_1_CONTRACT`），再呼叫 `HCD.classify` 取得
推導出的 category／disposition，後續所有規則都作用在**推導結果**上。

### 4. primitives 必須綁回這條鏈，否則只是把自報往上挪一層

- `comparison.current_content_hash` 必須等於本筆封包的 `content_hash`
  （`PKGREV_COMPARISON_HASH_NOT_BOUND_TO_PACKAGE`）
- 後續筆的 `comparison.prior_content_hash` 必須等於鏈上前一份封包的
  `content_hash`（`PKGREV_COMPARISON_PRIOR_NOT_BOUND_TO_CHAIN`）

## 重播 reviewer 的 P1 bypass

```
自報 MATERIALLY_CHANGED（實質全同）        → PKGREV_SELF_DECLARED_CLASSIFICATION
  SAME_CONTENT_HASH=true / SAME_EVIDENCE_REFS=true
  SAME_REDACTION=true / SAME_SENSITIVITY=true
同一情境改送真實 primitives                → PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE
                                            （推導為 UNCHANGED / NO_RESEND）
宣稱 material_effect 但無 reasons/evidence → PKGREV_COMPARISON_FAILS_SLICE_1_CONTRACT
```

三層都擋住：自報路徑不存在、真實 primitives 會推導出「不要送」、
宣稱 material effect 必須有 dimension reasons ＋ URN evidence 才成立。

## 組合證明

```
在共用推導 helper 裡中和 COMPARISON_EVIDENCE_REF_NOT_URN 一個 guard：
  切片 1      → FAIL HC_NEG_EVIDENCE_REF_NOT_URN
  切片 B      → FAIL PKGREV_NEG_COMPARISON_FAILS_SLICE_1
  aggregator  → FAIL ... validate_evidence_package_revision_contract exited 1
```

（repair-01 已對封包 evaluator 做過同樣的證明：中和
`MEP_PACKAGE_UNKNOWN_FIELD` 會同時讓切片 A 與切片 B 轉紅。）

## 一併移除的 dead code

第一筆若 category 推導為 `UNSEEN`，依定義就是 `no_prior_record`，所以
原本想加的「第一筆 prior_record_ref 必須為 nil」永遠不可達——移除，不留
驗不到的宣告。

## 逐 return site parity（非逐 code）

```
共用推導 helper（COMPARISON_）  14 sites → 14/14 全紅
共用封包 helper（MEP_）          22 sites → 22/22 全紅
切片 A（access_request）          4 sites → 4/4 全紅
切片 B（PKGREV_）                25 sites → 25/25 全紅
```

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
golden：切片 1 → 27/27 相同；切片 A → 42/42 相同
```

## Fixture 計數（P3 修正）

```
切片 A：3 positive + 34 negative = 37（前一份 handoff 誤寫 39）
切片 B：4 positive + 27 negative = 31
```
