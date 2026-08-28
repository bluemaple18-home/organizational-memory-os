# 研究包 A｜Raw Evidence 身分、時間序、Digest 與溯源

日期：2026-08-28

狀態：`RESEARCH_COMPLETE / DRAFT_INPUT / NOT_CANONICAL / NO_IMPLEMENTATION_AUTHORIZATION`

對應主線：

```text
STD-00 Schema Vocabulary Freeze
STD-01 RawEvidenceEnvelope JSON Schema
Raw Evidence Contract
```

本研究包只回答一個問題：

> 一筆來源資料或來源事件進入 Organizational Memory OS 時，哪些欄位可直接借成熟標準，哪些 identity／version／authority 必須由 OMOS 自己定義？

---

## 1. 結論

正式採用方向：

```text
CloudEvents
= optional transport / delivery envelope

OpenLineage
= extraction / transformation activity lineage

W3C PROV
= provenance relation vocabulary

UUIDv7
= OMOS-generated opaque identifier

RFC 8785 JCS
= structured JSON canonical digest option

OMOS RawEvidenceEnvelope
= Evidence identity / source identity / version / ACL / retention authority
```

核心 invariant：

```text
Transport Event ID
!= Source-native Entity ID
!= Source Version
!= Evidence ID
!= Payload Digest
```

任何兩個欄位即使剛好值相同，也不得因此合併語意。

---

## 2. Exact sources / pins

### 2.1 CloudEvents

```text
Repository: cloudevents/spec
Release: ce@v1.0.2
Commit: fc1f6f31f5f011a72183f1bcea20c987cb683ade
Specification: cloudevents/spec.md
License: Apache-2.0 / CNCF specification terms（正式採用時再封 notices）
```

Primary sources：

- https://github.com/cloudevents/spec/releases/tag/ce%40v1.0.2
- https://github.com/cloudevents/spec/blob/fc1f6f31f5f011a72183f1bcea20c987cb683ade/cloudevents/spec.md

CloudEvents required context attributes：

```text
id
source
specversion
type
```

Optional attributes：

```text
datacontenttype
dataschema
subject
time
extension attributes
```

### 2.2 OpenLineage

```text
Repository: OpenLineage/OpenLineage
Release: 1.52.0
Commit: cfd47d6f3e1b13167136b2508768c94a2351af23
Schema ID: https://openlineage.io/spec/2-0-2/OpenLineage.json
License: Apache-2.0
```

Primary sources：

- https://github.com/OpenLineage/OpenLineage/releases/tag/1.52.0
- https://github.com/OpenLineage/OpenLineage/blob/cfd47d6f3e1b13167136b2508768c94a2351af23/spec/OpenLineage.json

### 2.3 W3C PROV

```text
Specification family: W3C PROV
Status: W3C Recommendation
```

Primary sources：

- https://www.w3.org/TR/prov-dm/
- https://www.w3.org/TR/prov-o/

### 2.4 UUID

```text
Specification: RFC 9562
Chosen profile: UUIDv7
```

Primary source：

- https://www.rfc-editor.org/rfc/rfc9562.html

### 2.5 Canonical JSON digest

```text
Specification: RFC 8785
Name: JSON Canonicalization Scheme（JCS）
```

Primary source：

- https://www.rfc-editor.org/rfc/rfc8785.html

---

## 3. Identity layers

### 3.1 `evidence_id`

用途：OMOS 內部不可變 Evidence record identity。

建議：

```text
UUIDv7
serialized as urn:uuid:<uuid>
```

理由：

- 不需依賴來源系統產生全域 ID。
- 可按建立時間大致排序。
- 不把 tenant、來源或敏感資料編碼進 ID。
- 可安全區分「同一來源物件的不同 Evidence observation」。

禁止：

- 由檔名、Jira key或 URL直接當 `evidence_id`。
- 以 payload hash直接當 `evidence_id`。
- 因兩筆 Evidence payload相同就合併 Evidence identity。

### 3.2 Stable source-native identity

一個來源實體的穩定身分應為 structured tuple：

```yaml
source_identity:
  source_system: jira-cloud
  source_instance_id: <cloudId>
  entity_type: issue
  native_id: "10042"
  parent_native_id: null
```

正式 unique tuple：

```text
tenant_id
+ source_system
+ source_instance_id
+ entity_type
+ native_id
```

`native_id` 優先使用來源的 immutable／stable ID。

例如：

```text
Jira Cloud issue numeric id   > issue key
Git blob SHA                  > branch path only
Slack message ts/native id    > rendered permalink only
Email Message-ID/native id    > subject
```

Mutable key／URL／human name應放在 alias：

```yaml
source_aliases:
  - kind: MUTABLE_KEY
    value: PROJ-123
  - kind: URL
    value: https://example.atlassian.net/browse/PROJ-123
```

### 3.3 Source event identity

來源事件與來源實體要分開。

```yaml
source_event:
  source_event_id: <native event id if available>
  event_type: issue_updated
  delivery_id: <transport delivery id>
```

同一事件重送：

```text
source event identity相同
transport delivery identity可不同
```

來源沒有 event ID 時，可建立 deterministic event idempotency key，但不能假裝成來源 authoritative event ID。

### 3.4 Transport identity

CloudEvents `source + id` 可以用來判斷同一 producer 的重送事件，但只在 transport envelope scope內有效。

正式 mapping：

| CloudEvents | OMOS |
|---|---|
| `specversion` | `transport_envelope.spec_version` |
| `id` | `transport_envelope.event_id` |
| `source` | `transport_envelope.source` |
| `type` | `transport_envelope.event_type` |
| `subject` | `transport_envelope.subject`；可輔助定位 native subject |
| `time` | `transport_envelope.occurred_at_claim` |
| `datacontenttype` | `transport_envelope.data_media_type` |
| `dataschema` | `transport_envelope.data_schema_uri` |

CloudEvents欄位不得直接取得：

```text
Evidence identity authority
Source version authority
ACL authority
Retention authority
Deletion truth
Canonical Knowledge authority
```

---

## 4. Source version contract

不同來源沒有一個通用 revision欄位，因此 v0.1 不應強迫所有來源只填一個字串。

建議 schema：

```yaml
source_version:
  basis: AUTHORITATIVE_NATIVE
  kind: ETAG
  value: '"abc123"'
  observed_at: 2026-08-28T10:00:00Z
  secondary_digest: null
```

### 4.1 `basis`

```text
AUTHORITATIVE_NATIVE
COMPOUND_OBSERVED
CONTENT_ONLY
UNKNOWN
```

### 4.2 `kind`

```text
REVISION
ETAG
COMMIT
SEQUENCE
CHANGE_ID
UPDATED_AT_DIGEST
CONTENT_DIGEST
NONE
```

### 4.3 Version rules

1. 有 authoritative native revision時優先保存。
2. 沒有 authoritative revision時，用 compound observed version：

```text
updated_at
+ canonical payload digest
+ optional max changelog/cursor identity
```

3. `CONTENT_DIGEST` 只能證明 payload相同或不同，不能完整代表來源 lifecycle revision。
4. `updated_at` 單獨使用可能碰到相同時間戳、來源精度不足或未隨所有欄位變更。
5. `source_version` 必須保存採用基礎，讓 reviewer知道它是 native還是 synthetic。

---

## 5. Chronology contract

一筆 Evidence至少分四個時間：

```yaml
chronology:
  occurred_at: 2026-08-28T09:59:50Z
  occurred_at_basis: SOURCE
  observed_at: 2026-08-28T10:00:01Z
  received_at: 2026-08-28T10:00:02Z
  persisted_at: 2026-08-28T10:00:03Z
```

### 5.1 Semantics

| Field | 意義 |
|---|---|
| `occurred_at` | 來源世界事件實際發生時間；未知時可為 null |
| `occurred_at_basis` | `SOURCE / PRODUCER_ASSIGNED / OBSERVED / UNKNOWN` |
| `observed_at` | Adapter第一次看見來源狀態的時間 |
| `received_at` | OMOS ingestion endpoint收到資料的時間 |
| `persisted_at` | RawEvidence durable write完成時間 |

### 5.2 Rules

- 不可用 `persisted_at` 回填成 `occurred_at` 而不標 basis。
- 後補 Evidence只能建立新 observation／revision；不得改寫舊 AnswerTrace，假裝回答當時已看過。
- 來源時鐘與 OMOS時鐘可不同，必要時另保存 clock/skew warning。
- 所有 normative timestamp採 RFC 3339 UTC；來源原始 timestamp可放 adapter metadata。

---

## 6. Payload digest contract

### 6.1 必須區分三種 digest

```yaml
payload:
  raw_digest:
    algorithm: sha-256
    value: ...
    scope: RAW_SOURCE_BYTES
    canonicalization: NONE
  canonical_digest:
    algorithm: sha-256
    value: ...
    scope: STRUCTURED_PAYLOAD
    canonicalization: RFC8785_JCS
  normalized_digest: null
```

### 6.2 Semantics

#### `raw_digest`

對來源取得的實際 byte sequence做 SHA-256。

適用：

- PDF／DOCX原始檔
- webhook body raw bytes
- downloaded attachment
- API response snapshot bytes

#### `canonical_digest`

對 JSON等結構化 payload以指定 canonicalization後做 digest。

JCS適用條件：

- JSON符合 I-JSON限制。
- producer與consumer使用相同數字／字串語意。
- 明確保留 canonicalization版本。

#### `normalized_digest`

對 parser輸出的 NormalizedDocument／block representation做 digest。

正式 invariant：

```text
normalized_digest
不得取代
raw_digest
```

### 6.3 Digest declaration

任何 digest必須攜帶：

```text
algorithm
value
scope
canonicalization
media_type / representation_ref
```

禁止只有一個模糊的 `hash` 欄位。

---

## 7. Provenance mapping

W3C PROV只作 vocabulary mapping。

### 7.1 Core mapping

| OMOS | PROV vocabulary |
|---|---|
| Raw source payload / snapshot | `prov:Entity` |
| Ingestion / parse / normalize / distill | `prov:Activity` |
| Human / service / model / adapter | `prov:Agent` |
| Activity讀取 Entity | `prov:used` |
| Entity由 Activity產生 | `prov:wasGeneratedBy` |
| Derived entity | `prov:wasDerivedFrom` |
| Activity由 Agent執行／關聯 | `prov:wasAssociatedWith` |
| Entity責任歸屬 | `prov:wasAttributedTo` |

### 7.2 `wasRevisionOf`

只在以下成立時使用：

> 新 Entity確實是保留舊 Entity substantial content的修訂版本。

不能因為「後來取得」或「時間較晚」就自動標成 revision。

### 7.3 `specializationOf`

適合表示：

```text
stable source entity
← 某一時間／版本／scope的具體 snapshot
```

例如：

```text
Jira Issue stable entity
├─ snapshot at revision A
└─ snapshot at revision B
```

### 7.4 `alternateOf`

只表示同一事物的 alternate aspects／representations，不等於 revision或 duplicate。

### 7.5 Hard stop

不要求 v0.1 使用 RDF store。PROV relation可先以 controlled enum和 URI reference保存，再提供 JSON-LD projection。

---

## 8. OpenLineage mapping

OpenLineage適合 parser／transform receipt，不適合 RawEvidence envelope。

### 8.1 Mapping

```text
OpenLineage Run
→ Extraction / Transformation Activity

OpenLineage Job
→ Adapter / Parser Route Definition

Input Dataset
→ RawEvidence payload/version

Output Dataset
→ NormalizedDocument / Asset / Projection output

Facet
→ parser config / quality / schema / environment / statistics
```

### 8.2 Proposed receipt fields

```yaml
lineage:
  run_id: <uuid>
  job:
    namespace: omos.document-adapter
    name: docling-technical-pdf
  inputs:
    - evidence_ref: urn:omos:evidence:...
      content_digest: ...
  outputs:
    - normalized_document_ref: urn:omos:normalized-document:...
      content_digest: ...
  event_state: COMPLETE
  producer: git+https://...@<commit>
  schema_uri: https://schemas.example/omos/extraction-receipt/v0.1
```

### 8.3 Do not absorb

- 不把 OpenLineage Dataset namespace/name當 OMOS source identity。
- 不把 OpenLineage Run status當 Verification status。
- 不讓 facet deletion semantics成為 Knowledge deletion semantics。
- 不要求所有 ingestion event都轉成 OpenLineage event。

---

## 9. Proposed `RawEvidenceEnvelope v0.1` amendment

```json
{
  "schema_version": "omos.evidence.v0.1",
  "evidence_id": "urn:uuid:019...",
  "tenant_id": "tenant-example",
  "source_identity": {
    "source_system": "jira-cloud",
    "source_instance_id": "cloud-id",
    "entity_type": "issue",
    "native_id": "10042",
    "parent_native_id": null,
    "aliases": [
      {"kind": "MUTABLE_KEY", "value": "PROJ-123"}
    ]
  },
  "source_event": {
    "source_event_id": null,
    "event_type": "issue_updated",
    "delivery_id": "delivery-uuid"
  },
  "source_version": {
    "basis": "COMPOUND_OBSERVED",
    "kind": "UPDATED_AT_DIGEST",
    "value": "2026-08-28T09:59:50Z",
    "secondary_digest": "sha256:..."
  },
  "chronology": {
    "occurred_at": "2026-08-28T09:59:50Z",
    "occurred_at_basis": "SOURCE",
    "observed_at": "2026-08-28T10:00:01Z",
    "received_at": "2026-08-28T10:00:02Z",
    "persisted_at": "2026-08-28T10:00:03Z"
  },
  "payload": {
    "media_type": "application/json",
    "payload_ref": "object://evidence/...",
    "size_bytes": 1234,
    "raw_digest": {
      "algorithm": "sha-256",
      "value": "...",
      "scope": "RAW_SOURCE_BYTES",
      "canonicalization": "NONE"
    },
    "canonical_digest": {
      "algorithm": "sha-256",
      "value": "...",
      "scope": "STRUCTURED_PAYLOAD",
      "canonicalization": "RFC8785_JCS"
    },
    "retention_tier": "T1"
  },
  "access": {
    "acl_snapshot_ref": "acl-snapshot://...",
    "source_permission_version": null,
    "visibility_scope_refs": []
  },
  "transport_envelope": {
    "profile": "CLOUDEVENTS_1_0",
    "event_id": "...",
    "source": "...",
    "event_type": "com.atlassian.jira.issue.updated.v1",
    "subject": "issue/10042",
    "time": "2026-08-28T09:59:50Z"
  },
  "provenance": {
    "adapter_id": "jira-cloud-adapter",
    "adapter_version": "0.1.0",
    "ingestion_mode": "WEBHOOK",
    "ingestion_activity_ref": "activity://...",
    "lineage_receipt_ref": "receipt://..."
  },
  "state": {
    "availability": "AVAILABLE",
    "deletion_state": "ACTIVE",
    "legal_hold": false
  }
}
```

---

## 10. Availability / deletion distinction

`404`、missing payload、permission denied與source deletion不能壓成一個 state。

建議分開：

```text
availability:
  AVAILABLE
  TEMPORARILY_UNAVAILABLE
  UNAVAILABLE_UNKNOWN
  ACCESS_DENIED
  NOT_FOUND_UNCONFIRMED

lifecycle deletion_state:
  ACTIVE
  SOURCE_DELETED
  ACCESS_REVOKED
  RETENTION_EXPIRED
  LEGAL_HOLD
  TOMBSTONED
  PURGED
```

只有 deletion webhook、authoritative deletion audit、reconciliation證據或人工 authority，才可將 `SOURCE_DELETED` 視為確認狀態。

---

## 11. Hard stops

禁止：

- CloudEvents `id` 直接當 `evidence_id`。
- CloudEvents `time` 無 basis地當 authoritative occurrence time。
- OpenLineage Run COMPLETE直接推導 Extraction quality PASS。
- 只留 canonical JSON digest，丟掉來源 raw bytes digest。
- 只靠 `updated_at` 判斷所有 source revision。
- 只靠 payload hash合併不同 tenant／source entity／event。
- 將 UUIDv7 timestamp視為 business event time。
- 將 PROV relation store升成 Canonical Knowledge store。

---

## 12. Open decisions

仍需在 `STD-00 / STD-01` 明示裁決：

1. `evidence_id` 是否統一 `urn:uuid:`，或 API 層另提供 bare UUID。
2. JCS不適用的 JSON（非 I-JSON數字／重複 key）如何 fail closed。
3. Webhook raw body是否與 parsed JSON snapshot都保存 digest。
4. `source_event_id` 缺失時的 deterministic idempotency formula。
5. tenant salt是否只用於 dedup privacy index，不用於 canonical digest。
6. source clock skew warning threshold。
7. payload purged後保留 raw digest／canonical digest／transport envelope多久。

---

## 13. Acceptance criteria

本研究包升入正式 schema前，至少通過：

1. 同一 CloudEvent重送兩次只建立一次 delivery processing，但不覆寫既有 Evidence。
2. 同一 Jira Issue兩次不同 payload產生兩筆 observation／revision Evidence，stable source identity相同。
3. 兩個不同 source entity即使 payload bytes相同，也不合併 Evidence identity。
4. raw bytes digest與JCS digest都有 deterministic fixture。
5. occurrence／observed／received／persisted四個時間不互相覆寫。
6. OpenLineage receipt能指向一個 input Evidence與一個 output NormalizedDocument。
7. `NOT_FOUND_UNCONFIRMED`不自動轉成 `SOURCE_DELETED`。
8. 所有 ID、version、digest、time欄位都有明確 semantic description與negative tests。

---

## 14. Backlog disposition

```text
MERGE INTO STD-00:
- UUIDv7 ID convention
- chronology vocabulary
- digest vocabulary
- source_version union

MERGE INTO STD-01:
- RawEvidenceEnvelope field-level schema
- optional CloudEvents transport profile
- extraction lineage receipt reference

DO NOT CREATE:
- CloudEvents canonical event store
- OpenLineage canonical DB
- PROV RDF requirement for MVP
```
