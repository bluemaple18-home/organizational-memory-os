# SSP-323 切片 1 — repair-01 evidence

日期：2026-09-18　branch：`cc/ssp323-historical-comparison`

```
base            38b5d59   （既有 evidence/handoff 誤記 63464c3；worktree 建立時
                           main 已推進到 38b5d59，見下方「SHA 校正」）
original_review 0205d7b
repair_commit   （本次 commit，待 push 後補上）
```

## SHA 校正

`.work/evidence/SSP323-SLICE1-HISTORICAL-COMPARISON-20260917.md` 與
`.work/handoff/SSP323-SLICE1-HISTORICAL-COMPARISON-REVIEW-20260917.md` 記的
`base: 63464c3` 不是這條分支實際的 base——`63464c3` 是「SSP-294 切片 C 驗收」
commit。分支建立當下 `main` 已經因為 Owner 直接推的 SSP-323/324 決策文件
（`7ef51cf` → `e4a4240` → `38b5d59`）往前走了三個 commit。

```
git merge-base main cc/ssp323-historical-comparison
→ 38b5d598c8787c9ba45f9cf2c617b86faf6ca478
```

原始兩份文件不重寫（保留當時記錄），本次起 base 一律用 `38b5d59`。

## Reviewer NO_GO（2026-09-18，對 `0205d7b`）

```
P0=0 / P1=3 / P2=1 / P3=0
```

1. **P1**：`contradicts_prior` 的 `contradiction_reasons` 沒有比對
   `material_effect_dimensions` allowlist——`material_effect` 有 allowlist
   檢查，`contradicts_prior` 卻沒有，任意文字就能讓優先序最高的
   `CONTRADICTED` 成立。
2. **P1**：`classify()` 不是 total function——至少兩個具體輸入會落到
   「不應該到得了這裡」分支，回傳看起來合法的 `{category: nil,
   disposition: nil}`。
3. **P1**：`evidence_refs` 若不是 Array（例如直接送 scalar 字串），
   `compute_signals` 的 `.to_set` 會直接 `NoMethodError` 當掉，不是
   fail-closed 拒絕。
4. **P2**（residual，reviewer 明示留著）：`category`／`disposition` 若被
   呼叫端在 run 裡直接夾帶，會被靜默接受但忽略。

Reviewer 結論：「repair-01 建議只收這三筆 P1；P2 可留 residual。」

## 修法

### F-01（P1-1）：`contradiction_reasons` 補 dimension allowlist

`historical_comparison_failure` 的 `contradicts_prior` 分支，在既有
`reasons.is_a?(Array) && !reasons.empty?` 檢查後，新增：

```ruby
return "COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION" unless reasons.all? { |r| material_dimensions.include?(r) }
```

與 `material_effect` 分支完全對稱。

### F-02（P1-2）：讓 `classify()` 成為 total function

不是在 `classify()` 裡加防禦分支（那只是把 nil/nil 換一種寫法），而是在
`historical_comparison_failure` 補齊兩條 fail-closed 檢查，讓「會走到
`classify()` 卻沒有分支接住」的輸入在更早就被拒絕：

1. `prior_record_ref` 存在時，`prior_content_hash` 不得缺——新增
   `COMPARISON_MISSING_PRIOR_HASH`。
2. 有 prior record、`current_content_hash` 真的跟 `prior_content_hash`
   不同，卻沒有 `has_new_evidence`、沒有宣告 `material_effect`、也沒有
   宣告 `contradicts_prior`——代表資料本身缺乏解釋，新增
   `COMPARISON_HASH_CHANGED_WITHOUT_EXPLANATION`。

證明「這樣就總是能推導」：`classify()` 走到 5 個具名分支前，
`historical_comparison_failure` 已保證 hash 沒變（否則早被 F-02 的第 2 條
擋下），所以 `identical_to_prior` 必為 true，一定會命中 `UNCHANGED` 分支。
`classify()` 尾端的防禦分支改成 `raise`（fail loud），不再回傳 nil/nil。

### F-03（P1-3）：`evidence_refs` 陣列形狀先鎖

在 `compute_signals` 可能被呼叫之前（`historical_comparison_failure` 較早
的位置），新增：

```ruby
[run["prior_evidence_refs"], run["current_evidence_refs"]].each do |refs|
  next if refs.nil?
  return "COMPARISON_EVIDENCE_REFS_NOT_ARRAY" unless refs.is_a?(Array)
end
```

`nil`（欄位未提供）合法放行（沿用既有 `|| []` 語意），非 `nil` 又非
`Array` 一律 fail-closed 拒絕，不讓 scalar 字串有機會進到 `.to_set`。

### P2（residual，未修）

`category`／`disposition` 若被 run 夾帶會被忽略但不拒絕——已登
`文件/待辦重整.md` 的規範債 backlog 表格，依 reviewer 指示本輪不動。

## Fixture 變更

- 修正兩個既有正例（`HC_POS_CONTRADICTED`／
  `HC_POS_CONTRADICTION_PRECEDENCE_OVER_NEW_EVIDENCE`）：`contradiction_
  reasons` 原本是自由文字（不在 `material_effect_dimensions` 內），F-01
  補上 allowlist 檢查後這兩筆正例會被誤判為負例——改成合法 dimension
  值（`conflict_determination`／`conclusion`）。
- 修正既有負例 `HC_NEG_CONTRADICTS_NO_EVIDENCE`：`contradiction_reasons`
  原本用 `["x"]`（不在 allowlist 內），F-01 補上檢查後這筆會在
  dimension 檢查就被攔下，蓋不到原本要測的「缺 evidence_refs」路徑——
  改成合法 dimension 值 `["risk"]`，讓這筆負例繼續只測 evidence_refs
  缺失。
- 新增 4 筆負例：`HC_NEG_CONTRADICTS_UNRECOGNISED_DIMENSION`（F-01）、
  `HC_NEG_MISSING_PRIOR_HASH`（F-02 第 1 條）、
  `HC_NEG_HASH_CHANGED_WITHOUT_EXPLANATION`（F-02 第 2 條，對應 reviewer
  指出的兩個 nil/nil 具體輸入之一）、`HC_NEG_EVIDENCE_REFS_NOT_ARRAY`
  （F-03，reviewer 指出的第三個 P1 原始 repro）。
- `EXPECTED_NEGATIVE_LABELS` 同步補 4 個 label；`ERROR_CONTRACT` 同步補 3
  個新錯誤碼。

## 逐 return site parity（非逐 code）

`historical_comparison_failure` 目前 14 個 return site（repair 前 10 個，
本輪新增 4 個）。逐一中和、確認 RED、還原、確認逐位元相同：

```
line  84  COMPARISON_FORBIDDEN_LIFECYCLE_FIELD          → RED
line  86  COMPARISON_MISSING_CURRENT_HASH                → RED
line  89  COMPARISON_PRIOR_RECORD_INCONSISTENT            → RED
line  92  COMPARISON_MISSING_PRIOR_HASH        [新]       → RED
line 100  COMPARISON_EVIDENCE_REFS_NOT_ARRAY    [新]       → RED
line 104  COMPARISON_EVIDENCE_REF_NOT_URN                 → RED
line 110  COMPARISON_JUDGMENT_WITHOUT_PRIOR                → RED
line 115  COMPARISON_JUDGMENT_UNSUBSTANTIATED (material)   → RED
line 116  COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION (material) → RED
line 119  COMPARISON_JUDGMENT_UNSUBSTANTIATED (material evidence) → RED
line 124  COMPARISON_JUDGMENT_UNSUBSTANTIATED (contradicts)  → RED
line 128  COMPARISON_JUDGMENT_UNRECOGNISED_DIMENSION (contradicts) [新] → RED
line 131  COMPARISON_JUDGMENT_UNSUBSTANTIATED (contradicts evidence) → RED
line 143  COMPARISON_HASH_CHANGED_WITHOUT_EXPLANATION [新] → RED

14/14 全紅，未被測到：無。中和後每次都用 diff 對原始備份確認還原逐位元相同。
```

## 接回總入口的實測（新增，回應「不只驗直接呼叫」要求）

不只中和後對「直接呼叫 `validate_historical_comparison_contract.rb`」驗證
RED，額外對「呼叫總入口 `validate_personal_memory_contract.rb`」重跑一次：

```
中和 line 143（COMPARISON_HASH_CHANGED_WITHOUT_EXPLANATION，本輪新增的
guard 之一，挑作代表）：

直接呼叫新片   → FAIL HC_NEG_HASH_CHANGED_WITHOUT_EXPLANATION 預期 deny，實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_historical_comparison_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

證明本輪新增的三個 guard 不是只在切片自己的測資迴圈裡生效，聚合器確實會
轉發子驗證器的失敗。

## Gate

```
ruby scripts/validate_*.rb（31 支，含本片）→ 全部 PASS
4 支 Python schema engine                    → 環境缺 jsonschema 模組
                                                （pre-existing，與本次修改
                                                無關，未安裝 venv，本輪未
                                                改動任何被這三支涵蓋的檔案）
git diff --check                              → clean
```

## 明確不在本輪範圍

- P2（`category`／`disposition` 被夾帶但忽略）——已登 backlog，reviewer
  指示留 residual。
- 平台中立本機邊界（切片 3）、Organizational Value Assessment（切片 2）：
  與原卡相同，未變。
