# STD-00｜Schema Vocabulary Freeze v0.1 提案

日期：2026-08-28

狀態：

```text
LOCKED
OWNER_ACCEPTED_2026_09_04
TECHNICAL_ACCEPTANCE_PASS
MERGES_CTX_00_VOCABULARY
DOES_NOT_CHANGE_CURRENT_FRONTIER
```

鎖版依據：Owner 於 2026-09-04 明確接受 `STD-00`；P2 SourceAnchor digest缺口已在同日補齊 Jira positive `representation_digest`、profile digest basis與負向 fixture，並以 deterministic validator驗證。

基準 Repo：

```text
bluemaple18-home/organizational-memory-os
Base HEAD: 2be575c3bea70b3a91f9d97d89ca0dc6f878efa8
```

本文件是交給 Codex 與架構審查者的 `STD-00 Schema Vocabulary Freeze` 提案。

它只鎖定：

- 名詞。
- contract family。
- resource/document kind。
- 共用 enum。
- ID、版本、時間、digest、range convention。
- Evidence／Document／Knowledge／Procedure／Object Context／Projection 邊界。
- PDF／Markdown／Jira Phase-1 fixture vocabulary。
- negative fixture 的預期語意。

它**不是**：

- production JSON Schema。
- database migration。
- parser implementation。
- Jira connector implementation。
- Knowledge Graph ontology。
- Skill compiler。
- Workflow Engine。
- Agent Runtime。
- Canonical architecture acceptance。

本提案已由使用者／指定 architecture authority接受並升為 `LOCKED`。本鎖版不授權 STD-01、Adapter、Connector、DB、Skill、Hook、Loop、Harness或Hermes施工。

---

## 0. Authority inputs

本提案不得脫離以下文件獨立解讀：

- `文件/架構憲章.md`
- `文件/最小核心重基準.md`
- `文件/核心知識主幹.md`
- `文件/知識庫標準文件規格-v0.1-草案.md`
- `文件/研究包A-RawEvidence身份時間序與溯源-20260828.md`
- `文件/研究包B-PDF-Markdown-Jira-SourceAnchor-20260828.md`
- `文件/研究包C-ObjectContext與WorkRecord-20260828.md`
- `文件/權限政策與設定治理.md`
- `文件/驗證治理.md`

最高層 invariant：

```text
Raw Evidence != Derived Interpretation != Knowledge
Candidate != Canonical
Permission-before-Retrieval
Required Verification != Actual Verification
EXECUTED != VERIFIED != ACCEPTED
Proposal != Canonical Write
Chunk / Embedding / Graph / Skill != Canonical Knowledge
WorkRecord != Source Truth
ObjectLink != Permission Expansion
```

---

## 1. Normative language

本文件中的語氣：

- `MUST / 必須`：conformance 所需，不得任意省略。
- `MUST NOT / 禁止`：違反即不符合規格。
- `SHOULD / 應`：除非有明確、可記錄的理由，否則應採用。
- `SHOULD NOT / 不應`：除非有明確、可記錄的理由，否則避免。
- `MAY / 可以`：optional extension。

任何 implementation convenience 不得反向改寫 authority boundary。

---

## 2. 本輪已做的核心裁決

### 2.1 不把所有東西都叫「文件」

正式分開：

```text
Contract Family
Resource Kind
Document Kind
Canonicality
Lifecycle
Availability
Retention
Verification
Acceptance
```

它們是不同維度。

例如：

```text
Object
= Resource Kind
!= Document Kind

WorkRecord
= Resource Kind + Projection
!= Canonical Knowledge

VerificationReceipt
= Resource Kind + Immutable Governance Record
!= Knowledge Document

REFERENCE_PACK
= Document Kind + Projection
!= Canonical Knowledge
```

### 2.2 `ARCHIVED` 不再放進 `canonicality`

舊草案把 `ARCHIVED` 與 `EVIDENCE / CANDIDATE / CANONICAL / PROJECTION` 放在同一 enum，混合了 authority 與 lifecycle。

本提案修正為：

```text
canonicality
= EVIDENCE / NORMALIZED / CANDIDATE / CANONICAL / PROJECTION

lifecycle_state
= ACTIVE / SUPERSEDED / ARCHIVED / INVALIDATED
```

### 2.3 Source availability、payload retention、lifecycle 分開

禁止用單一 `deletion_state` 同時表示：

- 來源被刪。
- 權限撤回。
- payload 到期。
- legal hold。
- Knowledge 被 supersede。

本提案拆成：

```text
source_availability
payload_retention_state
lifecycle_state
```

### 2.4 `Object` 是 durable reference identity，但不是 Knowledge

正式裁決：

```text
Object identity registry
= durable organizational reference authority

Object attributes derived from Evidence
= observation / candidate unless separately accepted

Object
!= Canonical Knowledge
!= WorkRecord
```

### 2.5 `ObjectLink` 使用輕量 `LinkDecisionReceipt`

ObjectLink 的接受／拒絕不套用完整 Knowledge `AcceptanceReceipt`。

正式採：

```text
ObjectLinkAssertion
→ LinkDecisionReceipt
→ durable accepted link
```

高風險 link 仍可要求 human authority，但其語意是「關聯裁決」，不是「知識正式採用」。

### 2.6 WorkRecord 只能 permission-aware render

若一個 WorkRecord 連到不同 ACL／Client scope 的 Evidence：

```text
不得保存一份 unrestricted global summary
不得使用 permission union
```

每次 render／retrieve 必須依 requester 的 authorized subset 產生。

---

# 3. Contract Family Registry

## 3.1 Common primitives

### `omos.core`

用途：

- ID。
- reference。
- timestamp。
- digest。
- range。
- language。
- media type。
- common enums。
- extension namespace。

`omos.core` 不擁有任何 Knowledge lifecycle。

## 3.2 Truth-bearing content families

| Family | 回答的問題 | Authority |
|---|---|---|
| `omos.evidence` | 原始世界當時提供了什麼？ | Evidence identity／chronology／payload／ACL／provenance |
| `omos.document` | Evidence 經 parser 後形成哪些可定位結構？ | Rebuildable normalized representation |
| `omos.knowledge` | 組織正式認可哪些 assertion／decision／policy？ | Candidate／Canonical Knowledge |
| `omos.procedure` | 在什麼條件下要怎麼做與如何驗證？ | Canonical Procedure semantics |

## 3.3 Adjacent Knowledge System families

| Family | 用途 | Authority |
|---|---|---|
| `omos.object-context` | Object、Alias、Relation、ObjectLink、WorkRecord | Object reference identity；WorkRecord 仍是 projection |
| `omos.governance` | Verification、Acceptance、Canonical Write、Link Decision 等 receipt | Governance decision evidence |

## 3.4 Derived family

### `omos.projection`

包含：

- RAG Chunk。
- Embedding／Vector／Search。
- Graph。
- FAQ／Role View。
- Reference Pack。
- Agent Skill。
- Reviewer／Impact View。
- Cache。

全部：

```text
rebuildable = true
canonical authority = false
```

## 3.5 Platform-control families

以下是重要 contract，但不是 Knowledge Document：

```text
omos.source-adapter
omos.authz
omos.retrieval-trace
omos.evaluation
omos.control-plane
```

它們不得被塞進 `document_kind`。

---

# 4. Document Kind Registry

`document_kind` v0.1 只允許：

```text
SOURCE_EVIDENCE
NORMALIZED_DOCUMENT
KNOWLEDGE
DECISION
POLICY
PROCEDURE
REFERENCE_PACK
EXECUTABLE_SKILL
```

## 4.1 `SOURCE_EVIDENCE`

代表一個來源實體版本或來源事件 observation 的 exchange package。

```text
canonicality = EVIDENCE
```

## 4.2 `NORMALIZED_DOCUMENT`

Parser 可重建的結構化文件。

```text
canonicality = NORMALIZED
```

## 4.3 `KNOWLEDGE`

一般 assertion collection 或 human-readable canonical knowledge view。

```text
canonicality = CANDIDATE or CANONICAL
```

## 4.4 `DECISION`

Time／scope／context-scoped decision。

必須保留：

- problem。
- alternatives。
- rationale。
- consequences。
- revisit trigger。
- Evidence links。

## 4.5 `POLICY`

帶 enforcement authority 的規則。

必須保留：

- owner。
- scope。
- rule。
- exception。
- approval authority。
- audit requirement。
- effective period。

## 4.6 `PROCEDURE`

Canonical「如何做」語意。

不等於已綁工具、已授權執行的 Skill。

## 4.7 `REFERENCE_PACK`

由 Canonical Knowledge／Procedure 編譯的只讀 knowledge package。

```text
canonicality MUST be PROJECTION
```

## 4.8 `EXECUTABLE_SKILL`

Procedure 加上 runtime binding、tool／capability reference 與 execution metadata 的 artifact。

```text
canonicality MUST NOT be CANONICAL
```

其 promotion 另經：

```text
Capability Admission
→ Install
→ Enable
→ Authorize
→ Execute
→ Observe
→ Deprecate
```

---

# 5. Resource Kind Registry

不是所有 resource 都要包成 Markdown 文件。

v0.1 common resource kinds：

```text
EVIDENCE_RECORD
NORMALIZED_DOCUMENT
DOCUMENT_BLOCK
SOURCE_ANCHOR
ASSERTION
EVIDENCE_LINK
DECISION_RECORD
POLICY_RECORD
PROCEDURE_RECORD
PROCEDURE_STEP
OBJECT
OBJECT_ALIAS
OBJECT_RELATION
OBJECT_LINK_ASSERTION
WORK_RECORD
RECEIPT
PROJECTION_ARTIFACT
ANSWER_TRACE
EVALUATION_CASE
```

Extension 必須使用 namespace：

```text
custom:<tenant-id>:<resource-kind>
```

禁止無 namespace 任意新增全域 kind。

---

# 6. Identifier Convention

## 6.1 OMOS-generated ID

所有 OMOS 自產 primary ID：

```text
algorithm = UUIDv7
serialization = lowercase canonical hyphenated UUID
```

例：

```text
0198e6d0-7a2b-7c3d-8e4f-1234567890ab
```

規則：

- `*_id` field 保存 bare UUID。
- `*_ref` field 保存 typed URI：

```text
urn:omos:<resource-kind>:<uuid>
```

例：

```text
evidence_id  = 0198e6d0-7a2b-7c3d-8e4f-1234567890ab
evidence_ref = urn:omos:evidence:0198e6d0-7a2b-7c3d-8e4f-1234567890ab
```

ID 不得編碼：

- tenant 名稱。
- client 名稱。
- Jira key。
- email。
- filepath。
- URL。
- classification。
- sensitivity。

UUIDv7 內含的時間只代表 ID 生成順序，**不得**代替 `occurred_at`。

## 6.2 Stable Source Identity Tuple

每個 source-native entity 的 identity：

```text
tenant_id
+ source_system
+ source_instance_id
+ entity_type
+ native_id
```

範例：

```yaml
tenant_id: 0198e6d0-1111-7aaa-8bbb-111111111111
source_system: jira-cloud
source_instance_id: 11111111-2222-3333-4444-555555555555
entity_type: issue
native_id: "10042"
```

規則：

- `native_id` 一律 string。
- mutable human key 不得當唯一 identity。
- `source_instance_id` 必須可區分不同 Jira site、Slack workspace、Git repository、Microsoft tenant。
- ingestion route 不進 stable identity。

## 6.3 Source Alias

Alias kind：

```text
MUTABLE_KEY
URL
DISPLAY_NAME
LEGACY_ID
EXTERNAL_REF
```

Alias record應保存：

```text
value
valid_from
valid_to
status
source_evidence_ref
```

Jira issue key改名時：

```text
same source identity
+ new MUTABLE_KEY alias
+ old alias retired but retained
```

## 6.4 五種 identity 不得合併

```text
SOURCE_NATIVE_ENTITY_ID
SOURCE_NATIVE_EVENT_ID
TRANSPORT_DELIVERY_ID
INGESTION_ATTEMPT_ID
EVIDENCE_ID
```

另有：

```text
PAYLOAD_DIGEST
```

Digest 不是 identity。

### CloudEvents

CloudEvents：

```text
source + id
```

只用來識別 transport event／delivery語意。

禁止：

```text
CloudEvents id → evidence_id
```

## 6.5 Idempotency Profile

### `OMOS_ENTITY_SNAPSHOT_IDEMPOTENCY_V1`

JCS preimage：

```json
{
  "profile": "OMOS_ENTITY_SNAPSHOT_IDEMPOTENCY_V1",
  "tenant_id": "...",
  "source_identity": {
    "source_system": "...",
    "source_instance_id": "...",
    "entity_type": "...",
    "native_id": "..."
  },
  "source_version": {
    "basis": "...",
    "kind": "...",
    "value": "...",
    "secondary_digest": "..."
  }
}
```

Key：

```text
sha256(JCS(preimage))
```

若：

```text
source_version.basis = UNKNOWN
source_version.kind = NONE
```

則 preimage MUST 加入 `raw_digest`，並寫入：

```text
IDENTITY_FALLBACK_DERIVED
```

### `OMOS_SOURCE_EVENT_IDEMPOTENCY_V1`

來源提供 stable native event ID 時：

```json
{
  "profile": "OMOS_SOURCE_EVENT_IDEMPOTENCY_V1",
  "tenant_id": "...",
  "source_identity": {},
  "event_type": "...",
  "native_event_id": "..."
}
```

`delivery_id`、`received_at`、`ingestion_mode` 不得進 key，否則 redelivery 無法 deduplicate。

同 native event ID 再送不同 digest：

```text
不得覆寫
不得當普通新 revision
必須產生 REDELIVERY_PAYLOAD_MISMATCH
```

來源沒有 stable event ID 時，fallback preimage：

```text
source identity
+ event type
+ occurred_at
+ raw digest
```

並標記：

```text
identity_basis = FALLBACK_DERIVED
```

---

# 7. Source Version Convention

```yaml
source_version:
  basis: AUTHORITATIVE_NATIVE
  kind: ETAG
  value: "..."
  secondary_digest: "sha256:..."
```

## 7.1 `basis`

```text
AUTHORITATIVE_NATIVE
COMPOUND_OBSERVED
CONTENT_ONLY
UNKNOWN
```

## 7.2 `kind`

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

## 7.3 Rules

- `AUTHORITATIVE_NATIVE`：source明確提供 monotonic revision／etag／commit／sequence。
- `COMPOUND_OBSERVED`：多欄位＋digest組成 observation version，不能宣稱是 source canonical revision。
- `CONTENT_ONLY`：只能以內容 digest區分版本。
- `UNKNOWN`：無可靠 version；必須保留 raw digest與 gap。
- `secondary_digest` 只是校驗／representation fingerprint，不得冒充 native revision。
- 同一 stable source identity的新 version產生新 Evidence；不得修改舊 Evidence。

---

# 8. Chronology Convention

## 8.1 Four-clock model

```text
occurred_at
observed_at
received_at
persisted_at
```

### `occurred_at`

來源業務事件真正發生時間；未知可為 null。

### `observed_at`

Adapter、poller或 source endpoint觀察到該狀態的時間。

### `received_at`

OMOS ingress接受 payload／event的時間。

### `persisted_at`

Evidence durable commit完成時間。

## 8.2 `occurred_at_basis`

```text
SOURCE
PRODUCER_ASSIGNED
OBSERVED
UNKNOWN
```

## 8.3 Timestamp serialization

- RFC 3339。
- canonical timezone為 UTC `Z`。
- 可接受 0–9 位 fractional seconds。
- canonical serializer移除不必要尾端 0。
- 來源原始 timestamp可另存 receipt，避免精度或 timezone資訊損失。
- date-only 值使用 RFC 3339 full-date，不能塞進 timestamp field。

## 8.4 Evidence chronology rule

後補 Evidence：

```text
MUST NOT
```

被寫成舊 Answer／Evaluation當時已使用的 Evidence。

AnswerTrace 必須保留：

```text
evidence_refs_used_at_execution
generated_at
verification_started_at
verification_completed_at
```

---

# 9. Range Convention

所有 range預設：

```text
[start, end)
```

## 9.1 Unicode text

```text
unit = Unicode code point
index base = 0
start inclusive
end exclusive
```

不得默認用：

- UTF-8 byte。
- UTF-16 code unit。
- grapheme cluster。

若 adapter使用其他 offset單位，必須明示並提供 mapping receipt。

## 9.2 Line range

```text
index base = 1
start inclusive
end exclusive
```

例：

```text
start=18, end=24
```

代表 lines 18–23。

Line range只供 human navigation／fallback，不得是唯一 robust selector。

## 9.3 Time range

```text
[start_at, end_at)
```

## 9.4 Page／slide

```text
index base = 1
```

## 9.5 PDF bbox

Canonical bbox：

```text
origin = TOP_LEFT
space = normalized page [0,1]
fields = x_min, y_min, x_max, y_max
precision = 6 decimals
```

規則：

- `0 <= x_min < x_max <= 1`
- `0 <= y_min < y_max <= 1`
- raw parser-native bbox與coordinate origin保存在 ExtractionReceipt。
- 6位小數是 exchange canonical precision；不得用於宣稱 parser原始精度。

---

# 10. Digest Convention

Digest serialization：

```text
sha256:<64 lowercase hex>
```

## 10.1 `raw_digest`

輸入：

```text
persisted source payload bytes
after transport decoding
before semantic normalization
```

文件為原始 file bytes；JSON為 OMOS 實際保存的 payload bytes。

`raw_digest` MUST保留。

## 10.2 `canonical_digest`

結構化 JSON符合 I-JSON時，可以依 RFC 8785 JCS canonicalize後計算。

若無法 canonicalize：

```text
canonical_digest = null
quality_gap = CANONICALIZATION_UNAVAILABLE
```

預設不因此丟棄 Evidence。

Policy可以要求某些高風險 source canonicalization失敗時：

```text
Acceptance = BLOCKED
```

但不能偽造 digest。

## 10.3 `normalized_digest`

NormalizedDocument存在時：

```text
normalized_digest MUST exist
```

它是 normalized representation的digest，不可取代raw digest。

## 10.4 Digest rules

```text
same digest != same source identity
same digest != same Evidence identity
same normalized digest != same parser activity
```

Exact duplicate可以建立 relation，但不合併ACL、retention、source lifecycle。

---

# 11. Text、Language、Media Convention

## 11.1 `OMOS_TEXT_NORM_V1`

```text
encoding = UTF-8
Unicode normalization = NFC
newline = LF
whitespace collapse = false
case folding = false
```

規則：

- 不得把多個space／newline合併，否則selector失真。
- invisible Unicode移除或sanitization必須有transformation receipt。
- sanitization前後offset若不同，必須保存mapping或明示anchor只對normalized representation有效。

## 11.2 Language

- 使用BCP 47。
- 未知：`und`。
- 多語：`mul`，或block-level language override。
- canonical tag例：`zh-TW`、`en-US`。

## 11.3 Media type

- 使用IANA media type。
- text canonical encoding預設UTF-8。
- 原始 source宣告錯誤時，raw value可放receipt；canonical field使用實際detected type並附warning。

---

# 12. Common Status Axes

## 12.1 `canonicality`

```text
EVIDENCE
NORMALIZED
CANDIDATE
CANONICAL
PROJECTION
```

## 12.2 `lifecycle_state`

```text
ACTIVE
SUPERSEDED
ARCHIVED
INVALIDATED
```

## 12.3 `source_availability`

```text
AVAILABLE
NOT_FOUND_UNCONFIRMED
ACCESS_REVOKED
SOURCE_DELETED
UNAVAILABLE_UNKNOWN
REPRESENTATION_UNAVAILABLE
```

## 12.4 `payload_retention_state`

```text
RETAINED
LEGAL_HOLD
RETENTION_EXPIRED
TOMBSTONED
PURGED
```

## 12.5 `activity_status`

```text
STARTED
RUNNING
COMPLETE
PARTIAL
FAIL
ABORT
```

正式：

```text
activity COMPLETE
!= verification PASS
!= acceptance ACCEPTED
```

## 12.6 `verification_status`

```text
PASS
FAIL
PARTIAL
NOT_RUN
STATIC_ONLY
```

## 12.7 `acceptance_status`

```text
PENDING
ACCEPTED
REJECTED
BLOCKED
```

## 12.8 Confidence

Confidence建議保存為：

```text
0.0 <= confidence <= 1.0
```

它只能作：

- routing。
- review priority。
- threshold signal。

禁止：

```text
confidence high → VERIFIED
confidence high → ACCEPTED
```

---

# 13. Knowledge Vocabulary

## 13.1 Assertion kind

```text
FACT
DEFINITION
RULE
REQUIREMENT
RECOMMENDATION
DECISION
METRIC
THRESHOLD
EXCEPTION
CONSTRAINT
ASSUMPTION
RISK
UNKNOWN
```

## 13.2 Evidence relation

```text
SUPPORTS
CONTRADICTS
QUALIFIES
LIMITS
SUPERSEDES
DERIVED_FROM
QUOTED_FROM
PRIMARY_SOURCE
```

## 13.3 Conflict type

```text
VALUE_MISMATCH
SCOPE_MISMATCH
VERSION_MISMATCH
SOURCE_AUTHORITY_MISMATCH
TEMPORAL_MISMATCH
DEFINITION_MISMATCH
REQUIREMENT_MISMATCH
CLASSIFICATION_ERROR
```

## 13.4 Conflict resolution

```text
SELECT_ONE
QUALIFY_BY_SCOPE
QUALIFY_BY_TIME
KEEP_MULTIPLE_VALID
SUPERSEDE
RECLASSIFY
INSUFFICIENT_EVIDENCE
```

淘汰答案不必標成錯誤；它可能只是scope、time或classification不同。

---

# 14. Document Block Vocabulary

v0.1 common block type：

```text
title
section_header
paragraph
list
list_item
code
formula
table
image
chart
key_value
form
quote
footnote
header
footer
comment
speaker_note
transcript_segment
unknown
```

Phase-1 implementation只需：

```text
title
section_header
paragraph
list_item
code
table
image
unknown
```

`table`、`image`、`formula`不得只剩Markdown字串：

- table保存structured cells。
- image保存asset ref、caption、bbox。
- formula保存source與normalized representation。
- enrichment保存provider／model／version receipt。

---

# 15. Quality Gap Vocabulary

v0.1 core gap codes：

```text
PAGE_REQUIRES_OCR
TABLE_STRUCTURE_UNCERTAIN
MULTI_COLUMN_READING_ORDER_RISK
IMAGE_CONTENT_NOT_READ
FORMULA_NOT_PARSED
TRUNCATED_BY_LIMIT
ROBOTS_EXCLUDED
ATTACHMENT_UNREADABLE
UNSUPPORTED_FORMAT
ENCODING_REPLACEMENT_DETECTED
PARSER_FALLBACK_USED
SOURCE_PARTIAL
CANONICALIZATION_UNAVAILABLE
REDELIVERY_PAYLOAD_MISMATCH
CLOCK_SKEW_DETECTED
IDENTITY_FALLBACK_DERIVED
```

Severity：

```text
INFO
LOW
MEDIUM
HIGH
CRITICAL
```

Coverage：

```text
COMPLETE
PARTIAL
UNKNOWN
NOT_APPLICABLE
```

Parser exit 0不得自動推出：

```text
coverage = COMPLETE
verification = PASS
```

---

# 16. Authority Boundary Matrix

| Resource | Canonicality | Mutable? | Authority |
|---|---|---:|---|
| RawEvidence core | EVIDENCE | core immutable | Source observation truth |
| Evidence availability／retention state | governance record | append-only transition | Access／retention truth |
| NormalizedDocument | NORMALIZED | rebuildable | Parser representation |
| Assertion Candidate | CANDIDATE | proposal revision | Candidate only |
| Accepted Assertion | CANONICAL | new revision／supersession | Canonical Knowledge |
| Procedure Candidate | CANDIDATE | proposal revision | Candidate only |
| Accepted Procedure | CANONICAL | new revision／supersession | Canonical Procedure |
| Object identity | adjacent durable authority | governed | Reference identity, not Knowledge |
| ObjectLink Proposed | CANDIDATE-like context assertion | yes | Suggestion only |
| ObjectLink Accepted | durable context relation | supersede/invalidate | Context relation, no permission expansion |
| WorkRecord | PROJECTION | rebuildable | Work view only |
| VerificationReceipt | immutable receipt | no | What checks actually ran |
| AcceptanceReceipt | immutable receipt | no | Authority decision |
| CanonicalWriteReceipt | immutable receipt | no | Single Writer transaction evidence |
| RAG／Vector／Graph | PROJECTION | rebuildable | Retrieval artifact |
| Reference Pack／Agent Skill | PROJECTION | rebuildable | Consumption/runtime artifact |
| AnswerTrace | execution evidence | immutable | Historical answer execution truth |

---

# 17. Object Context Vocabulary

## 17.1 Contract suite

```text
OMOS-OBJECT-CONTEXT
```

包含：

```text
Object
ObjectAlias
ObjectRelation
ObjectLinkAssertion
LinkDecisionReceipt
ObjectLinkFeedback
WorkRecord
WorkRecordBuildReceipt
CloseoutProposal
```

## 17.2 Core Object types

```text
DOCUMENT
JIRA_ISSUE
JIRA_PROJECT
COMMENT_THREAD
PERSON
TEAM
CLIENT
PROJECT
ORDER
WORKSPACE
REPOSITORY
FILE
AGENT_RUN
```

Extension：

```text
custom:<tenant-id>:<object-type>
```

## 17.3 Relation qualifier

```text
ABOUT
PART_OF
ACTOR
PARTICIPANT
OWNER
ASSIGNEE
REQUESTER
CLIENT
PROJECT
ORDER
ISSUE
THREAD
ATTACHMENT_OF
COMMENT_ON
RESULT_OF
DECISION_FOR
BLOCKED_BY
RELATED_TO
```

## 17.4 ObjectLink method

```text
EXPLICIT_NATIVE_ID
EXPLICIT_FOREIGN_KEY
EXPLICIT_URL
THREAD_NATIVE
PARENT_NATIVE
RULE
HEURISTIC
EMBEDDING
MODEL
HUMAN
MIGRATION
```

## 17.5 ObjectLink status

```text
PROPOSED
AUTO_ACCEPTED
ACCEPTED
REJECTED
SUPERSEDED
INVALIDATED
```

## 17.6 Auto-accept policy

可以 `AUTO_ACCEPTED`：

- source-native parent ID。
- explicit foreign key。
- stable thread ID。
-唯一且schema-valid的explicit business ID。
- deterministic migration mapping。

只能 `PROPOSED`：

- keyword overlap。
- participant overlap。
- time proximity。
- heuristic score。
- embedding similarity。
- model inference。

必須 human authority：

- cross-client。
- cross-tenant。
- HR／Legal／Finance。
- scope promotion。
- private Evidence進broader context。
- Object merge／split。
- billing attribution。

## 17.7 LinkDecisionReceipt

最小欄位：

```text
link_ref
previous_status
decision
authority_ref
policy_ref
decided_at
reason_codes
supporting_evidence_refs
permission_impact = NONE
```

`permission_impact` v0.1固定只能：

```text
NONE
```

因為接受link不能擴張permission。

## 17.8 Effective permission

```text
effective visibility
=
Managed Policy Floor
∩ Evidence ACL
∩ Object Scope Policy
∩ Requester Permission
```

禁止使用union。

## 17.9 WorkRecord

WorkRecord：

```text
= Evidence refs
+ accepted ObjectLinks
+ grouping policy
+ build receipt
```

它是projection。

Status：

```text
OPEN
INACTIVE
CLOSE_PROPOSED
CLOSED
REOPENED
MERGED
SPLIT
ARCHIVED
```

正式：

```text
INACTIVE != CLOSED
CLOSE_PROPOSED != CLOSED
```

## 17.10 Mixed-scope rendering

WorkRecord base record可以保存membership refs，但：

- 不保存可繞過member ACL的global summary。
- requester view只包含authorized members。
- summary必須由authorized subset重新render或由permission-digest scoped cache取得。
- build／render receipt保存permission decision digest。
- WorkRecord本身的metadata sensitivity至少不得低於其member最高sensitivity，但此標籤不能取代逐member enforcement。

---

# 18. Source Anchor Common Envelope

最小語意：

```text
source identity
source version
representation digest
profile
selectors[]
quote
normalization profile
resolution
```

Resolution：

```text
EXACT_MATCH
RELOCATED
CONTENT_CHANGED
MISSING
ACCESS_REVOKED
REPRESENTATION_UNAVAILABLE
AMBIGUOUS
NOT_CHECKED
```

一個重要anchor應同時帶：

```text
position selector
+ quote selector
+ representation digest
```

---

# 19. `PDF_REGION_V1`

必須保存：

```text
source PDF raw digest
page number
normalized bbox
block id
normalized representation ref
codepoint range
exact quote
prefix / suffix
resolution
```

Canonical：

```text
page = 1-based
bbox origin = TOP_LEFT
bbox range = [0,1]
bbox precision = 6
codepoint range = 0-based half-open
```

若頁面有：

```text
PAGE_REQUIRES_OCR
MULTI_COLUMN_READING_ORDER_RISK
TABLE_STRUCTURE_UNCERTAIN
```

則：

```text
anchor EXACT_MATCH
!= semantic support PASS
```

---

# 20. `MARKDOWN_TEXT_V1`

Resolver順序：

```text
1. exact representation digest
2. codepoint range + exact quote
3. quote + prefix/suffix relocation
4. heading path + quote
5. line range fallback
```

必須保存：

```text
OMOS_TEXT_NORM_V1
codepoint range
line range
heading path
exact quote
prefix / suffix
representation digest
```

Git-managed Markdown另外保存：

```text
repository identity
commit SHA
path
blob SHA
```

Path不是永久 source identity的唯一依據；rename需要alias／disposition。

---

# 21. `JIRA_CLOUD_ENTITY_SEGMENT_V1`

## 21.1 Stable identity

| Entity | Stable identity | Alias |
|---|---|---|
| Issue | numeric issue ID | issue key／URL |
| Comment | issue ID + comment ID | URL |
| Attachment | issue ID + attachment ID | filename |
| Changelog | issue ID + changelog ID | item index |
| Worklog | issue ID + worklog ID | URL |
| Project | numeric project ID | project key |

## 21.2 Anchor fields

```text
entity_type
entity_id
container_issue_id
field_path
content_format
renderer_profile
node_path / item path
exact quote
prefix / suffix
source version
representation digest
```

ADF：

```text
renderer_profile MUST be versioned
```

STD-00只鎖「必須versioned」，不選定實作版本；交STD-02處理。

## 21.3 Webhook boundary

```text
Webhook
!= Complete Source History
!= Deletion Truth
!= Permission Truth
```

Jira Cloud adapter必須：

```text
webhook
+ periodic reconciliation
+ permission/deletion audit
```

## 21.4 404

單次404：

```text
MUST NOT → SOURCE_DELETED
```

先進：

```text
NOT_FOUND_UNCONFIRMED
```

再由：

- delete event。
- authoritative audit。
- repeated reconciliation。
- human authority。

決定 `SOURCE_DELETED` 或 `ACCESS_REVOKED`。

## 21.5 Cloud／Data Center

```text
JIRA_CLOUD_V3
!= JIRA_DATA_CENTER_V2
```

只共用common envelope與entity vocabulary，不共用未驗證field mapping。

---

# 22. Positive Fixtures

Machine-readable positive fixtures：

```text
規格/v0.1/fixtures/std-00-positive-fixtures.json
```

包含：

1. PDF manual upload。
2. Git Markdown SOP。
3. Jira Cloud issue description。

每個fixture至少驗：

- stable source identity。
- source version。
- four-clock chronology。
- raw／canonical／normalized digest。
- source availability。
- payload retention。
- source anchor。
- authority invariant。

---

# 23. Negative Fixtures

Machine-readable negative fixtures：

```text
規格/v0.1/fixtures/std-00-negative-fixtures.json
```

至少包含：

```text
same CloudEvent redelivery
redelivery payload mismatch
same source entity new revision
same payload from different sources
single Jira 404
permission revoked
project deletion missed webhooks
non-I-JSON JCS input
source event without native event ID
PDF anchor with parser risk
Jira key rename
cross-client ObjectLink
mixed-scope WorkRecord summary leak
model confidence auto-accept
OpenLineage COMPLETE treated as verification
projection deletion
```

Negative fixture比happy path更接近真正acceptance contract。

---

# 24. Conformance Rules

## 24.1 `CORE`

必須符合：

- schema ID／version。
- UUIDv7 ID。
- typed ref。
- timestamp。
- digest format。
- enum。
- extension namespace。

## 24.2 `EVIDENCE`

再符合：

- stable source identity。
- source aliases。
- event/delivery/Evidence identity separation。
- source version。
- four clocks。
- raw digest。
- ACL／retention refs。
- availability／retention分軸。

## 24.3 `DOCUMENT`

再符合：

- parser receipt。
- block hierarchy。
- source anchors。
- quality gaps。
- normalized digest。

## 24.4 `KNOWLEDGE`

再符合：

- assertions。
- Evidence links。
- conflict／freshness。
- Verification。
- Acceptance。
- Canonical Writer receipt。

## 24.5 `PROCEDURE`

再符合：

- trigger。
- precondition。
- steps。
- permission requirement。
- verification。
- failure／rollback。

## 24.6 `OBJECT_CONTEXT`

再符合：

- Object identity／alias。
- link method／status。
- LinkDecisionReceipt。
- no permission expansion。
- WorkRecord rebuildability。
- permission-aware rendering。

## 24.7 `PROJECTION`

再符合：

- canonical source refs。
- source revision digest。
- build receipt。
- permission filter policy。
- rebuildability test。

---

# 25. Frozen Decisions

本提案建議Codex審查後鎖定：

1. OMOS-generated primary ID採UUIDv7。
2. `*_id`使用bare UUID；`*_ref`使用typed URN。
3. stable source identity採五欄tuple。
4. CloudEvents只作transport envelope。
5. OpenLineage只作activity lineage。
6. source event／delivery／Evidence identity分離。
7. source version採basis＋kind＋value＋secondary digest。
8. chronology採four-clock。
9. range全面採half-open。
10. text offset採Unicode code point。
11. line index 1-based；page／slide 1-based。
12. PDF canonical bbox為top-left normalized [0,1]、6位小數。
13. raw／canonical／normalized digest分離。
14. JCS失敗預設不丟Evidence，改寫quality gap。
15. canonicality、lifecycle、availability、retention分軸。
16. Object identity是durable reference authority，不是Knowledge。
17. ObjectLink採LinkDecisionReceipt。
18. ObjectLink不擴權。
19. WorkRecord為projection且permission-aware render。
20. Jira numeric ID為stable identity，issue key為alias。
21. Jira webhook必須搭配reconciliation。
22. Cloud與Data Center adapter分離。
23. Reference Pack／Agent Skill永遠是projection。
24. Activity COMPLETE不等於Verification PASS。
25. Model confidence不等於accepted authority。

---

# 26. Deliberately Deferred Decisions

以下不阻塞STD-00 vocabulary review：

1. JSON Schema檔案拆分方式。
2. Production DB table／index。
3. UUID library選型。
4. JCS library選型。
5. Jira ADF renderer exact implementation/version。
6. Jira reconciliation頻率與delete confirmation threshold。
7. Source clock skew threshold。
8. Full Object merge／split transaction。
9. Full Review Assignment workflow。
10. Full AnswerTrace／Evaluation schema。
11. Graph ontology。
12. Reference Pack compiler。
13. Outline production角色。

這些進各自後續卡，不應反向阻塞名詞與authority freeze。

---

# 27. Codex Review Gate

Codex應做read-only review，輸出：

```text
VERDICT: ACCEPT | AMEND | BLOCK
```

每個finding必須包含：

```text
ID
Severity
Exact file / section / field
Problem
Why it violates an authority boundary or fixture
Proposed amendment
Required positive / negative fixture
```

Codex必須特別檢查：

1. 是否仍有兩個enum混合不同axis。
2. ID／source version／digest是否仍可能互相冒充。
3. idempotency是否能正確處理redelivery與new revision。
4. four-clock是否足以保存chronology。
5. PDF／Markdown／Jira anchor是否可重定位與驗證。
6. Jira 404／delete／permission是否誤分類。
7. ObjectLink是否可能擴張permission。
8. WorkRecord是否可能洩漏mixed-scope內容。
9. Projection是否可能偷偷取得Knowledge identity。
10. 是否有人把activity COMPLETE當verification PASS。

禁止Codex：

- 直接實作production schema。
- 新增database。
- 新增runtime。
- 推翻八顆Minimal Core。
- 因找到新framework而重開architecture。
- 將本提案直接標成Canonical。

---

# 28. Acceptance Criteria

`STD-00`只有在下列條件全部成立後可升 `LOCKED`：

1. `common-vocabulary.yaml`可被YAML parser讀取。
2. positive fixture JSON可解析。
3. negative fixture JSON可解析。
4. 所有enum只描述單一axis。
5. PDF／Markdown／Jira fixture都能明確區分source identity、version、Evidence ID、digest。
6. Redelivery fixture不產生第二筆Evidence。
7. New revision fixture產生新Evidence且保留舊Evidence。
8. Single Jira 404不會立即判delete。
9. Cross-client model link不會auto-accept。
10. Mixed-scope WorkRecord不會產生unrestricted summary。
11. Projection全部可刪除重建。
12. Codex沒有提出`BLOCK`級authority finding。
13. 使用者／指定authority明確接受。

鎖版結果：以上 13 條於 2026-09-04 全部通過；驗證證據見 `.work/evidence/STD00-LOCK-20260904.md`。

---

# 29. 下一步

本提案已通過Review並由Owner接受：

```text
STD-00 → LOCKED
```

後續可另開獨立卡處理：

```text
STD-01 RawEvidenceEnvelope JSON Schema
```

STD-01只做：

- JSON Schema 2020-12。
- PDF／Markdown／Jira RawEvidence fixtures。
- idempotency fixture。
- source availability／retention transitions。
- schema validation tests。

不做：

- parser。
- connector。
- database migration。
- Skill。
- Graph。
- Runtime。
- automatic canonical write。

---

# 30. 最終定義

```text
標準文件規格
!= 一份Markdown樣板

標準文件規格
=
Common Vocabulary
+ Typed Identity
+ Exact Source Version
+ Four-clock Chronology
+ Raw / Canonical / Normalized Digests
+ Exact Source Anchors
+ Type-specific Semantics
+ Permission / Lifecycle / Governance
+ Verification / Acceptance
+ Rebuildable Projections
```

`STD-00` 的目的不是把所有功能做完，而是確保從下一張 schema卡開始，所有人使用同一套名詞、同一套authority boundary與同一套negative fixtures。
