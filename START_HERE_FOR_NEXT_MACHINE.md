# START HERE — Next Machine Handoff

This file is the entry point for another machine / Codex session. **Do not redesign the system from scratch.** Continue from the authority decisions below.

## 1. Product identity

`organizational-memory-os` is a company product / SaaS architecture for organizational memory and enterprise knowledge. It begins with Knowledge SaaS, but Knowledge is the first capability, not the final product ceiling.

Long-term extension can include advertising troubleshooting, analytics, optimization, workflow automation, agent execution and AutoOps — all reusing the same evidence, permission, governance and evaluation substrate.

## 2. Non-negotiable architecture truths

1. Evidence != Knowledge.
2. Raw evidence is retained/provenanced separately from derived knowledge.
3. Candidate != Canonical.
4. Execution != Verification != Acceptance.
5. Missing verification never implies PASS.
6. `PARTIAL`, `NOT_RUN`, `STATIC_ONLY` must be preserved honestly.
7. Evidence chronology cannot be rewritten after the fact.
8. Canonical Knowledge has a single authoritative write path.
9. Permission is enforced before retrieval/context construction.
10. The LLM is never the permission enforcement boundary.
11. Knowledge != Procedure / Skill.
12. AI-discovered repeated patterns become Skill Candidates, not production skills automatically.
13. AI Core is a donor, not the product ceiling.
14. Multi-agent evaluation is allowed; Knowledge SaaS must not build a multi-agent runtime just to support it.
15. OpenTelemetry is a projection, not knowledge truth.
16. Vector DB is a retrieval store, not knowledge truth.
17. Outline is primarily the human/AI consumption surface for production knowledge; staging/candidates live behind a governance boundary.
18. General employees do not need Codex / Claude Code / Gemini CLI / full AI Core.

## 3. Core lifecycle

```text
Source Activity / Documents / Messages / Runtime Output
 -> Raw Evidence
 -> Normalize / Atomic Extraction / Object Linking
 -> Work Record projection and/or Knowledge Candidate
 -> Staging
 -> Permission / Provenance / Conflict / Review / Verification
 -> Acceptance
 -> Canonical Writer
 -> Canonical Knowledge
 -> Permission-aware Retrieval
 -> Context Budget / Bounded Retrieval
 -> Answer / Action
 -> Usage / Feedback Evidence
 -> Lifecycle / Re-evaluation
```

## 4. Personal/employee knowledge decision

Do **not** deploy one AI Core per employee.

Normal employee:

```text
Outlook / Teams / Jira / Web / Documents
 -> Evidence Hub
 -> Object-centric Activity / Work Correlation
 -> Work Record
 -> Closeout only when needed
 -> Knowledge Distillation
 -> PERSONAL / TEAM / COMPANY / CLIENT candidate
```

Power user using Codex/CC/Gemini only produces richer evidence into the same contracts.

Important prior art:

- OpenChronicle: timeline/session/reducer/idempotent rebuild patterns.
- DayTrail: activity-to-task correlation suggestions.
- OCEL: object-centric event model; one event can relate to Jira, client, order, user, project simultaneously.
- Microsoft Graph: Outlook/Teams/Calendar delta/change-notification ingestion.

## 5. Current priority rule

Never copy AI Core priority into this repo.

Formal rule:

> Shared Research, Independent Product Priority.

Every shared research item may have:

- `AI Core Priority`
- `Knowledge SaaS Priority`
- `Priority Rationale`

Company product priority is based on enterprise security, correctness, business value, product differentiation, operational cost, SLA, scale and commercial value.

## 6. P0 truth/security lane

- Permission-before-Retrieval
- Managed Policy Floor
- Evidence -> Candidate -> Canonical
- Raw/derived separation
- Provenance / source traceability
- Review / Approval
- Canonical Single Writer
- Conflict / Supersession
- Verification honesty
- Evaluation failure -> correction -> re-evaluation
- Minimum tenant/token/cost telemetry needed to prevent blind SaaS economics

## 7. P1 leverage/platform lane

- Context Budget Contract
- Bounded Retrieval
- Retrieval routing/filtering
- Config Scope / Precedence
- External Capability / Source Admission
- Source Freshness / Knowledge Lifecycle
- Personal/Team/Company scope
- Outlook/Teams/Jira passive evidence ingestion
- Repository Intelligence (formal product capability, no longer parked due to AI Core)
- Multi-Agent Evaluation (not runtime)
- Version/Compatibility Governance
- Reviewer/Impact Graph UI
- Full telemetry/usage/cost analytics

## 8. Product capability level model

All SaaS capabilities are complete capabilities and support depth levels.

Shared language:

- L1 Foundation
- L2 Automation
- L3 Intelligence
- L4 Autonomy

However customers can mix levels:

```text
Retrieval L3
Permission L4
Evaluation L2
Personal Knowledge L1
Knowledge Graph L2
```

They may also have scope overrides:

```text
PM Team: Personal Knowledge L3
Sales: Personal Knowledge L1
Client-A workspace: external models DENY
```

Do not confuse commercial levels with engineering maturity or architecture priority.

## 9. Prior-art policy

Before important custom implementation:

```text
Problem
 -> Existing seam
 -> Prior-art scan
 -> Semantic / authority diff
 -> Reuse tests/failure cases
 -> Reuse algorithm
 -> Adapt implementation
 -> Dependency only if justified
 -> Custom delta last
```

Required implementation-card fields:

- Prior Art
- Reuse Candidate
- Absorb
- Do Not Absorb
- License
- Existing Seam
- Why Custom Code Is Still Needed

If the final question cannot be answered, do not immediately write custom code.

## 10. Known donor map highlights

- Docling — MIT — primary structured document parsing donor.
- Unstructured — Apache-2.0 — partition/ingestion fallback donor.
- MarkItDown — Microsoft — lightweight LLM-friendly Markdown conversion donor; compare against Docling/Unstructured by capability level.
- OpenFGA — Apache-2.0 — fine-grained auth engine / RAG pre-filter donor; not permission authority.
- Qdrant — Apache-2.0 — payload-filtered / hybrid retrieval execution; not knowledge truth.
- DeepEval — Apache-2.0 — machine evaluation framework; result is evidence, not approval.
- OTel GenAI semantic conventions — telemetry vocabulary/projection.
- Microsoft Graph / Teams SDK — Outlook/Teams/Calendar connectors.
- Slack Bolt — Slack connector plumbing.
- GraphRAG — context assembly / graph/retrieval engineering donor; not canonical KB.
- OpenChronicle — activity timeline/session/reducer donor.
- DayTrail — work correlation/link suggestion donor.
- OCEL — object-centric event model reference.
- PM4Py — strong OCEL/process-mining reference but AGPL; reference/test donor unless licensing decision allows.
- ActivityWatch — local activity donor, MPL-2.0; optional and not MVP default.
- MyContext — highly relevant architecture reference but ELv2: reference/teardown only for SaaS.
- Munder Difflin — single-committer/failure patterns donor for AI Core/runtime; only single-authoritative-writer principle applies here.
- OpenAI Codex — context compaction, memory/evidence engineering and skill packaging donor; never import its runtime authority.
- CodeNib / CodeWiki / LSP / Lanser — repository intelligence donors.

## 11. Immediate next work

Do not start coding before auditing current architecture/backlog against:

`ALREADY_EXISTS / PARTIAL / MISSING / DONOR_AVAILABLE / CUSTOM_CODE_REQUIRED / SHOULD_NOT_ADOPT`.

Then build MVP cards around exact donor/file/test/license + only the organizational custom delta.
