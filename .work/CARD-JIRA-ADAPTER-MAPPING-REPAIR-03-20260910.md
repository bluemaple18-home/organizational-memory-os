---
id: JIRA-ADAPTER-MAPPING-REPAIR-03-20260910
parent: JIRA-ADAPTER-MAPPING-20260909
prior_repairs: [JIRA-ADAPTER-MAPPING-REPAIR-01-20260910, JIRA-ADAPTER-MAPPING-REPAIR-02-20260910]
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #3 / EMEM-02 前置）
tier: T1
review_line: JIRA-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: 170da7f
repair_01_sha: 733a9e3
repair_02_sha: fb939c1
repair_delta: fb939c1..HEAD（cc/jira-adapter-mapping）
scope: 只收 Repair 02 再 review 的 2 個 P1（identity binding 閉合 + reconciliation version fail-open）；fractional / json pointer prefix / optional identity 已收，不重開
---

# Repair 03｜Jira Adapter Mapping（repo #3）

Repair 02 的再 review 結論為 **NO_GO（P0=0, P1=2, P2=0）**：原 4 個 P1 已修掉大半（fractional
timestamp、JSON pointer prefix、optional reconciliation identity 都收了），但留下兩個能讓核心
contract 綠燈通過的旁路。原 review SHA `170da7f`、Repair 01 `733a9e3`、Repair 02 `fb939c1` 皆
不動；本修復是 `cc/jira-adapter-mapping` 上的新 commit。

## 收到的裁決

- **F-01-F03-R02（P1）**：identity binding 未真正閉合。`projection_instance_consistency()` 只驗
  `source_system == jira-cloud`、`native_id == issue_id`，沒驗
  `source_identity.source_instance_id == profile_details.cloud_id`、
  `source_identity.entity_type == "issue"`、也沒要求 RawEvidence 與 SourceAnchor 的
  `source_identity` 相等。可以把 full STD instance 的 `source_instance_id` 換成別的 Jira
  cloud id（`profile_details.cloud_id` 不動），兩個 instance 仍 schema-valid，
  compact projection / reconciliation 說 stable identity 是 (cloud-A, issue-10042)，實際被驗的
  Evidence / Anchor 卻是 (cloud-B, issue-10042) —— 違反 cloud_id + issue_id identity contract。
- **F-02-R02（P1）**：reconciliation version ordering 仍 fail-open。decision 檢查只在
  `previous_instant && current_instant` 都非 nil 時才跑 → `previous_version.value` malformed →
  整段 decision 驗證被跳過；`current_version.value` malformed 還會 fallback 到 projection 自身
  `version_instant`（靜默替換）。且 decision 只看 timestamp，完全沒讀 `secondary_digest` ——
  同 timestamp、不同 `secondary_digest`、decision NOOP 也沒有 machine path 指出 compound version
  已不同。

## 修復內容（只收這 2 個 P1）

### F-01-F03-R02 — full instance source_identity end-to-end 綁到 (cloud_id, issue_id)

- `projection_instance_consistency()`（已下沉到 `scripts/lib/omos_contract_helpers.rb`）新增：
  對 `raw_evidence_instance` 與 `source_anchor_instance` 各驗
  `source_identity.source_system == "jira-cloud"`、
  `source_identity.source_instance_id == profile_details.cloud_id`、
  `source_identity.entity_type == "issue"`、
  `source_identity.native_id == profile_details.issue_id`；並要求
  `raw_evidence_instance.source_identity == source_anchor_instance.source_identity`。
- YAML `projection_instance_consistency` 新增 `full_instance_identity_binding` 說明。
- 負例（`base_case_ref` + `instance_mutation`，主程式對 base positive 套 mutation 後跑
  `projection_instance_consistency`，必須非空）：
  `JIRA_MAP_NEG_INSTANCE_CLOUD_DRIFT`（兩個 instance 的 `source_instance_id` 換成別的 cloud id）、
  `JIRA_MAP_NEG_INSTANCE_ENTITY_TYPE_DRIFT`（`entity_type` 改成 `comment`）。
- parity：neutralize `source_instance_id == cloud_id` 或 `entity_type == issue` 檢查 → RED；
  positive fixture 直接 drift `source_instance_id` → RED。

### F-02-R02 — reconciliation version ordering fail closed + compound 比較

- `jira_mapping_failure` 的 decision 段：
  - `previous_version` 必填、`value` 必須可 parse，否則
    `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`（新 code）。
  - `current_version` 帶了就必須可 parse（不再 `parse_instant(...) || version_instant` 靜默
    fallback）；沒帶才用 projection 自身版本。
  - compound 比較：`same_compound` = timestamp 相等 **且** 雙方 `secondary_digest` 皆存在且相等；
    `ordered_new = current > previous || (timestamp 相等 && !same_compound)` —— 同 timestamp、
    digest 不同即視為 newer，decision NOOP 不成立 →
    `JIRA_MAP_RECONCILIATION_VERSION_DECISION_MISMATCH`。
- YAML `reconciliation.rule` 改寫：compound version（value + secondary_digest）比較、
  version 不可 parse 即 `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`（no silent fallback）、
  等 timestamp 的 NOOP 需 digest 相等。`error_contract` 新增該 code。
- positive `JIRA_MAP_POS_RECONCILE_NEWER_WITH_RENAME` 的 `previous_version` / `current_version`
  補上 `secondary_digest`。
- 負例：`JIRA_MAP_NEG_RECONCILIATION_VERSION_UNPARSEABLE_PREVIOUS`（`previous_version.value =
  "not-a-timestamp"`）、`JIRA_MAP_NEG_RECONCILIATION_COMPOUND_DIGEST_NOOP`（同 timestamp、
  `secondary_digest` 不同、decision NOOP）。
- parity：neutralize UNPARSEABLE fail-closed return → RED；把 `ordered_new` 退回純 timestamp
  比較 → RED。

### 檔案大小 / 重構

`scripts/validate_jira_adapter_mapping_contract.rb` 351 行（< 400）。`parse_instant` /
`json_pointer_addresses_field?` / `identity_complete?` / `projection_instance_consistency` 及
新增的 `deep_dup` / `set_path` 下沉到 `scripts/lib/omos_contract_helpers.rb`；既有 validator
行為不變（19 個 Ruby validator 回歸全 PASS）。

## 驗證（session evidence）

- `ruby scripts/validate_jira_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_jira_adapter_mapping_instances.py` →
  `PASS (positive_instances=6, instance_negatives=3)`
- 全 19 個 Ruby validator（STD-00~03 / cross-layer / personal-memory / AIWR regression）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- 針對性 enforcement parity（cp-based restore，5 項）全數 RED-on-tamper（見上）
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 registry / FSM / package / runtime；新增 1 個 error code
  `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`；F-01（完整 STD instance gate）、F-04、
  fractional / json pointer prefix / optional identity 成果原封保留。

## 交付

- branch `cc/jira-adapter-mapping`，repair-03 commit 在 `fb939c1` 之後。
- 針對性再 review 範圍：`fb939c1..<repair-03 SHA>`（`170da7f` / `733a9e3` / `fb939c1` 皆不動）。
