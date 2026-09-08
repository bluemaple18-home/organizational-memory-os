---
id: SSP299-TASK-CARD-FORMAT-20260908
type: evidence
card: .work/CARD-SSP299-TASK-CARD-FORMAT-20260908.md
status: IMPLEMENTED_AWAITING_BIG_REVIEW
---

# SSP-299 實作證據

## Checkpoint

- Branch：`cc/ssp299-task-card-format`（自 `cc/ssp298-aiwr-boundary` @ `b0401f3`）。
- Implementation commit：`86aaf8e79631580f486eb7a6508078cd2bbdc326`。
- Parent / base：`b0401f34ac44ff9f3d6d8dd672d8d7e4c95a9b27`（SSP-298 accepted tip）。
- Tree：`4e09b11df8f7699a254a55f6731649fb1989ec72`。

## 變更（`b0401f3..86aaf8e`，全新增）

| 狀態 | 路徑 | review blob OID |
|---|---|---|
| A | `規格/v0.1/ai-task-card-record.yaml` | `4fc574da887017e999345fdf5a3686180d2907e1` |
| A | `scripts/validate_ai_task_card_record_contract.rb` | `f587f7dfaafa8012eb3f4039263c6992d2aaa4d8` |
| A | `規格/v0.1/fixtures/ai-task-card-record-positive-fixtures.json` | `6188549f2dada209dc1756a272d0b75a6b694846` |
| A | `規格/v0.1/fixtures/ai-task-card-record-negative-fixtures.json` | `99af2f08687917c7e1ad883fe52bc9d4efbec5e2` |
| A | `.work/CARD-SSP299-TASK-CARD-FORMAT-20260908.md` | `c579b752a5eb01d351a993ae6b39b171a05c04e0` |

新增 4 檔 + 卡片。未觸碰任何既有 validator / schema / fixture。

## 契約（`ai-task-card-record.yaml`，`schema_id urn:omos:schema:ai-task-card-record:0.1.0`）

- `fields`：7 個控制欄位（`card_id` urn、`objective`/`scope`/`constraints`/`acceptance` non-empty string、`status` enum、`evidence_refs` urn_array），全 `required: true`。
- `status_enum` = `[OPEN, BLOCKED, IN_REVIEW, DONE, CANCELLED]`（與 boundary contract `task_card.status_enum` 一致）。
- `allowed_status_transitions`（資料表）：`OPEN→{BLOCKED, IN_REVIEW, CANCELLED}`、`BLOCKED→{OPEN, CANCELLED}`、`IN_REVIEW→{OPEN, DONE, CANCELLED}`、`DONE→[]`、`CANCELLED→[]`。
- `lifecycle_event_to_status`：`start→OPEN`、`block→BLOCKED`、`unblock→OPEN`、`submit_review→IN_REVIEW`、`complete→DONE`、`cancel→CANCELLED`。
- `fail_closed_rules`（7）、`reconstruction`（deterministic replay，第一步必為 `start`，逐步需在 `allowed_status_transitions` 內，final = last event 的映射）。
- `cross_reference.must_match`：`is_personal_memory: false`、`status_enum` / `required_fields` / `forbidden_fields` / `forbidden_authority` 均引用 boundary contract 的 `authority_boundary.task_card`。
- `hard_stops`：不做 skill/hook/loop/harness/hermes；`allowed_status_transitions` 是資料表不是狀態機引擎；不重定義 `SSP-298` 邊界或升格路徑。

## Validator（`validate_ai_task_card_record_contract.rb`，薄判斷）

- `task_card_record_failure(card, boundary_forbidden_fields)`：precedence `CARD_MISSING_REQUIRED_FIELD`（缺 key / 4 個 non-empty string 空 / `evidence_refs` 非 Array / `card_id` 空）→ `CARD_INVALID_STATUS` → `CARD_CARRIES_FORBIDDEN_FIELD`（boundary `forbidden_fields` 任一出現）→ `CARD_SENSITIVE_CONTENT_COPIED` → `CARD_DONE_WITHOUT_EVIDENCE`（僅 `status == DONE` 時要求 `evidence_refs` 非空）。`acceptance` 一律必須非空，含「DONE 但 acceptance 空」的假完成情境由此擋下。
- `lifecycle_replay_failure(events, final_status)`：純函式；`CARD_UNKNOWN_LIFECYCLE_EVENT` → `CARD_EMPTY_LIFECYCLE` → `CARD_LIFECYCLE_MUST_START`（第一步非 `start`）→ 逐步 `CARD_ILLEGAL_STATUS_TRANSITION`（target 不在 `allowed_status_transitions[current]`）→ `CARD_RECONSTRUCTION_MISMATCH`（final ≠ 最後 event 映射）。validator 對每個正例 replay 兩次比對，證明 deterministic。
- structural 斷言：`fields` keys/required/non_empty/type、`status_enum` exact 且 == boundary、`allowed_status_transitions` 逐 from exact、`lifecycle_event_to_status` == 鎖定表、`reconstruction.deterministic`、`cross_reference.must_match.is_personal_memory` 與 boundary `task_card.is_personal_memory` 皆 false、boundary `required_fields` 與本卡 `fields` 一致、`forbidden_fields` 非空、`required_negative_fixtures` == 鎖定 label。
- fixture 評估 + `EXPECTED_RECORD_NEGATIVE_LABELS - covered` 為空。

## Fixtures

- 正例：`TCR_POS_OPEN_MINIMAL`（OPEN、`evidence_refs: []` 合法）、`TCR_POS_DONE_WITH_EVIDENCE`；lifecycle `TCR_LC_POS_START_REVIEW_COMPLETE`（→DONE）、`TCR_LC_POS_START_BLOCK_UNBLOCK_CANCEL`（→CANCELLED）。
- 負例（7 個必備 label 全覆蓋）：
  - `TCR_NEG_MISSING_SCOPE` → `CARD_MISSING_REQUIRED_FIELD`
  - `TCR_NEG_DONE_EMPTY_EVIDENCE` → `CARD_DONE_WITHOUT_EVIDENCE`
  - `TCR_NEG_DONE_EMPTY_ACCEPTANCE` → `CARD_MISSING_REQUIRED_FIELD`（label「status DONE with empty acceptance」）
  - `TCR_NEG_SENSITIVE_CONTENT_COPIED` → `CARD_SENSITIVE_CONTENT_COPIED`
  - `TCR_NEG_BOUNDARY_FORBIDDEN_FIELD` → `CARD_CARRIES_FORBIDDEN_FIELD`
  - `TCR_LC_NEG_ILLEGAL_TRANSITION`（`[start, complete]`，OPEN→DONE 非法）→ `CARD_ILLEGAL_STATUS_TRANSITION`
  - `TCR_LC_NEG_UNKNOWN_EVENT`（`[start, frobnicate]`）→ `CARD_UNKNOWN_LIFECYCLE_EVENT`

## Gate 結果（在 `86aaf8e`）

| Gate | 結果 |
|---|---|
| `ruby scripts/validate_ai_task_card_record_contract.rb` | `PASS` |
| `ruby scripts/validate_ai_work_record_boundary_contract.rb`（regression） | `PASS` |
| `ruby scripts/validate_personal_memory_contract.rb`（regression） | `PASS` |
| STD schema engine | `PASS` |
| STD-00 / 01 / 02 / 03 | `PASS` × 4 |
| Cross-layer | `PASS`；8 negatives rejected |
| `git diff --check b0401f3 86aaf8e` | clean |
| JSON / YAML parse | OK |

## Mutation 探針（對 `86aaf8e`，還原乾淨）

| 探針 | 結果 |
|---|---|
| `allowed_status_transitions.IN_REVIEW` 加 `BLOCKED` | RED ✓ |
| `lifecycle_event_to_status.complete` 改 `CANCELLED` | RED ✓ |
| `allowed_status_transitions.DONE` 加 `OPEN` | RED ✓ |
| evaluator 移除 DONE-without-evidence 檢查 | RED ✓ |
| evaluator 移除 forbidden-field 檢查 | RED ✓ |
| illegal-transition 負例宣告錯誤 code | RED ✓ |

還原後 `git diff --stat` 為空。

## 待辦

- 大 review 交接卡：`.work/handoff/SSP299-REVIEW-20260908.md`。
- backlog 狀態等大 review `GO` 後由 Owner 更新。
