---
id: JIRA-ADAPTER-MAPPING-REPAIR-01-20260910
parent: JIRA-ADAPTER-MAPPING-20260909
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #3 / EMEM-02 前置）
tier: T1
review_line: JIRA-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: 170da7f
repair_delta: 170da7f..HEAD（cc/jira-adapter-mapping）
---

# Repair 01｜Jira Adapter Mapping（repo #3）

針對大 review 的 **NO_GO（4×P1）**，在同一條 review line 上做**針對性**修復。
原 review SHA `170da7f` 不動；本修復是 `cc/jira-adapter-mapping` 上的新 commit。

## 收到的裁決

- **F-01（P1）**：positive 只是 mapping fragment；`raw_evidence` / `source_anchor` 缺 locked
  STD-01 / base SourceAnchor 大量 required；gate 沒做完整 target-instance schema validation。
- **F-02（P1）**：compound version 實質 bypass —— evaluator 只驗 `basis` / `kind` /
  `secondary_digest` 非空，不看 `source_version.value`（updated timestamp），兩個 positive
  也沒帶 `value`；reconciliation 宣稱依 value 比較新舊，卻無 machine 驗。
- **F-03（P1）**：reconciliation identity 只靠自報 `changed_identity` boolean，沒有比較實際
  before/after identity；issue-key rename → alias、cloud_id+issue_id stable identity 只是
  規格敘述。
- **F-04（P1）**：mapping table binding 漏洞 —— locked Jira profile 的 `field_id` 是任意非空
  字串，evaluator 從未要求 `profile_details.field_id == field_id_by_kind[field_kind]`，
  json_pointer 也沒與 field_kind 綁定。

## 修復內容（逐條對應）

### F-01 — positive = 完整 STD instance + JSON Schema instance gate

- `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json` 重寫：3 個 case
  （`JIRA_MAP_POS_DESCRIPTION` / `JIRA_MAP_POS_COMMENT_BODY` /
  `JIRA_MAP_POS_RECONCILE_NEWER_WITH_RENAME`）各帶 compact `projection`（Ruby 語意 eval 用）
  ＋完整 `raw_evidence_instance`（STD-01）＋ `source_anchor_instance`（STD-02
  JIRA_CLOUD_ENTITY_SEGMENT_V1），instances 依 STD-01/02 既有合法 fixture 例改寫。
- 新 companion `scripts/validate_jira_adapter_mapping_instances.py`（PEP 723，
  `jsonschema==4.25.1` + `rfc3339-validator==0.1.4`，`uv run --no-project --script`）：
  Draft 2020-12 `Registry`（raw-evidence + base source-anchor + Jira profile，keyed by `$id`）
  驗每個 positive 的 `raw_evidence_instance` / `source_anchor_instance` 對 locked target
  schema 合法；再驗每個 `instance_negative_cases` 確實被拒。缺 required / 巢狀
  type·pattern·const 不符 → fail closed。
- yaml 新增 `instance_validation.engine` 指向 companion；Ruby validator assert engine 存在、
  且每個 positive 帶 `raw_evidence_instance` / `source_anchor_instance`。
- 新 `規格/v0.1/fixtures/jira-adapter-mapping-instance-negative-fixtures.json` ×3：
  RawEvidence 缺 `idempotency_basis`；Jira SourceAnchor 缺 base required `quote`；
  Jira SourceAnchor `profile_details.text_selector` 巢狀 shape 錯（只有 `{start,end}`）。

### F-02 — compound version machine-verifiable

- evaluator：`source_version.secondary_digest` 必須符合 `^sha256:[0-9a-f]{64}$`
  （`JIRA_MAP_SECONDARY_DIGEST_MALFORMED`）；`source_version.value` 必須是存在的
  RFC3339（UTC Z）timestamp —— 觀測到的 Jira issue updated 時間
  （`JIRA_MAP_VERSION_VALUE_INVALID`）。
- reconciliation 新增 `decision` 與觀測版本序一致性檢查：`decision == NEW_EVIDENCE` 須
  `current_version.value > previous_version.value`，`decision == NOOP` 須 `<=`，否則
  `JIRA_MAP_RECONCILIATION_VERSION_DECISION_MISMATCH`。
- yaml `raw_evidence_projection.source_version` 加 `value_format: RFC3339_TIMESTAMP` /
  `secondary_digest_format: SHA256_LOWER_HEX_64`；`reconciliation` 加 `version_decisions`。
- 負例：`JIRA_MAP_NEG_SECONDARY_DIGEST_MALFORMED`（`sha256:aa`）、
  `JIRA_MAP_NEG_VERSION_VALUE_INVALID`（`"28 Aug 2026"`）、
  `JIRA_MAP_NEG_RECONCILIATION_VERSION_DECISION_MISMATCH`（decision 與 value 序矛盾）。
- 正例：`JIRA_MAP_POS_RECONCILE_NEWER_WITH_RENAME` 帶 previous/current version 比較，
  `NEW_EVIDENCE` 決策與 value 序一致。

### F-03 — reconciliation identity 實際前後比較

- evaluator：reconciliation 帶 `previous_identity` / `current_identity`（各
  `{cloud_id, issue_id}`）時 component-wise 比較，不同 → `JIRA_MAP_RECONCILIATION_IDENTITY_DRIFT`
  （不論自報 `changed_identity`）。自報 `changed_identity == true` 仍另判
  `JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY`。
- issue-key rename：reconciliation 帶 `issue_key_change {from, to}` 時，`to` 必須進
  `raw_evidence.source_aliases` 且 identity components 不變，否則
  `JIRA_MAP_ISSUE_KEY_RENAME_NOT_ALIASED`。
- yaml `source_identity.identity_components: [cloud_id, issue_id]`、
  `reconciliation.identity_components: [cloud_id, issue_id]`、`source_aliases.rule` 更新。
- 負例：`JIRA_MAP_NEG_RECONCILIATION_IDENTITY_DRIFT`（`changed_identity:false` 但
  issue_id 1→2）、`JIRA_MAP_NEG_ISSUE_KEY_RENAME_NOT_ALIASED`（rename 未進 alias）。
- 正例：`JIRA_MAP_POS_RECONCILE_NEWER_WITH_RENAME` previous/current identity 相同、
  新 key `PLAT-900` 進 `source_aliases`。

### F-04 — field_kind ↔ field_id / json_pointer binding

- evaluator：`profile_details.field_id == EXPECTED_FIELD_ID_BY_KIND[field_kind]`
  （SUMMARY→summary、DESCRIPTION→description、COMMENT_BODY→comment、
  ADF_TEXT_NODE→description），否則 `JIRA_MAP_FIELD_ID_KIND_MISMATCH`；
  `profile_details.json_pointer` 必須以 `json_pointer_prefix_by_kind[field_kind]` 開頭
  （`/fields/summary`、`/fields/description`、`/fields/comment/comments/`），否則
  `JIRA_MAP_JSON_POINTER_FIELD_MISMATCH`。
- yaml 新增 `source_anchor_projection.json_pointer_prefix_by_kind` 對映 + `rule` 說明
  「locked Jira profile 的 field_id 是任意非空字串，故此 binding 只在本層強制」。
- 負例：`JIRA_MAP_NEG_FIELD_ID_KIND_MISMATCH`（DESCRIPTION → field_id `comment`）、
  `JIRA_MAP_NEG_JSON_POINTER_FIELD_MISMATCH`（DESCRIPTION → pointer
  `/fields/comment/comments/3/body`）。

## 驗證（session evidence）

- `ruby scripts/validate_jira_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_jira_adapter_mapping_instances.py` →
  `PASS (positive_instances=6, instance_negatives=3)`
- 全 19 個 Ruby validator（含 STD-00~03 / cross-layer / personal-memory / AIWR regression）
  → 全 PASS
- `uv run --no-project --script scripts/validate_std_schema_engine.py` → `PASS`
  （STD01 12/12、STD02 16/16、STD03 9/9）
- `uv run --no-project --script scripts/validate_cc_cross_layer_contract.py` → `PASS`
- enforcement parity：逐一 neutralize `jira_mapping_failure` 的 18 個 `return "<CODE>"` /
  key-set 判斷 → 每次 exit 1（RED），還原後 PASS
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 沒動任何 `LOCKED_OWNER_ACCEPTED` schema（`git diff --name-status ba518a0..HEAD` 僅
  新增 companion + instance-negative fixture + 卡 + evidence，其餘為 mapping yaml /
  validator / mapping fixture）。
- 沒新增 registry / FSM / package / runtime；companion 是純 JSON Schema 驗證器。
- Jira connector / REST client / webhook runtime 仍不在本卡。
- validator 306 行、companion 113 行，守 `.agentskills/docs/coding-standards.md` §2（< 400）。

## 交付

- branch `cc/jira-adapter-mapping`，repair commit 在 `170da7f`（原 review SHA，不動）之後。
- 針對性再 review 範圍：`170da7f..<repair SHA>`。
