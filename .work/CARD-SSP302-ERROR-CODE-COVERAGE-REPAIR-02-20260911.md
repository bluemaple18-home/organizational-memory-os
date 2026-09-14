---
id: SSP302-ERROR-CODE-COVERAGE-REPAIR-02-20260911
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
review_line: SSP-302 error-code 契約完整性
original_review_sha: 19b099bd3bb14325d1b6cca6c22b1d0535bbf505
previous_repair_sha: cf62d640b78000bb2516526bb4bb75d1afb34a04
base_sha: 096cea3
verdict_being_repaired: NO_GO (P0=0, P1=0, P2=1, P3=0)
tier: T1
blocker_attempt: 2
hard_stop: >-
  SSP302-F-01 已連續兩輪 NO_GO。依全域規則「同一 blocker 第 3 次失敗即停」，
  若本輪再被判 NO_GO，不得再開 repair-03：直接轉 Owner spec-freeze（T2），
  由 Owner 裁決「validator 完整性要驗到什麼程度」這個規格問題。
---

# SSP-302 Repair 02 — SSP302-F-01 改用語法樹求 return site

👉 [假設與目標確認]
- 目標：只收 `SSP302-F-01`。停止用 regex 逼近 evaluator 的 return site。
- 邊界：不做 branch-level coverage machinery（reviewer 兩輪都明說不需要）；
  不改既有錯誤語意或 evaluator 判斷邏輯；不重開 F-04 / F-05；不動上游；不新增外部套件。
- 驗收：reviewer 指定的 `if run["x"]; return EXPECTED_OUTCOMES.first; end` 必須 RED，
  且其他 return 位置形式一併 RED。

## 為什麼不再補 regex

repair-01 被判 NO_GO 的理由，與原始 finding 是同一句話的兩個實例：

| 輪次 | regex 的假設 | 被繞過的合法 Ruby |
| --- | --- | --- |
| 原始 | return 一定寫成雙引號字面量 | `return 'LOOP_UNDECLARED'` |
| repair-01 | return 一定在「以 return 開頭的實體行」 | `if run["x"]; return CONST; end` |

再補一次 regex，只會把漏洞推到下一種合法語法（`x and return y`、block 內 return、
三元運算子、heredoc……）。這與 Document Adapter Mapping 那條 review line 連錯六輪
的結構完全一樣：問題不在少驗了哪一個 case，而在**分類本身不是全集**。

## 修法

改用 `Ripper`（Ruby stdlib，不新增相依）解析 validator 自身，
取得 `loop_closeout_failure` 的**全部 return site**，再逐一分類。
return site 是窮舉出來的，不是猜的。

新檔 `scripts/lib/loop_return_contract.rb`（123 行）：

- `evaluator_def_node` —— 從語法樹找出 evaluator 定義（連函式本體的擷取都不再用 regex）。
- `return_nodes` —— 走訪子樹收集所有 `:return` / `:return0`。
- `classify` —— 每個 return 只能是 `return nil`，或 `return` 單一且無插值的字串字面量
  且符合 `<CODE>` 命名；其餘一律 `DISALLOWED`。
- `reachable_codes` / `disallowed_returns` —— 供 validator 使用。

validator 從 371 行降到符合 `< 400`（原 390 行，逼近上限的問題一併解掉）。

## 刻意的放寬（請 reviewer 裁決）

repair-01 禁止單引號，那是**為了遷就 regex 看不見單引號**才加的限制。
語法樹看到的是字串的值，單引號 code 會被正確列入可回傳集合，不會有未被計入的 return，
所以這條限制失去理由，已移除。契約文字同步改寫成實際 enforce 的性質
（「單一、無插值的字串字面量」），不再提引號風格。

後果：`return 'LOOP_UNBOUNDED'`（單引號、code 已宣告）現在是 GREEN。
這不是繞過 —— 那個 return 有被算到，且它回傳的是已宣告的 code。
若 reviewer 認為風格一致性仍須機器強制，那是另一條 finding，不是完整性缺口。
