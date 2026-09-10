---
id: JIRA-ADAPTER-MAPPING-REPAIR-02-20260910
parent: JIRA-ADAPTER-MAPPING-20260909
prior_repair: JIRA-ADAPTER-MAPPING-REPAIR-01-20260910
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #3 / EMEM-02 前置）
tier: T1
review_line: JIRA-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: 170da7f
repair_01_sha: 733a9e3
repair_delta: 733a9e3..HEAD（cc/jira-adapter-mapping）
scope: 集中修三件核心事 + json pointer boundary；不改架構、不擴 scope
---

# Repair 02｜Jira Adapter Mapping（repo #3）

Repair 01 的 targeted re-review 結論為 **NO_GO（P0=0, P1=4, P2=0）**：F-01 核心已 CLOSED 但
出現 projection↔instance 脫鉤 regression；F-02 / F-03 / F-04 都還有可實際繞過的路徑。原 review
SHA `170da7f`、Repair 01 commit `733a9e3` 皆不動；本修復是 `cc/jira-adapter-mapping` 上的新
commit。

## 收到的裁決

- **P1（F-03 仍可繞過）**：identity 比較是 optional（只在 `previous_identity` 與
  `current_identity` 都帶時才比），rename 邏輯還把「identity 沒帶」當 stable；且即使都帶，也沒
  要求 `current_identity` 等於實際 `source_anchor.profile_details.{cloud_id, issue_id}`。
- **P1（F-02 字串比較）**：`current_value > previous_value` 用 RFC3339 字串比較，`"." < "Z"`，
  fractional 秒（`12:00:00.1Z` vs `12:00:00Z`）會判成不是 newer，`decision = NOOP` 錯誤 PASS。
- **P1（F-04 prefix bypass）**：`json_pointer.start_with?("/fields/description")` 讓
  `/fields/description_extra` 過關 —— 已不是 Jira `description` 欄位。
- **P1（F-01 regression）**：compact `projection` 與完整 STD instance 是兩套測資，Ruby 只確認
  positive「有帶」instance、Python 只獨立驗 instance schema-valid，兩者內容沒有互綁 —— 沒證明
  那個合法 instance 是依這份 mapping 產生的。

## 修復內容（三件核心事 + pointer boundary）

### F-03 — identity 必填、且綁當輪實際 projected identity

- `jira_mapping_failure`：reconciliation 存在時，`previous_identity` 與 `current_identity`
  **皆必填**，且 `cloud_id` / `issue_id` 不得為空（`identity_complete?`）→ 否則
  `JIRA_MAP_RECONCILIATION_IDENTITY_INCOMPLETE`（新 code）。
- `current_identity` 必須等於當輪實際 projected identity
  `{cloud_id: profile_details.cloud_id, issue_id: profile_details.issue_id}` —— 不符即
  `JIRA_MAP_RECONCILIATION_IDENTITY_DRIFT`（不再信任自報 flag，也不再把 nil 當 stable）。
- rename 檢查移除 `identity_stable = previous.nil? || current.nil? || ...` 這條「沒帶＝穩定」的
  退讓；identity 穩定性已由上面兩條強制。
- YAML `reconciliation.identity_required: true`；`rule` 改寫成「Every reconciliation run carries
  both previous_identity and current_identity, each with a non-null cloud_id and issue_id …
  current_identity must also equal the run's actual projected identity」。
- 負例：`JIRA_MAP_NEG_RECONCILIATION_IDENTITY_INCOMPLETE`（只帶 previous）、
  `JIRA_MAP_NEG_RECONCILIATION_CURRENT_NOT_PROJECTED`（previous==current 但 issue_id 9 ≠
  projected 1）。既有 `SILENT_GAP` / `VERSION_DECISION_MISMATCH` 負例補上 matching identity
  以便走到各自的檢查點。

### F-02 — version ordering 真正 parse timestamp 比較

- 新 helper `parse_instant(value)`：`Time.iso8601(value)`（`require "time"`），parse 失敗回
  nil；`JIRA_MAP_VERSION_VALUE_INVALID` 改為 `parse_instant(version["value"]).nil?` 判斷
  （不再自寫 RFC3339 regex 假裝完整 parser，移除 `RFC3339_UTC_PATTERN`）。
- reconciliation version decision：`previous_instant` / `current_instant` 皆 `parse_instant`，
  `ordered_new = current_instant > previous_instant`（Time 比較，非字串）。
- 負例：`JIRA_MAP_NEG_VERSION_DECISION_FRACTIONAL`（`decision: NOOP`，previous `12:00:00Z`、
  current `12:00:00.100Z`）—— 字串比較會漏、parse 比較會抓（`current` 晚 100ms → NOOP 矛盾）。

### F-04 — json pointer 真正定址，不吃 prefix bypass

- 新 helper `json_pointer_addresses_field?(pointer, prefix)`：`pointer == prefix ||
  pointer.start_with?("#{prefix}/")` —— 不再裸用 `start_with?(prefix)`。
- `EXPECTED_JSON_POINTER_PREFIX_BY_KIND` 的 `COMMENT_BODY` 由 `/fields/comment/comments/`
  改為 `/fields/comment/comments`（不帶尾斜線，交給 helper 補 `/`）；YAML
  `json_pointer_prefix_by_kind.COMMENT_BODY` 同步。
- YAML `source_anchor_projection.rule` 改寫成「json_pointer either equals
  json_pointer_prefix_by_kind[field_kind] or begins with that prefix followed by "/" …
  not a sibling that merely shares a prefix such as /fields/description_extra」。
- 負例：`JIRA_MAP_NEG_JSON_POINTER_PREFIX_BYPASS`（DESCRIPTION，pointer
  `/fields/description_extra`）。

### F-01 regression — projection ↔ full STD instance 逐項綁定

- 新函式 `projection_instance_consistency(test_case)`：對每個 positive 逐項比對 compact
  `projection` 與完整 `raw_evidence_instance` / `source_anchor_instance` 的 mapping-critical
  欄位：`source_anchor.profile`、`profile_details.{field_id, json_pointer, cloud_id, issue_id}`、
  `raw_evidence.source_version.{basis, kind, value, secondary_digest}`、
  `raw_evidence.payload.{structured_profile, canonicalization_profile, payload_ref}`、
  `raw_evidence.provenance.ingestion_mode`、`raw_evidence_instance.source_identity.source_system
  == "jira-cloud"`、projected `native_id_basis == JIRA_CLOUD_ID_PLUS_ISSUE_ID`、
  `raw_evidence_instance / source_anchor_instance 的 native_id == profile_details.issue_id`，
  以及 reconciliation `current_identity == instance 的 (cloud_id, issue_id)`。任一不符 → gate RED。
- YAML 新增 `projection_instance_consistency` 區塊（rule + `bound_fields` 清單）。

### 檔案大小

`scripts/validate_jira_adapter_mapping_contract.rb` 386 行（< 400，守
`.agentskills/docs/coding-standards.md` §2）。companion 未改（113 行）。

## 驗證（session evidence）

- `ruby scripts/validate_jira_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_jira_adapter_mapping_instances.py` →
  `PASS (positive_instances=6, instance_negatives=3)`
- 全 19 個 Ruby validator（STD-00~03 / cross-layer / personal-memory / AIWR regression）
  → 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- 針對性 enforcement parity（cp-based restore，不用 git checkout）：
  - neutralize `JIRA_MAP_RECONCILIATION_IDENTITY_INCOMPLETE` return → RED
  - neutralize `current_identity == projected_identity` 檢查 → RED
  - 把 `parse_instant` 比較換回字串比較 → RED（fractional 負例不再被拒）
  - 把 `json_pointer_addresses_field?` 換回裸 `start_with?(prefix)` → RED（prefix-bypass 負例不再被拒）
  - 對 positive 的 `source_anchor_instance.profile_details.json_pointer` / `field_id` 做 drift
    → `FAIL … projection 與完整 STD instance 不一致` RED
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture（negative）；companion 未改；
  未動任何 `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 registry / FSM / package / runtime。
- 新增 1 個 error code（`JIRA_MAP_RECONCILIATION_IDENTITY_INCOMPLETE`）與 4 個 negative label
  （incomplete identity / current≠projected / pointer prefix bypass / fractional ordering）；
  F-01 的完整 STD instance gate 成果原封保留。

## 交付

- branch `cc/jira-adapter-mapping`，repair-02 commit 在 `733a9e3` 之後。
- 針對性再 review 範圍：`733a9e3..<repair-02 SHA>`（原 review SHA `170da7f`、Repair 01
  `733a9e3` 皆不動）。
