---
id: SCHEMA-HARDENING-PRE-ADAPTER-20260907
status: COMPLETE_OWNER_ACCEPTED_20260907
type: implementation
---

# Schema hardening before Adapter Mapping

- Objective：關閉 `CC-SF-004～008/010` 與 `STD03-RV-001/002`，讓 schema／fixture／validator gate 在 Adapter Mapping 開工前可 fail closed，不建立第二套 engine。
- Root question：目前 schema 契約已鎖版，最少要補哪些 deterministic guard，才不會出現「契約被刪、無關 error 或 duplicate key 卻仍顯示全綠」？
- Traces to：`文件/待辦重整.md` 第九節；`.work/evidence/STD03-NORMALIZED-DOCUMENT-20260906.md` 的 `STD03-RV-001/002`；`.work/evidence/CC-SCHEMA-FOUNDATION-TARGETED-REREVIEW-20260906.yaml`。
- Dependencies：`STD-01/02/03 = LOCKED_OWNER_ACCEPTED`。
- Current frontier：`HARDEN-S01`；`HARDEN-S02` 被 `HARDEN-S01` checkpoint 阻擋。
- Constraints：不做 parser／Document／Jira Adapter／EMEM-02／DB／runtime／Hook／Loop／Harness／Hermes；不改 authority 邊界；不新增 registry／workflow engine／package dependency；不 merge／push。
- Evidence：`.work/evidence/SCHEMA-HARDENING-PRE-ADAPTER-20260907.md`。

## Review chain｜2026-09-07

- Implementation checkpoint：`0b0b0dd`（parent `d7c064d`）。
- Initial review：`NO-GO`；唯一 P1 `SH-RV-001` 指出 `resolved_at` seconds-only pattern 與未啟用 format assertion 破壞 RFC3339 parity。
- Repair checkpoints：`c12213a`、`9fef981`。
- Targeted re-review：`SH-RV-001 CLOSED`；verdict `GO`；P0／P1／P2／P3 = `0/0/0/0`。
- Current state：限域 hardening 已實作並複審通過；Owner 於 2026-09-07 接受 STD-02 timestamp contract 精準化，Adapter Mapping gate 已解除。

## HARDEN-S01｜Gate integrity

Traces to：`CC-SF-004/005/007/008/010`、`STD03-RV-001/002`。

1. JSON／YAML loader 對 duplicate object keys fail closed；正常現有 fixtures 不變。
2. Standard engine 對 JSON_SCHEMA negatives 比對 `actual error pairs == declared error pairs`；多餘／缺少的 path／keyword 都轉紅。
3. Coverage 輸出必須是實際 tested／passed／semantic-excluded 計數，不得使用 `{n}/{n}` 自證。
4. STD-03 增 table `attributes={}` 與 image `attributes={}` schema negatives；Ruby schema document gate 鎖住 table／image conditional AST。
5. STD-01 NON_I_JSON Ruby defensive mirror 有 positive execution coverage，移除 mirror 時 gate 轉紅。
6. Cross-layer fixture 的 8 個 negative names／count 完整登錄並精確斷言；移除／改名／多加都轉紅。

Acceptance：每一點有正例／負例或 mutation probe；STD-00～03、standard engine、cross-layer、personal-memory、JSON／YAML parse、`git diff --check` 全 PASS。

Checkpoint A：`HARDEN-S01` 綠燈後才開 `HARDEN-S02`。

## HARDEN-S02｜Cross-schema reference alignment

Traces to：`CC-SF-006`。

1. 只收緊 STD-02 對已鎖定 STD-01 canonical refs 的表達：`evidence_ref`、`acl_snapshot_ref` 採與 STD-01 相同的 UUIDv7 URN pattern。
2. `resolution.resolved_at` 在 schema 與 imperative validator 保持 UTC RFC3339 `Z` 一致；如果 Draft 2020-12 `date-time` 本身允許 offset，用明確 pattern 補上已鎖 UTC 規則。
3. 新增單一 mutation negatives，證明 UUIDv4／寬鬆 36-char 與 non-UTC offset 會被 schema／Ruby 契約責任精確拒絕。
4. 不改既有合法 fixture identity，不重開 SourceAnchor authority、profile 或 selector 語意。

Acceptance：STD-02 schema／Ruby parity 及全量 regression PASS；差異只包含參考 pattern／fixtures／validators／evidence／backlog。

## Stop conditions

- 若現有正例使用非 UUIDv7 identity，或收緊需要改 source authority，停在 `HARDEN-S01` 並回報 Owner，不偷改鎖版契約。
- 只有 P0／P1 阻塞後續 Adapter Mapping；P2／P3 留 backlog。

## Likely files

- `scripts/validate_std_schema_engine.py`
- `scripts/validate_std00_contract.rb`／`validate_std01_raw_evidence_contract.rb`／`validate_std02_source_anchor_contract.rb`／`validate_std03_normalized_document_contract.rb`
- `scripts/validate_cc_cross_layer_contract.py`
- `規格/v0.1/source-anchor.schema.json`
- `規格/v0.1/fixtures/std-01-raw-evidence-*-fixtures.json`
- `規格/v0.1/fixtures/std-02-source-anchor-*-fixtures.json`
- `規格/v0.1/fixtures/std-03-normalized-document-negative-fixtures.json`
- `規格/v0.1/fixtures/cc-schema-foundation-cross-layer-fixtures.json`
- `文件/待辦重整.md`
- `.work/evidence/SCHEMA-HARDENING-PRE-ADAPTER-20260907.md`
