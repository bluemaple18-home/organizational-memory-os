---
id: STD03-NORMALIZED-DOCUMENT-20260906
status: LOCKED_OWNER_ACCEPTED_20260907
type: implementation
---

# STD-03 NormalizedDocument block subset v0.1

- Objective：以已鎖定的 STD-00／01／02 建立可重建的 `NormalizedDocument` root／block 最小契約、正負 fixtures 與 deterministic validator，解鎖 EMEM-02。
- Root question：如何讓 PDF／Markdown／Jira 的 parser 輸出在不取得 canonical authority 的前提下，可穩定綁定 RawEvidence、SourceAnchor、parser receipt 與 Phase-1 blocks？
- Traces to：`STD-03`；`文件/知識庫標準文件規格-v0.1-草案.md` 第 7、24、27 節；`文件/STD-00-Schema-Vocabulary-Freeze-v0.1-提案.md` 第 10.3、14、24.3 節；`文件/待辦補充-標準文件規格-20260828.md` 的 `STD-03`。
- Requirement IDs：原 spec 未定義 `US-*`／`FR-*`／`SC-*`，因此本卡以穩定 slice ID `STD03-S01` 追溯上述節點；不將空白當完成證明。
- Dependencies：`STD-00 = LOCKED`、`STD-01／02 = LOCKED_OWNER_ACCEPTED_20260904`、CC schema foundation targeted re-review = `GO`。Blockers：無；current frontier = `STD03-S01`。
- Scope：JSON Schema 2020-12 root／block contract、PDF／Markdown／Jira 正例、單一 mutation 負例、跨層 resolution／digest／hierarchy validator、標準 engine parity、backlog／evidence。
- Constraints：不做 parser／adapter runtime、DB／canonical writer，不做 STD-04～06，不做 EMEM-02，不新增 workflow engine／Hook／Loop／Harness／Hermes，不吸收 Docling runtime，不處理 CC-SF-004～008／010，不 push。
- Evidence：`.work/evidence/STD03-NORMALIZED-DOCUMENT-20260906.md`。

## Independent review｜2026-09-07

- Fixed commit：`cfaeec6`（parent `287f491`）。
- Verdict：`GO`；P0／P1 = `0/0`。
- Non-blocking：`STD03-RV-001` table／image conditional mutation coverage（P2）；`STD03-RV-002` STD-03 JSON Schema expected-error exact parity（P3）。
- Current state：實作與獨立 review 完成；Owner 於 2026-09-07 接受並鎖版，Document Adapter Mapping／EMEM-02 的 STD-03 依賴阻塞已解除。

## Owner lock｜2026-09-07

- Owner 明確同意鎖定與 push；`STD-03 = LOCKED_OWNER_ACCEPTED_20260907`。
- `STD03-RV-001/002` 是已登錄非阻塞 hardening，不取消本次鎖版；必須在 Adapter Mapping 前完成。

## Kickoff decisions

1. `source_aliases: []` 為合法語意，表示目前沒有已知的非 canonical alias；`source_identity.native_id` 仍必填且非空。`CC-SF-009` 以此裁決關閉，本卡不改 STD-01 schema。
2. Phase-1 `block_type` 精確採 LOCKED vocabulary：`title`、`section_header`、`paragraph`、`list_item`、`code`、`table`、`image`、`unknown`；不另造 `image_ref`。
3. `NormalizedDocument` 是 `PROJECTION_ONLY`，可重建；RawEvidence 仍是來源真相，SourceAnchor 只作定位，parser receipt 只作 provenance。
4. Root 與 block 分開 schema；fixture bundle 負責證明 `block_refs` 可解析到實體 blocks，不把 runtime store 寫進 schema。

## `STD03-S01` 垂直切片

### Public contract

- Root 最小必填：`schema_version`、`normalized_document_id`、`source_evidence_ref`、`source_content_sha256`、`normalized_digest`、`parser_receipt_ref`、`document`、`quality_gaps`、`block_refs`。
- Block 最小必填：`block_id`、`block_type`、`parent_id`、`order`、`level`、`content`、`content_sha256`、`language`、`content_layer`、`source_anchor_refs`、`attributes`、`quality`。
- Root／嵌套 object 與 block 一律 closed；ID、URN、SHA-256、BCP 47／`und`、media type 沿用 STD-00 規則。
- `table` 必須有 structured cells；`image` 必須有 asset ref／caption／bbox；不允許只剩 Markdown 字串。

### Deterministic invariants

- `source_evidence_ref` 必須解析到 STD-01 fixture，`source_content_sha256` 必須對齊該 Evidence raw digest。
- 每個 `source_anchor_ref` 必須解析到 STD-02 fixture，且該 anchor 的 `evidence_ref` 必須與 root 相同。
- `block_refs` 必須與 bundle 內 block IDs 一對一；block ID／order 不得重複；parent 必須存在且不得成環。
- `content_sha256` 必須由 UTF-8 `content` deterministic 重算；`normalized_digest` 必須由已定義的 root／blocks normalized representation deterministic 重算，不可只驗 pattern。
- schema 與 imperative validator 各自責任必須有負例及 expected error metadata，不得用無關 rejection 假裝 coverage。

### Acceptance

1. PDF／Markdown／Jira 各一個 root／blocks 正例，均解析到真實 STD-01／02 fixtures。
2. 負例至少覆蓋：root／block 未關閉、必填空值、非 Phase-1 block type、unresolved evidence／anchor／evidence mismatch、digest mismatch、duplicate／missing block／parent cycle、table／image structured payload 缺失。
3. 每個負例為單一主要 mutation，具 expected schema path／keyword 或 semantic failure code；移除對應 enforcement 時 gate 必須轉紅。
4. `uv run --script scripts/validate_std_schema_engine.py`、STD-00／01／02／cross-layer／personal-memory regression、STD-03 validator、JSON／YAML parse、`git diff --check` 全數 PASS。
5. backlog 狀態只在證據完整後改為 `READY_FOR_REVIEW`；未經獨立 review 不得標 `GO`／`LOCKED`。

### TDD／checkpoint

- RED：先加一個正例與對應負例，證明現有 engine 不知道 STD-03。
- GREEN：最少 schema／validator 使當前垂直路徑通過。
- Checkpoint A：root／block schema／positive／schema negatives 通過。
- Checkpoint B：cross-resource／digest／hierarchy negatives 與全量 regression 通過。

## Product fit

- Measured gap：STD-03 無 schema／fixtures／validator，EMEM-02 明確被此依賴阻擋。
- Why not less：只寫 root shape 無法證明 block／anchor／digest 真正可解析，會重演「URN pattern 通過但實體不存在」。
- Why not more：parser／adapter runtime、assertion／canonical write 與 retrieval 都不是此 contract slice 的必要證據。
- Do not absorb：Docling runtime／object model、Unstructured pipeline、第二套 job engine／registry／DB／agent orchestration。
- Rollback：新 schema／fixtures／validator 不連 production runtime；可以單獨 revert 本 slice。

## Likely files

- `規格/v0.1/normalized-document.schema.json`
- `規格/v0.1/normalized-document-block.schema.json`
- `規格/v0.1/fixtures/std-03-normalized-document-positive-fixtures.json`
- `規格/v0.1/fixtures/std-03-normalized-document-negative-fixtures.json`
- `scripts/validate_std03_normalized_document_contract.rb`
- `scripts/validate_std_schema_engine.py`
- `文件/待辦補充-標準文件規格-20260828.md`
- `文件/待辦重整.md`
- `.work/evidence/STD03-NORMALIZED-DOCUMENT-20260906.md`
