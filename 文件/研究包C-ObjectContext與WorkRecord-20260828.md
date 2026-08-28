# 研究包 C｜Object Context、ObjectLink 與 WorkRecord

日期：2026-08-28

狀態：`RESEARCH_COMPLETE / DRAFT_INPUT / NOT_CANONICAL / NO_IMPLEMENTATION_AUTHORIZATION`

對應主線：

```text
Object / Work Context Minimal Core
Personal Evidence / Work Record
STD-04 Knowledge Assertion / EvidenceLink
```

本研究包回答：

> 一筆 Evidence如何同時關聯 Jira、Client、Project、Thread、Person、Order等多個 Object？哪些關聯可 deterministic接受，哪些只能提出建議？WorkRecord要如何保持可重建而不長成第二套 source truth？

---

## 1. 結論

正式新增相鄰 contract suite：

```text
OMOS-OBJECT-CONTEXT
```

它不是新的 `document_kind`，也不是新的 canonical database。

包含：

```text
Object
ObjectAlias
ObjectRelation
ObjectLinkAssertion
ObjectLinkFeedback
WorkRecord
WorkRecordBuildReceipt
CloseoutProposal
```

核心 invariant：

```text
Evidence can link to multiple Objects

ObjectLink suggestion
!= accepted durable link

Accepted ObjectLink
!= permission expansion

WorkRecord
= rebuildable projection

WorkRecord summary
!= source Evidence
!= Canonical Knowledge
```

---

## 2. Exact sources / pins

### 2.1 OCEL 2.0

```text
Standard: Object-Centric Event Log 2.0
Specification paper: arXiv:2403.01975
Exchange formats: JSON / XML / SQLite
```

Primary sources：

- https://www.ocel-standard.org/specification/overview/
- https://www.ocel-standard.org/specification/formats/json/
- https://arxiv.org/abs/2403.01975

Relevant semantics：

```text
Event
Object
Event Type
Object Type
Event-to-Object Relationship
Object-to-Object Relationship
Relationship Qualifier
Time-varying Object Attributes
```

### 2.2 OpenChronicle

```text
Repository: Einsia/OpenChronicle
Pinned commit: bad3a1e86d8e85a82d76d3883a491abc06f8c6b7
License: MIT
```

Primary sources：

- https://github.com/Einsia/OpenChronicle/blob/bad3a1e86d8e85a82d76d3883a491abc06f8c6b7/docs/timeline.md
- https://github.com/Einsia/OpenChronicle/blob/bad3a1e86d8e85a82d76d3883a491abc06f8c6b7/docs/session.md

### 2.3 DayTrail

```text
Repository: varaprasadreddy9676/DayTrail
Pinned commit: 7185b6e49e06cb4a9c76b0195ad49ac7c3ba960d
License: MIT OR Apache-2.0
```

Primary sources：

- https://github.com/varaprasadreddy9676/DayTrail/blob/7185b6e49e06cb4a9c76b0195ad49ac7c3ba960d/LICENSE
- https://github.com/varaprasadreddy9676/DayTrail/blob/7185b6e49e06cb4a9c76b0195ad49ac7c3ba960d/apps/desktop/src-tauri/src/models.rs
- https://github.com/varaprasadreddy9676/DayTrail/blob/7185b6e49e06cb4a9c76b0195ad49ac7c3ba960d/apps/desktop/src-tauri/src/matching.rs

Exact useful structures：

```text
SourceEvent
ActivityTaskLink
LinkOrigin: manual / rule
TaskMatchRule
TaskLinkSuggestion
TaskActivitySummary
WorkspaceContext
WorkSessionSummary
ParallelStreamSummary
```

---

## 3. OCEL semantic mapping

### 3.1 What to absorb

| OCEL 2.0 | OMOS mapping |
|---|---|
| Event | Evidence occurrence／source event observation |
| Object | Business／work context object |
| Event-to-Object relation | Evidence→Object link |
| Object-to-Object relation | Object relation |
| qualifier | Controlled relation code／role |
| dynamic object attribute | time-scoped object attribute observation |

OCEL的核心價值：

> 一個 event不必被強塞進單一 case；它可以同時關聯多個不同型別 Object。

這正好支持：

```text
Email message
→ Person
→ Client
→ Project
→ Jira Issue
→ Thread
```

### 3.2 What not to absorb

- 不把 OCEL JSON／SQLite當 OMOS canonical store。
- 不把所有 Evidence強迫成 process-mining event。
- 不讓 qualifier任意文字化，導致 relation無法治理。
- 不讓 OCEL object attribute變成 Canonical Knowledge。
- 不使用單一 case ID重新壓平 object-centric semantics。

### 3.3 Controlled qualifiers

Phase-1 建議：

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

Relation vocabulary應可擴充，但 unknown value必須保存 namespace：

```text
omos:ABOUT
jira:COMMENT_ON
custom:<tenant>:<relation>
```

---

## 4. `Object`

```json
{
  "object_id": "urn:uuid:...",
  "tenant_id": "tenant-example",
  "object_type": "JIRA_ISSUE",
  "canonical_label": "PROJ-123｜訂單花費為 0",
  "scope": {
    "scope_type": "PROJECT",
    "scope_ref": "project:ad-platform"
  },
  "native_refs": ["object-alias://..."],
  "lifecycle": {
    "status": "ACTIVE",
    "valid_from": null,
    "valid_to": null
  },
  "attributes": {},
  "created_at": "...",
  "updated_at": "..."
}
```

### 4.1 Phase-1 object types

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
MEETING
EMAIL_THREAD
CHAT_THREAD
UNKNOWN
```

### 4.2 Object identity

`object_id` 是 OMOS identity；來源 native identity放 `ObjectAlias`。

同一 business object可以有多個 alias：

```text
Jira numeric id
Jira key
Order ID
Client-specific reference
URL
human alias
```

但 alias resolution不能自動合併 Object而不留 Merge Proposal／receipt。

---

## 5. `ObjectAlias`

```json
{
  "alias_id": "urn:uuid:...",
  "object_ref": "urn:uuid:...",
  "source_system": "jira-cloud",
  "source_instance_id": "cloud-id",
  "entity_type": "issue",
  "alias_kind": "PRIMARY_NATIVE_ID",
  "value": "10042",
  "uri": "jira://cloud-id/issue/10042",
  "valid_from": "...",
  "valid_to": null,
  "evidence_refs": []
}
```

### 5.1 Alias kinds

```text
PRIMARY_NATIVE_ID
MUTABLE_KEY
URL
EMAIL_ADDRESS
DOMAIN
REPOSITORY_PATH
HUMAN_ALIAS
EXTERNAL_REFERENCE
```

### 5.2 Alias rules

- `PRIMARY_NATIVE_ID` 必須 source-instance scoped。
- Mutable key需要有效時間或revision history。
- Human alias不能單獨觸發 Object merge。
- 同 alias撞到多 Object時產生 ambiguity，不可挑第一個。

---

## 6. `ObjectRelation`

Object-to-Object relation：

```json
{
  "relation_id": "urn:uuid:...",
  "from_object_ref": "urn:uuid:project",
  "to_object_ref": "urn:uuid:client",
  "qualifier": "CLIENT",
  "direction": "DIRECTED",
  "validity": {
    "valid_from": "...",
    "valid_to": null
  },
  "evidence_links": [],
  "status": "ACCEPTED"
}
```

Relation可以 time-scoped；例如 Person角色、Issue所屬 Project、Order綁定 Client可能變更。

ObjectRelation不是 Knowledge Graph projection的 layout edge；它是有 Evidence support的 object-context assertion。

---

## 7. `ObjectLinkAssertion`

Evidence-to-Object relation必須先表達成 link assertion。

```json
{
  "link_id": "urn:uuid:...",
  "evidence_ref": "urn:uuid:evidence",
  "object_ref": "urn:uuid:object",
  "qualifier": "ISSUE",
  "method": "EXPLICIT_NATIVE_ID",
  "confidence": 1.0,
  "score_basis": {
    "rule_id": null,
    "features": ["jira_issue_id=10042"]
  },
  "generated_by": {
    "executor_type": "DETERMINISTIC_RULE",
    "executor_ref": "object-linker:v0.1"
  },
  "status": "AUTO_ACCEPTED",
  "review": null,
  "created_at": "..."
}
```

### 7.1 Link methods

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

### 7.2 Status

```text
PROPOSED
AUTO_ACCEPTED
ACCEPTED
REJECTED
SUPERSEDED
INVALIDATED
```

### 7.3 Confidence semantics

```text
confidence
= linking confidence / routing signal

confidence
!= Verification PASS
!= Acceptance authority
!= Permission expansion
```

---

## 8. Link acceptance policy

### 8.1 Deterministic auto-accept

可 auto-accept 的典型條件：

| Signal | Default |
|---|---|
| Jira comment carries parent issue numeric ID | `AUTO_ACCEPTED` |
| Attachment carries parent issue ID | `AUTO_ACCEPTED` |
| Native thread message carries thread ID | `AUTO_ACCEPTED` |
| Explicit order／ticket ID matches unique active alias | `AUTO_ACCEPTED` |
| User manually links | `ACCEPTED` |

即使 auto-accepted，也要保存 method、features、rule/version與time。

### 8.2 Candidate only

預設只能 propose：

| Signal | Default |
|---|---|
| title keyword overlap | `PROPOSED` |
| participant overlap | `PROPOSED` |
| time proximity | `PROPOSED` |
| semantic similarity | `PROPOSED` |
| model inference | `PROPOSED` |
| mutable human alias only | `PROPOSED` |

### 8.3 Human authority required

以下不得單靠模型／score auto-accept：

```text
跨 Client linking
跨 tenant linking
敏感 HR / legal / finance Object
會導致 scope promotion
會讓私人 Evidence進入 broader WorkRecord
Object merge / split
high-impact billing attribution
```

### 8.4 Permission invariant

```text
Accepted ObjectLink
不得放寬 Evidence ACL
不得自動放寬 Object scope
不得自動升 Candidate scope
```

有效 retrieval scope取 Evidence與Object policy的交集／authoritative decision，不取聯集。

---

## 9. DayTrail patterns to absorb

DayTrail的 shipped code已清楚分：

```text
TaskLinkSuggestion
→ event id / match reason / score

ActivityTaskLink
→ durable association
→ origin manual / rule

TaskMatchRule
→ field / matcher / pattern / case sensitivity
```

其 deterministic matcher支援：

```text
Field:
Title / URL / App / Source / Any

Matcher:
Contains / Wildcard / Regex
```

且在已 redacted local values上執行。

### 9.1 OMOS adaptation

吸收：

- suggestion與durable link分開。
- `match_reason`／score basis可解釋。
- deterministic rule優先。
- user accept／reject。
- activity proof aggregation。

補強：

- source-native identity method優先於keyword。
- accepted／rejected feedback有 receipt。
- semantic/model link不直接auto-accept。
- link correction不修改 RawEvidence。
- permission與scope另外決策。
- rule version／config digest必須保存。

---

## 10. `ObjectLinkFeedback`

```json
{
  "feedback_id": "urn:uuid:...",
  "link_ref": "urn:uuid:...",
  "decision": "REJECTED",
  "reason_code": "WRONG_PROJECT",
  "correct_object_ref": "urn:uuid:...",
  "decided_by": "person:...",
  "decided_at": "...",
  "notes": null
}
```

Decision：

```text
ACCEPTED
REJECTED
CORRECTED
SNOOZED
```

Reject應可作負例，避免相同 rule一直提出同樣建議；但不能直接用個人負例覆蓋全 tenant policy。

---

## 11. Timeline / sessionization donor findings

OpenChronicle值得吸收的是 operation pattern，不是 memory truth。

### 11.1 Fixed wall-clock windows

OpenChronicle以固定牆鐘區間建立 timeline block，例如：

```text
[10:00, 10:01)
[10:01, 10:02)
```

而不是從daemon任意啟動時刻rolling。

價值：

- natural unique key `(start_time, end_time)`。
- 多 daemon／restart較容易 idempotent。
- human可以直接理解時間區段。

### 11.2 Never silently drop

Aggregator失敗時留下 fallback／gap，不把整個 window消失。

對 OMOS 的規則：

```text
Grouping failure
→ QualityGap
not
→ missing Evidence silently
```

### 11.3 Session cuts

可借：

```text
hard idle gap
soft context cut
timeout safety cap
bookmark / watermark
incremental flush
final reconciliation
```

但 session只是 WorkRecord candidate boundary signal，不是 business case truth。

### 11.4 Session policy version

所有 WorkRecord build必須保存：

```text
window policy
sessionization policy
thresholds
config digest
builder version
```

改 policy後可重建，不改 Evidence。

---

## 12. `WorkRecord`

WorkRecord回答：

> 某段工作圍繞哪些 Object發生、有哪些 Evidence、目前進度／結果／未結事項是什麼？

它不回答：

> 公司正式認可的 Knowledge是什麼？

### 12.1 Schema

```json
{
  "work_record_id": "urn:uuid:...",
  "tenant_id": "tenant-example",
  "record_type": "TASK_WORK",
  "status": "OPEN",
  "time_range": {
    "start": "...",
    "end": null,
    "range_semantics": "START_INCLUSIVE_END_EXCLUSIVE"
  },
  "primary_object_ref": "urn:uuid:jira-issue",
  "related_object_refs": [
    "urn:uuid:client",
    "urn:uuid:project"
  ],
  "evidence_refs": [],
  "accepted_link_refs": [],
  "participants": [],
  "results": [],
  "open_loops": [],
  "decision_refs": [],
  "knowledge_candidate_refs": [],
  "quality_gaps": [],
  "projection": {
    "rebuildable": true,
    "build_receipt_ref": "receipt://work-record-build/..."
  }
}
```

### 12.2 Record types

```text
TASK_WORK
INCIDENT
CLIENT_REQUEST
MEETING_FOLLOWUP
DECISION_PROCESS
SUPPORT_CASE
ORDER_OPERATION
RESEARCH_THREAD
GENERAL_WORK
```

### 12.3 Status

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

`INACTIVE` 不等於 CLOSED。

### 12.4 Closeout

```text
close signal
→ CloseoutProposal
→ policy / authority decision
→ CLOSED
```

可 deterministic propose：

- Jira status進入指定 terminal status。
- explicit human close action。
- authoritative order／case completion event。

不能自行 close：

- 只有長時間沒活動。
- 模型摘要寫「完成」。
- Agent execution exit 0。
- Email thread暫時沒有新訊息。

### 12.5 WorkRecord → Knowledge

一個 WorkRecord可以產生：

```text
0..N Knowledge Candidates
0..N Procedure Candidates
0..N Decision Candidates
```

Candidate的 Evidence support必須指向 exact Evidence／Source Anchor，而不能只指向 WorkRecord summary。

---

## 13. `WorkRecordBuildReceipt`

```json
{
  "schema_version": "omos.work-record-build-receipt.v0.1",
  "receipt_id": "urn:uuid:...",
  "work_record_ref": "urn:uuid:...",
  "builder": {
    "id": "work-grouper",
    "version": "0.1.0",
    "policy_id": "work-grouping-default",
    "policy_version": "0.1.0",
    "config_digest": "sha256:..."
  },
  "inputs": {
    "evidence_refs": [],
    "object_link_refs": [],
    "window_start": "...",
    "window_end": "..."
  },
  "excluded": [
    {
      "evidence_ref": "...",
      "reason": "AMBIGUOUS_OBJECT_LINK"
    }
  ],
  "quality_gaps": [],
  "built_at": "...",
  "rebuildable": true
}
```

### 13.1 Rebuild invariant

刪除 WorkRecord projection後，使用：

```text
Evidence
+ Object registry
+ accepted ObjectLinks
+ grouping policy/version
```

應可重建等價 WorkRecord。

Human-edited summary若需保留，應另保存為 annotation／candidate，不可讓不可重建的手工文字混入 projection truth而無 receipt。

---

## 14. `CloseoutProposal`

```json
{
  "proposal_id": "urn:uuid:...",
  "work_record_ref": "urn:uuid:...",
  "proposed_status": "CLOSED",
  "signals": [
    {
      "type": "JIRA_TERMINAL_STATUS",
      "evidence_ref": "..."
    }
  ],
  "uncertainty": "LOW",
  "required_authority": "POLICY_OR_HUMAN",
  "status": "PENDING",
  "created_at": "..."
}
```

Closeout decision不得隱含 Knowledge Acceptance。

---

## 15. Object merge / split

### 15.1 Merge

兩個 Object看似相同時：

```text
MergeProposal
→ alias/evidence comparison
→ permission impact
→ acceptance
→ merged identity / redirects
```

不能直接刪掉其中一個 Object。

### 15.2 Split

一個錯誤聚合 Object需要拆分時：

- 保留舊 identity tombstone／history。
- ObjectLinks重新指向新 Object。
- WorkRecord projection重建。
- Canonical Knowledge support需 impact analysis。

### 15.3 Reclassification

使用者先前要求「淘汰答案可能只是分類錯誤」；Object context也相同：

```text
Wrong ObjectLink
或 Wrong WorkRecord membership
可能是 classification error
不是 Evidence錯誤
```

---

## 16. ACL / scope rules

### 16.1 Evidence remains authoritative

Object與WorkRecord不得擴張 Evidence權限。

```text
Effective visibility
= Managed Policy Floor
∩ Evidence ACL
∩ Object scope policy
∩ requester permission
```

### 16.2 Mixed-scope WorkRecord

一個 WorkRecord若包含不同 ACL Evidence：

- 不建立「所有 Evidence全文合併後共用最寬 ACL」。
- WorkRecord summary需要 permission-aware rendering。
- 每個 summary claim保留 Evidence refs。
- 不同 identity可能看到不同 projection內容。

### 16.3 Personal → Team → Company

Scope promotion：

```text
ObjectLink acceptance
!= Scope promotion
```

Personal Evidence即使正確連到 Company Project，也不能因此自動公開給 Company。

---

## 17. Phase-1 grouping order

正式採 Deterministic First：

```text
1. Explicit native parent / foreign key
2. Explicit Jira / Order / Ticket ID
3. Explicit URL / thread / repository identity
4. Accepted ObjectAlias
5. Participant / project / client exact match
6. Time proximity
7. Keyword / rule
8. Embedding similarity
9. Model suggestion
10. Human clarification
```

前段確定性高，後段只提高 suggestion品質，不提高 authority。

---

## 18. Example

### Input Evidence

```text
E1 Jira Issue PROJ-123
E2 Jira Comment parent issue=10042
E3 Teams message mentions PROJ-123 and Client A
E4 PDF runbook attached to issue
E5 Git commit message includes PROJ-123
```

### Objects

```text
O1 Jira Issue 10042
O2 Client A
O3 Project Ad Platform
O4 Repository campaign-service
```

### Links

```text
E2 → O1 PARENT_NATIVE / AUTO_ACCEPTED
E3 → O1 EXPLICIT_KEY / AUTO_ACCEPTED if alias unique
E3 → O2 RULE_OR_MODEL / PROPOSED
E4 → O1 ATTACHMENT_OF / AUTO_ACCEPTED
E5 → O1 EXPLICIT_KEY / AUTO_ACCEPTED
E5 → O4 REPOSITORY_NATIVE / AUTO_ACCEPTED
```

### WorkRecord

```text
Primary Object: O1
Related: O2, O3, O4（只含已接受 links）
Evidence: E1–E5依 requester permission渲染
Status: OPEN
Candidates: 0..N
```

---

## 19. Hard stops

禁止：

- 一筆 Evidence只能屬於一個 Object。
- 把 WorkRecord當 Raw Evidence或Canonical Knowledge。
- keyword score高就 auto-accept cross-client link。
- embedding/model confidence直接提升 ACL或scope。
- session boundary變成 business case authority。
- WorkRecord summary取代 exact Evidence support。
- 關閉 Jira Issue就自動 Acceptance所有 Knowledge Candidate。
- link correction直接改 RawEvidence payload。
- Object merge不留 proposal／receipt／redirect。
- mixed ACL Evidence先合併全文再套一個 ACL。
- 採用 DayTrail task model作 OMOS WorkRecord authority。
- 採用 OpenChronicle memory DB作 OMOS canonical store。
- 採用 OCEL SQLite作產品主資料庫。

---

## 20. Open decisions

1. `Object`是否屬 canonical registry或可重建 projection；不同 object type可能不同。
2. ObjectLinkAssertion是否納入一般 AcceptanceReceipt，或使用輕量 LinkDecisionReceipt。
3. `AUTO_ACCEPTED` link的撤回與rule regression策略。
4. ObjectAlias collision resolution。
5. WorkRecord summary是否 deterministic render或允許 human-authored overlay。
6. 一筆 WorkRecord是否必須有 primary object。
7. Mixed-scope WorkRecord的UI／API projection形狀。
8. Closeout authority按 object type如何配置。
9. Merge／split receipt與canonical impact analysis schema。
10. Object attribute observation與Canonical Knowledge Assertion的邊界。

---

## 21. Acceptance criteria

1. 一筆 Teams Evidence可以同時連到 Person、Client、Project與Thread。
2. Jira Comment parent issue link能 deterministic auto-accept並保存理由。
3. keyword-only cross-client suggestion維持 PROPOSED，不會自動寫入。
4. rejected link不會被相同rule立即重新提出。
5. accepted link不會放寬 Evidence ACL。
6. WorkRecord刪除後可由 Evidence＋accepted links＋policy version重建。
7. session policy改變只重建 WorkRecord，不改 RawEvidence。
8. WorkRecord close proposal與final close decision分離。
9. WorkRecord產出的 Knowledge Candidate保留 exact Evidence anchors。
10. Object merge／split保留歷史與impact receipt。

---

## 22. Backlog disposition

```text
ADD ADJACENT CONTRACT SUITE:
OMOS-OBJECT-CONTEXT

MERGE INTO STD-00:
- object / relation / link status vocabulary
- time range semantics

ADD CTX-00:
Object / ObjectAlias / qualifier vocabulary freeze

ADD CTX-01:
ObjectLinkAssertion + LinkDecision / Feedback contract

ADD CTX-02:
WorkRecord + WorkRecordBuildReceipt projection contract

ADD CTX-03:
Closeout / Merge / Split proposals

DO NOT CHANGE:
- eight Minimal Core responsibilities
- current first frontier Raw Evidence Contract
- WorkRecord remains projection
```
