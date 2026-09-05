# CC Schema Foundation P1 Repair 01 Evidence

- Branch: `codex/schema-foundation-cc-repair-01`
- Base / HEAD: `d0824e5a4dc02e8f77211ba1e790698a829e2a44`
- Scope: only `CC-SF-001` / `CC-SF-002` / `CC-SF-003`
- Commit / push: not performed

## Source Decision Evidence

- CodeGraph query: `CC-SF-001 CC-SF-002 CC-SF-003 validate_envelope RawEvidence schema conditional validate_raw_negatives JSON_SCHEMA RUBY_SEMANTIC scripts/validate_std_schema_engine.py scripts/validate_std01_raw_evidence_contract.rb 規格/v0.1/raw-evidence-envelope.schema.json 規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json`
- Located blast radius:
  - `scripts/validate_std_schema_engine.py`: `validate_raw_negatives`
  - `scripts/validate_std01_raw_evidence_contract.rb`: `validate_envelope`, `validate_negative_fixtures`
  - `規格/v0.1/raw-evidence-envelope.schema.json`: source event and canonicalization root conditionals
  - `規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json`: STD-01 negative fixtures

## RED Evidence

Before patch, current schema / Ruby validator allowed the two target counterexamples:

```text
uv run --with jsonschema --with referencing python -c '<CC-SF-001 native_event_id empty schema probe>'
CC-SF-001 schema errors 0
[]

uv run --with jsonschema --with referencing python -c '<CC-SF-002 NON_I_JSON no gap schema probe>'
CC-SF-002 schema errors 0
[]

ruby -rjson -ryaml -e '<CC-SF-001 native_event_id empty Ruby probe>'
CC-SF-001 ruby failures 0
```

Before patch, `NEG-011` schema rejection was unrelated to the actual NON_I_JSON gap invariant:

```text
uv run --with jsonschema --with referencing python -c '<NEG-011 schema error path probe>'
NEG-011 schema error paths ['payload.structured_profile']
NEG-011 schema messages ["'I_JSON' was expected"]
```

## Changes

- `規格/v0.1/raw-evidence-envelope.schema.json`
  - Added `minLength: 1` to `source_event.native_event_id` string values.
  - Added a `NON_I_JSON` conditional requiring `digests.canonical_digest = null` and a `quality_gaps` item whose `code` is `CANONICALIZATION_UNAVAILABLE`.
- `scripts/validate_std01_raw_evidence_contract.rb`
  - Mirrored native event identity branching with `present?`, not only `.nil?`.
  - Added schema document assertions for non-empty native event ids and NON_I_JSON gap semantics.
  - Enforced declared `expected_failure_codes` for JSON_SCHEMA fixtures too, so Ruby mirror regressions cannot hide behind schema authority.
- `scripts/validate_std_schema_engine.py`
  - Added fail-closed `expected_schema_errors` support for STD-01 JSON_SCHEMA negative cases.
  - Dedicated schema cases now require non-empty `{path, validator}` metadata and fail if rejection happens only through an unrelated error pair.
- `規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json`
  - Added `NEG-006A source-event-empty-native-event-id-native-identity`.
  - Added `NEG-011A non-i-json-without-canonicalization-gap`.
  - Added executable `expected_schema_errors` target pairs to all 12 STD-01 JSON_SCHEMA cases.

## GREEN Evidence

Targeted invariant probes:

```text
uv run --with jsonschema --with referencing python -c '<target fixture schema paths probe>'
{
  'source-event-empty-native-event-id-native-identity': ['source_event.native_event_id'],
  'non-i-json-canonical-digest-claimed': ['digests.canonical_digest', 'payload.structured_profile', 'quality_gaps'],
  'non-i-json-without-canonicalization-gap': ['quality_gaps']
}

ruby -rjson -ryaml -e '<target fixture Ruby failure codes probe>'
source-event-empty-native-event-id-native-identity: SOURCE_EVENT_FALLBACK,SOURCE_EVENT_FALLBACK_BASIS,SOURCE_EVENT_FALLBACK_GAP
non-i-json-without-canonicalization-gap: NON_I_JSON_GAP
```

Targeted mutation probes:

```text
uv run --with jsonschema --with referencing python -c '<remove native_event_id minLength in memory>'
native minLength removed paths []
probe FAIL_EXPECTED

uv run --with jsonschema --with referencing python -c '<remove NON_I_JSON allOf branch in memory>'
NON_I_JSON branch removed paths []
probe FAIL_EXPECTED

uv run --with jsonschema --with referencing python scripts/validate_std_schema_engine.py --probe-structural-relabel
STD schema engine validator FAIL
FAIL STD01_RUBY_SEMANTIC_SCHEMA_REJECTED:missing-raw-digest:0
```

Standard gates:

```text
uv run --with jsonschema --with referencing python scripts/validate_std_schema_engine.py
STD schema engine validator PASS
STD01 JSON_SCHEMA coverage: 12/12
STD01 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 11
STD02 JSON_SCHEMA coverage: 12/12
STD02 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 10

ruby scripts/validate_std00_contract.rb
STD-00 validator PASS

ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator PASS

ruby scripts/validate_std02_source_anchor_contract.rb
STD-02 SourceAnchor validator PASS

uv run python scripts/validate_cc_cross_layer_contract.py
CC cross-layer validator PASS
resolved registry: STD01 RawEvidence + STD02 SourceAnchor
negative cases rejected: 8

ruby scripts/validate_personal_memory_contract.rb
PASS personal memory contract validation

ruby -rjson -ryaml -e 'Dir.glob("規格/v0.1/**/*.json").each { |path| JSON.parse(File.read(path)) }; Dir.glob("規格/v0.1/**/*.yaml").each { |path| YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) }; puts "JSON/YAML parse PASS"'
JSON/YAML parse PASS

git diff --check
PASS
```

## Changed Blobs

- `scripts/validate_std_schema_engine.py`: `da15ce7fe3d2d36b0cbac6225b6891f970c4d6da`
- `scripts/validate_std01_raw_evidence_contract.rb`: `63d0810bae1562b0b025e3579b396c7cfde90791`
- `規格/v0.1/raw-evidence-envelope.schema.json`: `aea6b3228a5104f520386a378de9f12319c912bf`
- `規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json`: `0c5e31d9a9c433cec7782248ce1dd33f34e7dab9`

## Repair-02 Evidence

Mainline returned Repair-01 because `CC-SF-003` still allowed 9/12 STD-01 JSON_SCHEMA cases to pass through arbitrary unrelated schema errors, and the engine treated missing metadata as an optional empty list. Repair-02 makes STD-01 JSON_SCHEMA metadata fail-closed.

Fail-closed RED after engine change and before fixture metadata backfill:

```text
uv run --with jsonschema --with referencing python scripts/validate_std_schema_engine.py
STD schema engine validator FAIL
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:source-event-without-native-event-id-missing-fallback
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:source-event-empty-native-event-id-native-identity
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:non-i-json-canonical-digest-claimed
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:non-i-json-without-canonicalization-gap
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:missing-raw-digest
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:missing-acl-snapshot
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:missing-provenance
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:entity-snapshot-idempotency-missing-source-version
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:source-event-idempotency-missing-native-event-id
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:canonicalization-none-with-canonical-digest
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:jcs-with-non-i-json-profile
FAIL STD01_JSON_SCHEMA_EXPECTED_ERRORS:unknown-quality-gap-code
```

12/12 STD-01 JSON_SCHEMA metadata after backfill:

```text
jq -r '.cases[] | select(.validation_authority=="JSON_SCHEMA") | [.id,.name,((.expected_schema_errors // []) | map(.path+":"+.validator) | join(";"))] | @tsv' 規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json
NEG-006	source-event-without-native-event-id-missing-fallback	/source_event/idempotency_basis/includes:contains;/source_event/identity_basis:const
NEG-006A	source-event-empty-native-event-id-native-identity	/source_event/native_event_id:minLength
NEG-011	non-i-json-canonical-digest-claimed	/digests/canonical_digest:type;/payload/structured_profile:const;/quality_gaps:contains
NEG-011A	non-i-json-without-canonicalization-gap	/quality_gaps:contains
NEG-012	missing-raw-digest	/digests/raw_digest:type
NEG-013	missing-acl-snapshot	/access/acl_snapshot_ref:type
NEG-014	missing-provenance	/provenance/adapter_id:type
NEG-016	entity-snapshot-idempotency-missing-source-version	/idempotency_basis/includes:contains
NEG-017	source-event-idempotency-missing-native-event-id	/source_event/idempotency_basis/includes:contains
NEG-018	canonicalization-none-with-canonical-digest	/digests/canonical_digest:type
NEG-019	jcs-with-non-i-json-profile	/payload/structured_profile:const
NEG-020	unknown-quality-gap-code	/quality_gaps/0/code:enum
```

Unrelated rejection mutation probe:

```text
uv run --with jsonschema --with referencing python scripts/validate_std_schema_engine.py --probe-unrelated-json-schema
STD schema engine validator FAIL
FAIL STD01_JSON_SCHEMA_UNRELATED_REJECTION:non-i-json-without-canonicalization-gap:/quality_gaps:contains
```

Repair-02 GREEN gates:

```text
uv run --with jsonschema --with referencing python scripts/validate_std_schema_engine.py
STD schema engine validator PASS
STD01 JSON_SCHEMA coverage: 12/12
STD01 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 11
STD02 JSON_SCHEMA coverage: 12/12
STD02 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 10

ruby scripts/validate_std00_contract.rb
STD-00 validator PASS

ruby scripts/validate_std01_raw_evidence_contract.rb
STD-01 RawEvidenceEnvelope validator PASS

ruby scripts/validate_std02_source_anchor_contract.rb
STD-02 SourceAnchor validator PASS

uv run python scripts/validate_cc_cross_layer_contract.py
CC cross-layer validator PASS
resolved registry: STD01 RawEvidence + STD02 SourceAnchor
negative cases rejected: 8

ruby scripts/validate_personal_memory_contract.rb
PASS personal memory contract validation

ruby -rjson -ryaml -e 'Dir.glob("規格/v0.1/**/*.json").each { |path| JSON.parse(File.read(path)) }; Dir.glob("規格/v0.1/**/*.yaml").each { |path| YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) }; puts "JSON/YAML parse PASS"'
JSON/YAML parse PASS

git diff --check
PASS
```

## Residual Risk

- `uv run python scripts/validate_std_schema_engine.py` without `--with jsonschema --with referencing` still fails in this checkout because no `.venv` is present and `jsonschema` is not installed by default. The reproducible verification command used here is `uv run --with jsonschema --with referencing python scripts/validate_std_schema_engine.py`.
- No independent reviewer was spawned or `create_thread` task created in this worker turn; no commit was made.

## Mainline internal targeted review

- Fixed base：`d0824e5a4dc02e8f77211ba1e790698a829e2a44`。
- Verdict：`GO`；P0／P1／P2／P3 = `0／0／0／0`。
- `CC-SF-001`：empty `native_event_id` 的 schema `minLength` 與 Ruby `present?` 雙層關閉。
- `CC-SF-002`：`NON_I_JSON` 無 `CANONICALIZATION_UNAVAILABLE` gap 的 schema `contains` 與 Ruby mirror 雙層關閉。
- `CC-SF-003`：12／12 JSON_SCHEMA cases 必須具 non-empty `(absolute path, validator keyword)` parity metadata；無關 rejection probe 預期 `exit 1`。
- Scope 複驗：未改 STD-03、P3 findings 或 STD-02 contract；無關 untracked files 不納入 commit。
