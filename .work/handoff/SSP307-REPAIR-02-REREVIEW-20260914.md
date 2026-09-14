# SSP-307 Repair 02 — 定點 re-review 交付包

同一條 review line。只收 `SSP307-F-04` 殘留部分。F-01/F-02/F-03 你已裁決
CLOSED，本輪不重開。

## 1. 鎖定

```
base                e73488d100526341cea08ebc331714dc90456fa1
original_review     a9bb40a908fd2ca04758791d69809ed42906531c   （immutable，NO_GO）
repair_01           77ffc67c8dd2dd7418af06cdf6368cc3c48095c7   （immutable，NO_GO P2=1）
repair_02           1351dc1d17e66d173aef734b7318b6a2b3c97d5e
branch              cc/ssp307-codex-native-adapter
```

定點 diff：`git diff 77ffc67..1351dc1`

## 2. 收法

你指出：上一輪只比對 `measured_native_vocabulary.observed_event_types` 與
runtime sample `event_type_counts` 的 **key 集合**，從未比對**數值**本身，
也從未把契約 `sampled_sessions` 與 runtime sample `sampled_sessions` 綁定。

新增兩條斷言：

```ruby
assert(declared_observed == sample_counts, ...)
assert(declared_sampled_sessions == sample_sampled_sessions, ...)
```

## 3. 請重播你的確切 mutation

```
measured_native_vocabulary:
  sampled_sessions: 999
  observed_event_types:
    task_started: 1
```

我的結果：**RED/assertion**。

另外拆成兩個獨立 mutation（各自單獨也要攔下，不能只在同時發生時才攔）：

| # | 動作 | 我的結果 |
| --- | --- | --- |
| 1 | 單獨 count drift：`task_started 9529 → 1`（keys 不變） | RED |
| 2 | 單獨 session-count drift：`sampled_sessions 818 → 999`（counts 不變） | RED |

**3/3 RED。** 還原請用 `cp` 備份，不要用 `git checkout --`。

## 4. 回歸

本輪只加了結構斷言，未動任何 evaluator 函式：

```
ruby scripts/validate_*.rb                     → 22 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

validator **335 行**（< 400 硬上限）。

請就 `SSP307-F-04` 給 `GO` 或 `NO_GO`。
