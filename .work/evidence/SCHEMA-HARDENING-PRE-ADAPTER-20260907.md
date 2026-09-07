# Schema Hardening Pre-Adapter Evidence

Status: READY_FOR_REVIEW

## Scope

- HARDEN-S01 Gate integrity completed to Checkpoint A.
- HARDEN-S02 Cross-schema reference alignment completed after stop-condition check.
- No Adapter, EMEM-02, runtime, DB, Hook, Loop, Harness, Hermes, KM, SSP, or HTML changes.
- No commit, merge, push, GO, or LOCKED status.

## RED Evidence

- `uv run scripts/validate_std_schema_engine.py` turned RED after exact-pair enforcement and before fixture completion:
  - `STD02_JSON_SCHEMA_EXPECTED_ERRORS:*`
  - `STD02_JSON_SCHEMA_ERROR_PAIRS_MISMATCH:*`
  - `STD03_JSON_SCHEMA_ERROR_PAIRS_MISMATCH:root-empty-parser-receipt`
- Existing mutation probes still turn RED:
  - `uv run scripts/validate_std_schema_engine.py --probe-unrelated-json-schema`
  - `uv run scripts/validate_std_schema_engine.py --probe-structural-relabel`

## GREEN Evidence

- Standard engine now compares actual JSON Schema `(path, validator)` pairs exactly against declared pairs.
- Coverage output now reports actual counters:
  - `json_schema_tested`
  - `json_schema_passed`
  - `ruby_semantic_excluded`
- STD-03 added schema negatives:
  - `table-empty-attributes`
  - `image-empty-attributes`
- STD-03 Ruby schema document gate now locks conditional AST for:
  - table blocks requiring `attributes.table`
  - image blocks requiring `attributes.asset`
  - non table/image Phase-1 blocks requiring empty attributes
- STD-01 Ruby gate now explicitly checks NON_I_JSON defensive mirror execution.
- Cross-layer validator now locks the exact 8 negative case names and count.
- JSON/YAML loaders in existing validators now reject duplicate object/mapping keys fail-closed.

## HARDEN-S02 Stop Condition

Checked existing positive identities before S02:

- STD-01 positive `evidence_ref` values are UUIDv7 URNs.
- STD-01 positive `access.acl_snapshot_ref` values are UUIDv7 URNs.
- STD-02 positive `anchor_ref`, `evidence_ref`, `access.acl_snapshot_ref` values are UUIDv7 URNs.
- STD-02 positive `resolution.resolved_at` values use UTC `Z`.

No source authority, profile, selector, or legal fixture identity change was required.

## HARDEN-S02 Changes

- `source-anchor.schema.json`
  - `evidence_ref` pattern aligned to STD-01 UUIDv7 evidence URN.
  - `access.acl_snapshot_ref` pattern aligned to STD-01 UUIDv7 ACL snapshot URN.
  - `resolution.resolved_at` keeps `format: date-time` and adds UTC `Z` pattern.
- STD-02 negatives added:
  - `source-evidence-ref-uuidv4`
  - `acl-snapshot-ref-wide-uuid`
  - `resolution-non-utc-offset`

## Final Gate Receipt

- `ruby scripts/validate_std00_contract.rb`：PASS
- `ruby scripts/validate_std01_raw_evidence_contract.rb`：PASS
- `ruby scripts/validate_std02_source_anchor_contract.rb`：PASS
- `ruby scripts/validate_std03_normalized_document_contract.rb`：PASS
- `uv run scripts/validate_std_schema_engine.py`：PASS
  - `STD01 coverage: json_schema_tested=12 json_schema_passed=12 ruby_semantic_excluded=11`
  - `STD02 coverage: json_schema_tested=15 json_schema_passed=15 ruby_semantic_excluded=10`
  - `STD03 coverage: json_schema_tested=9 json_schema_passed=9 ruby_semantic_excluded=11`
- `uv run scripts/validate_cc_cross_layer_contract.py`：PASS
  - `negative cases rejected: 8`
- `ruby scripts/validate_personal_memory_contract.rb`：PASS
- `git diff --check`：PASS
