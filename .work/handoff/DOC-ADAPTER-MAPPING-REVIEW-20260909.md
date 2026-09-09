---
id: DOC-ADAPTER-MAPPING-REVIEW-20260909
type: big-review-handoff
card: .work/CARD-DOC-ADAPTER-MAPPING-20260909.md
evidence: .work/evidence/DOC-ADAPTER-MAPPING-20260909.md
---

# 大 review 交接卡｜Document Adapter Mapping（repo #2）

平台無關。對著凍結 commit 自足。

## 1. 審查身份與不可變邊界

| 項目 | 值 |
|---|---|
| repo | `bluemaple18-home/organizational-memory-os` |
| review branch | `cc/doc-adapter-mapping` |
| base SHA | `ba518a06db797de955cc4830b4564ddd676ac775`（`main`） |
| review SHA（凍結） | `c2e184f8225961de58c48dc872013a995519e56a` |
| tree SHA | `4601dce8532acbd7ecdd5f149dd57985d24edf14` |
| 唯一 diff range | `ba518a06db797de955cc4830b4564ddd676ac775..c2e184f8225961de58c48dc872013a995519e56a` |

```bash
git rev-parse HEAD                 # = c2e184f8225961de58c48dc872013a995519e56a
git rev-parse HEAD^{tree}          # = 4601dce8532acbd7ecdd5f149dd57985d24edf14
git merge-base --is-ancestor ba518a06db797de955cc4830b4564ddd676ac775 HEAD && echo base-ok
git diff --stat ba518a06db797de955cc4830b4564ddd676ac775..HEAD
```

## 2. In-scope allowlist（路徑 + review SHA blob OID）

| 路徑 | blob OID | 性質 |
|---|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | `51f863f8db76f03f9487c08bdeb59aadba2450be` | 新契約 |
| `scripts/validate_document_adapter_mapping_contract.rb` | `813e36d4b5772c8b4f52bfb600321bbd8f7ae766` | 新薄 validator（229 行） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | `f91fcc61d10825167f7fb2bd3d2aa94c226cc1eb` | 2 positive |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | `9712d2915743080a1d22ddabf546e55565eafb59` | 12 negative |
| `.work/CARD-DOC-ADAPTER-MAPPING-20260909.md` | — | 任務卡 |
| `.work/evidence/DOC-ADAPTER-MAPPING-20260909.md` | — | evidence |

## 3. 明確排除範圍

- 不改 `規格/v0.1/raw-evidence-envelope.schema.json`（STD-01）/ `source-anchor*.schema.json`
  （STD-02）/ `normalized-document*.schema.json`（STD-03）—— 皆 `LOCKED_OWNER_ACCEPTED`，
  range 內零筆修改。
- 不改 STD-00~03 validator、AIWR / personal-memory 契約。
- 不做 connector / PDF・Markdown parser / ingestion runtime。
- 不動 repo #3（Jira Adapter Mapping，另 branch `cc/jira-adapter-mapping`）。
- 不新增 gem / package。

## 4. Normative authority 與可重跑命令（全部須 PASS）

```bash
ruby scripts/validate_document_adapter_mapping_contract.rb        # 本卡
for c in boundary task_card_record skill hook loop harness hermes_adapter e2e_acceptance; do ruby scripts/validate_ai_work_record_${c}_contract.rb 2>/dev/null || ruby scripts/validate_ai_${c}_contract.rb; done  # AIWR regression
ruby scripts/validate_personal_memory_contract.rb                 # aggregator regression
for n in 00 01_raw_evidence 02_source_anchor 03_normalized_document; do ruby scripts/validate_std${n}_contract.rb; done
uv run --no-project --script scripts/validate_std_schema_engine.py
uv run --no-project --script scripts/validate_cc_cross_layer_contract.py
git diff --check ba518a06db797de955cc4830b4564ddd676ac775..HEAD
```

`std_schema_engine` coverage 應維持 `STD01 12/12 excl 11`、`STD02 16/16 excl 10`、`STD03 9/9 excl 11`。

## 5. Spec claim → exact enforcement → fixture parity

| Spec claim | enforcement（`document_mapping_failure` / 結構） | fixture |
|---|---|---|
| 只映射 PDF / MARKDOWN | `source_kinds == [PDF, MARKDOWN]`；evaluator `DOC_MAP_UNKNOWN_SOURCE_KIND` | `DOC_MAP_NEG_UNKNOWN_SOURCE_KIND` |
| 投影欄位是目標 schema 的合法 property | evaluator 讀 `raw-evidence-envelope.schema.json` properties → `DOC_MAP_FIELD_NOT_IN_TARGET_SCHEMA` | `DOC_MAP_NEG_FIELD_NOT_IN_TARGET_SCHEMA` |
| 確定性身份 | `native_id_basis == CONTENT_SHA256` → `DOC_MAP_NONDETERMINISTIC_IDENTITY` | `DOC_MAP_NEG_NONDETERMINISTIC_IDENTITY` |
| payload reference-only | `payload_ref` present、無 `inline_content` → `DOC_MAP_PAYLOAD_INLINE` | `DOC_MAP_NEG_PAYLOAD_INLINE` |
| profile / selector 對映 | `profile == profile_by_kind[kind]` 且 ∈ schema enum；`selectors` 含 `required_selector_type_by_kind[kind]` → `DOC_MAP_PROFILE_MISMATCH` / `DOC_MAP_SELECTOR_MISSING` | `DOC_MAP_NEG_PROFILE_MISMATCH` / `DOC_MAP_NEG_SELECTOR_MISSING` |
| profile_details 確定 shape | key set == `profile_details_shape[profile]`；PDF page 正整數 + bbox 四個 0..1；Markdown codepoint/line 序 → `DOC_MAP_PROFILE_DETAILS_MALFORMED` | `DOC_MAP_NEG_PROFILE_DETAILS_MALFORMED` |
| NormalizedDocument block | `block_type` ∈ STD-03 enum；`content_layer == content_layer_by_block_type[block_type]`；table/image 帶 attribute；block 有 anchor → `DOC_MAP_BLOCK_TYPE_UNKNOWN` / `DOC_MAP_CONTENT_LAYER_MISMATCH` / `DOC_MAP_TABLE_IMAGE_ATTR_MISSING` / `DOC_MAP_BLOCK_NOT_ANCHORED` | 對應 4 個負例 |
| fail-loud | `error` present 但 `ok != false` → `FAIL_SILENT` | `DOC_MAP_NEG_FAIL_SILENT` |
| cross_reference pointer binding | `must_match` 五 pointer 字串 exact + 引用目標存在 | 結構斷言 |

每個負例單一 mutation；evidence 記錄「移除對應 enforcement → `ruby` exit 1（RED）」×12，全數 load-bearing。

## 6. 指定加壓面

1. **`claimed_field_keys` 的語意**：evaluator 靠 fixture 宣告一份 `claimed_field_keys` 清單來
   模擬「adapter 說它會投影哪些 raw_evidence 欄位」，再比對 `raw-evidence-envelope.schema.json`
   的 top-level properties。這是否足以擋「投影了 schema 不存在的欄位」？還是應該直接比對一份
   完整投影 envelope 的實際 key（更貼近真實）？（傾向現行對 T1 mapping 契約足夠，但想聽意見。）
2. **`profile_details` 是 STD-02 的 `{"type":"object"}` 鬆綁點**：本卡在 mapping 層補上
   per-profile 的確定 shape。確認這**不是**重定義 STD-02（STD-02 只說 profile_details 是
   object，本卡說「document adapter 產出的 profile_details 必須是這個 shape」——是收斂不是放寬）。
3. **`bbox_normalized` 只驗「四個 0..1 的數」**：沒驗 `x0<=x1 / y0<=y1` 或非退化。是否該加？
   （傾向 P2/P3 backlog —— 退化 bbox 是 parser 品質問題，非 mapping 契約。）
4. **`source_version.value_is_null: true`**：純文件無 authoritative native version，
   `source_version.value` 恆 null、`kind: CONTENT_DIGEST`、`secondary_digest` 帶 content sha256。
   確認這對 STD-01 `source_version` 的 `basis/kind/value/secondary_digest` required 四欄相容
   （`value` schema 允許 `["string","null"]`）。
5. **`allowed_block_types` 用了 STD-03 的**全部** 8 個**：document adapter 是否應排除某些
   （例如 `unknown` 只在 parser 失敗時出現，mapping 契約是否該允許）？本卡選擇「全允許，
   `unknown` 交由 STD-03 自己的 quality gap 處理」。
6. **duplicate JSON / YAML key**：4 個新檔經 `StrictJsonObject` / `assert_unique_yaml_mapping_keys`（lib）解析。

## 7. 結構化輸出契約（YAML）

```yaml
review_input:
  base_sha: "ba518a06db797de955cc4830b4564ddd676ac775"
  review_sha: "c2e184f8225961de58c48dc872013a995519e56a"
  tree_sha: "4601dce8532acbd7ecdd5f149dd57985d24edf14"
verdict: GO | NO_GO
counts: { p0: 0, p1: 0, p2: 0, p3: 0 }
findings:
  - id: F-01
    severity: P0 | P1 | P2 | P3
    path: "規格/v0.1/document-adapter-mapping.yaml:<line> | scripts/validate_document_adapter_mapping_contract.rb:<line>"
    trigger: "<觸發輸入 / 重跑步驟>"
    observed: "<spec 宣稱 vs validator 實擋>"
    risk: "<非確定性投影 / 重定義 STD / 投影欄位不合法 / block 未 anchor 被繞過的風險>"
    recommendation: "<定點修法>"
verification:
  gate_all_pass: true | false
  enforcement_parity_replayed: true | false      # 12 個 enforcement 移除 → RED
  std_schemas_untouched: true | false
  profile_details_convergence_reviewed: true | false
  dup_key_fail_closed: true | false
```

## 8. Gate 與 targeted re-review 規則

- 任一 reviewer `P0` / `P1` → `NO_GO`。開 `.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-NN-20260909.md`，
  同 branch 定點修，沿同一 review line 定點複審（只驗原 finding + regression），原 review
  SHA `c2e184f` immutable。
- `P2` / `P3` → 記 `文件/待辦重整.md` backlog；若能繞過「確定性投影」「不重定義 STD」
  「投影欄位合法」「block 必 anchor」任一，升 `P1`。
- 無 `P0` / `P1` 且 gate 全綠 + enforcement parity 成立 → 寫
  `.work/evidence/DOC-ADAPTER-MAPPING-REREVIEW-NN-20260909.yaml` receipt → 更新
  `文件/待辦重整.md` → Owner accept → merge `cc/doc-adapter-mapping` → `main`。
- accept 後（連同 repo #3 Jira Adapter Mapping）→ `EMEM-02`（`SSP-291`）解除。
