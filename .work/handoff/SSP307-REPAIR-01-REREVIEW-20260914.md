# SSP-307 Repair 01 — 定點 re-review 交付包

同一條 review line。收 `SSP307-F-01`／`F-02`／`F-03`／`F-04` 全部四筆。

## 1. 鎖定

```
base                e73488d100526341cea08ebc331714dc90456fa1
original_review     a9bb40a908fd2ca04758791d69809ed42906531c   （immutable，NO_GO）
repair_commit       77ffc67c8dd2dd7418af06cdf6368cc3c48095c7
branch              cc/ssp307-codex-native-adapter
```

定點 diff：`git diff a9bb40a..77ffc67`

## 2. 逐筆收法

**F-01（P1）**：驗證屬實。`ai-task-card-record.yaml` 沒有 `OPEN→DONE` 邊。
改 `task_complete → submit_review`（`OPEN→IN_REVIEW` 合法）。直接重播
`lifecycle_event_to_status` + `allowed_status_transitions` 確認：

```
start -> OPEN
OPEN -> IN_REVIEW via submit_review: OK
```

**F-02（P1）**：採信你引用的 Codex 原始碼事實（`TurnAborted`/`RecoverTurn`
可恢復）。`turn_aborted` 移出 `lifecycle_event_map`，併入
`non_lifecycle_event_types`（8 項）。

**F-03（P2）**：驗證屬實。在**未修正版本**（`a9bb40a`）上實測你描述的 bypass：

```
codex_mapping_failure 新增
  return "CODEX_BRAND_NEW_UNDECLARED_CODE" if run["__probe__"] == true
（不動 YAML）→ 完整 gate 仍然綠
```

修法：**沒有新增第二套機制**，直接沿用 SSP-302 已建立、參數化過的
`scripts/lib/loop_return_contract.rb`（`source_path` + `evaluator_name`
皆為參數）。三個 evaluator 各自求 `reachable_codes`，`error_contract`
與三者聯集機器綁定。

**主動延伸（你沒有明講的部分）**：同時套用該模組的 `exit_shape_violations`。
理由：只綁 `reachable_codes`、不綁出口形狀，evaluator 尾端換成隱式回傳一個
未宣告的 code 一樣能繞過——那正是 SSP-302 closeout 花了三輪才收斂的問題。
沿用完整機制而非選擇性擷取，是為了不重新引入同一類缺口。

**F-04（P2）**：驗證屬實。在**未修正版本**上實測：

```
non_lifecycle_event_types 加入一個從未觀測過的事件（classified ⊋ observed）
→ 完整 gate 仍然綠
```

修法：`codex_runtime_sample_failure` 改成 `sorted_set` 雙向相等，
新增反向 negative fixture 與對應 `required_negative_fixtures` label。

## 3. 請重播

**A. F-01/F-02 fixture 連鎖修正**：`CODEX_POS_TASK_COMPLETE_MAPS_COMPLETE`
→ 改名 `..._MAPS_SUBMIT_REVIEW`，`mapped_to` 改 `submit_review`；
`CODEX_POS_TURN_ABORTED_MAPS_CANCEL` → 改名 `..._NOT_LIFECYCLE`，`outcome`
改 `NOT_LIFECYCLE`。

**B. F-03 bypass probe（修法前後對照）**

| # | 動作 | 修法前（`a9bb40a`） | 修法後（`77ffc67`） |
| --- | --- | --- | --- |
| A | evaluator 改名一個既有 return code，YAML 未同步 | RED（原本就綁） | RED |
| B | evaluator 新增一個從未宣告過的全新 code（你描述的確切攻擊） | **GREEN(bad)** | **RED** |

**C. F-04 bypass probe（修法前後對照）**

| 動作 | 修法前 | 修法後 |
| --- | --- | --- |
| 分類清單多一個從未觀測過的事件 | **GREEN(bad)** | **RED** |

**D. 三個 evaluator guard parity（回歸，證明修法沒動到既有判斷邏輯）**

| evaluator | 結果 |
| --- | --- |
| `codex_mapping_failure`（15 條） | 15 RED / 0 GREEN（assertion 14 / exception 1） |
| `codex_rollback_failure`（6 條） | 6 RED / 0 GREEN（assertion 5 / exception 1） |
| `codex_runtime_sample_failure`（1 條） | 1 RED / 0 GREEN |

還原請用 `cp` 備份，不要用 `git checkout --`。

## 4. Gate

```
ruby scripts/validate_*.rb                     → 22 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：validator **316 行**（原 288；F-03 刪掉三張手寫清單，換成呼叫共用
模組，淨增加不多）；契約 **234 行**（原 215）。皆在 `< 400` 硬上限內。

## 5. 未動的部分

上游契約（`ai-task-card-record.yaml`／`ai-work-record-hook.yaml`）逐字未變。
你上一輪沒有列 finding 的部分（content-free runtime fixture、authority
boundary、optional dependency、no-org-wide-install、rollback side effects、
guard parity 方向）本輪未動。沒有重新驗證 F-02 引用的 Codex 上游原始碼——
直接採信你的技術主張。

請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
