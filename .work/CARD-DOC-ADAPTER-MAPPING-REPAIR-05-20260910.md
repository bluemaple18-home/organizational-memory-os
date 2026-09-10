---
id: DOC-ADAPTER-MAPPING-REPAIR-05-20260910
parent: DOC-ADAPTER-MAPPING-20260909
prior_repairs: [REPAIR-01, REPAIR-02, REPAIR-03, REPAIR-04 — 20260910]
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_chain_sha: [faddb8c, d2ee1d2, df6b2ff, f2333e1]
repair_delta: f2333e1..HEAD（cc/doc-adapter-mapping）
scope: 只收 F-03-R04（deterministic surface 未定義乾淨）；不重開 F-01 / F-02 / P2
---

# Repair 05｜Document Adapter Mapping（repo #2）

Repair 04 再 review 結論為 **NO_GO（P1=1, `F-03-R04`）**：`tenant_id` 已進 inputs、idempotency
改由 inputs 計算、identity 開始互綁，但 `derived = f(declared inputs)` 仍未真正成立 ——
`normalized_digest` 只是「兩份 instance 互等」、`source_instance_id` 沒綁任何 input，因此**同一組
declared inputs 仍可接受兩份不同的 stable projection identity**（paired drift）。原 review SHA
`c2e184f` 與 repair-01..04（`faddb8c` / `d2ee1d2` / `df6b2ff` / `f2333e1`）皆不動。

## 收到的裁決（F-03-R04，P1）

- `normalized_digest` binding 只是 `raw.digests.normalized_digest ==
  anchor.representation.representation_digest`；沒有任何 input 決定它。兩邊一起改成同一個新
  SHA256、四個 declared inputs 不動 → 12 個 binding 全數成立。
- SourceAnchor identity 同理：`source_instance_id` 沒綁任何 input，兩份一起改 → 仍 PASS。
- `projection_digest` 是從「已 mutate 的 fixture」算的，救不了這件事。
- 建議：**不要再一個欄位一個 binding**，把 deterministic surface 一次定義乾淨（input /
  derived / run-scoped-excluded），再用「同 inputs、兩份獨立 projection」做 machine comparison。

## 修復內容（重新定義 deterministic surface）

### 1. 六個 declared input

`deterministic_derivation.inputs` = `[content_digest, adapter_id, adapter_version, tenant_id,
source_instance_id, normalized_representation_digest]`。後兩者是前輪未宣告的隱藏依賴：
`source_instance_id`（該 tenant 的文件來源實例 id）與 `normalized_representation_digest`
（`SHA256(normalized representation bytes)`，非 `content_digest` 的函數）。

### 2. run_scoped_paths — 完整列舉「非 deterministic identity 一部分」的 per-run 欄位

`deterministic_derivation.run_scoped_paths`（validator `DOC_MAP_RUN_SCOPED_PATHS`，逐字綁定）：
`raw_evidence` 的 `evidence_id/ref`、`source_aliases`、`source_event`、`chronology`、`access`、
`transport_delivery`、`activity_refs`、`source_availability`、`payload_retention_state`、
`deletion_confirmation_ref`、`permission_decision_ref`、`quality_gaps`、`payload/payload_ref`、
`payload/size_bytes`、`provenance/ingestion_mode`、`provenance/*_receipt_ref` +
`adapter_activity_ref`；`source_anchor` 的 `anchor_id/ref`、`evidence_ref`、`access`、`quote`、
`source_availability`、`resolution`、`selectors`、`profile_details`、
`representation/source_payload_ref` + `source_payload_digest` + `representation_ref`。

### 3. reconstruct(kind, inputs) + machine comparison

新 `reconstruct_deterministic_projection(kind, inputs)`（共用 lib）：**只由 6 個 input（+ 固定
schema constant）** 重建 `{raw_evidence, source_anchor}` 的 deterministic 片段 ——
`source_identity`（兩份 instance 為同一物件：`{source_system: document, source_instance_id:
inputs.source_instance_id, entity_type: <kind>, native_id: inputs.content_digest,
parent_native_id: null}`）、`source_version`（`{CONTENT_ONLY, CONTENT_DIGEST, value: null,
secondary_digest: inputs.content_digest}`）、`digests`（`{raw_digest: content_digest,
canonical_digest: null, normalized_digest: inputs.normalized_representation_digest}`）、
`payload`（media_type/structured_profile/canonicalization_profile/retention_tier）、
`provenance`（adapter_id/version + 3 個固定狀態 const）、`idempotency_key`
（`sha256(canonical_json({content_digest, tenant_id}))`）、`idempotency_basis`（const）、
`representation`（media_type/representation_digest = normalized_representation_digest/
digest_basis）、`profile`、`normalization_profile`、`schema_version`。

`deterministic_surface_mismatches(kind, inputs, raw, anchor)`：把 fixture 的
`{raw_evidence, source_anchor}` 移掉 `run_scoped_paths` 後，用 `diff_paths` 逐鍵與
`reconstruct(...)` 比對，回傳所有不符（含**未分類欄位** —— 既不在 run_scoped_paths、也不在
reconstruction）的路徑。任一非空 → `DOC_MAP_NONDETERMINISTIC_IDENTITY`。

> 因為每個保留欄位都被 6 個 input（或固定 constant）釘死，**兩份宣稱相同 inputs 的 projection
> 必然共用同一組 deterministic identity surface** —— paired drift 沒有立足點。PDF 的
> `profile_details.char_representation_digest`（profile_details 整體 run-scoped）另加一條
> targeted 檢查綁到 `normalized_representation_digest`。

### 4. 負例

- input mutation ×6：`content_digest` / `adapter_id` / `adapter_version` / `tenant_id` /
  **`source_instance_id`** / **`normalized_representation_digest`** 各改一個、instance 不動
  → reconstruction 變、fixture 未變 → surface diff → RED。
- **paired drift ×2**（reviewer 的原案例）：`raw.digests.normalized_digest` +
  `anchor.representation.representation_digest` 一起改成同值；`raw` + `anchor`
  `source_identity.source_instance_id` 一起改成同值 —— inputs 不動 → 兩者都偏離
  `inputs.*` → RED。
- **unclassified field ×1**：在 reconstructed 子物件（`idempotency_basis`）內加一個既不在
  run_scoped_paths、也不在 reconstruction 的欄位 → diff → RED。
- 既有 6 個 derivation 負例（含 anchor identity drift、normalized_digest drift）在新機制下
  仍 RED。

### 5. 檔案大小

`scripts/validate_document_adapter_mapping_contract.rb` 394 行（< 400）。
`reconstruct_deterministic_projection` / `deterministic_surface_mismatches` / `diff_paths` /
`DOC_MAP_DETERMINISM_INPUTS` / `DOC_MAP_RUN_SCOPED_PATHS` 在 `scripts/lib/omos_contract_helpers.rb`。

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 19 個 Ruby validator（含共用 lib 回歸）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- enforcement parity（cp-based restore）：
  - neutralize `deterministic_surface_mismatches` → 永遠 `[]` → RED
  - **reviewer bypass A**：fixture paired `normalized_digest` drift、inputs 固定 → RED
  - **reviewer bypass B**：fixture paired `source_instance_id` drift、inputs 固定 → RED
  - YAML `run_scoped_paths` 少一條 → RED
  - YAML `inputs` 少 `normalized_representation_digest` → RED
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 error code（新負例沿用 `DOC_MAP_NONDETERMINISTIC_IDENTITY`）；F-01 / F-02 / P2
  成果原封保留。

## 交付

- branch `cc/doc-adapter-mapping`，repair-05 commit 在 `f2333e1` 之後。
- 針對性再 review 範圍：`f2333e1..<repair-05 SHA>`（`c2e184f` / `faddb8c` / `d2ee1d2` /
  `df6b2ff` / `f2333e1` 皆不動）。
