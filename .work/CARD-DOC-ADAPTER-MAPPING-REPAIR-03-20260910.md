---
id: DOC-ADAPTER-MAPPING-REPAIR-03-20260910
parent: DOC-ADAPTER-MAPPING-20260909
prior_repairs: [DOC-ADAPTER-MAPPING-REPAIR-01-20260910, DOC-ADAPTER-MAPPING-REPAIR-02-20260910]
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_01_sha: faddb8c
repair_02_sha: d2ee1d2
repair_delta: d2ee1d2..HEAD（cc/doc-adapter-mapping）
scope: 只收 Repair 02 再 review 的 2 個 P1（F-02 regression 完全關 + F-03 derivation binding）；不擴 scope
---

# Repair 03｜Document Adapter Mapping（repo #2）

Repair 02 的再 review 結論為 **NO_GO（P0=0, P1=2, P2=0）**：F-01 CLOSED、P2 CLOSED、F-02 core
schema validity CLOSED，但 F-02 的 mapping↔fixture regression 未完全關、F-03 仍未證明
`derived = f(inputs)`。原 review SHA `c2e184f`、Repair 01 `faddb8c`、Repair 02 `d2ee1d2` 皆不動；
本修復是 `cc/doc-adapter-mapping` 上的新 commit。

## 收到的裁決

- **F-02-R02（P1）**：YAML 仍寫 `source_version.value_is_null: true`（handoff：純文件
  `source_version.value` 恆為 null，content SHA256 放 `secondary_digest`），但兩個 positive
  fixture 反過來（`value = <content digest>`、`secondary_digest = null`）。Repair 02 只重綁
  `basis`/`kind`，沒綁 `value_is_null` / `secondary_digest`，spec 寫 A、fixture 測 B，Ruby +
  Python 仍同時 PASS。YAML 新增的「Every value in this block is bound by the thin validator」
  也不屬實。
- **F-03-R02（P1）**：validator 現在真的自算 canonical projection digest，但 per-positive
  驗證完全沒把 `determinism.inputs` 拿去驗 output derivation。mutate
  `determinism.inputs.content_digest`、其他 instance 完全不動 → 仍 PASS。`IDENTITY_BEARING_FIELDS`
  equality check 是 construction-by-design（patched copy 本來就禁止碰 identity-bearing paths），
  不是「相同 inputs → 相同 derived output」的證據。

## 修復內容（只收這 2 個 P1）

### F-02-R02 — source_version 表示法 end-to-end 鎖定

- 選定 normative 表示法（沿用 handoff 契約）：純文件 `source_version.value == null`，
  content SHA256 放在 `source_version.secondary_digest`。
- YAML `raw_evidence_projection.source_version` 加 `secondary_digest_basis: CONTENT_SHA256`；
  `digests` 由 `canonical_digest_by_kind`（Markdown 宣告 NORMALIZED_TEXT_SHA256，與 STD-01
  `canonicalization_profile NONE → canonical_digest 必 null` 的 allOf[0] 矛盾）改為
  `canonical_digest_is_null: true` + `normalized_digest_basis: NORMALIZED_REPRESENTATION_SHA256`。
- 兩個 positive fixture（PDF / Markdown）的 `raw_evidence_instance` 與 `source_anchor_instance`
  的 `source_version` 改成 `{basis: CONTENT_ONLY, kind: CONTENT_DIGEST, value: null,
  secondary_digest: <content digest>}`；`source_identity.native_id` 由 `sha256-aaaa` 短式改成
  完整 content digest。
- Ruby：`assert value_is_null == true`、`secondary_digest_basis == CONTENT_SHA256`、
  `digests.canonical_digest_is_null == true`；並在 derivation binding（下）逐項驗 fixture
  的 `value == null` / `secondary_digest == content_digest` / `canonical_digest == null`。
- 負例 parity：fixture 回退成 `value = <digest>` / `secondary_digest = null` → RED；
  YAML `value_is_null` → false → RED；YAML 移除 `canonical_digest_is_null` → RED。

### F-03-R02 — derived = f(determinism.inputs) 由 validator 重算驗證

- YAML `deterministic_derivation` 新增 `binding:` map —— 每個 derived 欄位對應的綁定規則
  （`native_id == inputs.content_digest`、`source_version.value == null`、
  `source_version.secondary_digest == inputs.content_digest`、
  `digests.raw_digest == inputs.content_digest`、`digests.canonical_digest == null`、
  `provenance.adapter_id == inputs.adapter_id`、`provenance.adapter_version == inputs.adapter_version`、
  `idempotency_key == "sha256:" + sha256_hex(canonical_json({content_digest, tenant_id}))`）。
- Ruby 新函式 `derivation_binding_failures(inputs, raw_instance, anchor_instance)`：依
  `determinism.inputs` 重算每個 derived 欄位，與 projected instance 逐項比對，回傳失配的
  binding 名稱。`EXPECTED_DERIVATION_BINDING_KEYS` 綁定 YAML `binding` 的 key（key 漂移 → RED）。
- positive loop：`assert determinism.inputs.keys == [content_digest, adapter_id, adapter_version]`；
  `assert derivation_binding_failures(...).empty?`。
- 負例：新增 `document_mapping_negative_cases` 三筆（`base_case_ref` + `input_mutation`），
  各改 `determinism.inputs` 的一個值（content_digest / adapter_id / adapter_version），
  instance 完全不動；主程式以 `derivation_binding_failures(mutated_inputs, base instance)` 檢查，
  **必須有 binding 失配**，否則 gate RED。covers label
  `a declared deterministic input changed but the derived fields did not`（YAML
  `required_negative_fixtures` 同步）。
- parity：reviewer 的原 mutation（positive `determinism.inputs.content_digest` 改、instance
  不動）→ RED；`derivation_binding_failures` neutralize 成永遠回 `[]` → RED；刪 3 個
  input_mutation 負例 → RED；YAML 移除 `binding` block → RED。

### 檔案大小 / 重構

`scripts/validate_document_adapter_mapping_contract.rb` 399 行（< 400）。`triple_of` /
`profile_details_required` 下沉到 `scripts/lib/omos_contract_helpers.rb`（+20 行），既有
validator 行為不變（19 個 Ruby validator 回歸全 PASS）。

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 19 個 Ruby validator（STD-00~03 / cross-layer / personal-memory / AIWR regression）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- 針對性 enforcement parity（cp-based restore，7 項）全數 RED-on-tamper（見上）
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 registry / FSM / package / runtime；沒新增 error code（新負例沿用
  `DOC_MAP_NONDETERMINISTIC_IDENTITY`）；F-01 / P2 成果原封保留。

## 交付

- branch `cc/doc-adapter-mapping`，repair-03 commit 在 `d2ee1d2` 之後。
- 針對性再 review 範圍：`d2ee1d2..<repair-03 SHA>`（`c2e184f` / `faddb8c` / `d2ee1d2` 皆不動）。
