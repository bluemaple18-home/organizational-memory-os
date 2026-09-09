# Evidence｜Repo-wide validator 結構 Refactor（`REFACTOR-VALIDATOR-STRUCTURE-20260909`）

- 卡：`.work/CARD-REFACTOR-VALIDATOR-STRUCTURE-20260909.md`
- Mode：`REFACTOR_STRICT`
- branch：`cc/refactor-validator-structure`（off `main` @ `9328828`）
- 前提：6 張 `ACCEPTED_GO` slice（SSP-290/292/293/298/299/300）已整合進 `main`（`9328828`）。

## 行為不變基準（golden baseline）

Refactor 前在 `main` @ `9328828` 對每個 validator 擷取 stdout+exit 到 `/tmp/golden/`：

```
0 validate_personal_memory_contract
0 validate_ai_work_record_boundary_contract
0 validate_ai_task_card_record_contract
0 validate_ai_work_record_skill_contract
0 validate_std00_contract
0 validate_std01_raw_evidence_contract
0 validate_std02_source_anchor_contract
0 validate_std03_normalized_document_contract
0 std_schema_engine
0 cc_cross_layer
```

## S01｜共用 helper 抽取（commit `7b9c714`）

- 新 `scripts/lib/omos_contract_helpers.rb`：`DuplicateKeyError`、`StrictJsonObject`、
  `assert_unique_yaml_mapping_keys`、`present?`（8 檔逐字相同的部分）+ personal-memory 家族
  共用的簡單 `read_json` / `read_yaml` / `assert`(3-arg) / `sorted_set`(Set) / `allowed_resource_ref?`。
- 全部 8 個 Ruby validator 移除逐字相同的區塊，改 `require_relative "lib/omos_contract_helpers"`。
- STD-01/02/03 與 AIWR validator 保留各自不同 arity 的本地 `read_json` / `read_yaml` / `assert` /
  `sorted_set`（在 `require` 之後定義，覆蓋 lib 版；因此加入 lib 的簡單版本不改變其行為）。
- 驗證：10/10 validator stdout+exit 對 `/tmp/golden/` 逐字相同（唯一差異 = 未動的 Python schema
  engine 前面一行 `uv` 套件安裝 log，屬環境噪音）。mutation 抽樣 RED。
- `validate_std03` 429 → 397（僅靠移除重複 helper 即回到 `< 400`）。

## S02｜`validate_personal_memory_contract.rb` 拆分（1119 → 5 檔）

以 `grep -nE` 定位 section 邊界後，用 Python 依行範圍切出片段組裝。原檔剩 EMEM-00
（scope modes / ownership_visibility_contract / actor_action_policy / backlog registry /
policy fixture）。新增 4 檔，各自 `require_relative "lib/omos_contract_helpers"`、
讀同一份 `personal-harness-integration.yaml` + 各自 fixture section、自帶 `PASS/FAIL` footer：

| 檔案 | 內容 | 行數 |
|---|---|---|
| `validate_personal_memory_contract.rb` | EMEM-00：scope/ownership/actor_action_policy/backlog | 168 |
| `validate_personal_memory_resource_contract.rb` | EMEM-01 / PMCORE-02：四個 resource 結構、lifecycle、support/conflict ref 綁定 | 347 |
| `validate_personal_capability_contract.rb` | SSP-290：`capability_matrix` / `level_transitions` / `capability_safety_floor` + `capability_profile_failure` / `level_transition_failure` | 253 |
| `validate_recall_context_pack_contract.rb` | SSP-292：`recall_context_pack.contract` + `context_pack_failure` | 179 |
| `validate_correction_flow_contract.rb` | SSP-293：`correction_flow.contract` + `correction_proposal_failure` / `supersession_receipt_failure` | 218 |

- 卡片 body 原估「4 檔」，但 Acceptance #2 要求「每檔 `< 400`」；EMEM-00+EMEM-01 併在原檔為
  487 行仍超標，且 EMEM-01（resource contracts）自成一單元（獨立 4 resource、獨立 enums、
  獨立 `resource_cases` fixture section、helper 全 `resource`/`support`/`conflict` 前綴、
  只用到 `has_path?`/`assert_required_paths`/`enum_from` 三個本地 helper、無 EMEM-00 交參），
  故再切出第 5 檔 `validate_personal_memory_resource_contract.rb`，讓 5 檔全部 `< 400`。
- 原檔本地 `read_json` / `read_yaml` / `assert` / `sorted_set` / `allowed_resource_ref?`
  與 lib 版逐字相同，移除後改用 lib 版；stdout 仍逐字相同。

### S02 行為不變驗證

```
== golden byte-identical check (8) ==
  validate_personal_memory_contract              exit=0  IDENTICAL
  validate_ai_work_record_boundary_contract      exit=0  IDENTICAL
  validate_ai_task_card_record_contract          exit=0  IDENTICAL
  validate_ai_work_record_skill_contract         exit=0  IDENTICAL
  validate_std00_contract                        exit=0  IDENTICAL
  validate_std01_raw_evidence_contract           exit=0  IDENTICAL
  validate_std02_source_anchor_contract          exit=0  IDENTICAL
  validate_std03_normalized_document_contract    exit=0  IDENTICAL
== new S02 files (4) ==
  validate_personal_memory_resource_contract     exit=0  PASS personal memory resource contract validation
  validate_personal_capability_contract          exit=0  PASS personal capability contract validation
  validate_recall_context_pack_contract          exit=0  PASS recall context pack contract validation
  validate_correction_flow_contract              exit=0  PASS correction flow contract validation
== python ==
  cc_cross_layer IDENTICAL
  STD schema engine validator PASS
  STD01 coverage: json_schema_tested=12 json_schema_passed=12 ruby_semantic_excluded=11
  STD02 coverage: json_schema_tested=16 json_schema_passed=16 ruby_semantic_excluded=10
  STD03 coverage: json_schema_tested=9 json_schema_passed=9 ruby_semantic_excluded=11
== git diff --check ==
  clean
```

原 `validate_personal_memory_contract.rb` happy-path stdout（`PASS personal memory contract
validation`）維持逐字相同；EMEM-01 / SSP-290/292/293 的檢查移到新檔但邏輯、failure code、
fixture 判定零改動。

### mutation 探針（RED/GREEN 不變）

| 目標 | 探針 | 結果 |
|---|---|---|
| EMEM-01 結構 | `personal_memory_resource_contracts` 的 `MemoryConflictSet.forbidden_authority` 移除 `winner_selection` | RED：`FAIL MemoryConflictSet 必須禁止自行選 winner` |
| EMEM-00 evaluator | 正向 policy case 塞 `attempts_history_erasure: true` | RED：`FAIL PMEM_POS_EMPLOYEE_READ_PRIVATE 預期 allow，實際 deny` |
| SSP-290 結構 | `capability_matrix.cumulative` true→false | RED：`FAIL capability_matrix.cumulative 必須為 true` |
| SSP-290 evaluator | 正向 profile `claimed_capabilities` 塞 above-grant capability | RED：`CAPABILITY_ABOVE_LEVEL_GRANT` |
| SSP-292 結構 | `recall_context_pack.permission_strategy` INTERSECTION→UNION | RED：`FAIL ...必須是 INTERSECTION` |
| SSP-292 evaluator | 正向 pack `permission_decision_before_selection` true→false | RED：`PERMISSION_DECISION_AFTER_SELECTION` |
| SSP-293 結構 | `correction_flow.contract.immutable_receipt` true→false | RED：`FAIL ...immutable_receipt 必須為 true` |
| SSP-293 evaluator | 正向 receipt `verification_status` PASS→FAIL | RED：`CORRECTION_SKIPS_VERIFICATION` |

全部探針還原後 5 檔重跑皆 `PASS`；`規格/`、`fixtures/` 以 backup-file 方式還原，`diff` 乾淨。

## S03｜`draft_card_contract_valid?` 去重（DEFER 至 backlog）

- 卡片列為選配（「若風險過高則留 backlog」）。
- AIWR 三檔（skill 232 / task_card_record 268 / boundary 330）本身已 `< 400`，S03 不影響合規。
- S03 需再建 `scripts/lib/ai_task_card_shape.rb` 並從 `SSP-299`（`ACCEPTED_GO`）的
  `task_card_record_failure` 抽出 shape 判定 —— 動到已鎖 evaluator，風險大於收益。
- 現況維持：`validate_ai_work_record_skill_contract.rb` 內已標註的第二份 shape 檢查 + parity 測試。
- 記入 `文件/待辦重整.md` 規範債 backlog。

## `.agentskills` §2 合規現況（refactor 後）

| 檔 | 行數 | 狀態 |
|---|---|---|
| `validate_std00_contract.rb` | 124 | ✅ |
| `validate_personal_memory_contract.rb` | 168 | ✅ |
| `validate_recall_context_pack_contract.rb` | 179 | ✅ |
| `validate_correction_flow_contract.rb` | 218 | ✅ |
| `validate_ai_work_record_skill_contract.rb` | 232 | ✅ |
| `validate_personal_capability_contract.rb` | 253 | ✅ |
| `validate_ai_task_card_record_contract.rb` | 268 | ✅ |
| `validate_ai_work_record_boundary_contract.rb` | 330 | ✅ |
| `validate_personal_memory_resource_contract.rb` | 347 | ✅ |
| `validate_std03_normalized_document_contract.rb` | 397 | ✅（S01 由 429 降回） |
| `validate_std_schema_engine.py` | 436 | ⚠️ `LOCKED_OWNER_ACCEPTED`：只做 S01 helper 抽取，結構拆分 backlog |
| `validate_std02_source_anchor_contract.rb` | 512 | ⚠️ 同上（S01 前 540） |
| `validate_std01_raw_evidence_contract.rb` | 525 | ⚠️ 同上（S01 前 557） |
| `scripts/lib/omos_contract_helpers.rb` | 80 | ✅（新，共用 module） |
| `validate_cc_cross_layer_contract.py` | 168 | ✅ |

3 個 STD `LOCKED_OWNER_ACCEPTED` 檔仍 `> 400`：卡片 Scope 明訂「只做 helper 抽取，不拆結構」，
結構拆分需重開已鎖契約，記入 backlog。其餘全部合規。

## S02 Repair 01｜大 review NO_GO（1×P1 F-01）

- **F-01（P1）**：S02 把舊入口 `validate_personal_memory_contract.rb` 的 coverage 縮成只剩
  EMEM-00。golden byte-identical 沒抓到，因為 base 與 refactor 後 happy-path 都印
  `PASS personal memory contract validation`，但實際驗的面向少了 capability/resource/recall/correction。
  仍只呼叫舊命令的 CI／流程會在那些 slice 壞掉時得到假綠 → 違反 `REFACTOR_STRICT`。
- **修法（不重拆）**：
  - `git mv validate_personal_memory_contract.rb → validate_personal_memory_scope_contract.rb`
    （EMEM-00 本體整份搬，PASS 字串改 `...scope contract validation`）。
  - 新 `validate_personal_memory_contract.rb` = backward-compatible aggregator：`Open3.capture3`
    fail-closed 依序跑 5 個 slice（scope/resource/capability/recall/correction），全綠才印
    與 refactor 前逐字相同的 `PASS personal memory contract validation`；任一 slice 非 0 →
    轉發其 stdout/stderr + `exit 1`。只 `require "open3"` / `require "rbconfig"`，無新 gem。
- **舊命令 mutation parity**（`ruby scripts/validate_personal_memory_contract.rb`）：

  | slice | mutation | 舊命令 |
  |---|---|---|
  | scope | `legal_hold_overrides_delete_and_purge` true→false | RED `FAIL legal hold 必須覆蓋 delete/purge` |
  | resource | `MemoryConflictSet.forbidden_authority` 去 `winner_selection` | RED `FAIL MemoryConflictSet 必須禁止自行選 winner` |
  | capability | `capability_matrix.cumulative` true→false | RED `FAIL capability_matrix.cumulative 必須為 true` |
  | recall | `permission_strategy` INTERSECTION→UNION | RED `FAIL ...必須是 INTERSECTION` |
  | correction | `immutable_receipt` true→false | RED `FAIL ...immutable_receipt 必須為 true` |

  全部還原後舊命令 → `PASS personal memory contract validation` exit 0。

- **行為不變 regression**：aggregator stdout+exit 對 golden byte-identical（stderr 空）；其餘 7 個
  base validator + cross-layer byte-identical；schema engine PASS、coverage 不變；5 個 slice
  直接跑皆 PASS；`git diff --check` 乾淨。
- repair 卡：`.work/CARD-REFACTOR-VALIDATOR-STRUCTURE-REPAIR-01-20260909.md`。原 frozen review
  SHA `f3bb423` 不動。

## Gate 全綠（整合樹）

`ruby` 全 14 個 Ruby validator（aggregator + 5 slice + STD-00~03 + AIWR ×3 + cross-layer）
+ `uv run --no-project --script` schema engine + JSON/YAML parse + `git diff --check` 全 PASS。
