---
id: DOC-ADAPTER-DETERMINISM-CLOSEOUT-20260910
parent: DOC-ADAPTER-MAPPING-20260909
implements: DOC-ADAPTER-DETERMINISM-SPEC-FREEZE-20260910（OWNER_SIGNED）
status: IMPLEMENTED_AWAITING_TARGETED_REREVIEW
type: implementation
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_chain_sha: [faddb8c, d2ee1d2, df6b2ff, f2333e1, 9ef254f, e7505f8]
delta: e7505f8..HEAD（cc/doc-adapter-mapping）
scope: 只實作 Owner 簽定的 FP-1..FP-5 + carry-over P2；不重開任何已 CLOSED finding
---

# Determinism 收尾｜Document Adapter Mapping（repo #2）

這**不是 repair-07**。repair-06 的 hard stop 已觸發，`F-03` 轉 T2 spec-freeze
（`.work/CARD-DOC-ADAPTER-DETERMINISM-SPEC-FREEZE-20260910.md`），Owner 於 2026-09-10 簽定
FP-1…FP-5（全採 CC 建議）。本卡只做「照簽定實作」。

## 簽定內容 → 實作對照

### FP-1 — determinism 只宣稱 evidence identity

- YAML `deterministic_derivation.claim: EVIDENCE_IDENTITY_ONLY` + `claim_rule` 明寫
  「不宣稱整份 emitted projection 逐位元相同；per-run ref／ingestion metadata／extraction
  quality 依設計即為 run-scoped」。
- validator 斷言 `claim` 逐字相符（竄改 → RED）。

### FP-2 — `projection_digest` → `deterministic_projection_digest`

- 舊 `projection_digest()`（hash 整份 triple、只扣 `excluded_from_canonical_digest`）**刪除**。
- 新 `deterministic_projection_digest(triple)` =
  `"sha256:" + SHA256(canonical_json(deterministic_surface(triple)))` —— 與 reconstruction
  比對用的是**同一個 surface**，因此 run-scoped 欄位在構造上不可能改變它。
- YAML `derived` 改列 `deterministic_projection_digest`。

### FP-3 — 單一總分類（止血點）

- `DOC_MAP_RUN_SCOPED_PATHS` 成為**唯一**權威分類，涵蓋三個 slice（新增
  `blocks/*/block_id`、`blocks/*/parent_id`、`blocks/*/source_anchor_refs`、`blocks/*/quality`）。
- 刪除 `DETERMINISTIC_EXCLUDED_PATHS`、`IDENTITY_BEARING_FIELDS`、
  `DOC_MAP_BLOCK_RUN_SCOPED_KEYS` 三份舊清單。
- 新 `run_scoped_path?(path)`：路徑落在任一 pattern（含其子樹、`*` 展開 block index）之下
  即 RUN_SCOPED，否則 DETERMINISTIC。
- `deterministic_surface` / `deterministic_projection_digest` / `normalized_document_digest` /
  `deterministic_surface_mismatches` **全部**由這一份推導。
- validator 斷言 YAML **不得**再出現 `excluded_from_canonical_digest` /
  `identity_bearing_fields` / `block_run_scoped_keys`（另立第二份清單 → RED）。
- path helper 升級：支援 Array 索引段與 `*` 萬用段。

### FP-4 — block `parent_id` / `source_anchor_refs` = run-scoped

已納入單一分類；文件結構由 deterministic surface 內的 `level` / `order` 承載。

### FP-5 — `quality` = run-scoped

已納入單一分類；不參與 identity，也不參與 `deterministic_projection_digest`。

### Carry-over P2 — 我捏造的 hash

`DOC_MAP_NEG_DERIVATION_PAIRED_BLOCK_CONTENT_DRIFT` 的 `content_sha256`
`sha256:0e2b0a4b…`（捏造）→ 校正為 `"Authorization boundary"` 的實算值
`sha256:6553c60633584d85f96a7063a340735c017dd6cc9de33f1b1e296d3d46ba43b4`。該負例現在只
證明 paired block drift 本身。

## F-03-R06 的直接關閉（本地重現，非推論）

positive fixture 的 `determinism.runtime_only_patch` 更名 `run_scoped_patch`，並**加入
reviewer 的原 mutation**：`blocks/0/quality/extraction_confidence: 0.5`（另加
`blocks/0/block_id`、`blocks/1/source_anchor_refs`、markdown 的 `blocks/2/quality` +
`blocks/0/parent_id`）。validator 斷言：patch 的每個 key 必須 run-scoped、且
`deterministic_projection_digest` **不得改變**。

實測（確認 patch 真的落地、不是 no-op）：

```
quality.extraction_confidence : 0.98 -> 0.5          （確實生效）
blocks/0/block_id             : …111111 -> …999999   （確實生效）
base != patched (full)        : true                 （projection 真的不同）
deterministic_projection_digest base    : sha256:3109701453fe5615…
deterministic_projection_digest patched : sha256:3109701453fe5615…
EQUAL                                   : true       ← F-03-R06 關閉
run_scoped_path? : quality/block_id/chronology -> true；raw_digest/content/content_sha256 -> false
```

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 19 個 Ruby validator（含共用 lib 回歸）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- enforcement parity（cp-based restore，6 項全 RED-on-tamper）：
  1. `deterministic_projection_digest` 改回 hash 整份 projection（即 R06 的錯）→ **RED**
  2. 單一分類移除 `blocks/*/quality` → RED
  3. YAML 重新引入第二份清單 `excluded_from_canonical_digest` → RED
  4. YAML `claim` 改成 `WHOLE_EMITTED_PROJECTION` → RED
  5. YAML `run_scoped_paths` 少一條 → RED
  6. `run_scoped_patch` 混入 deterministic path → RED
- `git add -A && git diff --cached --check` → clean
- validator 369 行（< 400；三份清單收斂成一份後反而縮小）

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 error code。F-01 / F-02 / P2 / F-03-R04 / F-03-R05 成果原封保留。

## 交付

- branch `cc/doc-adapter-mapping`，收尾 commit 在 `e7505f8` 之後。
- 針對性再 review 範圍：`e7505f8..<closeout SHA>`。
- **review 判準已由 spec-freeze 收斂**：只驗「有沒有照 FP-1…FP-5 簽定實作」+ repair regression，
  不再是開放式 determinism 探索。
