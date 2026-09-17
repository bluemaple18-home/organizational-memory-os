# SSP-294 切片 A repair-01 — 定點 re-review 交付包

同一條 review line。收 `c8a8511` 的 P1 ＋ P2。

## 鎖定

```
base                3706d09
original_review     c8a8511   （NO_GO，P1=1 / P2=1）
repair_commit       43afef5
branch              cc/ssp294-promotion-gate
```

## 收法

**P1**：`run["declared_paths"].to_a` 把型別資訊前處理掉——Hash 變 pair 陣列、
缺欄位變空陣列、String 直接炸。改成先 fail-closed 驗證必須是 string list，
再做 forbidden 比對。新增 `PROMOTION_DECLARED_PATHS_NOT_LIST` 與三個負例
（缺欄位／Hash／含非字串元素）。

**P2**：`provenance_boundary.does_not_verify` 改列兩項，補上
`THE_DECLARED_PATHS_ARE_COMPLETE`，並在 rule 寫明「擋得住宣告 forbidden
path，擋不住刻意漏報」。結構斷言跟著驗這兩項都在。

## 請重播（你的三個案例）

```
declared_paths = {"direct_copy_to_shared_canonical": true}，6 條件全備 → 應 FAIL
declared_paths 整個省略                                             → 應 FAIL
declared_paths = "direct_copy_to_shared_canonical"                  → 應 FAIL（非 NoMethodError）
```

我的結果三者皆 `PROMOTION_DECLARED_PATHS_NOT_LIST`；逐 return site parity
8/8 全紅。

## 依你的指示登 backlog、未在本輪動

「禁止重述」用全文 substring 掃描偏脆。已登 `文件/待辦重整.md` 規範債表，
記下成因（常見英文詞誤殺／拆行漏判）與建議修法（改驗結構而非掃 prose），
留待下次動到該 validator 時一併收。

## 同型錯誤第六次（自我檢討）

`.to_a` 是「比對對象被自己前處理過」的又一變體。這次的具體形狀是 **Ruby 的
寬容轉型默默把格式錯誤圓成合法輸入**。我把這條寫進 evidence：日後任何
`.to_a`／`.to_s`／`.to_h` 出現在被驗資料上，都要先問是不是在替 caller 補洞。

## Gate

```
ruby scripts/validate_*.rb（28 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```
