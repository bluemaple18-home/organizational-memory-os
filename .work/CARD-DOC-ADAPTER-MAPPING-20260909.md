---
id: DOC-ADAPTER-MAPPING-20260909
status: NO_GO_REPAIRED_05_AWAITING_TARGETED_REREVIEW
type: implementation
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
---

# Document Adapter Mapping（repo #2）

👉 [假設與目標確認]
- 目標：定義一份 machine-readable 契約：文件來源（PDF、Markdown）如何**確定性地**
  映射成 `RawEvidenceEnvelope`（STD-01）+ `SourceAnchor`（STD-02，profile
  `PDF_REGION_V1` / `MARKDOWN_TEXT_V1`）+ `NormalizedDocument` block subset（STD-03）。
  只封「來源 → 三個已鎖 schema 的欄位對映與組合規則」；不做 connector、parser 實作、
  ingestion runtime。
- 邊界：不重定義 STD-01/02/03（皆 `LOCKED_OWNER_ACCEPTED`）；不動 Jira（repo #3 另卡）；
  不做 Permission/Retention/Deletion（repo #4）或 Canonical writer（repo #5）。
- 驗收：見 Acceptance；正向 + fail-closed 負例通過，且能對一份真實 PDF / 一份真實 Markdown
  重建同一組 envelope + anchor + normalized blocks。

## Objective

以 `規格/v0.1/raw-evidence-envelope.schema.json`、`規格/v0.1/source-anchor.schema.json`
（含 `source-anchor-pdf-region-v1.schema.json` / `source-anchor-markdown-text-v1.schema.json`）、
`規格/v0.1/normalized-document*.schema.json` 為對映目標，定義：

- `document_source_kinds`：`PDF` / `MARKDOWN`；每種的 `source_identity` / `source_version`
  組成規則（PDF：檔案 hash + 頁碼範圍；Markdown：檔案 hash + codepoint 範圍）。
- `raw_evidence_projection`：來源欄位 → `RawEvidenceEnvelope` 必填欄位（`digests` 演算法、
  `payload` reference-only、`chronology` 四時鐘的哪幾個可得、`provenance`、`source_availability`）。
- `source_anchor_projection`：`profile_details` 的**確定性 shape**（PDF：normalized bbox +
  page；Markdown：codepoint offset + quote prefix/suffix）、`selectors` 組合規則、
  `normalization_profile: OMOS_TEXT_NORM_V1` 綁定、`resolution` 重解析規則。
- `normalized_document_projection`：文件 → NormalizedDocument block subset（哪些 block kind、
  table/image conditional、AST guard）。
- `hard_stops`：no connector / parser / runtime；pure mapping tables + thin validator；
  不重定義 STD 契約。

## Root question

如何讓「一份 PDF / Markdown 來源確定性地產出 STD-01/02/03 三個已鎖 schema 的實例、且可重建、
可 fail-closed 驗」變成可驗契約，而不重開任何 `LOCKED_OWNER_ACCEPTED` schema？

## Traces to

- `規格/v0.1/raw-evidence-envelope.schema.json`（STD-01，LOCKED）。
- `規格/v0.1/source-anchor*.schema.json`（STD-02，LOCKED；profile enum `PDF_REGION_V1` /
  `MARKDOWN_TEXT_V1`）。
- `規格/v0.1/normalized-document*.schema.json`（STD-03，LOCKED_OWNER_ACCEPTED_20260907）。
- `文件/研究包B-PDF-Markdown-Jira-SourceAnchor-20260828.md`（`RESEARCH_COMPLETE`：selector
  composition、PDF normalized bbox、Markdown codepoint+quote）。
- `文件/待辦補充-標準文件規格-20260828.md` §1 施工順序 #2。
- 下游：`EMEM-02`（SSP-291，Personal Evidence Profile / Source Mapping，
  `UNBLOCKED_NOT_STARTED_BY_STD_03_LOCK`）；repo #3 Jira Adapter Mapping（共用組合慣例）。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `DOC-ADAPTER-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：STD-01/02/03 = `LOCKED_OWNER_ACCEPTED`；pre-adapter hardening
  `SCHEMA-HARDENING-PRE-ADAPTER-20260907` = `COMPLETE_OWNER_ACCEPTED`（Adapter Mapping gate 已解除）。
- Blockers：無。
- Current frontier：`DOC-ADAPTER-S01`。

## Scope

- 新 `規格/v0.1/document-adapter-mapping.yaml`：上述 5 個 mapping 區塊。
- `scripts/validate_document_adapter_mapping_contract.rb`（新薄 validator）：structural +
  純函式 `document_mapping_failure(source, projected)` evaluator（PDF / Markdown 兩路），
  交叉讀 STD-01/02/03 三個 schema（pointer binding，驗投影欄位確實是目標 schema 的合法欄位）。
  沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures（含一份 PDF 樣本 anchor、一份 Markdown 樣本 anchor 的完整投影）。
- `文件/待辦重整.md` §八 / §十 狀態更新。

## Constraints

- 不重定義 STD-01/02/03；pointer 引用並交叉驗證。
- validator 只做薄判斷；不新增 registry / FSM / 狀態機引擎；不新增 package。推 branch，不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：STD-01/02/03 定義了 schema，但沒有把「文件來源如何確定性投影成這三者」
  寫成可驗契約。`EMEM-02` 需要一個 Personal Evidence Profile，而 Personal Profile 是本卡
  Document Mapping 的個人層特化。
- Why not less：沒有 Mapping 契約，每個 ingestion path 會各自解讀 STD schema，重演欄位分裂。
- Why not more：connector、PDF/Markdown parser、ingestion runtime、Job Engine 都不是本卡。
- Do not absorb：任何 parser library、WorkPool、Knowledge DB。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. `document_source_kinds` 剛好 `[PDF, MARKDOWN]`；每種的 `source_identity` / `source_version`
   組成規則明確且確定性（同來源同輸入 → 同 identity/version）。
2. `raw_evidence_projection`：投影出的欄位集合 ⊆ `raw-evidence-envelope.schema.json` 的
   properties；必填欄位齊；`payload` 為 reference（非內嵌內容）；`digests` 演算法鎖定。
3. `source_anchor_projection`：`profile` ∈ STD-02 enum；`profile_details` shape 對 PDF /
   Markdown 各自確定；`normalization_profile: OMOS_TEXT_NORM_V1`；`resolution` 有重解析定義。
4. `normalized_document_projection`：block kind ⊆ STD-03 block subset；table / image
   conditional 有專用規則。
5. 缺任一必填投影欄位 / 投影出非目標 schema 欄位 / profile 不符 → 各自 exact failure code。
6. 正向：一份 PDF + 一份 Markdown 樣本各自產出 contract-valid 的 envelope + anchor +
   normalized blocks → allow。
7. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
8. `ruby scripts/validate_document_adapter_mapping_contract.rb` + STD schema engine +
   STD-00~03 + cross-layer + personal-memory aggregator（regression）+ JSON/YAML parse +
   `git diff --check` 全 PASS。

## Stop conditions

- 若映射需要改 STD-01/02/03 任一已鎖 schema → 停，回 Owner（那是 schema 變更，不是 mapping）。
- 若確定性投影無法用純函式 + 資料表表達 → 停，回 Owner。

## Likely files

- `規格/v0.1/document-adapter-mapping.yaml`（新）
- `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json`（新）
- `scripts/validate_document_adapter_mapping_contract.rb`（新）
- `文件/待辦重整.md`
- `.work/evidence/DOC-ADAPTER-MAPPING-20260909.md`

## Evidence

`.work/evidence/DOC-ADAPTER-MAPPING-20260909.md`
