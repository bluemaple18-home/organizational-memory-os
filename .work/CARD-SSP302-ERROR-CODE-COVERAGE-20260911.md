---
id: SSP302-ERROR-CODE-COVERAGE-20260911
status: AWAITING_BIG_REVIEW
type: implementation
jira: SSP-302（後續強化第二輪，原卡與 TIGHTEN 皆已 ACCEPTED_GO）
lane: B
tier: T1
origin: "SSP302-CONTRACT-TIGHTEN 大 review（8d9c829）的 TIGHTEN-F-01（P2）+ TIGHTEN-F-02（P3），reviewer disposition = NON_BLOCKING_BACKLOG"
---

# SSP-302 error-code 契約完整性 + 控制測資對齊

👉 [假設與目標確認]
- 目標：把 `SSP302-CONTRACT-TIGHTEN` 留下的兩個非阻塞 finding 收乾淨——
  (1) `EXPECTED_LOOP_ERROR_CODES` 漏了 `LOOP_MISSING_FIELD`，且該斷言驗的是「YAML 清單 ==
  手寫常數清單」而非其宣稱的「YAML 清單 == evaluator 完整回傳集合」；
  (2) 控制正負例實際差四欄，與 handoff／evidence 宣稱的「只差 terminal_condition 一欄」不符。
- 邊界：不改任何既有錯誤語意（`LOOP_MISSING_FIELD` 的行為原樣保留）；不重開 F-04 / F-05；
  不動上游；不新增 outcome 值。
- 驗收：見 Acceptance。

## Objective

### 1. TIGHTEN-F-01（P2）—— error-code 契約完整性

reviewer 實證：從合法 run 刪除 `iterations` / 設為 `null` / 設為非 Array，三次都得到
`LOOP_MISSING_FIELD`；但該 code 不在 `EXPECTED_LOOP_ERROR_CODES`（14 個）也不在 YAML
`error_contract`（14 個）。兩張清單互相比較會通過，所以把這個未宣告的 `return` **改名**，
完整 gate 仍然綠 —— 斷言驗錯了對象。

收法：
- `LOOP_MISSING_FIELD` 補進常數與 YAML `error_contract`（15 個）。**不得**為了湊回 14 個而
  改掉既有錯誤語意。
- 新增 exact-code 負例：`iterations` 缺欄 / 非 Array → `LOOP_MISSING_FIELD`。
- 把斷言從「常數 vs YAML」升級為**真正的覆蓋檢查**：由 evaluator 原始碼掃出所有可達的
  `return "<CODE>"` literal，與 YAML `error_contract` 的 key 集合比對。這樣未來新增／改名
  任一 return 而未同步宣告，gate 會自動轉紅（本輪缺口的根因就是缺這層）。
- `required_negative_fixtures` 同步 +1 label。

### 2. TIGHTEN-F-02（P3）—— 控制測資與證據對齊

`LOOP_POS_MAX_ITERATIONS_WITH_ORDINARY_GAP` 與 `LOOP_NEG_REQUIRED_PRESENT_WITH_GAPS`
實際差四欄（`max_iterations` 2/5、`timeout_seconds` 120/300、`elapsed_seconds` 95/110、
`terminal_condition`）。

收法：由正例的 `run` 複製出負例，**只替換 `terminal_condition`**，`expected` 與 case
metadata 另外設定，讓測資本身就支撐「單欄翻轉」的描述。

## Root question

如何讓 error-code 宣告與 evaluator 實際可回傳集合成為機器綁定（而非兩張手寫清單互比），
並讓控制測資真的只差一個欄位？

## Traces to

- `.work/evidence/SSP302-CONTRACT-TIGHTEN-REVIEW-20260910.yaml`（TIGHTEN-F-01 / F-02）
- `規格/v0.1/ai-work-record-loop.yaml`、`scripts/validate_ai_work_record_loop_contract.rb`
- Requirement ID：`SSP302-COVERAGE-S01`

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP302-CONTRACT-TIGHTEN` = `ACCEPTED_GO` + merged（`5201f1e`）。
- Blockers：無。
- Current frontier：`SSP302-COVERAGE-S01`。

## Constraints

- 不改既有錯誤語意、不重開 F-04 / F-05、不動上游、不新增 outcome 值、不新增 package。
- validator 維持 `< 400`。推 branch，不 merge。
- 原始碼掃描只針對 evaluator 函式本體，避免掃到註解或其他函式的字串。

## Acceptance

1. `LOOP_MISSING_FIELD` 進常數與 YAML `error_contract`；既有行為與錯誤碼不變。
2. 新負例：`iterations` 缺欄 / 非 Array → exact code `LOOP_MISSING_FIELD`。
3. 覆蓋斷言：把 evaluator 任一 `return "<CODE>"` 改名而未同步 YAML → gate 轉紅
   （這是本卡的關鍵 parity，必須實測）。
4. 控制負例由正例複製，diff 僅 `terminal_condition`（+ `expected` / metadata）。
5. 既有 6 正例 / 18 負例判定與 exact code 完全不變。
6. 全 20 validator + schema engine + cross-layer + `git diff --check` 全 PASS。

## Stop conditions

- 若原始碼掃描無法穩定辨識可達 return（例如出現動態組出的 code），停，回 Owner 討論改用
  其他綁定方式，不要放寬成「大約涵蓋」。

## Likely files

- `規格/v0.1/ai-work-record-loop.yaml`
- `scripts/validate_ai_work_record_loop_contract.rb`
- `規格/v0.1/fixtures/ai-work-record-loop-{positive,negative}-fixtures.json`
- `文件/待辦重整.md`
- `.work/evidence/SSP302-ERROR-CODE-COVERAGE-20260911.md`

## Evidence

`.work/evidence/SSP302-ERROR-CODE-COVERAGE-20260911.md`
