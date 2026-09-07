---
id: SSP290-PERSONAL-KNOWLEDGE-LEVELS-20260907
type: evidence
card: .work/CARD-SSP290-PERSONAL-KNOWLEDGE-LEVELS-20260907.md
status: IMPLEMENTED_AWAITING_BIG_REVIEW
---

# SSP-290 實作證據

## Checkpoint

- Branch：`cc/ssp290-personal-knowledge-levels`（worktree，未 push）。
- Implementation commit：`a93313d18884b0dd73b33632e813d18b7f255b7b`。
- Parent / base：`78e570a74af45f5337d7db8376cd83b67e131b26`（`docs: add CC dispatch workflow and SSP-290/298 kickoff cards`）。
- Tree：`d838e8bdc4cea03ca094dff8e4ddc241070a0809`。

## 變更檔案（`78e570a..a93313d`）

| 狀態 | 路徑 | review blob OID |
|---|---|---|
| M | `規格/v0.1/personal-harness-integration.yaml` | `cf963e2d69da15745f01c4f9736b386d58195691` |
| M | `scripts/validate_personal_memory_contract.rb` | `9bfb30535985525912c058e0d8287f5439c3ab4e` |
| M | `規格/v0.1/fixtures/personal-memory-positive-fixtures.json` | `c8b4083a045b11d45b8cc3568ae22e8786da860b` |
| M | `規格/v0.1/fixtures/personal-memory-negative-fixtures.json` | `5942c5dc0a76cad3b27e4bad947df557a1a16f3a` |
| M | `.work/CARD-SSP290-PERSONAL-KNOWLEDGE-LEVELS-20260907.md` | `a09a49ccaaf346cef91ddb9cda44fd45d3a15754` |

## 契約新增（`personal-harness-integration.yaml`，`capability_levels` 之後、`core_pipeline` 之前）

1. `capability_matrix`：16 個 phase-1 capability；`cumulative: true`；`grants` 逐級列「該級首次解鎖」的 capability（L1 4／L2 3／L3 5／L4 4，聯集 = 16，各級不重複）；`grant_semantics` 定義「有效授予 = 本級 ∪ 所有較低級」；`level_gated_actions.L4 = [correction_proposal, promotion_proposal]`。
2. `level_transitions`：`single_step_only: true`；`allowed_upgrades` L1→L2→L3→L4、L4 空；`allowed_downgrades` L4→L3→L2→L1、L1 空；`transition_requirements = [authorized_actor, reason_recorded]`；`downgrade_rules.must_preserve_safety_floor: true`；`forbidden` 列 `multi_step_jump`、`unauthorized_actor`、`downgrade_that_removes_safety_floor`、`transition_that_forks_core_contract`。
3. `capability_safety_floor`：`invariants = [permission_before_retrieval, provenance_required, canonical_single_writer, candidate_not_auto_accepted_by_level, promotion_requires_widening_gate]`；`applies_to_all_levels: true`；`downgrade_preserves_all_invariants: true`；`l4_authority_gate.authority_gate_required: true` 且 `gated_actions = [correction_proposal, promotion_proposal]`。
- 未改動 `capability_levels` 既有內容；新增 block 為 top-level sibling，`EXPECTED_CAPABILITY_KEYS` 斷言維持不變。

## Validator 新增（`validate_personal_memory_contract.rb`）

- 常數：`LEVEL_ORDER`、`EXPECTED_MATRIX_CAPABILITIES`、`EXPECTED_LEVEL_GRANTS`、`EXPECTED_CAPABILITY_SAFETY_FLOOR`、`L4_AUTHORITY_GATED_ACTIONS`、`EXPECTED_CAPABILITY_NEGATIVE_LABELS`（第 44–98 行）。
- `effective_capability_grant`（第 467 行）：回傳「本級 ∪ 所有較低級」的授予聯集。
- `capability_profile_failure`（第 477 行）：回 `nil` 或精確 code —— `UNKNOWN_CAPABILITY_LEVEL` → `LEVEL_FORKS_CORE_CONTRACT` → `CAPABILITY_ABOVE_LEVEL_GRANT` → `L4_ACTION_BYPASSES_AUTHORITY_GATE` → `SAFETY_FLOOR_INVARIANT_MISSING`。
- `level_transition_failure`（第 500 行）：回 `nil` 或 `UNKNOWN_CAPABILITY_LEVEL` / `LEVEL_TRANSITION_NOT_SINGLE_STEP` / `LEVEL_TRANSITION_UNAUTHORIZED_ACTOR` / `LEVEL_TRANSITION_REASON_NOT_RECORDED` / `LEVEL_TRANSITION_FORKS_CORE_CONTRACT` / `DOWNGRADE_REMOVES_SAFETY_FLOOR`。
- 結構斷言（第 589 行起）：`capability_matrix` capabilities／cumulative／grants 逐級鎖定值／各級 disjoint／聯集 = capabilities／`level_gated_actions.L4`；`level_transitions` 逐條 up/down 目標、`transition_requirements`、`downgrade_rules`、`forbidden`；`capability_safety_floor` invariants／`applies_to_all_levels`／`downgrade_preserves_all_invariants`／`l4_authority_gate`；並交叉檢查 `capability_levels.L4.authority_gate_required == true`。
- Fixture 評估（第 722 行起）：正例須 `failure == nil`；負例須 `failure != nil` 且 `actual == expected_failure_code`（宣告 code parity，防無關拒絕假裝覆蓋）；`EXPECTED_CAPABILITY_NEGATIVE_LABELS - covered` 必須為空。

## Fixtures

- 正例（`personal-memory-positive-fixtures.json`）：`capability_profile_cases` 5（L1／L2／L3／L4-gated／L3 部分宣稱且無 floor_state）；`level_transition_cases` 4（升 L1→L2、L3→L4；降 L4→L3、L2→L1 且 floor 保留）。
- 負例（`personal-memory-negative-fixtures.json`）：`capability_profile_negative_cases` 4、`level_transition_negative_cases` 2，覆蓋 6 個 `EXPECTED_CAPABILITY_NEGATIVE_LABELS`：
  - `CAP_NEG_L1_CLAIMS_L3_CAPABILITY` → `CAPABILITY_ABOVE_LEVEL_GRANT`
  - `CAP_NEG_L4_AUTO_PROMOTE_WITHOUT_GATE` → `L4_ACTION_BYPASSES_AUTHORITY_GATE`
  - `CAP_NEG_PROFILE_UNKNOWN_LEVEL` → `UNKNOWN_CAPABILITY_LEVEL`
  - `CAP_NEG_LEVEL_FORKS_CORE_CONTRACT` → `LEVEL_FORKS_CORE_CONTRACT`
  - `TR_NEG_L1_TO_L3_MULTI_STEP_JUMP` → `LEVEL_TRANSITION_NOT_SINGLE_STEP`
  - `TR_NEG_DOWNGRADE_DROPS_PERMISSION_FLOOR` → `DOWNGRADE_REMOVES_SAFETY_FLOOR`

## Gate 結果（在 `a93313d`）

| Gate | 命令 | 結果 |
|---|---|---|
| Personal memory contract | `ruby scripts/validate_personal_memory_contract.rb` | `PASS personal memory contract validation` |
| STD schema engine | `uv run --script scripts/validate_std_schema_engine.py` | `PASS`；STD01 12/12、STD02 16/16、STD03 9/9 |
| STD-00 | `ruby scripts/validate_std00_contract.rb` | `PASS` |
| STD-01 | `ruby scripts/validate_std01_raw_evidence_contract.rb` | `PASS` |
| STD-02 | `ruby scripts/validate_std02_source_anchor_contract.rb` | `PASS` |
| STD-03 | `ruby scripts/validate_std03_normalized_document_contract.rb` | `PASS` |
| Cross-layer | `uv run --script scripts/validate_cc_cross_layer_contract.py` | `PASS`；8 negatives rejected |
| Whitespace | `git diff --check 78e570a a93313d` | clean |
| JSON / YAML parse | `json.load` × 2、`YAML.safe_load` | OK |

## Mutation 探針（對 `a93313d`，改動後還原乾淨）

| 探針 | 結果 |
|---|---|
| `grants.L3` 移除 `cross_source_object_linking` | validator RED ✓ |
| `capability_safety_floor.invariants` 移除 `canonical_single_writer` | RED ✓ |
| `downgrade_preserves_all_invariants` 改 `false` | RED ✓ |
| `l4_authority_gate.authority_gate_required` 改 `false` | RED ✓ |
| `level_transitions` 允許 `L1 -> L3` | RED ✓ |
| 負例宣告錯誤 `expected_failure_code` | RED ✓ |
| 負例 trigger 拿掉（負例改成合法 profile） | RED ✓（validator 抓到失效負例） |
| 正例 `CAP_POS_L1_BASIC` claim `promotion_proposal` | RED ✓ |
| `capability_matrix.grants.L1` 竄改 | RED ✓ |

還原後 `git diff --stat` 為空。

## Product fit 回填

- Measured gap 已關閉：level 契約現在有能力矩陣、升降級規則與 safety-floor 不變性，`SSP-291` 的 `capability_level` 可引用可驗契約。
- Why not less / why not more / do not absorb / rollback：見卡片；本 slice 未連 runtime，單獨 revert `a93313d` 即可移除。

## 待辦

- backlog（`文件/待辦補充-個人知識庫Harness-20260830.md`、`規格/v0.1/personal-harness-integration.yaml` 的 `backlog`）未改；等大 review `GO` 後由 Owner accept 時一併更新。
- 大 review 交接卡：`.work/handoff/SSP290-REVIEW-20260907.md`（＋companion diff `.work/handoff/SSP290-REVIEW-20260907.diff`）。
