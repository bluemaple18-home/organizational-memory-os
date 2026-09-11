# SSP-302 Repair 01 — SSP302-F-01 掃描語法繞過　evidence

日期：2026-09-11　branch：`cc/ssp302-error-code-coverage`
原 review commit：`19b099b`（immutable）　base：`096cea3`

## 收的 finding

`SSP302-F-01`（P2）唯一一筆。reviewer 明說**不必**做 branch-level coverage machinery，
本輪也沒有做。

## 根因

`reachable_loop_failure_codes` 用 `/return "([A-Z][A-Z0-9_]*)"/` 掃描。
我只保證了「掃到的都對」，沒有保證「沒有掃不到的」。regex scanner 必然是語法特定的，
所以任何一種合法但不符該 pattern 的 Ruby return，都能在不動 YAML、不動鎖定常數、
不動負例的情況下靜默新增一個真正可回傳的 code —— 三層 assertion 全綠。

## 修法：採 reviewer 的第二條路

reviewer 給了兩條：(a) 把取得方式做到無法被任何合法 return 語法繞過；
(b) 明確機器限制 evaluator 只能採用 scanner 可辨識的 return 形式，再補 bypass mutation。

**選 (b)。** (a) 要用 regex 涵蓋 Ruby 全部 return 語法（插值、heredoc、常數、
方法回傳、`%w`）本質上做不完，做了也只是換一個更難察覺的 under-approximation。
(b) 把不確定性關掉：形式白名單是可窮舉的，違反即轉紅。

1. `ALLOWED_EVALUATOR_RETURN` —— evaluator 內每一條 `return` 只能是
   `return nil` 或 `return "<CODE>"`（可帶 `if` / `unless` 修飾）。
2. scanner 同時放寬到單引號，讓單引號 code **同時**踩中形式白名單與完整性斷言。
3. 抽出 `loop_evaluator_body`，掃描與形式檢查共用同一段函式本體，不會各掃各的。
4. YAML `error_contract_binding.evaluator_return_form_rule` 把這個限制寫進契約。

**既有 evaluator 邏輯逐字未改** —— 現有 17 條 return 本來就全部符合白名單，
沒有為了通過檢查而改寫任何判斷。

## 驗證

### 1. Bypass mutation（reviewer 指定的驗收）

在 evaluator 插入各種合法 Ruby return 形式：

| # | 注入 | 結果 |
| --- | --- | --- |
| B1 | `return 'LOOP_UNDECLARED' if ...`（reviewer 指定） | RED/assertion |
| B2 | `return "LOOP_UNDECLARED" if ...` | RED/assertion |
| B3 | `return "LOOP_#{...}" if ...`（字串插值） | RED/assertion |
| B4 | `return EXPECTED_OUTCOMES.first if ...`（常數） | RED/assertion |
| B5 | `return run["x"].to_s if ...`（方法回傳） | RED/assertion |
| B6 | `return 'LOOP_UNBOUNDED' if ...`（單引號、code 已宣告） | RED/assertion |
| B7 | `return %w[LOOP_UNDECLARED].first if ...` | RED/assertion |

**7 RED / 0 GREEN。**

### 2. 哪一層真的攔下哪一個（不憑宣稱，實測）

把形式白名單斷言移除後重跑同一組：

| probe | 完整 | 移除白名單 | 白名單是否唯一防線 |
| --- | --- | --- | --- |
| B1 | RED | RED | 否（scanner 放寬單引號後也看得到） |
| B2 | RED | RED | 否（完整性斷言攔下） |
| B3 | RED | **GREEN** | **是** |
| B4 | RED | **GREEN** | **是** |
| B5 | RED | **GREEN** | **是** |
| B6 | RED | **GREEN** | **是** |
| B7 | RED | **GREEN** | **是** |

誠實標註：reviewer 舉的那個例子（B1）其實被兩層各自攔下，
**單靠放寬 scanner 就能擋掉 B1**。但 B3~B7 這五類只有形式白名單擋得住 ——
它們回傳的 code 是 scanner 在原理上看不見的。所以白名單不是為了 B1 而加，
而是為了把「regex 必然低估」這件事本身關掉。

### 3. 回歸（全部維持）

- 逐 code 改名 parity：**15 RED / 0 GREEN**
- guard parity（17 條 return site）：**17 RED / 0 GREEN，assertion 15 / exception 2**
- 既有判定：與修正前 `main` 的 24 案逐案比對，**exact code 逐字相同**，
  只有本卡新增的 4 案：

```
> NEG LOOP_NEG_ITERATIONS_FIELD_ABSENT      => "LOOP_MISSING_FIELD"
> NEG LOOP_NEG_ITERATIONS_NOT_A_LIST        => "LOOP_MISSING_FIELD"
> NEG LOOP_NEG_PERFORMS_MEMORY_ACCEPTANCE   => "LOOP_EXCEEDS_AUTHORITY"
> NEG LOOP_NEG_WRITES_COMPANY_KNOWLEDGE     => "LOOP_EXCEEDS_AUTHORITY"
```

### 4. Gate

```
ruby scripts/validate_*.rb                     → 21 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

## 主動回報：檔案大小逼近上限

validator 現在 **390 行**，仍在 `.agentskills/docs/coding-standards.md` §2 的
`< 400` 硬上限內，但只剩 10 行。下次再往這支加東西應先進 Refactor Mode
（候選：把三個 error-contract 綁定斷言抽成獨立函式）。本輪不順手重構 ——
那會擴大本次 repair 的 blast radius。

## 本輪沒有做的事

- 沒有做 branch-level coverage machinery（reviewer 明說不需要）。
- 沒有改任何既有錯誤語意或 evaluator 判斷邏輯。
- 沒有重開 F-04 / F-05、沒有動上游、沒有新增 package。
