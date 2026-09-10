---
id: DOC-ADAPTER-MAPPING-REPAIR-04-20260910
parent: DOC-ADAPTER-MAPPING-20260909
prior_repairs: [REPAIR-01-20260910, REPAIR-02-20260910, REPAIR-03-20260910]
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_01_sha: faddb8c
repair_02_sha: d2ee1d2
repair_03_sha: df6b2ff
repair_delta: df6b2ff..HEAD（cc/doc-adapter-mapping）
scope: 只收 F-03-R03（derivation binding 未涵蓋 normalized_digest / SourceAnchor identity；idempotency 從 raw.tenant_id 取隱藏依賴）；F-01 / F-02 / P2 已 CLOSED，不重開
---

# Repair 04｜Document Adapter Mapping（repo #2）

Repair 03 的再 review 結論為 **NO_GO（P0=0, P1=1, P2=0）** —— F-01 / F-02 / P2 皆 CLOSED，
剩 F-03-R03。原 review SHA `c2e184f`、Repair 01/02/03（`faddb8c` / `d2ee1d2` / `df6b2ff`）皆
不動；本修復是 `cc/doc-adapter-mapping` 上的新 commit。

## 收到的裁決

- **F-03-R03（P1）**：`derivation_binding_failures()` 仍只綁 `raw_digest`、`canonical_digest`
  與 RawEvidence 的 `native_id`，沒補上前輪指出的 `normalized_digest`、SourceAnchor identity
  binding；`idempotency` derivation 也仍從 `raw.tenant_id` 取得額外（未宣告的）依賴。

## 修復內容（只收 F-03-R03）

### 1. `tenant_id` 變成明確宣告的 deterministic input（不再是隱藏依賴）

- `deterministic_derivation.inputs` 由 3 個增為 4 個：`[content_digest, adapter_id,
  adapter_version, tenant_id]`。
- `derivation_binding_failures()` 的 `idempotency_key` 改為由 `inputs["tenant_id"]` 計算
  （`sha256_hex(canonical_json({content_digest, tenant_id}))`），不再讀 `raw["tenant_id"]`。
- 新 binding `tenant_id`：`raw_evidence.tenant_id == inputs.tenant_id`。
- positive fixture 兩個 case 的 `determinism.inputs` 補 `tenant_id`。
- 負例 `DOC_MAP_NEG_DERIVATION_INPUT_TENANT_ID`（`input_mutation` 改 `tenant_id`）：
  recompute 的 idempotency_key 與 fixture 不符 → binding 失配。

### 2. `normalized_digest` 綁到 SourceAnchor representation_digest

- 新 binding `normalized_digest`：`raw_evidence.digests.normalized_digest ==
  source_anchor.representation.representation_digest`（兩份 instance 的 normalized 層必須是同一
  digest）。
- 負例 `DOC_MAP_NEG_DERIVATION_INSTANCE_NORMALIZED_DIGEST`（`instance_mutation` 改
  `raw_evidence_instance/digests/normalized_digest`）→ binding 失配。

### 3. SourceAnchor identity binding

- 新 binding `anchor_source_identity`：`source_anchor.source_identity ==
  raw_evidence.source_identity`。
- 新 binding `anchor_identity_content_bound`：`source_anchor.source_identity.native_id ==
  inputs.content_digest` 且 `source_system == "document"` 且 `entity_type ==
  raw_evidence.source_identity.entity_type`。
- 負例 `DOC_MAP_NEG_DERIVATION_INSTANCE_ANCHOR_IDENTITY`（`instance_mutation` 改
  `source_anchor_instance/source_identity/native_id`）→ 兩條 anchor identity binding 同時失配。

### 4. 其他

- `source_version_value` / `source_version_secondary_digest` binding 同時涵蓋 RawEvidence 與
  SourceAnchor 兩份 instance（明確寫進 YAML `binding`）。
- `EXPECTED_DERIVATION_BINDING_KEYS` 由 8 增為 12，綁 YAML `binding` 的 key（key 漂移 → RED）。
- 主程式 derivation 負例迴圈由「只吃 `input_mutation`」擴為「`input_mutation` 或
  `instance_mutation`」；`instance_mutation` path 前綴 `source_anchor_instance/` 走 anchor、
  其餘走 raw，套用後跑 `derivation_binding_failures` 必須非空。
- `derivation_binding_failures()` 下沉到 `scripts/lib/omos_contract_helpers.rb`
  （lib 加 `require "digest"`）；validator 394 行（< 400）。

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 19 個 Ruby validator（含共用 lib 下沉回歸）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- 定點驗證（直接呼叫 `derivation_binding_failures`）：baseline gaps `[]`；
  `source_anchor_instance/source_identity/native_id` drift → `["anchor_source_identity",
  "anchor_identity_content_bound"]`；`raw_evidence_instance/digests/normalized_digest` drift →
  `["normalized_digest"]`。
- enforcement parity（cp-based restore）：neutralize `normalized_digest` binding → RED；
  neutralize `tenant_id` binding + 改回 `raw.tenant_id` 計算 idem → RED；positive
  `determinism.inputs.tenant_id` drift（instance 不動）→ RED；YAML 移除 `tenant_id` input →
  RED；YAML 移除一個 `binding` key → RED。
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 error code（新負例沿用 `DOC_MAP_NONDETERMINISTIC_IDENTITY`）；F-01 / F-02 / P2
  成果原封保留。

## 交付

- branch `cc/doc-adapter-mapping`，repair-04 commit 在 `df6b2ff` 之後。
- 針對性再 review 範圍：`df6b2ff..<repair-04 SHA>`（`c2e184f` / `faddb8c` / `d2ee1d2` /
  `df6b2ff` 皆不動）。
