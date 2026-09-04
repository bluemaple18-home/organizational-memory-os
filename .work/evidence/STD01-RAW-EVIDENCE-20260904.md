---
id: STD01-RAW-EVIDENCE-20260904-EVIDENCE
status: LOCKED_OWNER_ACCEPTED_20260904
type: implementation-evidence
---

# STD-01 RawEvidenceEnvelope v0.1 證據｜2026-09-04

## 範圍與權限

- 依 `STD-00 = LOCKED` 建立 RawEvidenceEnvelope v0.1 JSON Schema、PDF／Markdown／Jira 正負 fixtures與 deterministic validator。
- 保留既有未提交 STD00 LOCK 變更，不重寫或混改 STD00 鎖版內容。
- 未啟動 parser、Connector、DB、migration、runtime、Skill、Hook、Loop、Harness、Hermes或 canonical write。
- 未 commit／push；未標任務卡 `COMPLETE`。

## 本機標準 schema engine 檢查

本機未找到可直接使用且不需下載的 JSON Schema 2020-12 runtime validator：

```text
ruby -e 'begin; require "json_schemer"; puts "json_schemer available"; rescue LoadError => e; puts "json_schemer missing"; end'
json_schemer missing

python3 - <<'PY'
try:
    import jsonschema
    print('python jsonschema available', jsonschema.__version__)
except Exception as exc:
    print('python jsonschema missing', type(exc).__name__, exc)
PY
python jsonschema missing ModuleNotFoundError No module named 'jsonschema'

node -e 'try { const Ajv = require("ajv"); const ajv = new Ajv(); console.log("ajv available"); } catch (e) { console.log("ajv missing", e.code || e.message); }'
ajv missing MODULE_NOT_FOUND

node -e 'try { require("ajv/dist/2020"); console.log("ajv2020 available"); } catch (e) { console.log("ajv2020 missing", e.code || e.message); }'
ajv2020 missing MODULE_NOT_FOUND
```

驗證邊界：本卡產出標準 JSON Schema 2020-12 並做 JSON parse／schema document sanity check；runtime validation由無依賴 deterministic validator覆蓋結構與跨事件 invariants，不宣稱已由標準 JSON Schema engine驗證 fixtures。

## TDD 證據

RED：

```text
ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator FAIL
- MISSING_FILE: 規格/v0.1/raw-evidence-envelope.schema.json
- MISSING_FILE: 規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json
- MISSING_FILE: 規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json
```

GREEN：

```text
ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator PASS
```

## 修補內容

- `規格/v0.1/raw-evidence-envelope.schema.json`：新增 JSON Schema 2020-12 field-level contract，覆蓋 evidence identity、source tuple／aliases、event／delivery、source version、four clocks、digests、payload retention、ACL、transport、provenance、availability、idempotency與quality gaps。
- `規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json`：新增 PDF manual upload、Git Markdown SOP、Jira Cloud issue description三個正向 RawEvidenceEnvelope。
- `規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json`：新增 20 個完整 envelope 負向 cases；每個單筆 case 宣告 base fixture 與最小 mutation path，並覆蓋 evidence identity、redelivery／revision／cross-source identity、兩種 idempotency profile、event fallback、four clocks、availability／deletion、raw／canonical digest、ACL、provenance、LOCKED quality gap與 `COMPLETE != VERIFIED`。
- `scripts/validate_std01_raw_evidence_contract.rb`：新增無依賴 deterministic validator，驗單筆 envelope結構與跨事件 semantic invariants。
- Historical status note：當時 `文件/待辦補充-標準文件規格-20260828.md` 以分段 token 記錄 STD-01；current truth 已統一為 `LOCKED_OWNER_ACCEPTED_20260904`。

## Acceptance mapping

| Acceptance | 結果 |
|---|---|
| evidence identity／UUIDv7／URN語意 | PASS |
| stable source identity tuple／aliases | PASS |
| source event／delivery identity分離 | PASS |
| source version union | PASS |
| four-clock chronology | PASS |
| raw／optional canonical digest | PASS |
| payload ref／retention | PASS |
| ACL snapshot ref | PASS |
| optional transport envelope | PASS |
| adapter／activity／lineage refs | PASS |
| availability／deletion distinction | PASS |
| PDF／Markdown／Jira positive fixtures | PASS |
| required negative fixtures與卡片追加負向類別 | PASS |
| schema與跨事件 deterministic tests | PASS |

## 最終驗證

```text
ruby -e 'require "json"; JSON.parse(File.read("規格/v0.1/raw-evidence-envelope.schema.json")); JSON.parse(File.read("規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")); JSON.parse(File.read("規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json")); puts "std01 json parse PASS"'
std01 json parse PASS

ruby -c scripts/validate_std01_raw_evidence_contract.rb
Syntax OK

ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator PASS

ruby scripts/validate_std00_contract.rb
STD-00 validator PASS

ruby scripts/validate_personal_memory_contract.rb
PASS personal memory contract validation

git diff --check
PASS
```

## Repair-01｜獨立審查 P1／P2 修補

RED（先加強 gate，再修改 fixtures）：

```text
ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator FAIL
- NEGATIVE_FIXTURE_NAMES
- NEGATIVE_BASE / NEGATIVE_COMPLETE_ENVELOPE
- NEGATIVE_UNRELATED_FAILURE（既有負例為局部片段，會同時觸發多個無關錯誤）
```

GREEN：

```text
ruby -c scripts/validate_std01_raw_evidence_contract.rb
Syntax OK
ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator PASS
ruby scripts/validate_std00_contract.rb
STD-00 validator PASS
ruby scripts/validate_personal_memory_contract.rb
PASS personal memory contract validation
ruby -e 'require "json"; JSON.parse(File.read("規格/v0.1/raw-evidence-envelope.schema.json")); JSON.parse(File.read("規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")); JSON.parse(File.read("規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json")); puts "std01 json parse PASS"'
std01 json parse PASS
git diff --check
PASS
```

修補結果：

- Entity snapshot idempotency profile強制 `tenant_id + stable_source_identity + source_version`。
- Native source event profile強制 `tenant_id + stable_source_identity + event_type + native_event_id`；缺 native event id時改走 `FALLBACK_DERIVED`，強制 `tenant_id + stable_source_identity + event_type + occurred_at + raw_digest`及 `IDENTITY_FALLBACK_DERIVED`。
- `NONE` canonicalization強制 canonical digest為 `null`；`RFC8785_JCS`強制 `I_JSON`與 canonical digest；不可 canonicalize時 fail closed並留下 `CANONICALIZATION_UNAVAILABLE`。
- Four clocks強制 `observed_at <= received_at <= persisted_at`，且禁止四個時間全部相等。
- 負例改為完整 envelope並封住 unrelated failure；schema AST gate檢查 root／nested closure、required、pattern及 conditional branches。
- `quality_gaps.code`綁定 `common-vocabulary.yaml` 的 LOCKED vocabulary，不接受任意字串。

任務卡維持 `ACTIVE`，等待同一 reviewer re-review；未標示 `COMPLETE`。

## Repair-02｜新 revision 重用 idempotency key P1 修補

負例先行：新增 `same-source-new-revision-reuses-idempotency-key` 完整跨事件情境。兩筆 envelope 的 stable source identity 相同、`source_version` 不同，第二筆使用新的 `evidence_id`／`evidence_ref`／`payload_ref`／delivery，但刻意沿用第一筆 `idempotency_key`。

RED（新增完整 fixture、尚未加入跨事件 key 規則）：

```text
ruby -e 'require "json"; JSON.parse(File.read("規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json")); puts "std01 negative json parse PASS"' && ruby scripts/validate_std01_raw_evidence_contract.rb
std01 negative json parse PASS
STD-01 RawEvidenceEnvelope validator FAIL
- NEGATIVE_EXPECTED_FAILURE: same-source-new-revision-reuses-idempotency-key 未觸發 REVISION_REUSED_IDEMPOTENCY_KEY
```

GREEN：

```text
ruby -c scripts/validate_std01_raw_evidence_contract.rb
Syntax OK
ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator PASS
```

修補結果：

- `validate_cross_event_semantics` 於同一 stable source identity、不同 source version 且 idempotency key 相同時，以 `REVISION_REUSED_IDEMPOTENCY_KEY` fail closed。
- 保留既有 `REVISION_REUSED_EVIDENCE_ID` gate；其 fixture 的新 revision 改用不同 idempotency key 與 delivery，避免無關 redelivery failure。
- schema 未改：既有 `OMOS_ENTITY_SNAPSHOT_IDEMPOTENCY_V1` 已強制 basis 包含 `tenant_id`、`stable_source_identity`、`source_version`；跨 envelope 的 key 值相異性無法由單筆 JSON Schema 表達，故僅由 deterministic cross-event validator 承擔。
- 未變更 STD00 或其他 STD01 contract；任務卡維持 `ACTIVE`，未標示 `COMPLETE`。

## 判定

```text
std_00_status: PRESERVED_LOCKED
std_01_status: LOCKED_OWNER_ACCEPTED_20260904
standard_json_schema_engine_runtime_validation: NOT_RUN_ENGINE_NOT_AVAILABLE
deterministic_validator: PASS
std_02_status: NOT_STARTED
```

## 最終獨立複驗

- Repair-02 新增完整跨事件 `NEG-004A`：同一 stable source、新 version、新 evidence identity，但重用舊 idempotency key。
- Validator 以 `REVISION_REUSED_IDEMPOTENCY_KEY` 單獨拒絕該情境，不依賴其他結構錯誤。
- 獨立 reviewer 最終 verdict：`GO`；未解 P0／P1：無；未發現 repair regression。
- 最終狀態：Owner 已於 2026-09-04 接受，`STD-01 = LOCKED_OWNER_ACCEPTED_20260904`。
