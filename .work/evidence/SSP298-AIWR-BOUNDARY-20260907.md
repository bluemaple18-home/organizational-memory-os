---
id: SSP298-AIWR-BOUNDARY-20260907
type: evidence
card: .work/CARD-SSP298-AIWR-BOUNDARY-20260907.md
status: IMPLEMENTED_AWAITING_BIG_REVIEW
---

# SSP-298 實作證據

## Checkpoint

- Branch：`cc/ssp298-aiwr-boundary`（worktree，未 push）。
- Implementation commit：`67f76fa5fdc7aadee178e45d76af05c66bb5139c`。
- Parent / base：`78e570a74af45f5337d7db8376cd83b67e131b26`。
- Tree：`041a9688c5aaef3cf8f1a32d0bdd17ee2f261583`。

## 變更檔案（`78e570a..67f76fa`）

| 狀態 | 路徑 | review blob OID |
|---|---|---|
| A | `規格/v0.1/ai-work-record-boundary.yaml` | `7a923a7fb6ab6ab0aec87feb77a8a3d518a20f1f` |
| A | `scripts/validate_ai_work_record_boundary_contract.rb` | `a8d01080f177e9aba70fc7c9875684b7ced1174a` |
| A | `規格/v0.1/fixtures/ai-work-record-boundary-positive-fixtures.json` | `b2261ec86626e371d108d50ae468abc9d13a5ecb` |
| A | `規格/v0.1/fixtures/ai-work-record-boundary-negative-fixtures.json` | `eb0c2696bb0f73c61fd5ba0c4445462b1ab33614` |
| M | `.work/CARD-SSP298-AIWR-BOUNDARY-20260907.md` | `1d411a0ae13dfce24248c1111bc8789f16fddb0c` |

新增 4 檔、修改 1 卡片。未觸碰任何既有 validator / schema / fixture。

## 契約（`ai-work-record-boundary.yaml`，`schema_id urn:omos:schema:ai-work-record-boundary:0.1.0`）

- `authority_boundary.task_card`：`role WORK_CONTROL_AND_REPORT_ARTIFACT`、`is_personal_memory: false`；`required_fields` = `card_id/objective/scope/constraints/acceptance/status/evidence_refs`；`status_enum` = `OPEN/BLOCKED/IN_REVIEW/DONE/CANCELLED`；`forbidden_fields` = `personal_acceptance_ref/verification_receipt_ref/accepted_for_record/memory_kind/record_id/candidate_status`；`forbidden_authority` 含 `memory_acceptance`；`sensitive_content_rule: reference_only_never_copied`。
- `authority_boundary.work_record`：沿用既有 `work_record` 語意（`REBUILDABLE_PROJECTION`、`may_generate_candidates 0..N`），`forbidden_authority` 含 `memory_acceptance`。
- `promotion_path.ordered_steps` = `TASK_CARD_OR_WORK_RECORD → RAW_EVIDENCE_ENVELOPE → PERSONAL_MEMORY_CANDIDATE → VERIFICATION → PERSONAL_ACCEPTANCE → PERSONAL_MEMORY_RECORD`；`rules` 禁 `task_card_direct_to_record`、`skip_any_step`、`steps_out_of_order`；`receipts_required` 綁 `VERIFICATION→verification_receipt_ref`、`PERSONAL_ACCEPTANCE→personal_acceptance_ref`。
- `non_acceptance_authority.signals` = `branch/worktree/runtime_completion/model_confidence`。
- `automated_step_contract.required_per_step` = `input_schema_ref/output_schema_ref/error_behavior/human_acceptance_gate/dry_run_supported`；`error_behavior_enum` = `[FAIL_LOUD]`；`fail_silent: forbidden`。
- `cross_reference`：指向 `personal-harness-integration.yaml` 的 `not_long_lived_memory_by_default`（`transient_kinds_must_match: true`）與 `runtime_policy`（`executor_authority_over_memory_must_be: false`）；`reused_core_invariants` = `WORK_RECORD_NE_PERSONAL_MEMORY / CANDIDATE_NE_ACCEPTED_PERSONAL_MEMORY / CAPTURED_NE_REMEMBERED / MODEL_CONFIDENCE_NE_VERIFICATION`。
- `hard_stops` 明列不建 workflow engine / registry / FSM / DB，不定義 task card frontmatter schema，不做 hook/loop/harness/hermes。

## Validator（`validate_ai_work_record_boundary_contract.rb`，薄判斷）

- 重用 `StrictJsonObject`（duplicate JSON key fail-closed）、`assert_unique_yaml_mapping_keys`、`YAML.safe_load(aliases:false)`。
- `task_card_failure`（第 132 行）：`TASK_CARD_CLAIMS_PERSONAL_MEMORY` → `TASK_CARD_MISSING_CONTROL_FIELD` → `TASK_CARD_CARRIES_MEMORY_ACCEPTANCE_FIELD` → `TASK_CARD_INVALID_STATUS` → `TASK_CARD_SENSITIVE_CONTENT_COPIED`。
- `promotion_path_failure`（第 148 行）：`NON_ACCEPTANCE_SIGNAL_USED_AS_AUTHORITY` → `TRANSIENT_KIND_PROMOTED`（比對 personal spec 的 `not_long_lived_memory_by_default`）→ `PROMOTION_UNKNOWN_STEP` → `TASK_CARD_DIRECT_TO_RECORD` / `PROMOTION_SKIPS_EVIDENCE` → `PROMOTION_SKIPS_VERIFICATION_OR_ACCEPTANCE` → `PROMOTION_STEPS_OUT_OF_ORDER` → `PROMOTION_MISSING_RECEIPT`。
- `automated_step_failure`（第 183 行）：`AUTOMATED_STEP_MISSING_CONTRACT_FIELD` → `AUTOMATED_STEP_FAIL_SILENT` → `AUTOMATED_STEP_BYPASSES_HUMAN_GATE` → `AUTOMATED_STEP_NO_DRY_RUN`。
- 結構斷言（第 211 行起）：task_card / work_record / promotion_path / non_acceptance_authority / automated_step_contract 逐項鎖定；cross_reference 交叉讀 personal spec 實體並驗 `not_long_lived_memory_by_default` 非空、`runtime_policy.executor_authority_over_memory == false`、四條被引用 `core_invariants` 確實存在於 personal spec；`required_negative_fixtures` 與鎖定 label 清單相等。
- Fixture 評估（第 292 行起）：正例須 `failure == nil`；負例透過 `check_negative` 驗 `failure != nil` 且 `actual == expected_failure_code`（宣告 code parity）；`EXPECTED_BOUNDARY_NEGATIVE_LABELS - covered` 必須為空。

## Fixtures

- 正例：`task_card_cases` 2、`promotion_path_cases` 3（TASK_CARD 全路徑、WORK_RECORD 全路徑、candidate-only 無 record）、`automated_step_cases` 1。
- 負例：`task_card_negative_cases` 2、`promotion_path_negative_cases` 7、`automated_step_negative_cases` 2。7 個必備 label：
  - `AIWR_TC_NEG_CARRIES_PERSONAL_ACCEPTANCE_REF` → `TASK_CARD_CARRIES_MEMORY_ACCEPTANCE_FIELD`（task card carries a memory acceptance field）
  - `AIWR_PP_NEG_CURRENT_TASK_STATUS_PROMOTED` → `TRANSIENT_KIND_PROMOTED`（current task status promoted as long-lived memory）
  - `AIWR_PP_NEG_BRANCH_WORKTREE_STATE_PROMOTED` → `TRANSIENT_KIND_PROMOTED`（temporary branch or worktree state promoted as memory）
  - `AIWR_PP_NEG_RUNTIME_COMPLETION_AS_ACCEPTANCE` → `NON_ACCEPTANCE_SIGNAL_USED_AS_AUTHORITY`（runtime completion message treated as accepted）
  - `AIWR_PP_NEG_MODEL_CONFIDENCE_AUTO_ACCEPT` → `NON_ACCEPTANCE_SIGNAL_USED_AS_AUTHORITY`（model confidence auto-accepts candidate）
  - `AIWR_PP_NEG_TASK_CARD_DIRECT_TO_RECORD` → `TASK_CARD_DIRECT_TO_RECORD`（task card creates record skipping evidence）
  - `AIWR_AS_NEG_NO_HUMAN_GATE` → `AUTOMATED_STEP_BYPASSES_HUMAN_GATE`（automated step bypasses human acceptance gate）
- 額外 branch 覆蓋負例（label 不在必備清單，coverage 斷言為單向）：`TASK_CARD_MISSING_CONTROL_FIELD`、`PROMOTION_SKIPS_EVIDENCE`、`PROMOTION_SKIPS_VERIFICATION_OR_ACCEPTANCE`、`AUTOMATED_STEP_FAIL_SILENT`。

## Gate 結果（在 `67f76fa`）

| Gate | 命令 | 結果 |
|---|---|---|
| AIWR boundary | `ruby scripts/validate_ai_work_record_boundary_contract.rb` | `PASS ai work record boundary contract validation` |
| Personal memory（regression） | `ruby scripts/validate_personal_memory_contract.rb` | `PASS` |
| STD schema engine | `uv run --script scripts/validate_std_schema_engine.py` | `PASS`；exit 0 |
| STD-00 / 01 / 02 / 03 | 各自 validator | `PASS` × 4 |
| Cross-layer | `uv run --script scripts/validate_cc_cross_layer_contract.py` | `PASS`；exit 0；8 negatives rejected |
| Whitespace | `git diff --cached --check` | clean |
| JSON / YAML parse | `json.load` × 2、`YAML.safe_load` | OK |

## Mutation 探針（對 `67f76fa`，改動後還原乾淨）

| 探針 | 結果 |
|---|---|
| `non_acceptance_authority.signals` 移除 `runtime_completion` | RED ✓ |
| `promotion_path.rules.task_card_direct_to_record` 改 `allowed` | RED ✓ |
| `promotion_path.ordered_steps` 移除 `RAW_EVIDENCE_ENVELOPE` | RED ✓ |
| `automated_step_contract.required_per_step` 移除 `human_acceptance_gate` | RED ✓ |
| `cross_reference.executor_authority_over_memory_must_be` 改 `true` | RED ✓ |
| 負例宣告錯誤 `expected_failure_code` | RED ✓ |
| 負例 no-human-gate trigger 拿掉（負例改成合法 step） | RED ✓ |
| 正例 automated_step `human_acceptance_gate` 翻 `false` | RED ✓ |

還原後 `git diff --stat` 為空。第一次探針因 perl 縮排寫錯（6 空格 vs 實際 4 空格）誤顯 PASS，改正縮排後確認 RED。

## Product fit 回填

- Measured gap 已關閉：AIWR 線（`SSP-299`～`SSP-305`）現有可驗邊界契約，升格語意集中於此。
- Why not less / why not more / do not absorb / rollback：見卡片。新增 4 檔不連 runtime，單獨 revert `67f76fa` 即可移除。

## 待辦

- backlog 未改；等大 review `GO` 後由 Owner accept 時更新（`文件/待辦重整.md` 需加 AIWR 段或註記）。
- 大 review 交接卡：`.work/handoff/SSP298-REVIEW-20260907.md`（＋companion diff `.work/handoff/SSP298-REVIEW-20260907.diff`）。
