# SSP-302 error-code 契約完整性 + 控制測資對齊 — evidence

日期：2026-09-11　branch：`cc/ssp302-error-code-coverage`　base：`096cea3`

收 `SSP302-CONTRACT-TIGHTEN` 大 review（`8d9c829`）留下的兩個非阻塞 finding。

---

## TIGHTEN-F-01（P2）—— error-code 契約完整性

### 缺口的實測復現（修正前）

在**未修正的 `main`（`096cea3`）**上，把 evaluator 裡未宣告的 `LOOP_MISSING_FIELD`
整個改名，然後跑完整 validator：

```
perl -0pi -e 's/LOOP_MISSING_FIELD/LOOP_RENAMED_PROOF/g' scripts/validate_ai_work_record_loop_contract.rb
ruby scripts/validate_ai_work_record_loop_contract.rb
→ GREEN（PASS）
```

**gate 仍然綠。** reviewer 的判讀完全正確：原本的斷言比的是
`YAML error_contract` 與 `EXPECTED_LOOP_ERROR_CODES` 兩張**都由我寫的**清單，
兩邊同時漏掉 `LOOP_MISSING_FIELD`，所以互比會通過，卻證明不了 evaluator。

（測試後已用 `cp` 還原 `main`，`git status` 乾淨。全程未用 `git checkout --`。）

### 實際可回傳集合

掃 `loop_closeout_failure` 函式本體：**17 個 return site、15 個相異 code**。
原宣告 14 個 —— 差的正是 `LOOP_MISSING_FIELD`。

### 修法

1. `LOOP_MISSING_FIELD` 補進 `EXPECTED_LOOP_ERROR_CODES` 與 YAML `error_contract`（15 個）。
   **既有錯誤語意逐字未動** —— 沒有為了湊回 14 個而改行為。
2. 新增 `reachable_loop_failure_codes`：只掃 `loop_closeout_failure` 函式本體的
   `return "<CODE>"` literal，避免掃到註解、常數清單或其他函式的字串；掃不到任何 code
   視為掃描失效並轉紅。
3. 斷言升級成三層：
   - YAML `error_contract` keys **==** evaluator 原始碼實際可回傳集合（真正的綁定）
   - 該集合 **==** `EXPECTED_LOOP_ERROR_CODES`（鎖定集合，防止有人同時改兩邊而悄悄變更契約）
   - 每個 `error_contract` entry 必須宣告事件名
4. 常數上方的註解改寫，明說**這張清單不是完整性的證據來源**，真正的綁定在原始碼掃描。
   原註解宣稱它是「evaluator 可回傳的完整集合」，那句話當時就是不成立的。
5. YAML 新增 `error_contract_binding.rule` 記錄這個設計與它的由來。

### 修正後的 parity（關鍵驗收）

對 15 個 code 逐一**只在 evaluator 改名、不動 YAML**：

**15 RED / 0 GREEN（assertion 15 / exception 0）。**

含當初穿過去的 `LOOP_MISSING_FIELD` —— 同一個操作，修正前綠、修正後紅。

### 新負例

| case | 觸發 | exact code |
| --- | --- | --- |
| `LOOP_NEG_ITERATIONS_FIELD_ABSENT` | `iterations` 整欄不存在 | `LOOP_MISSING_FIELD` |
| `LOOP_NEG_ITERATIONS_NOT_A_LIST` | `iterations` 是 Hash 而非 Array | `LOOP_MISSING_FIELD` |

reviewer 原始重播的三種壞法，修正後逐一回傳正確的碼：

```
刪除 iterations       → "LOOP_MISSING_FIELD"
iterations = null     → "LOOP_MISSING_FIELD"
iterations = 非 Array  → "LOOP_MISSING_FIELD"
```

---

## 本輪新發現：兩條 authority 分支從未被負例踩到（主動回報）

guard parity 第一輪跑出 **2 個 GREEN(bad)**：

```
GREEN(bad)  line 145  LOOP_EXCEEDS_AUTHORITY   (run["performs_memory_acceptance"] == true)
GREEN(bad)  line 146  LOOP_EXCEEDS_AUTHORITY   (run["writes_company_knowledge"] == true)
```

`LOOP_EXCEEDS_AUTHORITY` 有三個 return site，但負例只踩到第三個
（`EXPECTED_FORBIDDEN_RUN_FIELDS`）。中和前兩條，gate 仍綠。

這與 TIGHTEN-F-01 是**同一類缺陷**：宣告層面看起來覆蓋了，分支層面沒有。
既然本卡就是收這類債，我一併補上兩個負例
（`LOOP_NEG_PERFORMS_MEMORY_ACCEPTANCE`、`LOOP_NEG_WRITES_COMPANY_KNOWLEDGE`），
不改任何行為語意。

同時在 validator 加了第二層保險：**evaluator 每個可回傳 code 都必須有負例實際踩到**
（code 層級），以及每個負例的 `expected_failure_code` 必須在 `error_contract` 宣告過。

> 誠實標註：新加的是 **code 層級**覆蓋斷言，不是 **branch 層級**。
> 上述兩條 authority 分支是我用 guard parity 手動抓到的，不是這條斷言抓到的。
> 要做到 branch 層級自動化需要 coverage 工具，超出本卡範圍。

---

## TIGHTEN-F-02（P3）—— 控制測資與證據對齊

reviewer 指出 `LOOP_POS_MAX_ITERATIONS_WITH_ORDINARY_GAP` 與
`LOOP_NEG_REQUIRED_PRESENT_WITH_GAPS` 實際差四欄，與我當時 evidence 宣稱的
「只差 `terminal_condition` 一欄」不符。確認屬實：

```
max_iterations     2   → 5
timeout_seconds    120 → 300
elapsed_seconds    95  → 110
terminal_condition MAX_ITERATIONS_REACHED → ALL_REQUIRED_PRESENT
```

### 修法

負例的 `run` 直接從正例的 `run` **逐行複製**，只替換 `terminal_condition` 一行。
`expected` / `expected_failure_code` / `covers_*` 是 case metadata，在 `run` 之外。

複製後以程式逐欄比對（不是用宣稱的）：

```
控制對 run 差異欄位：["terminal_condition"]
```

判定不變：仍為 `LOOP_REQUIRED_PRESENT_WITH_GAPS`。

---

## 回歸：既有判定逐案未變

把 evaluator 載進來，對每一個 fixture case 求值，與**修正前的 `main`** 逐案比對：

```
main（修正前）24 案　本卡 28 案
diff:
  > NEG LOOP_NEG_ITERATIONS_FIELD_ABSENT      => "LOOP_MISSING_FIELD"
  > NEG LOOP_NEG_ITERATIONS_NOT_A_LIST        => "LOOP_MISSING_FIELD"
  > NEG LOOP_NEG_PERFORMS_MEMORY_ACCEPTANCE   => "LOOP_EXCEEDS_AUTHORITY"
  > NEG LOOP_NEG_WRITES_COMPANY_KNOWLEDGE     => "LOOP_EXCEEDS_AUTHORITY"
```

**既有 24 案（6 正例 / 18 負例）判定與 exact code 逐字相同，只有 4 個新增。**
控制負例的 `run` 換過但判定不變，這一行 diff 的缺席就是證據。

---

## Guard parity（全 17 條 return site）

中和方式：`unless true` / `if false`；多行條件區塊內的裸 `return "<CODE>"` 改成 `return nil`
（語意上等同「移除這條拒絕」）。備份還原一律用 `cp`。

**17 RED / 0 GREEN。assertion-RED 15、exception-RED 2。**

exception-RED 兩條是移除型別／存在性 guard 後產生 Ruby 例外，**不是乾淨的契約拒絕**：
`LOOP_UNBOUNDED`（`positive_integer?` 前置）與 `LOOP_MISSING_FIELD`（`iterations.is_a?(Array)`）。
依 SSP-291 那輪 reviewer 的要求，分開列，不混為一談。

---

## 契約現況

| 項目 | 修正前 | 修正後 |
| --- | --- | --- |
| YAML `error_contract` | 14 | 15 |
| evaluator 可回傳相異 code | 15 | 15 |
| 兩者是否機器綁定 | **否**（兩張手寫清單互比） | **是**（原始碼掃描） |
| 負例 | 18 | 22 |
| code 覆蓋 | 14 / 15 | **15 / 15** |
| `required_negative_fixtures` | 18 | 22 |

## Gate

```
ruby scripts/validate_*.rb                     → 21 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
validator 行數                                  → 355（< 400 硬上限）
```

## 本輪沒有做的事

- 沒有改任何既有錯誤語意，`LOOP_MISSING_FIELD` 的行為原樣保留。
- 沒有重開 F-04 / F-05。
- 沒有動上游、沒有新增 outcome 值、沒有新增 package。
