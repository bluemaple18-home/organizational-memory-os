# Schema Hardening Repair-01 Evidence

Status: READY_FOR_TARGETED_REREVIEW

## Scope

- 僅修 P1 `SH-RV-001`：`resolution.resolved_at` 的 UTC RFC3339 schema／standard engine／STD-02 fixture／Ruby schema AST parity。
- 未修改 UUID、authority、profile、selector、Adapter、EMEM-02，亦未 commit、merge 或 push。

## RED Evidence

以 HARDEN-S02 修補前的 seconds-only pattern 且未傳入 format checker 重現：

```text
fractional ['pattern']
invalid_calendar []
```

- `2026-09-04T01:00:00.123Z` 被舊 pattern 誤拒。
- `2026-99-99T99:99:99Z` 在未 assert `format` 時未被 schema 拒絕。

## Repair

- `source-anchor.schema.json` 的 UTC pattern 改為 `^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,9})?Z$`：允許零到九位 fractional seconds，拒絕空小數點與非 `Z` 結尾。
- `validate_std_schema_engine.py` 對 RawEvidence、NormalizedDocument、NormalizedDocumentBlock 與三個 SourceAnchor profile validator 一律傳入標準 `FormatChecker()`。
- `jsonschema` 的 `date-time` checker 只有在 `rfc3339-validator` 可用時才會註冊；因此 script metadata 釘入最小直接依賴 `rfc3339-validator==0.1.4`，不以自訂 format checker 擴張 UTC 規則。
- STD-02 正例改為 `.123Z`；新增 invalid calendar JSON_SCHEMA negative，精確期望 `format` error；既有 `+08:00` case 保留精確 `pattern` error（標準 date-time format 合法、但本契約要求 UTC `Z`）。
- Ruby AST gate 鎖定相同 0–9 位 fractional UTC pattern，並鎖定新增 negative case 名稱；Ruby imperative validator 以 `Time.iso8601` 驗證同一正負 timestamp 語意。

## GREEN Evidence

- `uv run --with jsonschema==4.25.1 --with referencing --with rfc3339-validator==0.1.4 python scripts/validate_std_schema_engine.py`：PASS
  - `STD01 coverage: json_schema_tested=12 json_schema_passed=12 ruby_semantic_excluded=11`
  - `STD02 coverage: json_schema_tested=16 json_schema_passed=16 ruby_semantic_excluded=10`
  - `STD03 coverage: json_schema_tested=9 json_schema_passed=9 ruby_semantic_excluded=11`
- `ruby scripts/validate_std00_contract.rb`：PASS
- `ruby scripts/validate_std01_raw_evidence_contract.rb`：PASS
- `ruby scripts/validate_std02_source_anchor_contract.rb`：PASS
- `ruby scripts/validate_std03_normalized_document_contract.rb`：PASS
- `uv run --with jsonschema==4.25.1 --with referencing --with rfc3339-validator==0.1.4 python scripts/validate_cc_cross_layer_contract.py`：PASS（`negative cases rejected: 8`）
- `ruby scripts/validate_personal_memory_contract.rb`：PASS
- JSON/YAML parse：PASS（18 JSON、2 YAML）
- `git diff --check`：PASS

## Regression Probes

下列 probes 如預期回傳 exit 1，外層 assertion 因而通過：

- `--probe-unrelated-json-schema`：`STD01_JSON_SCHEMA_ERROR_PAIRS_MISMATCH:...:extra`
- `--probe-structural-relabel`：`STD01_RUBY_SEMANTIC_SCHEMA_REJECTED:missing-raw-digest:0`
- `--probe-duplicate-json`：`DUPLICATE_JSON_KEY:inline duplicate-key JSON:schema_version`

## Remaining Risk

- 本修補以 pinned `rfc3339-validator` 驗證標準 JSON Schema `date-time`，並由 explicit UTC `Z` pattern 收緊 `resolved_at`；未加入第二套 timestamp parser。後續只需針對 `SH-RV-001` 與其 regression 定點複審。
