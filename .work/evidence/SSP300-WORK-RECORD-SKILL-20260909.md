---
id: SSP300-WORK-RECORD-SKILL-20260909
type: evidence
card: .work/CARD-SSP300-WORK-RECORD-SKILL-20260909.md
status: IMPLEMENTED_AWAITING_BIG_REVIEW
---

# SSP-300 實作證據

## Checkpoint

- Branch：`cc/ssp300-work-record-skill`（自 `cc/ssp299-task-card-format` @ `1ea01cf`）。
- Implementation commit：`ce154ecd642c9e7198ef84925ea497297d5cb2f8`。
- Parent / base：`1ea01cfb1af0668cf0f9c3f7c935030bec2dd22c`（SSP-299 accepted tip）。
- Tree：`952f1a638372b67e701851476ae04cc858d5450d`。

## 變更（`1ea01cf..ce154ec`，全新增）

| 狀態 | 路徑 | review blob OID |
|---|---|---|
| A | `規格/v0.1/ai-work-record-skill.yaml` | `206e1faa19a6fbf379b5e7f12d0de2c11271c6f6` |
| A | `scripts/validate_ai_work_record_skill_contract.rb` | `8eb598cab71033010d3188598a71332b23056917` |
| A | `規格/v0.1/fixtures/ai-work-record-skill-positive-fixtures.json` | `f3abde1769d1303faa267b75e1d4d796a9bf484a` |
| A | `規格/v0.1/fixtures/ai-work-record-skill-negative-fixtures.json` | `c479c3ed48bcf474bca565f57db80b50f7365800` |
| A | `.work/CARD-SSP300-WORK-RECORD-SKILL-20260909.md` | `696da5ea8633ea3621b77a1047535ac688123f88` |

新增 4 檔 + 卡片。未觸碰任何既有 validator / schema / fixture。

## 契約（`ai-work-record-skill.yaml`，`schema_id urn:omos:schema:ai-work-record-skill:0.1.0`）

- `input_contract`：`required_fields = [lifecycle_events, seed_fields]`；`seed_field_keys = [objective, scope, constraints, acceptance]`；events 非空、首個為 `start`、每個 ∈ `ai-task-card-record.lifecycle_event_to_status` keys。
- `output_contract`：`required_fields = [draft_card, evidence_refs, dry_run, replayed_status]`；`draft_card` 必須 contract-valid（依 `ai-task-card-record` spec）；`evidence_refs` 每項 omos URN string（reference only）；`replayed_status` == lifecycle replay final。
- `authority`：`accepts_memory: false`、`writes_company_knowledge: false`、`error_behavior: FAIL_LOUD`、`forbidden_output_fields = [personal_acceptance_ref, verification_receipt_ref, accepted_for_record, canonical_write_receipt_ref]`。
- `error_contract`：8 個 code → message key。
- `runtime_independence: true`。
- `cross_reference.must_match`：`lifecycle_events_from` / `gate_positions_from` / `non_acceptance_authority_from` 三個 pointer 綁至 boundary 與 card-record spec 的實際路徑；validator 鎖 pointer 字串且要求引用目標存在非空。
- `hard_stops`：不做 hook/loop/harness/hermes；pure function + 資料表；不重定義 `SSP-298` automated_step 或 `SSP-299` 卡片格式；不建 registry/FSM/DB。

## Validator（`validate_ai_work_record_skill_contract.rb`，薄判斷）

- `skill_transform_failure(input, output, card_record_spec, boundary_forbidden_fields)`：純函式。precedence `MISSING_INPUT_FIELD`（input required / seed keys 空 / events 非陣列或空）→ `UNKNOWN_LIFECYCLE_EVENT` → `SKILL_LIFECYCLE_MUST_START` → `MISSING_INPUT_FIELD`（output required）→ `SKILL_EXCEEDS_AUTHORITY`（`writes_company_knowledge == true` / output 或 draft_card 帶 forbidden_output_field）→ `DRAFT_CARD_INVALID` → `EVIDENCE_INLINE_CONTENT`（evidence_refs 非全 URN string）→ `REPLAYED_STATUS_MISMATCH` → `FAIL_SILENT`（`output.error` present 且 `output.ok == true`）。
- `draft_card_contract_valid?`：資料驅動 —— 讀 `ai-task-card-record` spec 的 `fields` keys / `status_enum`，加 `card_id` URN pattern、`evidence_refs` URN array、4 個 non-empty string、boundary `forbidden_fields`、DONE 需非空 evidence。等效於 `SSP-299` 的 record shape 檢查，不 require 跨檔。
- structural 斷言：schema、`purpose.no_second_workflow_authority`、`runtime_independence`、`input/output_contract` 清單 exact、`authority` 四項、`forbidden_output_fields` exact-set、三個 `must_match.*_from` pointer exact、被引用目標存在非空、`required_negative_fixtures` == 鎖定 label。
- fixture 評估 + `EXPECTED_SKILL_NEGATIVE_LABELS - covered` 為空。

## Fixtures

- 正例：`SKILL_POS_START_REVIEW_COMPLETE`（events → DONE、draft_card DONE 帶 evidence）、`SKILL_POS_DRY_RUN_OPEN`（events `[start]` → OPEN、dry_run true）。
- 負例（7 個必備 label 全覆蓋）：
  - `SKILL_NEG_MISSING_SEED_FIELD` → `MISSING_INPUT_FIELD`
  - `SKILL_NEG_UNKNOWN_LIFECYCLE_EVENT` → `UNKNOWN_LIFECYCLE_EVENT`
  - `SKILL_NEG_DRAFT_CARD_INVALID` → `DRAFT_CARD_INVALID`
  - `SKILL_NEG_EVIDENCE_INLINE_CONTENT` → `EVIDENCE_INLINE_CONTENT`
  - `SKILL_NEG_OUTPUT_CARRIES_MEMORY_ACCEPTANCE` → `SKILL_EXCEEDS_AUTHORITY`
  - `SKILL_NEG_REPLAYED_STATUS_MISMATCH` → `REPLAYED_STATUS_MISMATCH`
  - `SKILL_NEG_FAIL_SILENT` → `FAIL_SILENT`

## Gate 結果（在 `ce154ec`）

| Gate | 結果 |
|---|---|
| `ruby scripts/validate_ai_work_record_skill_contract.rb` | `PASS` |
| `ruby scripts/validate_ai_task_card_record_contract.rb`（regression） | `PASS` |
| `ruby scripts/validate_ai_work_record_boundary_contract.rb`（regression） | `PASS` |
| `ruby scripts/validate_personal_memory_contract.rb`（regression） | `PASS` |
| STD schema engine | `PASS` |
| STD-00 / 01 / 02 / 03 | `PASS` × 4 |
| Cross-layer | `PASS`；8 negatives rejected |
| `git diff --check 1ea01cf ce154ec` | clean |
| JSON / YAML parse | OK |

## Mutation 探針（對 `ce154ec`，還原乾淨）

| 探針 | 結果 |
|---|---|
| `authority.accepts_memory` 改 `true` | RED ✓ |
| `forbidden_output_fields` 移除 `canonical_write_receipt_ref` | RED ✓ |
| `runtime_independence` 改 `false` | RED ✓ |
| evaluator 移除 replayed-status-mismatch 檢查 | RED ✓ |
| evaluator 移除 evidence-inline 檢查 | RED ✓ |
| evaluator 移除 fail-silent 檢查 | RED ✓ |
| `SKILL_NEG_OUTPUT_CARRIES_MEMORY_ACCEPTANCE` 宣告錯誤 code | RED ✓ |

（`runtime_independence` 探針第一次因 perl 縮排寫 2 空格、實際 0 空格誤顯 PASS，改正後確認 RED。）還原後 `git diff --stat` 為空。

## 待辦

- 大 review 交接卡：`.work/handoff/SSP300-REVIEW-20260909.md`。
- backlog 狀態等大 review `GO` 後由 Owner 更新。
