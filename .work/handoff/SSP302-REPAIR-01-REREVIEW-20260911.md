# SSP-302 Repair 01 — 定點 re-review 交付包

同一條 review line。只收 `SSP302-F-01`。

## 1. 鎖定

```
base                096cea3
original_review     19b099bd3bb14325d1b6cca6c22b1d0535bbf505   （immutable，未改寫）
repair_commit       cf62d640b78000bb2516526bb4bb75d1afb34a04
branch              cc/ssp302-error-code-coverage
```

定點 diff：`git diff 19b099b..cf62d64`

## 2. 只審這個

`SSP302-F-01`（P2）：source scan 語法特定，低估 evaluator 實際可回傳集合。

你已裁決、本輪不必重開：code-level coverage assertion 可接受、
三個 `LOOP_EXCEEDS_AUTHORITY` return site 都有負例、17 條 guard parity 全紅、
不需要 branch-level coverage machinery。

## 3. 修法 —— 採你給的第二條路

我選 (b)「明確機器限制 evaluator 只能採用 scanner 可辨識的 return 形式」，不選 (a)。
理由寫在 evidence：用 regex 涵蓋 Ruby 全部 return 語法本質上做不完，
做了也只是換一個更難察覺的 under-approximation。

```ruby
ALLOWED_EVALUATOR_RETURN = /\Areturn (?:nil|"[A-Z][A-Z0-9_]*")(?:\s+(?:if|unless)\b.*)?\z/
```

evaluator 內每一條 `return` 只能是 `return nil` 或 `return "<CODE>"`，違反即轉紅。
另把 scanner 放寬到單引號，讓單引號 code 被兩層各自攔下。
YAML `error_contract_binding.evaluator_return_form_rule` 記錄這個限制。

**既有 evaluator 判斷邏輯逐字未改** —— 現有 17 條 return 本來就全部符合白名單，
沒有為了通過檢查而改寫任何判斷。請確認：

```
git diff 19b099b..cf62d64 -- scripts/validate_ai_work_record_loop_contract.rb
```

diff 應只有新增常數／函式／斷言，`loop_closeout_failure` 函式本體不變。

## 4. 請重播 —— Bypass mutation

在 evaluator 插入以下各種合法 Ruby return，逐一跑完整 validator。
我的結果：**7 RED / 0 GREEN（全部 assertion-RED）**。

```ruby
B1  return 'LOOP_UNDECLARED' if run["x"] == true          # 你指定的案例
B2  return "LOOP_UNDECLARED" if run["x"] == true
B3  return "LOOP_#{run["x"]}" if run["x"] == true
B4  return EXPECTED_OUTCOMES.first if run["x"] == true
B5  return run["x"].to_s if run["x"] == true
B6  return 'LOOP_UNBOUNDED' if run["x"] == true           # 單引號但 code 已宣告
B7  return %w[LOOP_UNDECLARED].first if run["x"] == true
```

## 5. 主動回報：哪一層真的攔下哪一個

我把形式白名單斷言移除後重跑同一組，實測（不是推論）：

| probe | 完整 | 移除白名單 | 白名單是否唯一防線 |
| --- | --- | --- | --- |
| B1 | RED | RED | 否 |
| B2 | RED | RED | 否 |
| B3 | RED | **GREEN** | **是** |
| B4 | RED | **GREEN** | **是** |
| B5 | RED | **GREEN** | **是** |
| B6 | RED | **GREEN** | **是** |
| B7 | RED | **GREEN** | **是** |

也就是說：**你舉的那個例子（B1），單靠把 scanner 放寬到單引號就能擋掉**，
白名單在 B1 上是冗餘的。白名單真正不可取代的是 B3~B7 ——
那五類回傳的 code 是 regex 在原理上看不見的。

我沒有只做能過你那一題的最小修正，理由就是這張表。
如果你認為只需放寬 scanner、白名單是過度工程，請提出來。

## 6. 回歸（全部維持）

| 項目 | 結果 |
| --- | --- |
| 逐 code 改名 parity（15 個） | 15 RED / 0 GREEN |
| Guard parity（17 條 return site） | 17 RED / 0 GREEN，assertion 15 / exception 2 |
| 既有判定（對比修正前 `main` 的 24 案） | exact code 逐字相同，只新增本卡的 4 案 |
| Ruby validators | 21 PASS / 0 FAIL |
| 四支 Python engine | 全 PASS |
| `git diff --check` | clean |

## 7. 主動回報：檔案大小

validator 現 **390 行**，仍在 `< 400` 硬上限內，但只剩 10 行。
下次再往這支加東西應先進 Refactor Mode（候選：三個 error-contract 綁定斷言抽成函式）。
本輪不順手重構，那會擴大 repair 的 blast radius。

## 8. 邊界（未變）

沒有做 branch-level coverage machinery、沒有改既有錯誤語意或 evaluator 判斷邏輯、
沒有重開 F-04 / F-05、沒有動上游、沒有新增 package。

請就 `SSP302-F-01` 給 `GO` 或 `NO_GO`。
