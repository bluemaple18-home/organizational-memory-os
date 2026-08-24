# Backlog Reconciliation

Status vocabulary for architecture/backlog audit:

- `ALREADY_EXISTS`
- `PARTIAL`
- `MISSING`
- `DONOR_AVAILABLE`
- `CUSTOM_CODE_REQUIRED`
- `SHOULD_NOT_ADOPT`

Priority rule:

> Shared Research, Independent Product Priority.

Do not copy AI Core priority into this repo. Track both when relevant:

- AI Core Priority
- Knowledge SaaS Priority
- Priority Rationale

## Lane A — Knowledge Truth / Security

| Capability | Status | Knowledge SaaS Priority | Notes |
|---|---|---:|---|
| Evidence -> Candidate -> Canonical | PARTIAL | P0 | Formalize immutable/raw evidence boundary and candidate/promotion contracts |
| Raw/derived separation | PARTIAL | P0 | Donor available from Codex/memory/event-sourcing patterns; product owns authority |
| Provenance/source trace | PARTIAL | P0 | Extend to chronology, model/rule version, evidence chain |
| Canonical Single Writer | MISSING/PARTIAL | P0 | Audit all direct-write paths before adding a new writer component |
| Review/Approval Ledger | PARTIAL | P0 | record who/what/before/after/reason/evidence/acceptance |
| Conflict/Supersession | PARTIAL | P0 | preserve context split/reclassification/version semantics |
| Permission-before-Retrieval | PARTIAL | P0 | OpenFGA/Qdrant donors; organizational semantics custom |
| Managed Policy Floor | MISSING/PARTIAL | P0 | lower scope may restrict but not expand denied authority |
| Verification honesty | PARTIAL | P0 | PASS/FAIL/PARTIAL/NOT_RUN/STATIC_ONLY |
| Eval failure -> correction -> re-eval | ALREADY_EXISTS/PARTIAL | P0 | preserve failure routing and regression evidence |
| Tenant isolation safety floor | PARTIAL | P0 | cannot become paid “optional security” |

## Lane B — SaaS Platform / Economics

| Capability | Status | Priority | Notes |
|---|---|---:|---|
| Minimum tenant/token/cost telemetry | MISSING/PARTIAL | P0-min | Required to know SaaS unit economics and support incidents |
| Full telemetry/usage/cost analytics | MISSING | P1 | OTel GenAI projection; do not invent vocabulary |
| Context Budget Contract | MISSING/PARTIAL | P1-A | Codex/GraphRAG donor available; ContextPolicy custom |
| Bounded Retrieval | PARTIAL | P1-A | permission + budget + routing |
| Retrieval routing/filtering | PARTIAL | P1-A | authority/freshness/source class + Qdrant filters |
| Config Scope/Precedence | MISSING/PARTIAL | P1-A | Platform/Org/Tenant/Dept/Team/User/Client/Project |
| External Capability/Source Admission | MISSING/PARTIAL | P1-A | connector origin/trust/permission/tenant policy |
| Source Freshness | PARTIAL | P1-A | risk-based source/dependency policy, not AI Core cadence |
| Knowledge Lifecycle | PARTIAL | P1-A | no low-usage delete authority |
| Version/Compatibility Governance | MISSING | P1-B | connector/runtime/skill/model/embedding/client compatibility |
| Capability entitlement/scope overrides | PARTIAL | P1-A | commercial SaaS control plane |

## Lane C — Product Knowledge Capabilities

| Capability | Status | Priority | Notes |
|---|---|---:|---|
| Outlook/Teams/Jira evidence ingestion | PARTIAL/DONOR_AVAILABLE | P1-A | Microsoft Graph / Teams SDK + existing Jira adapters |
| Personal/Team/Company scopes | PARTIAL | P1-A | one platform, multiple identity/scope spaces |
| Activity -> Work Record | MISSING/PARTIAL | P1-A | OpenChronicle + DayTrail + OCEL donor path |
| Knowledge/Procedure separation | PARTIAL | P1-A/P1-B | schema + relationships |
| Knowledge -> Skill Candidate | MISSING/PARTIAL | P1/P2 | capability-level dependent |
| Skill validation/publishing | PARTIAL | P1/P2 | prior-art skill packaging can be absorbed |
| Skill Runtime Governance | MISSING | P1/P2 conditional | becomes required when a commercial level executes skills |
| Repository Intelligence | RE-EVALUATED | P1-B | AI Core P2 must not propagate; formal product capability |
| Multi-Agent Evaluation | PARTIAL | P1-B | verification strategy, not runtime subsystem |
| Reviewer/Impact Graph | PARTIAL | P1-B | governance UI may be important product value |
| Advanced Graph Explorer | PLANNED | P2 | visualization remains projection |

## Lane D — Expansion / Triggered

| Capability | Status | Priority | Notes |
|---|---|---:|---|
| Achievement/Engagement | PLANNED | P2/P3 | reward verified contribution/reuse, never volume/truth authority |
| Skill marketplace | NORTH_STAR | P2/P3 | commercial expansion |
| Shared Blackboard | SHOULD_NOT_ADOPT NOW | TRIGGER-BASED | only if real long-running multi-agent/human collaboration emerges |
| Multi-Agent Runtime | SHOULD_NOT_ADOPT NOW | DO NOT BUILD | use provider/runtime adapters |
| Agent mailbox/wake/PTY/process manager | SHOULD_NOT_ADOPT | N/A | belongs to runtime plane |
| Collaboration UI | NORTH_STAR | P2/P3 | evidence-driven demand first |
| High-end cross-industry automation | NORTH_STAR | P2/P3 | domain packs + capability levels later |

## Independent-priority reconciliation examples

| Capability | AI Core Priority | Knowledge SaaS Priority | Why |
|---|---:|---:|---|
| Repository Intelligence | P2/deferred | P1-B | engineering Q&A/code impact/repository ingestion can be core company product value |
| Config Scope/Precedence | P2 | P1-A | enterprise hierarchy and commercial scope overrides |
| Managed Policy Floor | P2 | P0 | prevents lower scopes from expanding denied authority |
| Telemetry/Cost | P3-ish | P0-min/P1-full | billing, margin, SLA, support, capacity |
| External Capability Admission | P2/P3 | P1-A | enterprise connector ecosystem |
| Multi-Agent Evaluation | P2 | P1-B | knowledge correctness without building runtime |
| Skill Runtime Governance | P2 | P1/P2 conditional | required when SaaS capability level executes company skills |
| Version Compatibility | P2 | P1-B | rollout/support/SLA |
| Knowledge Graph UI | P3 | P1-B reviewer UI / P2 advanced explorer | reviewer workflow/product differentiation |
| Shared Blackboard | P3 | TRIGGER-BASED | still lacks enough demand evidence |

## MVP vertical-slice acceptance

MVP is considered operational when one real enterprise flow can run end-to-end:

```text
Outlook/Teams/Jira/Documents Evidence
 -> Provenanced Raw Evidence
 -> Work Record and/or Candidate
 -> Staging
 -> Permission/Conflict/Review/Verification
 -> Acceptance
 -> Canonical Writer
 -> Canonical Knowledge
 -> Permission-before-Retrieval
 -> Context Budget/Bounded Retrieval
 -> PM/RD Answer with Citation
 -> Machine/Human Evaluation
 -> Failure -> Correction -> Re-evaluation
```

MVP does not require advanced graph UI, achievement, marketplace, blackboard or a custom multi-agent runtime.

## Mandatory implementation-card template

Every important implementation card must answer:

```text
Capability:
Architecture Priority:
Delivery Maturity:
Commercial Level(s) Enabled:
Existing Seam:
Current Status: ALREADY_EXISTS/PARTIAL/MISSING/...

Prior Art:
Pinned Donor / Version:
License:
Reuse Candidate:
Absorb:
Do Not Absorb:
Tests / Failure Cases To Reuse:
Dependency vs Adapter Decision:

Custom Organizational Delta:
Why Custom Code Is Still Needed:
Permission / Authority Impact:
Telemetry / Cost Impact:
Acceptance Criteria:
```

If `Why Custom Code Is Still Needed` cannot be answered, do not immediately reimplement the engineering.
