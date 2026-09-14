# SSP-302 error-code 契約完整性 — Big Review 交付包

平台中立。以下都可從 branch 直接重現。

## 1. 審什麼

`SSP302-CONTRACT-TIGHTEN` 大 review（`8d9c829`）留下的兩個非阻塞 finding 的收尾：

- `TIGHTEN-F-01`（P2）：`error_contract` 的完整性斷言驗錯對象 —— 比的是兩張手寫清單。
- `TIGHTEN-F-02`（P3）：控制正負例實際差四欄，與 evidence 宣稱的「只差一欄」不符。

核心問題：**「宣告的錯誤碼集合等於 evaluator 實際可回傳的集合」能否被證偽？**

## 2. Frozen commit

```
base             096cea3
實作 frozen      19b099bd3bb14325d1b6cca6c22b1d0535bbf505
branch           cc/ssp302-error-code-coverage（已 push origin）
本交付包          19b099b 的下一個 commit，docs-only
```

```
git fetch origin && git checkout cc/ssp302-error-code-coverage
git diff 096cea3..19b099b --stat
```

## 3. 契約變更

| 檔 | 變更 |
| --- | --- |
| `scripts/validate_ai_work_record_loop_contract.rb` | +`reachable_loop_failure_codes`；斷言升級為三層；+code 覆蓋斷言；常數 +1、註解改寫。355 行 |
| `規格/v0.1/ai-work-record-loop.yaml` | `error_contract` 14 → 15；+`error_contract_binding.rule`；`required_negative_fixtures` 18 → 22 |
| `規格/v0.1/fixtures/ai-work-record-loop-negative-fixtures.json` | 負例 18 → 22；控制負例的 `run` 改為由正例複製 |
| `文件/待辦重整.md` | 狀態更新 |

**未改動任何上游規格、未改任何既有錯誤語意、未新增 outcome 值。**

## 4. 特別請看的點

1. **修正前的缺口我已實測復現，請自行確認**。在**未修正的 `main`（`096cea3`）**上：

   ```
   perl -0pi -e 's/LOOP_MISSING_FIELD/LOOP_RENAMED_PROOF/g' scripts/validate_ai_work_record_loop_contract.rb
   ruby scripts/validate_ai_work_record_loop_contract.rb
   ```

   我的結果：**PASS（綠）** —— 改掉一個 evaluator 實際會回傳的 code，完整 gate 沒反應。
   這就是 TIGHTEN-F-01。請確認你在 `19b099b` 上做同樣的事會轉紅。

2. **原始碼掃描的邊界**。`reachable_loop_failure_codes` 只掃
   `loop_closeout_failure` 函式本體，避開註解、常數清單與其他函式的字串。
   請找它可能漏掃或誤掃的情況（例如 heredoc、動態組出的 code、多行 return）。
   目前 evaluator 沒有動態組 code；若你找到一種寫法能繞過掃描，那是 finding。

3. **我把常數的角色改掉了**。`EXPECTED_LOOP_ERROR_CODES` 原本的註解宣稱它是
   「evaluator 可回傳的完整集合」—— 那句話當時就不成立。現在它只負責第二件事：
   防止有人**同時**改 evaluator 與 YAML 而悄悄變更鎖定集合。請判斷這個雙層設計
   是多餘、還是必要。

4. **本輪自己抓到的新缺口（主動回報）**。guard parity 第一輪跑出 2 個 GREEN(bad)：
   `LOOP_EXCEEDS_AUTHORITY` 有三個 return site，但負例只踩到第三個。
   我補了兩個負例。這與 TIGHTEN-F-01 是同一類缺陷（宣告層覆蓋、分支層沒有）。

5. **誠實標註覆蓋斷言的層級**。我新加的是 **code 層級**覆蓋（每個 code 至少一個負例），
   **不是 branch 層級**。上述兩條 authority 分支是我手動用 parity 抓到的，
   不是這條斷言抓到的。要做到 branch 層級自動化需要 coverage 工具，超出本卡範圍。
   如果你認為沒有 branch 層級保證就不算收乾淨，請提出來。

## 5. Mutation 要求

**A. 逐 code 改名 parity（15 個）**
只在 evaluator 改名、不動 YAML。我的結果：**15 RED / 0 GREEN（assertion 15 / exception 0）**。

**B. Guard parity（17 個 return site）**
中和方式：`unless true` / `if false`；多行條件區塊內的裸 `return "<CODE>"` 改 `return nil`。
我的結果：**17 RED / 0 GREEN，assertion 15 / exception 2**。
exception-RED 兩條是移除型別／存在性 guard 後的 Ruby 例外
（`LOOP_UNBOUNDED` 的 `positive_integer?`、`LOOP_MISSING_FIELD` 的 `iterations.is_a?(Array)`），
**不是乾淨的契約拒絕**。

**C. 既有判定不得改變**
把 evaluator 載進來，對每個 fixture case 求值，與修正前的 `main` 逐案比對。
我的結果：**既有 24 案（6 正例 / 18 負例）判定與 exact code 逐字相同**，只新增 4 案。
控制負例的 `run` 被整塊換掉但判定不變 —— 這一行 diff 的缺席就是證據。

**D. 控制對只差一欄**
請自行逐欄比對 `LOOP_POS_MAX_ITERATIONS_WITH_ORDINARY_GAP` 與
`LOOP_NEG_REQUIRED_PRESENT_WITH_GAPS` 的 `run`。
我的結果：差異欄位 `["terminal_condition"]`。

還原請用 `cp` 備份，**不要用 `git checkout --`**（會從 index 還原）。

## 6. 邊界

不改既有錯誤語意、不重開 F-04 / F-05、不動上游、不新增 outcome 值、不新增 package、
不新增 registry / FSM / runtime。若 finding 需跨過以上任一條，那是 Owner 決策。

## 7. 已跑的 gate

```
ruby scripts/validate_*.rb                     → 21 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
validator 行數                                  → 355（< 400）
```

## 8. 契約現況對照

| 項目 | 修正前 | 修正後 |
| --- | --- | --- |
| YAML `error_contract` | 14 | 15 |
| evaluator 可回傳相異 code | 15 | 15 |
| 兩者機器綁定 | **否** | **是**（原始碼掃描） |
| 負例 | 18 | 22 |
| code 覆蓋 | 14 / 15 | **15 / 15** |

請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
