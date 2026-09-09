# Evidence｜SSP-302 AIWR-05 Loop 收口與缺口補登

- 卡：`.work/CARD-SSP302-LOOP-CLOSEOUT-20260909.md`
- Tier：T1
- branch：`cc/ssp302-loop-closeout`（off `main` @ `b0e0fee`）
- lane：B

## 交付物

| 檔 | 說明 | 行數 |
|---|---|---|
| `規格/v0.1/ai-work-record-loop.yaml` | Loop 契約：termination / scope_lock / human_decision_gate / unfixable / run_record / authority / error_contract / cross_reference / hard_stops | 141 |
| `scripts/validate_ai_work_record_loop_contract.rb` | 薄 validator：結構斷言 + 純函式 `loop_closeout_failure(run, fillable_fields, outcome_condition_map)`；交叉讀 task-card-record／skill／boundary；沿用 `scripts/lib/omos_contract_helpers.rb` | 240 |
| `規格/v0.1/fixtures/ai-work-record-loop-positive-fixtures.json` | `loop_closeout_cases` ×4（normal / closed-at-max / blocked-on-human-decision / failed-loud-unfixable） | — |
| `規格/v0.1/fixtures/ai-work-record-loop-negative-fixtures.json` | `loop_closeout_negative_cases` ×11，各單一 mutation + `expected_failure_code` + `covers_loop_negative_fixture` | — |

檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator 240 < 400）。

## 契約重點（對應 Acceptance）

- **有界**：`termination.terminal_conditions` 鎖定 5 值；`max_iterations` / `timeout_seconds`
  非正整數或缺 → `LOOP_UNBOUNDED`。
- **iterations 不超過 max**：`iterations.length > max_iterations` → `LOOP_OVER_MAX_ITERATIONS`。
- **outcome 合法且與 condition 一致**：`outcome ∉ {CLOSED,BLOCKED,FAILED_LOUD}` →
  `LOOP_INVALID_OUTCOME`；`terminal_condition ∉ outcome_condition_map[outcome]` →
  `LOOP_OUTCOME_CONDITION_MISMATCH`（`CLOSED→{ALL_REQUIRED_PRESENT,MAX_ITERATIONS_REACHED}`、
  `BLOCKED→{BLOCKER_MARKED}`、`FAILED_LOUD→{TIMEOUT,UNFIXABLE}`）。
- **scope lock**：每輪 `filled_fields` 只能是 `[status, evidence_refs]`；含 `objective`/`scope`/
  `constraints`/`acceptance`/`card_id`/未知欄位 → `LOOP_SCOPE_EXPANSION`。結構斷言另鎖
  `fillable ∪ forbidden == ai-task-card-record.fields`。
- **人類決策 gate**：最後一輪 `remaining_gaps` 含 `requires_human_decision: true`，但
  `outcome != BLOCKED` 或缺 `blocker_ref` → `LOOP_SKIPPED_HUMAN_DECISION`。
- **unfixable**：最後一輪含 `auto_fixable: false` 且非人類決策的缺口，但 `outcome != FAILED_LOUD`
  → `LOOP_UNFIXABLE_NOT_LOUD`；`outcome == FAILED_LOUD` 但 `original_evidence_preserved != true`
  → `LOOP_EVIDENCE_NOT_PRESERVED`。
- **authority floor**：`performs_memory_acceptance`/`writes_company_knowledge` 皆 `false`；run 帶
  `personal_acceptance_ref` 等 4 個 forbidden 欄位 → `LOOP_EXCEEDS_AUTHORITY`。
- **fail-loud**：`authority.error_behavior: FAIL_LOUD`（與 boundary `error_behavior_enum` 交叉鎖）；
  run 有 `error` 但 `ok != false` → `FAIL_SILENT`。
- **cross_reference**：`must_match` 四 pointer 字串 exact，引用目標
  （`ai-task-card-record.fields` / `status_enum`、skill `output_contract.draft_card`、
  boundary `error_behavior_enum`）存在且非空。
- **runtime_independence: true**：fixtures 無 runtime-specific 欄位。

## 驗證

### gate 全綠（branch head）

```
15 Ruby validator（含 loop 本卡 + hook/skill/boundary/task-card-record regression
+ personal-memory aggregator + STD-00~03 + 4 個 personal-memory slice）  exit=0 PASS
std_schema_engine.py   PASS  coverage 12/12、16/16、9/9（不變）
validate_cc_cross_layer_contract.py   PASS
git diff --check   clean
```

### 負例 enforcement parity（移除 enforcement → gate 轉紅）

逐一 neutralize 每個 `return "<CODE>"`，跑 `ruby scripts/validate_ai_work_record_loop_contract.rb`：

| enforcement | 移除後 |
|---|---|
| `LOOP_UNBOUNDED` | exit 1（RED） |
| `LOOP_EXCEEDS_AUTHORITY`（forbidden run fields） | exit 1（RED） |
| `FAIL_SILENT` | exit 1（RED） |
| `LOOP_OVER_MAX_ITERATIONS` | exit 1（RED） |
| `LOOP_SCOPE_EXPANSION` | exit 1（RED） |
| `LOOP_INVALID_OUTCOME` | exit 1（RED） |
| `LOOP_OUTCOME_CONDITION_MISMATCH` | exit 1（RED） |
| `LOOP_SKIPPED_HUMAN_DECISION` | exit 1（RED） |
| `LOOP_UNFIXABLE_NOT_LOUD` | exit 1（RED） |
| `LOOP_EVIDENCE_NOT_PRESERVED` | exit 1（RED） |

全部還原後 `PASS`。10 個 enforcement 全數 load-bearing。

### DoD 四類案例

- 正常收口：`LOOP_POS_NORMAL_CLOSEOUT`（補 evidence_refs → status，`outcome: CLOSED` /
  `ALL_REQUIRED_PRESENT`）+ `LOOP_POS_CLOSED_AT_MAX_ITERATIONS`（2/2 輪，`MAX_ITERATIONS_REACHED`）→ allow。
- 缺欄位：正例每輪 `filled_fields` 補 `status`／`evidence_refs`；負例 `LOOP_NEG_SCOPE_EXPANSION`
  補 `scope` → `LOOP_SCOPE_EXPANSION`。
- 需要人類決策：`LOOP_POS_BLOCKED_ON_HUMAN_DECISION`（`requires_human_decision` gap →
  `outcome: BLOCKED` + `blocker_ref`）→ allow；`LOOP_NEG_SKIPPED_HUMAN_DECISION` → 拒。
- 超限：`LOOP_NEG_OVER_MAX_ITERATIONS`（3 > max 2）→ `LOOP_OVER_MAX_ITERATIONS`；
  `LOOP_NEG_NO_MAX_ITERATIONS` / `LOOP_NEG_NO_TIMEOUT` → `LOOP_UNBOUNDED`。
- 無法修復 fail-loud：`LOOP_POS_FAILED_LOUD_UNFIXABLE`（`auto_fixable: false` gap →
  `outcome: FAILED_LOUD` + `original_evidence_preserved: true`）→ allow；
  `LOOP_NEG_UNFIXABLE_NOT_LOUD` / `LOOP_NEG_EVIDENCE_NOT_PRESERVED` → 拒。

## Repair 01｜大 review NO_GO（2×P1 + 1×P2 + 1×P3）

| finding | 修法 | 新 fixture → code |
|---|---|---|
| F-01（P1）timeout 是 metadata 不是 enforcement | run record 加 `elapsed_seconds`（非負整數，入 bounded 檢查）；新 `LOOP_OVER_TIMEOUT`：`elapsed > timeout` 且非 `FAILED_LOUD+TIMEOUT` 收尾 → 拒 | `LOOP_NEG_NO_ELAPSED` → `LOOP_UNBOUNDED`；`LOOP_NEG_OVER_TIMEOUT` → `LOOP_OVER_TIMEOUT`；正例 `LOOP_POS_TIMEOUT_TERMINATED`（305>300 但 FAILED_LOUD+TIMEOUT）→ allow |
| F-02（P1）mandatory-stop gap 只看最後一輪 | 改逐輪 `each_with_index`：第一個帶 human-decision / 非人類 unfixable gap 的 iteration 必須是最後一輪且 outcome 對應 BLOCKED / FAILED_LOUD | `LOOP_NEG_HUMAN_GAP_MIDWAY`（iter1 human、iter2 清、outcome BLOCKED）→ `LOOP_SKIPPED_HUMAN_DECISION`；`LOOP_NEG_UNFIXABLE_MIDWAY`（iter1 unfixable、iter2 清、outcome FAILED_LOUD）→ `LOOP_UNFIXABLE_NOT_LOUD` |
| F-03（P2）iteration 三欄未 fail-closed 驗 | 每個 iteration 驗 `iteration_fields` 齊備且 `filled_fields`/`remaining_gaps` 為 Array → `LOOP_MALFORMED_ITERATION` | `LOOP_NEG_MALFORMED_ITERATION`（缺 `remaining_gaps`）→ `LOOP_MALFORMED_ITERATION` |
| F-04（P3）CLOSED+MAX_ITERATIONS_REACHED 留普通缺口 | reviewer 判 spec 定義問題、非 evaluator 偷漏、不阻塞 → 記 `文件/待辦重整.md` 規範債 backlog，本 repair 不改契約 | — |

- `required_negative_fixtures` / `EXPECTED_LOOP_NEGATIVE_LABELS` 各 11 → 16。
- enforcement parity 重跑：`elapsed_seconds` 入 bounded 檢查 / `LOOP_OVER_TIMEOUT` /
  `LOOP_MALFORMED_ITERATION` / F-02 `index == last_index` guard（兩處）/ F-02 改回「只看最後一輪」
  —— 逐一移除 → `ruby` exit 1（RED）；原有 10 個 enforcement 亦重跑保持 load-bearing；全部還原後 `PASS`。
- 行為 regression：15 Ruby validator + `std_schema_engine`（coverage 不變）+ cross-layer +
  `git diff --check` 全綠；4 個既有正例補 `elapsed_seconds` 後仍 PASS + 1 新正例；上游 4 份契約
  （boundary / task-card-record / skill / hook）未改動。validator 269 行（< 400）。
- repair 卡：`.work/CARD-SSP302-REPAIR-01-20260909.md`。原 frozen review SHA `165209195` 不動。

## 上游契約未被改動

`git diff --name-status b0e0fee..HEAD` 僅新增 4 檔 + 卡 + evidence + 待辦重整；未碰
`ai-work-record-boundary.yaml`／`ai-task-card-record.yaml`／`ai-work-record-skill.yaml`／
`ai-work-record-hook.yaml` 或其 validator。dup-key fail-closed 對 3 個新檔已跑
（`StrictJsonObject` / `assert_unique_yaml_mapping_keys`，來自共用 lib）。
