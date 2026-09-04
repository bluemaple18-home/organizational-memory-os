# CC Schema Foundation｜契約與鎖版裁決 v0.1

狀態：`LOCKED_OWNER_ACCEPTED_20260904`

## Normative authority

`STD-01 RawEvidenceEnvelope` 與 `STD-02 SourceAnchor` 的 field-level
normative authority 是 JSON Schema Draft 2020-12。標準 engine 必須以
`scripts/validate_std_schema_engine.py` 實際解析 URN registry 後驗證正向
fixture，並逐一驗證、拒絕每一個 `JSON_SCHEMA` negative case；任一 case
未被拒絕或缺少可驗證 instance 即 fail-closed。Ruby validators 不得取代此
gate。

Ruby deterministic validators 的唯一補充責任是 JSON Schema 不適合表達的
跨事件／跨資源 invariant、完整 base 的單一 mutation isolation，以及
fixture status／coverage contract。每個 negative 必須明示
`validation_authority` 與 `expected_result: REJECT`；standard engine 對每個
`JSON_SCHEMA` case fail-closed，並逐族輸出 coverage。每個 `RUBY_SEMANTIC`
case 必須明示 `schema_expected_result: ALLOW`，且先由同一 Draft 2020-12
engine 實際接受；任一被 schema 拒絕即 fail-closed。只有完成此 schema
前置閘門後，case 才不計入 schema rejection coverage 並交由 Ruby semantic
validator 拒絕。Ruby 的欄位檢查僅是從 schema 導出的 defensive mirror，非
欄位 normative authority。

## STD Lock DoD

| 標準 | 現在狀態 | Lock DoD |
|---|---|---|
| `STD-00` | `LOCKED` | versioned vocabulary、正負 fixture、`validate_std00_contract.rb` 與 lock evidence 一致。 |
| `STD-01` | `LOCKED_OWNER_ACCEPTED_20260904` | Draft 2020-12 schema、正負完整 envelope、standard engine、跨事件 Ruby invariant、evidence 與 backlog token 一致。 |
| `STD-02` | `LOCKED_OWNER_ACCEPTED_20260904` | common/profile Draft 2020-12 schemas、三 profile正負 fixture、URN registry engine、跨資源 Ruby invariant、evidence 與 backlog token 一致。 |

`STD-03` 沒有被本裁決啟動；其真實前置 `STD-01` 已滿足，狀態為
`UNBLOCKED_NOT_STARTED_BY_STD_01_LOCK`，仍需要獨立 scope 決策。

## Claim → enforcement matrix

| Spec claim | Exact artifact | Enforcement gate |
|---|---|---|
| STD-00 vocabulary frozen | `規格/v0.1/common-vocabulary.yaml` | `ruby scripts/validate_std00_contract.rb` |
| RawEvidence field contract | `規格/v0.1/raw-evidence-envelope.schema.json` | `UV_CACHE_DIR=/tmp/cc-schema-foundation-uv uv run --script scripts/validate_std_schema_engine.py` |
| SourceAnchor common/profile contract | `規格/v0.1/source-anchor*.schema.json` | 同一 standard engine gate（含 URN registry） |
| STD-01 semantic／cross-event rules | `scripts/validate_std01_raw_evidence_contract.rb` | `ruby scripts/validate_std01_raw_evidence_contract.rb` |
| STD-02 cross-resource／fixture isolation | `scripts/validate_std02_source_anchor_contract.rb` | `ruby scripts/validate_std02_source_anchor_contract.rb` |
| Candidate→Support→Anchor→RawEvidence binding | `規格/v0.1/fixtures/cc-schema-foundation-cross-layer-fixtures.json` | `UV_CACHE_DIR=/tmp/cc-schema-foundation-uv uv run --script scripts/validate_cc_cross_layer_contract.py` |
| Personal memory resource constraints | `規格/v0.1/personal-harness-integration.yaml` | `ruby scripts/validate_personal_memory_contract.rb` |
| Review snapshot integrity | fixed commit、allowlist、commit SHA/blob digest | Mainline commit 後填入 handoff，不得預填或偽造。 |

## Review handoff template

```text
review_commit_sha: <MAINLINE_TO_FILL_AFTER_COMMIT>
allowlisted_paths: <MAINLINE_TO_FILL_AFTER_COMMIT>
commit_blob_digests: <MAINLINE_TO_FILL_AFTER_COMMIT>
engine_gate_receipt: .work/evidence/CC-SCHEMA-FOUNDATION-PREP-20260904.md
external_reviewer_mode: read-only immutable snapshot; structured stdout only
working_tree_mutation: forbidden
canonical_direct_write_audit: pending, excluded from this review
```

此卡不實作 `STD-03`、runtime、Connector、DB、Hook、Loop、Harness 或 Hermes。
