---
id: REFACTOR-VALIDATOR-STRUCTURE-REVIEW-20260909
type: big-review-handoff
card: .work/CARD-REFACTOR-VALIDATOR-STRUCTURE-20260909.md
evidence: .work/evidence/REFACTOR-VALIDATOR-STRUCTURE-20260909.md
gate_kind: REFACTOR_STRICT / behaviour-invariance
---

# 大 review 交接卡｜Repo-wide validator 結構 Refactor

平台無關。對著凍結 commit 自足。審查目標是**行為不變**：這是一次純結構 refactor，
不得改任何契約語意、evaluator 判定、failure code、fixture。

---

## 1. 審查身份與不可變邊界

| 項目 | 值 |
|---|---|
| repo | `organizational-memory-os`（工作目錄別名 `知識庫`） |
| review branch | `cc/refactor-validator-structure` |
| base SHA | `93288287034885b425f5600a10a89d4c140cc9b8`（`main`，含 6 張 accepted slice） |
| review SHA（凍結） | `f3bb423b03e18097ba21110b9a68144c57785414` |
| tree SHA | `42e03650a51d9570daca73222738f57765a60bfc` |
| 中繼 commit | `7b9c714ce253a5ff1d52810c0175a7e7ac3e8eb4`（S01）→ `f3bb423`（S02） |
| 唯一 diff range | `93288287034885b425f5600a10a89d4c140cc9b8..f3bb423b03e18097ba21110b9a68144c57785414` |

綁定檢查命令：

```bash
git rev-parse HEAD                       # 需等於 f3bb423b03e18097ba21110b9a68144c57785414
git rev-parse HEAD^{tree}                # 需等於 42e03650a51d9570daca73222738f57765a60bfc
git merge-base --is-ancestor 93288287034885b425f5600a10a89d4c140cc9b8 HEAD && echo base-ok
git diff --stat 93288287034885b425f5600a10a89d4c140cc9b8..HEAD
```

---

## 2. In-scope allowlist（路徑 + review SHA blob OID）

新增：

| 路徑 | blob OID |
|---|---|
| `scripts/lib/omos_contract_helpers.rb` | `da93e37966c83fd77f49c821344cd12ec7a20172` |
| `scripts/validate_personal_memory_resource_contract.rb` | `6d36c644f5284dc6b92c67e45ada34339323f270` |
| `scripts/validate_personal_capability_contract.rb` | `9ba2e259485e7189c677ea02ee84a07acfdba035` |
| `scripts/validate_recall_context_pack_contract.rb` | `a490bf51e23a24afa01a2ce4c3a6cac84921b6a0` |
| `scripts/validate_correction_flow_contract.rb` | `1aa22e4e99a6d4c06b6f835da78bcc76f8eb90b3` |
| `.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-20260909.md` | （evidence，非受審 code） |

修改：

| 路徑 | review SHA blob OID | 改動性質 |
|---|---|---|
| `scripts/validate_personal_memory_contract.rb` | `d3a64b52e398105dadee3f7d83b6eacea396d847` | 1119→168：移出 EMEM-01 / SSP-290/292/293；移除與 lib 逐字相同的本地 helper |
| `scripts/validate_std00_contract.rb` | `e0316d865f32f13cf3f8640ade5d5d8147745c82` | 僅移除重複 helper + 加 `require_relative` |
| `scripts/validate_std01_raw_evidence_contract.rb` | `6076f9dda291968fd04611e49b8d6f9f69efb411` | 同上（本地不同 arity 版本保留） |
| `scripts/validate_std02_source_anchor_contract.rb` | `f47bb04c9dbae1ea1235022f0709a7c8ef09bd5f` | 同上 |
| `scripts/validate_std03_normalized_document_contract.rb` | `34c724efc16d73f14c7abdd66fdabb8fb3d34a33` | 同上（429→397） |
| `scripts/validate_ai_task_card_record_contract.rb` | `5d7ca55cd1c1d2e8a50a8334d9544a1ca990951a` | 同上 |
| `scripts/validate_ai_work_record_boundary_contract.rb` | `daf9d92e4c58328cb54bb69edc9baffe99b1ed7c` | 同上 |
| `scripts/validate_ai_work_record_skill_contract.rb` | `a863979ab59408c74ec64ce01090945094b759ac` | 同上 |
| `文件/CC-Schema-Foundation-Contract-Decision-v0.1.md` | — | claim→enforcement 表補 4 條新 gate 命令 |
| `文件/待辦重整.md` | — | 規範債段補「處置結果」+ backlog |
| `.work/CARD-REFACTOR-VALIDATOR-STRUCTURE-20260909.md` | — | status → `IMPLEMENTED_AWAITING_BIG_REVIEW` |

用 `git diff-tree --no-commit-id -r --name-status f3bb423` 可重算。

---

## 3. 明確排除範圍

- 不改任何 `規格/v0.1/*.yaml`、`*.schema.json`、`規格/v0.1/fixtures/*.json`（range 內零筆）。
- 不改 evaluator 判定邏輯、failure code 字串、`EXPECTED_*` 常數值。
- 不改 STD-01/02/03 + `std_schema_engine.py` 的契約結構（僅抽 helper）。
- 不新增 gem / package；只有 `require_relative`。
- S03（`draft_card_contract_valid?` 去重）不在本次 —— DEFER backlog。
- Jira 狀態轉換、merge to main：非本卡。

---

## 4. Normative authority 與可重跑命令

全部須 PASS：

```bash
# Ruby validators（13）
for f in validate_std00_contract validate_std01_raw_evidence_contract \
         validate_std02_source_anchor_contract validate_std03_normalized_document_contract \
         validate_personal_memory_contract validate_personal_memory_resource_contract \
         validate_personal_capability_contract validate_recall_context_pack_contract \
         validate_correction_flow_contract validate_ai_work_record_boundary_contract \
         validate_ai_task_card_record_contract validate_ai_work_record_skill_contract; do
  ruby "scripts/$f.rb" || echo "FAIL $f"
done

# Python（PEP 723 inline deps）
uv run --no-project --script scripts/validate_std_schema_engine.py
uv run --no-project --script scripts/validate_cc_cross_layer_contract.py

git diff --check 93288287034885b425f5600a10a89d4c140cc9b8..HEAD
```

**行為不變基準**：在 base `9328828` 對每個 validator 擷取 stdout+exit，refactor 後逐字 `diff`。
8 個 base 已存在的 validator + cross-layer 應 stdout+exit 完全相同；schema engine 應
`PASS` 且三行 coverage 數字不變（`STD01 12/12 excl 11`、`STD02 16/16 excl 10`、`STD03 9/9 excl 11`）。
新增 4 檔應各自 `PASS`。

---

## 5. 結構搬移 → 對應關係（claim → 搬去哪 → 是否等價）

| 原 `validate_personal_memory_contract.rb` 區塊 | 搬到 | 等價性檢查 |
|---|---|---|
| scope modes / `ownership_visibility_contract` / `actor_action_policy` / `evaluate_request` / backlog registry / `cases` fixture | 留原檔（168 行） | happy-path stdout `PASS personal memory contract validation` 不變 |
| `personal_memory_resource_contracts` 結構 asserts + `resource_failures` / `evaluate_resource_case` / `validate_support_*` / `validate_conflict_*` / `build_indexes` + `resource_cases` fixture + `EXPECTED_RESOURCE_NEGATIVE_LABELS` 覆蓋 | `validate_personal_memory_resource_contract.rb`（347） | 只用 `has_path?`/`assert_required_paths`/`enum_from` 三個本地 helper（一併搬），無 EMEM-00 交參 |
| `capability_matrix` / `level_transitions` / `capability_safety_floor` asserts + `capability_profile_failure` / `level_transition_failure` + capability/transition fixtures | `validate_personal_capability_contract.rb`（253） | 常數 `EXPECTED_CAPABILITY_*` / `LEVEL_ORDER` 等逐字搬移 |
| `recall_context_pack.contract` asserts + `context_pack_failure` + context-pack fixtures | `validate_recall_context_pack_contract.rb`（179） | 同上 |
| `correction_flow.contract` asserts + `correction_proposal_failure` / `supersession_receipt_failure` + `omos_urn?` / `dig_dotted` + correction fixtures | `validate_correction_flow_contract.rb`（218） | `EXPECTED_CORRECTION_KINDS.each_value` cross-assert 至 `PersonalMemoryRecord` lifecycle 一併搬 |
| 8 檔逐字相同的 `DuplicateKeyError` / `StrictJsonObject` / `assert_unique_yaml_mapping_keys` / `present?` | `scripts/lib/omos_contract_helpers.rb` | 逐字；STD/AIWR 的本地 `read_json`/`read_yaml`/`assert`/`sorted_set`（不同 arity）保留並覆蓋 lib |

---

## 6. 指定加壓面

1. **行為不變是唯一驗收**：對每個 validator，在 `9328828` 與 `f3bb423` 各跑一次，
   `diff` stdout、比對 exit code。任一不同 = `NO_GO`。
2. **搬移完整性**：原檔 1119 行的每一條 `assert(...)` 與每個 `*_failure` 分支，是否在
   5 個新檔中都還在？有沒有哪條 assert 在搬移時被吞掉（→ 假綠）？
3. **helper 覆蓋語意**：lib 現在也定義簡單版 `read_json`/`read_yaml`/`assert`/`sorted_set`。
   STD-01/02/03 與 AIWR 檔在 `require_relative` **之後**還定義自己的版本 —— 確認 Ruby 的
   後定義覆蓋前定義對「頂層 `def`（等同 `Object` private method）」成立，且這些檔實際用到的
   是自己的版本（例如 STD 的 `read_json(path, failures)` 兩參數版）。
4. **`sorted_set` 型別**：lib 版回傳 `Set`（`values.to_set`）；AIWR 版回傳排序 `Array`。
   確認 AIWR 檔仍載自己的版本，沒有因為 lib 版被誤用而讓「集合相等比較」語意改變。
5. **`require "set"`**：lib 加了 `require "set"`；確認 `sorted_set` 的 `Set` 版在所有
   personal-memory 家族檔可用（Ruby 3.2+ `Set` 為 autoload，但明示 require 較保險）。
6. **新檔獨立性**：4 個新檔各自 `read_yaml(SPEC_PATH)` 讀同一份 yaml；確認沒有跨檔隱性
   相依（例如某個 `EXPECTED_*` 常數只在原檔定義、搬移後某檔漏帶）。
7. **fixture 重複讀取**：新檔各自 `read_json(POSITIVE_FIXTURE_PATH).fetch(...)` 多次；
   `StrictJsonObject` dup-key guard 仍在（來自 lib），確認沒有繞過。

---

## 7. 結構化輸出契約（YAML）

```yaml
review_input:
  base_sha: "93288287034885b425f5600a10a89d4c140cc9b8"
  review_sha: "f3bb423b03e18097ba21110b9a68144c57785414"
  tree_sha: "42e03650a51d9570daca73222738f57765a60bfc"
verdict: GO | NO_GO
counts:
  p0: 0
  p1: 0
  p2: 0
  p3: 0
findings:
  - id: F-01
    severity: P0 | P1 | P2 | P3
    path: "scripts/<file>:<line>"        # 對 review SHA 的行號
    trigger: "<觸發輸入 / 重跑步驟>"
    observed: "<與 base 相比的 stdout/exit/行為差異>"
    risk: "<契約語意或覆蓋面被改變的具體風險>"
    recommendation: "<定點修法>"
verification:
  behaviour_diff_vs_base:
    ran: true | false
    all_byte_identical: true | false        # 8 base validators + cross-layer
    schema_engine_pass: true | false
    schema_engine_coverage_unchanged: true | false
  new_files_all_pass: true | false          # 4 new S02 files
  mutation_probes_replayed: true | false
  git_diff_check_clean: true | false
```

---

## 8. Gate 與 targeted re-review 規則

- 任一 reviewer `P0` / `P1` → `NO_GO`。開
  `.work/CARD-REFACTOR-VALIDATOR-STRUCTURE-REPAIR-NN-20260909.md`，同 branch 定點修，
  沿同一 review line 定點複審（只驗原 finding + 行為不變 regression），原 review SHA
  `f3bb423` 保持 immutable。
- `P2` / `P3` → 記 `文件/待辦重整.md` backlog；若其實會改變任一契約語意或覆蓋面，升 `P1`。
- 無 `P0` / `P1` 且「8 base validators + cross-layer stdout/exit 逐字不變 + schema engine
  coverage 不變 + 4 新檔 PASS」→ 寫
  `.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-REREVIEW-NN-20260909.yaml` receipt →
  Owner accept → merge `cc/refactor-validator-structure` → `main`。
- accept 後：Lane A → `SSP-294`、Lane B → `SSP-301`。
