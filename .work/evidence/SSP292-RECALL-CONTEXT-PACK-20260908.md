---
id: SSP292-RECALL-CONTEXT-PACK-20260908
type: evidence
card: .work/CARD-SSP292-RECALL-CONTEXT-PACK-20260908.md
status: IMPLEMENTED_AWAITING_BIG_REVIEW
---

# SSP-292 實作證據

## Checkpoint

- Branch：`cc/ssp292-recall-context-pack`（自 `cc/ssp290-personal-knowledge-levels` @ `5b7b883` 分出）。
- Implementation commit：`6bdf56f982955e0badceb8e9b342faa987e207af`。
- Parent / base：`5b7b88374966a64ca4bdcda8682bc016c76f938a`（SSP-290 accepted tip）。
- Tree：`4c33c63128e7134411078fac6ba957250ee2b4d7`。

## 變更（`5b7b883..6bdf56f`）

| 狀態 | 路徑 | review blob OID |
|---|---|---|
| M | `規格/v0.1/personal-harness-integration.yaml` | `441b7e9d88c18d41ef441e77777a5e463057c24e` |
| M | `scripts/validate_personal_memory_contract.rb` | `ef75ae6ad40ccac091c6229a1f5e0cfb43766234` |
| M | `規格/v0.1/fixtures/personal-memory-positive-fixtures.json` | `41d65eff9301ab1ad4fb70c42e6a0b3ef1396e21` |
| M | `規格/v0.1/fixtures/personal-memory-negative-fixtures.json` | `fafbf7ae15cd9fe609b6c9c06437ca56f3291dac` |
| A | `.work/CARD-SSP292-RECALL-CONTEXT-PACK-20260908.md` | `79a56c95355e9c876c8bd401443fe6d556d623ad` |

## 契約新增（`recall_context_pack.contract`）

- `request_required_fields`（6，== `input`）與 `pack_required_fields`（12：`pack_id` / `request_ref` / `permission_decision_ref` / `permission_decision_before_selection` / `permission_decision_covered_memory_refs` / `selected_memories` / `source_refs` / `applicability` / `freshness` / `permission_intersection_refs` / `omitted_or_gap_notice` / `budget_usage`）。
- `permission_ordering.decision_before_candidate_set: true`、`decision_scope_covers_selected: true`。
- `gap_notice_reasons: [STALE_PRESENT, NOT_APPLICABLE_FILTERED, BUDGET_OMITTED]`。
- `forbidden: [SEARCH_ALL_THEN_PROMPT_GUARD, UNRESTRICTED_GLOBAL_SEARCH, STALE_WITHOUT_FRESHNESS, CROSS_OWNER_WITHOUT_INTERSECTION]`。
- `contract_registry.define_for_employee_memory.MemoryContextPack.required_fields_ref` → `recall_context_pack.contract.pack_required_fields`。
- 未動 `recall_context_pack.input` / `output` / `permission_strategy` / `unrestricted_global_personal_memory_search`。

## Validator 新增

- 常數（第 91–128 行）：`EXPECTED_RECALL_REQUEST_FIELDS`、`EXPECTED_CONTEXT_PACK_FIELDS`、`EXPECTED_RECALL_GAP_REASONS`、`EXPECTED_RECALL_FORBIDDEN`、`EXPECTED_RECALL_NEGATIVE_LABELS`（6）。
- `context_pack_failure(request, pack)`（第 570 行）：薄判斷，回 `nil` 或精確 code —— precedence：`RECALL_REQUEST_MISSING_FIELD` → `CONTEXT_PACK_MISSING_FIELD` → `SEARCH_ALL_THEN_PROMPT_GUARD` → `PERMISSION_DECISION_AFTER_SELECTION` → `PERMISSION_DECISION_SCOPE_TOO_NARROW` → `CROSS_OWNER_WITHOUT_INTERSECTION` → `STALE_WITHOUT_FRESHNESS` → `BUDGET_OMITTED_WITHOUT_NOTICE`。不做 retrieval / 向量 / budget 演算法。
- structural 斷言（第 733 行起）：`permission_strategy == INTERSECTION`、`unrestricted_global_personal_memory_search == forbidden`、`contract.request_required_fields` / `pack_required_fields` exact 順序、`permission_ordering` 兩旗標、`gap_notice_reasons` / `forbidden` exact-set、`MemoryContextPack.required_fields_ref` 指向正確。
- fixture 評估（第 870 行起）：正例 `failure == nil`；負例 `failure != nil` 且 `actual == expected_failure_code`；`EXPECTED_RECALL_NEGATIVE_LABELS - covered` 必須為空。

## Fixtures

- 正例：`CTXPACK_POS_FRESH_SELF_ONLY`（單一 fresh、自己 owner、無 gap）、`CTXPACK_POS_STALE_BUDGET_CROSS_OWNER_ALL_NOTICED`（stale + budget omission + 跨 owner 全部正確標註／帶 intersection）。
- 負例（6，覆蓋全部 `EXPECTED_RECALL_NEGATIVE_LABELS`）：
  - `CTXPACK_NEG_REQUEST_MISSING_BUDGET` → `RECALL_REQUEST_MISSING_FIELD`
  - `CTXPACK_NEG_DECISION_SCOPE_TOO_NARROW` → `PERMISSION_DECISION_SCOPE_TOO_NARROW`
  - `CTXPACK_NEG_SEARCH_ALL_THEN_PROMPT_GUARD` → `SEARCH_ALL_THEN_PROMPT_GUARD`
  - `CTXPACK_NEG_STALE_WITHOUT_FRESHNESS` → `STALE_WITHOUT_FRESHNESS`
  - `CTXPACK_NEG_BUDGET_OMITTED_WITHOUT_NOTICE` → `BUDGET_OMITTED_WITHOUT_NOTICE`
  - `CTXPACK_NEG_CROSS_OWNER_WITHOUT_INTERSECTION` → `CROSS_OWNER_WITHOUT_INTERSECTION`

## Gate 結果（在 `6bdf56f`）

| Gate | 結果 |
|---|---|
| `ruby scripts/validate_personal_memory_contract.rb` | `PASS`（含新 recall 分支；SSP-290 6 個 capability negative label 未 regress） |
| STD schema engine | `PASS` |
| STD-00 / 01 / 02 / 03 | `PASS` × 4 |
| Cross-layer | `PASS`；8 negatives rejected |
| `git diff --check 5b7b883 6bdf56f` | clean |
| JSON / YAML parse | OK |

## Mutation 探針（對 `6bdf56f`，還原乾淨）

| 探針 | 結果 |
|---|---|
| `recall_context_pack.contract.forbidden` 移除 `SEARCH_ALL_THEN_PROMPT_GUARD` | RED ✓ |
| `permission_ordering.decision_before_candidate_set` 改 `false` | RED ✓ |
| `request_required_fields` 移除 `context_budget` | RED ✓ |
| evaluator 移除 scope-covers 檢查 | RED ✓ |
| evaluator 移除 cross-owner 檢查 | RED ✓ |
| stale 負例宣告錯誤 code | RED ✓ |

（第一次 forbidden-list 探針因 perl 縮排寫 4 空格、實際 6 空格誤顯 PASS，改正後確認 RED。）

## 待辦

- 大 review 交接卡：`.work/handoff/SSP292-REVIEW-20260908.md`。
- backlog 狀態等大 review `GO` 後由 Owner 更新。
