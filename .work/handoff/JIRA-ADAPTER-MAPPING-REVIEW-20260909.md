---
id: JIRA-ADAPTER-MAPPING-REVIEW-20260909
type: big-review-handoff
card: .work/CARD-JIRA-ADAPTER-MAPPING-20260909.md
evidence: .work/evidence/JIRA-ADAPTER-MAPPING-20260909.md
---

# 大 review 交接卡｜Jira Adapter Mapping（repo #3）

平台無關。對著凍結 commit 自足。與 repo #2（`cc/doc-adapter-mapping`）為獨立平行 branch，
兩者皆 off `main` @ `ba518a0`，無交集。

## 1. 審查身份與不可變邊界

| 項目 | 值 |
|---|---|
| repo | `bluemaple18-home/organizational-memory-os` |
| review branch | `cc/jira-adapter-mapping` |
| base SHA | `ba518a06db797de955cc4830b4564ddd676ac775`（`main`） |
| review SHA（凍結） | `170da7fdbf93d2bff29172abdad59c830aa53641` |
| tree SHA | `4b66e1bbbf5e029300166d661659c85072327fd0` |
| 唯一 diff range | `ba518a06db797de955cc4830b4564ddd676ac775..170da7fdbf93d2bff29172abdad59c830aa53641` |

```bash
git rev-parse HEAD                 # = 170da7fdbf93d2bff29172abdad59c830aa53641
git rev-parse HEAD^{tree}          # = 4b66e1bbbf5e029300166d661659c85072327fd0
git merge-base --is-ancestor ba518a06db797de955cc4830b4564ddd676ac775 HEAD && echo base-ok
git diff --stat ba518a06db797de955cc4830b4564ddd676ac775..HEAD
```

## 2. In-scope allowlist（路徑 + review SHA blob OID）

| 路徑 | blob OID | 性質 |
|---|---|---|
| `規格/v0.1/jira-adapter-mapping.yaml` | `d58da1585d6d233291eda642db829ff172a036d0` | 新契約 |
| `scripts/validate_jira_adapter_mapping_contract.rb` | `8d2a2ea0f2bef3c788b3cd8b10a2e6d59721707d` | 新薄 validator（208 行） |
| `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json` | `bba7f449b7a9a98b996f8d1896a1e6619c8420a0` | 2 positive |
| `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json` | `cf21c735591ff0378136352ea8c571e651ac96b5` | 11 negative |
| `.work/CARD-JIRA-ADAPTER-MAPPING-20260909.md` | — | 任務卡 |
| `.work/evidence/JIRA-ADAPTER-MAPPING-20260909.md` | — | evidence |

## 3. 明確排除範圍

- 不改 `規格/v0.1/raw-evidence-envelope.schema.json`（STD-01）/
  `source-anchor-jira-cloud-entity-segment-v1.schema.json`（STD-02 profile）—— 皆
  `LOCKED_OWNER_ACCEPTED`，range 內零筆修改。
- 不改 STD-00~03 validator、AIWR / personal-memory 契約。
- 不做 Jira connector / REST client / webhook runtime。
- 不動 repo #2（Document Adapter Mapping，branch `cc/doc-adapter-mapping`）。
- 不新增 gem / package。

## 4. Normative authority 與可重跑命令（全部須 PASS）

```bash
ruby scripts/validate_jira_adapter_mapping_contract.rb           # 本卡
ruby scripts/validate_personal_memory_contract.rb                # aggregator regression
for n in 00 01_raw_evidence 02_source_anchor 03_normalized_document; do ruby scripts/validate_std${n}_contract.rb; done
for c in boundary task_card_record skill hook loop harness hermes_adapter e2e_acceptance; do ruby scripts/validate_ai_work_record_${c}_contract.rb 2>/dev/null || ruby scripts/validate_ai_${c}_contract.rb; done
uv run --no-project --script scripts/validate_std_schema_engine.py
uv run --no-project --script scripts/validate_cc_cross_layer_contract.py
git diff --check ba518a06db797de955cc4830b4564ddd676ac775..HEAD
```

`std_schema_engine` coverage 應維持 `STD01 12/12 excl 11`、`STD02 16/16 excl 10`、`STD03 9/9 excl 11`。

## 5. Spec claim → exact enforcement → fixture parity

| Spec claim | enforcement（`jira_mapping_failure` / 結構） | fixture |
|---|---|---|
| 只映射 4 個 issue 文字欄位 kind | `jira_field_kinds == [SUMMARY, DESCRIPTION, COMMENT_BODY, ADF_TEXT_NODE]`；evaluator `JIRA_MAP_UNKNOWN_FIELD_KIND` | `JIRA_MAP_NEG_UNKNOWN_FIELD_KIND` |
| 投影欄位是 STD-01 的合法 property | evaluator 讀 `raw-evidence-envelope.schema.json` properties → `JIRA_MAP_FIELD_NOT_IN_TARGET_SCHEMA` | `JIRA_MAP_NEG_FIELD_NOT_IN_TARGET_SCHEMA` |
| 確定性身份（cloud_id + issue_id） | `native_id_basis == JIRA_CLOUD_ID_PLUS_ISSUE_ID` → `JIRA_MAP_NONDETERMINISTIC_IDENTITY` | `JIRA_MAP_NEG_NONDETERMINISTIC_IDENTITY` |
| payload reference-only | `payload_ref` present、無 `inline_content` → `JIRA_MAP_PAYLOAD_INLINE` | `JIRA_MAP_NEG_PAYLOAD_INLINE` |
| compound source_version | `basis == COMPOUND_OBSERVED` ∈ STD-01 enum + `kind == UPDATED_AT_DIGEST` ∈ enum + 非空 `secondary_digest` → `JIRA_MAP_VERSION_NOT_COMPOUND` | `JIRA_MAP_NEG_VERSION_NOT_COMPOUND` |
| anchor profile 綁 STD-02 locked profile | `profile == JIRA_CLOUD_ENTITY_SEGMENT_V1` 且等於 profile schema const；`profile_details` key set == schema `profile_details.required`（10 欄）；deployment_type CLOUD / entity_type issue / issue_id `^[0-9]+$` / text_selector unit+range+序 → `JIRA_MAP_PROFILE_MISMATCH` / `JIRA_MAP_PROFILE_DETAILS_MALFORMED` | `JIRA_MAP_NEG_PROFILE_MISMATCH` / `JIRA_MAP_NEG_PROFILE_DETAILS_MALFORMED` |
| JSON_POINTER selector | `selectors` 含 `JSON_POINTER` → `JIRA_MAP_SELECTOR_MISSING` | `JIRA_MAP_NEG_SELECTOR_MISSING` |
| reconciliation 不改 identity、不靜默漏 gap | `changed_identity == true` → `JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY`；`detected_gap == true && emitted_evidence_or_gap != true` → `JIRA_MAP_RECONCILIATION_SILENT_GAP` | `JIRA_MAP_NEG_RECONCILIATION_CHANGES_IDENTITY` / `JIRA_MAP_NEG_RECONCILIATION_SILENT_GAP` |
| fail-loud | `error` present 但 `ok != false` → `FAIL_SILENT` | `JIRA_MAP_NEG_FAIL_SILENT` |
| cross_reference pointer binding | `must_match` 五 pointer 字串 exact + 引用目標存在（含 profile const == JIRA_CLOUD_ENTITY_SEGMENT_V1、profile_details.required 含 text_selector） | 結構斷言 |

每個負例單一 mutation；evidence 記錄「移除對應 enforcement → `ruby` exit 1（RED）」×11，全數 load-bearing。

## 6. 指定加壓面

1. **`profile_details` 由 STD-02 profile schema 已鎖成 10 欄 `additionalProperties: false`**：
   本卡 evaluator 額外驗 key set exact + deployment_type/entity_type/issue_id/text_selector 幾個
   值。確認這是「document adapter 產出時必須符合 schema」的收斂，**不是**重定義 STD-02。
2. **`reconciliation` 為 optional**：`projection["reconciliation"]` 缺時 evaluator 跳過該段
   （代表這次不是 reconciliation run）。確認沒有讓「其實是 reconciliation 卻不宣告」的 run 溜過
   —— 屬契約邊界（本卡無法知道 run 隱藏了 reconciliation 語意），非漏洞。
3. **compound version 的第三元素**：目前驗 `basis + kind + secondary_digest 非空` 三項。
   `source_version.value`（updated timestamp）本身沒驗非空。是否該要求 `value` 為 RFC3339
   string？（傾向 P2 backlog —— `value` schema 允許 `["string","null"]`，但 compound 語意下
   應有值。）
4. **`field_id_by_kind` 把 `ADF_TEXT_NODE` 也映到 `description`**：ADF 文字節點目前一律當
   description 欄位的子節點。若未來要支援 comment 內的 ADF 節點，這個對映需擴充。確認現階段
   （文件 + Jira 第一批）足夠。
5. **`issue_id` 正整數字串檢查**：`/\A[0-9]+\z/`。Jira Cloud issue id 是數字字串（非 issue key
   `SSP-291`）。確認與 STD-02 profile schema 的 `issue_id` pattern `^[0-9]+$` 一致。
6. **duplicate JSON / YAML key**：4 個新檔經 `StrictJsonObject` / `assert_unique_yaml_mapping_keys`（lib）解析。

## 7. 結構化輸出契約（YAML）

```yaml
review_input:
  base_sha: "ba518a06db797de955cc4830b4564ddd676ac775"
  review_sha: "170da7fdbf93d2bff29172abdad59c830aa53641"
  tree_sha: "4b66e1bbbf5e029300166d661659c85072327fd0"
verdict: GO | NO_GO
counts: { p0: 0, p1: 0, p2: 0, p3: 0 }
findings:
  - id: F-01
    severity: P0 | P1 | P2 | P3
    path: "規格/v0.1/jira-adapter-mapping.yaml:<line> | scripts/validate_jira_adapter_mapping_contract.rb:<line>"
    trigger: "<觸發輸入 / 重跑步驟>"
    observed: "<spec 宣稱 vs validator 實擋>"
    risk: "<非確定性投影 / 重定義 STD / compound version 弱化 / reconciliation 破壞 identity 被繞過的風險>"
    recommendation: "<定點修法>"
verification:
  gate_all_pass: true | false
  enforcement_parity_replayed: true | false      # 11 個 enforcement 移除 → RED
  std_schemas_untouched: true | false
  reconciliation_semantics_reviewed: true | false
  dup_key_fail_closed: true | false
```

## 8. Gate 與 targeted re-review 規則

- 任一 reviewer `P0` / `P1` → `NO_GO`。開 `.work/CARD-JIRA-ADAPTER-MAPPING-REPAIR-NN-20260909.md`，
  同 branch 定點修，沿同一 review line 定點複審（只驗原 finding + regression），原 review
  SHA `170da7f` immutable。
- `P2` / `P3` → 記 `文件/待辦重整.md` backlog；若能繞過「確定性投影」「不重定義 STD」
  「compound version」「reconciliation 不破壞 identity」任一，升 `P1`。
- 無 `P0` / `P1` 且 gate 全綠 + enforcement parity 成立 → 寫
  `.work/evidence/JIRA-ADAPTER-MAPPING-REREVIEW-NN-20260909.yaml` receipt → 更新
  `文件/待辦重整.md` → Owner accept → merge `cc/jira-adapter-mapping` → `main`。
- accept 後（連同 repo #2 Document Adapter Mapping）→ `EMEM-02`（`SSP-291`）解除。
