---
id: DOC-ADAPTER-MAPPING-REPAIR-02-20260910
parent: DOC-ADAPTER-MAPPING-20260909
prior_repair: DOC-ADAPTER-MAPPING-REPAIR-01-20260910
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_01_sha: faddb8c
repair_delta: faddb8c..HEAD（cc/doc-adapter-mapping）
scope: 只做 review 指定的兩件核心事 + P2；不擴 scope
---

# Repair 02｜Document Adapter Mapping（repo #2）

Repair 01 的再 review 結論為 **NO_GO（P1=2, P2=1）**：F-01 已 CLOSED；F-02 核心已修但引入
「YAML mapping table ↔ schema-valid fixture 脫鉤」regression；F-03（determinism）NOT CLOSED
—— 仍是 fixture 自報 digest，validator 沒有實算。原 review SHA `c2e184f` 與 Repair 01 commit
`faddb8c` 皆不動；本修復是 `cc/doc-adapter-mapping` 上的新 commit。

## 收到的裁決

- **P1（F-02 regression）**：Repair 01 重寫 validator 時移除了 `raw_evidence_projection` 的整段
  結構斷言（`source_system` / `structured_profile_by_kind` / `allowed_ingestion_modes` /
  target enum 相容性）。YAML 仍宣告這些值，但 Ruby gate 不再看；Python companion 只驗 fixture
  是不是合法 STD instance，不讀 YAML。結果 spec 寫 A、fixture 測 B，兩個 gate 都能 PASS
  —— 違反本卡「mapping contract」本身。
- **P1（F-03 未關）**：determinism 只比對 `runs[0].projection_digest != runs[1].projection_digest`
  —— reviewer 給兩個相同 digest 它就信；沒有從實際 instance 算 projection digest，也沒驗
  `native_id / source_version / digests / idempotency_key` 是 inputs 的函數。且 spec 宣稱
  「whole projection 只由 content_digest + adapter_id + adapter_version 決定」，但 STD-01
  instance 本身帶 `observed_at / received_at / persisted_at` 等 runtime 時間 —— 契約沒定義
  canonical deterministic surface 與 exclusion。
- **P2**：`required_instance_negative_fixtures` 是 dead contract —— Python 只 for-loop 跑 case，
  沒比對 required coverage 三個是否都在、`covers` 是否 exact、case_id 是否唯一。

## 修復內容（只做兩件核心事 + P2）

### 核心 1 — 重新綁回 mapping table ↔ spec/fixture（關 F-02 regression）

- `scripts/validate_document_adapter_mapping_contract.rb` 補回 `raw_evidence_projection`
  結構斷言，且進一步做 **spec ↔ fixture 一致性**：
  - enum-valued 值必須是對應 `raw-evidence-envelope.schema.json` enum 成員：
    `payload.structured_profile_by_kind`（∈ `payload.structured_profile.enum`）、
    `payload.canonicalization_profile`（∈ enum）、
    `provenance.allowed_ingestion_modes`（⊆ `provenance.ingestion_mode.enum`）、
    `source_version.basis` / `.kind`（∈ 各自 enum）。
  - 鎖定值：`source_system == document`、`native_id_basis == CONTENT_SHA256`、
    `entity_type_by_kind == {PDF: PDF, MARKDOWN: MARKDOWN}`、
    `structured_profile_by_kind == {PDF: BINARY, MARKDOWN: TEXT}`、
    `allowed_ingestion_modes == [MANUAL_UPLOAD, BULK_EXPORT]`、
    `source_version.basis == CONTENT_ONLY` / `.kind == CONTENT_DIGEST`。
  - **每個 positive fixture 的 `raw_evidence_instance` / `source_anchor_instance` /
    `block_instances` 必須與 mapping table 對該 source kind 的宣告逐欄一致**
    （`source_system` / `entity_type` / `payload.structured_profile` /
    `payload.canonicalization_profile` / `provenance.ingestion_mode` /
    `source_version.basis` / `.kind` / anchor `profile` / required selector /
    `normalization_profile` / 每個 block 的 `content_layer`）。YAML 一改、或 fixture 一改，
    另一邊對不上就 RED。
- YAML `raw_evidence_projection.rule` 補上這段綁定的文字說明。

### 核心 2 — determinism 改為 validator 實算 canonical projection digest（關 F-03）

- YAML `deterministic_derivation` 新增明確的 deterministic surface 定義：
  - `identity_bearing_fields`：跨 run 必須 byte-identical 的 stable 欄位
    （`raw_evidence/source_identity/native_id`、`/source_version`、`/digests`、
    `/idempotency_key`、`/payload/payload_ref`）。
  - `excluded_from_canonical_digest`：ingestion-time / wall-clock surface
    （`chronology/observed_at|received_at|persisted_at`、
    `provenance/source_observation_receipt_ref|adapter_activity_ref|lineage_receipt_ref`、
    `activity_refs`、`source_anchor/resolution/resolved_at|resolver_version`）。
  - `projection_digest` 的定義：`{raw_evidence, source_anchor, blocks}` 移除 excluded path
    後，遞迴 sorted-key canonical JSON 的 SHA256。**fixture 不再提供任何 digest。**
- validator 自帶 `DETERMINISTIC_EXCLUDED_PATHS` / `IDENTITY_BEARING_FIELDS` 常數，斷言 YAML
  兩份清單逐字等於常數（yaml ↔ validator 綁定）。
- positive fixture：`determinism.two_runs`（自報 digest）→ 改為
  `determinism.runtime_only_patch`（一組只落在 excluded path 的 pointer→值）。validator：
  (a) 斷言 patch 的 key 全部 ∈ excluded；(b) `projection_digest(base) ==
  projection_digest(patched)`（只改 runtime 欄位不得改 digest）；(c)
  `identity_bearing_fields` 逐欄 byte-identical；(d) 拒收任何殘留的 `two_runs` / 自報
  `projection_digest`。
- negative fixture：`DOC_MAP_NEG_NONDETERMINISTIC_TWO_RUNS`（自報 digest）→ 改為
  `DOC_MAP_NEG_NONDETERMINISTIC_STABLE_FIELD_DRIFT`：`base_case_ref: DOC_MAP_POS_PDF` +
  `stable_field_mutation`（改 `raw_evidence/digests/raw_digest` 與
  `raw_evidence/source_identity/native_id`）。validator 取 base positive 的實際 instance、
  apply mutation、自算兩份 canonical digest，**必須不同**，否則 determinism gate 視為失效
  （RED）；並斷言 mutation 不能只落在 excluded path。

### P2 — `required_instance_negative_fixtures` 變活契約

- Ruby validator 現在也讀 `document-adapter-mapping-instance-negative-fixtures.json`，斷言：
  `instance_negative_cases[].covers` 排序後**剛好等於** `required_instance_negative_fixtures`；
  `case_id` 唯一；每個 case 帶 `target_schema` / `expected_result == REJECT` / `instance`。
  YAML 的 `required_instance_negative_fixtures` 也綁到 Ruby 常數
  `EXPECTED_INSTANCE_NEGATIVE_LABELS`。
- Python companion 加第二道防線：`covers` 排序等於硬編清單、`case_id` 唯一、每個 label 必須
  出現在 mapping spec 檔內。刪任一 instance-negative case → Ruby 與 Python 皆 RED。

### 檔案大小

`scripts/validate_document_adapter_mapping_contract.rb` 373 行（< 400，守
`.agentskills/docs/coding-standards.md` §2）。通用工具 `deep_dup` / `*_path` /
`canonical_json` 下沉到 `scripts/lib/omos_contract_helpers.rb`（+40 行），未改既有 validator
行為（該檔既有 `sorted_set` 等本地覆蓋仍在 require 後定義）。

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 19 個 Ruby validator（STD-00~03 / cross-layer / personal-memory / AIWR regression）
  → 全 PASS（含共用 lib 下沉後的回歸）
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- 針對性 enforcement parity（cp-based restore，不用 git checkout）：
  - YAML `native_id_basis` / `structured_profile_by_kind` / `allowed_ingestion_modes` drift → RED
  - positive fixture instance 與 mapping 不一致（`structured_profile` / `entity_type`）→ RED
  - `runtime_only_patch` 改到非 excluded path → RED
  - 移除 `runtime_only_patch` → RED
  - determinism negative 的 mutation 只落在 excluded path（digest 不會動）→ RED
  - fixture 殘留自報 `two_runs` → RED
  - 刪一個 instance-negative case（Ruby + Python）→ RED
  - YAML `excluded_from_canonical_digest` 竄改 → RED
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / companion / 兩份 mapping fixture + 共用 lib；
  未動任何 `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 registry / FSM / package / runtime。
- 沒新增 error code、沒新增 negative label（`DOC_MAP_NEG_NONDETERMINISTIC_TWO_RUNS` 換名
  但 `covers` label 不變）；F-01 的成果原封保留。

## 交付

- branch `cc/doc-adapter-mapping`，repair-02 commit 在 `faddb8c` 之後。
- 針對性再 review 範圍：`faddb8c..<repair-02 SHA>`（原 review SHA `c2e184f`、Repair 01
  `faddb8c` 皆不動）。
