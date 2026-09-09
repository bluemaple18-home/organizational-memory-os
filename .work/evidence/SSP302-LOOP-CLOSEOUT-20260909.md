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

### 上游契約未被改動

`git diff --name-status b0e0fee..HEAD` 僅新增 4 檔 + 卡 + evidence + 待辦重整；未碰
`ai-work-record-boundary.yaml`／`ai-task-card-record.yaml`／`ai-work-record-skill.yaml`／
`ai-work-record-hook.yaml` 或其 validator。dup-key fail-closed 對 3 個新檔已跑
（`StrictJsonObject` / `assert_unique_yaml_mapping_keys`，來自共用 lib）。
