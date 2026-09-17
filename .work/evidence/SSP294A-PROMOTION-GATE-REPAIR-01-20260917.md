# SSP-294 切片 A repair-01 — evidence

回應 `c8a8511` 的 NO_GO（P1×1 ＋ P2×1）。兩筆都收。

## P1：`declared_paths` fail-open

屬實，而且是**同型錯誤第六次**：我寫 `run["declared_paths"].to_a`——把輸入
前處理掉，型別資訊就消失了。

| 輸入 | 修正前 | 原因 |
|---|---|---|
| `{"direct_copy_to_shared_canonical": true}` | **PASS** | Hash `.to_a` 變成 `[[k,v]]`，比不中任何 forbidden 字串 |
| 整個省略 | **PASS** | `nil.to_a` = `[]`，forbidden 檢查等於沒跑 |
| `"direct_copy_to_shared_canonical"` | **NoMethodError** | String 沒有 `to_a` |

三條 forbidden 的核心 enforcement 因此可被輸入型別繞過。

修法：先 fail-closed 鎖型別，再比對。

```ruby
declared_paths = run["declared_paths"]
return "PROMOTION_DECLARED_PATHS_NOT_LIST" unless declared_paths.is_a?(Array)
return "PROMOTION_DECLARED_PATHS_NOT_LIST" unless declared_paths.all? { |p| p.is_a?(String) }
```

重播三個案例：

```
A. Hash（6 條件全備齊）→ PROMOTION_DECLARED_PATHS_NOT_LIST
B. 整個省略            → PROMOTION_DECLARED_PATHS_NOT_LIST
C. String              → PROMOTION_DECLARED_PATHS_NOT_LIST（不再 NoMethodError）
```

新增三個負例釘住：缺欄位／Hash／陣列含非字串元素。

## P2：provenance boundary 少界定一件事

屬實。原本只承認「receipt 真實性不驗」，但 `declared_paths` 同樣是 caller
自述——本層擋得住「宣告了 forbidden path」，擋不住「刻意漏報真正用過的
forbidden path」。

`does_not_verify` 改成列出兩件事，並在 `rule` 裡寫明：要證明升格實際走了哪條
路徑，需要本系統沒有的執行紀錄；漏報因此是呼叫端責任，**先講清楚而不是等
review 抓**。結構斷言也跟著改成驗這兩項都在。

## 同型錯誤第六次

`.to_a` 是「比對的對象被自己前處理過」的又一個變體。前五次：整份文字判定
綁定／pointer prefix 太鬆／用現行名稱過濾後比對／被驗方界定檢查範圍／
`split(".")` 吃掉尾端空 segment。

這次的具體形狀是 **Ruby 的寬容轉型**（`nil.to_a`、`Hash#to_a`）默默把「格式
不對」變成「空的／不同形狀但合法」。之後寫 evaluator 時，任何 `.to_a`／
`.to_s`／`.to_h` 出現在**被驗資料**上都應該先問：這是不是在替 caller 把錯誤
輸入圓成合法輸入。

## Gate

```
ruby scripts/validate_*.rb（28 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
逐 return site parity（8 個）         → 8/8 全紅
```

## 依 reviewer 指示登 backlog、未在本輪修

「禁止重述」用全文 substring 掃描偏脆（條件名若是常見英文詞會誤殺、拆行書寫
會漏判）。長期應改成驗結構——檢查契約有沒有重新宣告一個內容等同上游的清單。
已登 `文件/待辦重整.md` 規範債表，含成因與建議修法。
