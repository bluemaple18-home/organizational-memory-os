---
id: SSP293-CORRECTION-SUPERSESSION-20260909
type: evidence
card: .work/CARD-SSP293-CORRECTION-SUPERSESSION-20260909.md
status: IMPLEMENTED_AWAITING_BIG_REVIEW
---

# SSP-293 實作證據

## Checkpoint

- Branch：`cc/ssp293-correction-supersession`（自 `cc/ssp292-recall-context-pack` @ `8e7985f`）。
- Implementation commit：`8ca640b1417189bd8d8637c7035afa00843e96c3`。
- Parent / base：`8e7985f97aa47eb0cba0996792a697601adf9ca4`（SSP-292 accepted tip）。
- Tree：`859dd5d9e79b6d75d57645e6e329af51704dc3aa`。

## 變更（`8e7985f..8ca640b`）

| 狀態 | 路徑 | review blob OID |
|---|---|---|
| M | `規格/v0.1/personal-harness-integration.yaml` | `2aac98e566bb8324f6c2af4e62fe348d4a9a1cfd` |
| M | `scripts/validate_personal_memory_contract.rb` | `b766df66785384db41f47817e60819faa5ce4123` |
| M | `規格/v0.1/fixtures/personal-memory-positive-fixtures.json` | `879eb1a93c135e80297ccd9d0eab2251f1dd083b` |
| M | `規格/v0.1/fixtures/personal-memory-negative-fixtures.json` | `5cbc941f9a0f905293b0e1341bf37b745669d697` |
| A | `.work/CARD-SSP293-CORRECTION-SUPERSESSION-20260909.md` | `dbba0bc5fada98a4c633b18b75759a668a5bdd9b` |

## 契約新增（`correction_flow.contract`）

- `correction_kinds`：`AMEND → SUPERSEDED`、`INVALIDATE → INVALIDATED`、`SUPERSEDE → SUPERSEDED`（validator 交叉檢查目標 status ∈ `record_status` enum）。
- `proposal_required_fields`（8）、`supersession_receipt_required_fields`（10，identity/lineage 用）、`gate_enforced_fields`（`verification_receipt_ref` / `personal_acceptance_ref` —— 不放 required list，由 gate 分支強制，避免被通用 missing-field 先攔掉失去語意）。
- `gate.verification_status_must_be: PASS` + `gate.requires`；`supersede_requires_new_record_ref: true`；`immutable_receipt: true`；`forbidden`（`history_erasure` / `in_place_record_overwrite` / `skip_verification` / `skip_acceptance` / `receipt_mutation`）。
- `contract_registry.define_for_employee_memory.{MemoryCorrectionProposal, MemorySupersessionReceipt}.required_fields_ref` 指向對應清單。
- 未動 `personal_memory_resource_contracts`（保持 exact-4 resource 斷言）、`correction_flow.steps`、`SSP-290`/`SSP-292` 已鎖區塊。

## Validator 新增

- `correction_proposal_failure`：`CORRECTION_PROPOSAL_MISSING_FIELD`（`correction_evidence_refs` 只做 `key?`，空/非陣列另回 `CORRECTION_MISSING_EVIDENCE`）→ `CORRECTION_PROPOSAL_INVALID_ID` → `CORRECTION_TARGET_NOT_RECORD` → `CORRECTION_KIND_INVALID` → `CORRECTION_MISSING_EVIDENCE`。
- `supersession_receipt_failure`：`SUPERSESSION_RECEIPT_MISSING_FIELD` → `SUPERSESSION_RECEIPT_INVALID_ID`（`receipt_id` / `old_record_ref`）→ `CORRECTION_RECEIPT_MUTATED`（`mutated` / `receipt_superseded_by`）→ `CORRECTION_HISTORY_ERASURE` → `CORRECTION_IN_PLACE_OVERWRITE`（`in_place_overwrite` / `in_place_content_patch`）→ `CORRECTION_KIND_INVALID` → `CORRECTION_SKIPS_VERIFICATION`（status != PASS 或缺 `verification_receipt_ref`）→ `CORRECTION_SKIPS_ACCEPTANCE`（缺 `personal_acceptance_ref`）→ `CORRECTION_KIND_LIFECYCLE_MISMATCH` → `CORRECTION_SUPERSEDE_MISSING_NEW_RECORD`（SUPERSEDE 需 `new_record_ref` ≠ `old_record_ref`）。
- structural 斷言：`correction_kinds` 映射、兩個 required-fields 清單 exact、`gate.verification_status_must_be`、`gate.requires` / `gate_enforced_fields` exact-set、`supersede_requires_new_record_ref`、`immutable_receipt`、`forbidden` exact-set、兩個 `required_fields_ref` pointer、`correction_kind` 目標 status ∈ `record_status` enum。
- fixture 評估：正例 `failure == nil`；負例 `actual == expected_failure_code`；`EXPECTED_CORRECTION_NEGATIVE_LABELS - covered` 為空。

## Fixtures

- 正例：`CORR_PROP_POS_AMEND`；`CORR_RECEIPT_POS_AMEND`、`CORR_RECEIPT_POS_SUPERSEDE_NEW_RECORD`（`new_record_ref` ≠ `old_record_ref`）。
- 負例（7 個必備 label 全覆蓋）：
  - `CORR_PROP_NEG_NO_EVIDENCE` → `CORRECTION_MISSING_EVIDENCE`
  - `CORR_RECEIPT_NEG_SKIPS_VERIFICATION` → `CORRECTION_SKIPS_VERIFICATION`
  - `CORR_RECEIPT_NEG_SKIPS_ACCEPTANCE` → `CORRECTION_SKIPS_ACCEPTANCE`
  - `CORR_RECEIPT_NEG_IN_PLACE_OVERWRITE` → `CORRECTION_IN_PLACE_OVERWRITE`
  - `CORR_RECEIPT_NEG_HISTORY_ERASURE` → `CORRECTION_HISTORY_ERASURE`
  - `CORR_RECEIPT_NEG_KIND_LIFECYCLE_MISMATCH` → `CORRECTION_KIND_LIFECYCLE_MISMATCH`
  - `CORR_RECEIPT_NEG_MUTATED_AFTER_THE_FACT` → `CORRECTION_RECEIPT_MUTATED`

## Gate 結果（在 `8ca640b`）

| Gate | 結果 |
|---|---|
| `ruby scripts/validate_personal_memory_contract.rb` | `PASS`（含新 correction 分支；SSP-290 6 個 capability negative label + SSP-292 6 個 recall negative label 未 regress） |
| STD schema engine | `PASS` |
| STD-00 / 01 / 02 / 03 | `PASS` × 4 |
| Cross-layer | `PASS`；8 negatives rejected |
| `git diff --check 8e7985f 8ca640b` | clean |
| JSON / YAML parse | OK |

## Mutation 探針（對 `8ca640b`，還原乾淨）

| 探針 | 結果 |
|---|---|
| `correction_kinds.AMEND` 改 `INVALIDATED` | RED ✓ |
| `gate.verification_status_must_be` 改 `PARTIAL` | RED ✓ |
| `forbidden` 移除 `receipt_mutation` | RED ✓ |
| evaluator 移除 skips-acceptance 檢查 | RED ✓ |
| evaluator 移除 kind-lifecycle-mismatch 檢查 | RED ✓ |
| `CORR_RECEIPT_NEG_MUTATED_AFTER_THE_FACT` 宣告錯誤 code | RED ✓ |
| evaluator 移除 missing-evidence 檢查 | RED ✓ |

還原後 `git diff --stat` 為空。

## 待辦

- 大 review 交接卡：`.work/handoff/SSP293-REVIEW-20260909.md`。
- backlog 狀態等大 review `GO` 後由 Owner 更新。
