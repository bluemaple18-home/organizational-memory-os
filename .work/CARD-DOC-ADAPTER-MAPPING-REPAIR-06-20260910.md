---
id: DOC-ADAPTER-MAPPING-REPAIR-06-20260910
parent: DOC-ADAPTER-MAPPING-20260909
prior_repairs: [REPAIR-01 .. REPAIR-05 — 20260910]
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_chain_sha: [faddb8c, d2ee1d2, df6b2ff, f2333e1, 9ef254f]
repair_delta: 9ef254f..HEAD（cc/doc-adapter-mapping）
scope: 只收 F-03-R05（blocks 未進 deterministic reconstruction）
hard_stop: 若 repair-06 再 review 仍 NO_GO，不做 repair-07 —— 轉 Owner spec-freeze（T2）決策
---

# Repair 06｜Document Adapter Mapping（repo #2）

Repair 05 再 review 結論為 **NO_GO（P1=1, `F-03-R05`）**：RawEvidence / SourceAnchor 的
deterministic reconstruction 已 CLOSED（含 R04 的兩個 paired-drift bypass），但 `reconstruct` /
`deterministic_surface_mismatches` **完全沒把 `block_instances` 傳進去**；`projection_digest`
（YAML `derived` 仍列）涵蓋 blocks，因此同一組 declared inputs 仍可接受兩份 block 內容不同的
完整 projection。原 review SHA `c2e184f` 與 repair-01..05（`faddb8c` / `d2ee1d2` / `df6b2ff` /
`f2333e1` / `9ef254f`）皆不動。

## 收到的裁決（F-03-R05，P1）

- 保持 6 個 inputs 不動，把某個 schema-valid block 的 `content` + `content_sha256` 一起換成
  另一組合法值 → `deterministic_surface_mismatches(...) == []` 仍成立、`projection_digest`
  只是從「已修改的 projection」重算 → 兩份不同完整 projection 各自 PASS。
- 建議：把 deterministic block projection 納入 reconstruction / machine comparison，並補上
  決定它所需的明確 input；或明確停止宣稱 projection_digest 由現有 inputs 決定。補一個 paired
  block content / content_sha256 drift 負例，gate 必須 RED。

## 修復內容（只收 F-03-R05）— 第 7 個 declared input + block slice 納入 machine comparison

### 1. `normalized_document_digest` — 第 7 個 declared input

`deterministic_derivation.inputs` = 前 6 個 + `normalized_document_digest`
（`sha256(canonical_json(deterministic block surface))` —— 決定 NormalizedDocument block 集）。

### 2. `block_run_scoped_keys` — 每個 block 的 per-run 欄位

`DOC_MAP_BLOCK_RUN_SCOPED_KEYS = [block_id, parent_id, source_anchor_refs, quality]`
（YAML `block_run_scoped_keys` 逐字綁定）：`block_id` / `parent_id` / `source_anchor_refs` 是
per-run urn 連結，`quality` 是 per-run 抽取量測。deterministic block surface = block 物件
去掉這 4 個 key。

### 3. block slice 進 `deterministic_surface_mismatches`

`deterministic_surface_mismatches(kind, inputs, raw, anchor, blocks)`（多收 `blocks` 參數）：
- 原 RawEvidence / SourceAnchor reconstruction 比對不變。
- **新**：`normalized_document_digest(block_instances)` —— 每個 block 去掉
  `block_run_scoped_keys` → canonical JSON list → SHA256 —— 必須逐字等於
  `inputs.normalized_document_digest`，否則加 `blocks/normalized_document_digest` 到 diff。
- **新**：每個 block `content_sha256` 必須等於 `"sha256:" + SHA256(block.content)`，否則加
  `blocks/N/content_sha256` 到 diff（block content 與其 digest 不得脫鉤）。
- PDF `profile_details.char_representation_digest` 的 targeted 綁定一併移進本函式。

任一 diff 非空 → `DOC_MAP_NONDETERMINISTIC_IDENTITY`。

> 因為 RawEvidence + SourceAnchor 的每個保留欄位、以及整個 deterministic block surface，都被
> 7 個 declared input（或固定 schema constant）釘死，**兩份宣稱相同 inputs 的完整 projection
> 必然共用同一組 deterministic projection** —— identity slice 與 block slice 都沒有 paired
> drift 的空間。

### 4. 負例

- `DOC_MAP_NEG_DERIVATION_INPUT_NORMALIZED_DOC_DIGEST`（`input_mutation` 改
  `normalized_document_digest`、blocks 不動）→ 重算 digest ≠ input → RED。
- **`DOC_MAP_NEG_DERIVATION_PAIRED_BLOCK_CONTENT_DRIFT`**（reviewer 的原案例：`block_instances[0]`
  的 `content` + `content_sha256` 一起換成另一組合法一致對、7 個 inputs 全固定）→ block-set
  digest 偏離 `inputs.normalized_document_digest` → RED。
- `DOC_MAP_NEG_DERIVATION_BLOCK_SHA_INCONSISTENT`（只改 `content`、`content_sha256` 不動）→
  `content_sha256 != SHA256(content)` 且 block-set digest 也偏離 → RED。
- 定點驗證：`SHA_INCONSISTENT` → 2 gaps；`PAIRED_DRIFT` → `["blocks/normalized_document_digest"]`；
  baseline → `[]`。

### 5. 檔案大小 / 重構

`scripts/validate_document_adapter_mapping_contract.rb` 397 行（< 400）。
`deterministic_block_surface` / `normalized_document_digest` / block 比對邏輯在
`scripts/lib/omos_contract_helpers.rb`。fixture 的 6 個 block `content_sha256` 一併校正為
`SHA256(content)`。

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 19 個 Ruby validator（含共用 lib 回歸）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- enforcement parity（cp-based restore）：
  - neutralize `normalized_document_digest` 比對 → RED
  - **reviewer bypass**：fixture paired block `content` + `content_sha256` drift、7 inputs 固定 → RED
  - YAML `block_run_scoped_keys` 少一條 → RED
  - YAML `inputs` 少 `normalized_document_digest` → RED
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 error code（新負例沿用 `DOC_MAP_NONDETERMINISTIC_IDENTITY`）；F-01 / F-02 / P2、
  以及 R05 的 RawEvidence / SourceAnchor reconstruction 成果原封保留。

## 交付

- branch `cc/doc-adapter-mapping`，repair-06 commit 在 `9ef254f` 之後。
- 針對性再 review 範圍：`9ef254f..<repair-06 SHA>`（`c2e184f` / `faddb8c` / `d2ee1d2` /
  `df6b2ff` / `f2333e1` / `9ef254f` 皆不動）。
- **hard stop**：若本輪 verdict 仍 NO_GO，不做 repair-07 —— 依 Owner 選項轉 spec-freeze（T2）。
