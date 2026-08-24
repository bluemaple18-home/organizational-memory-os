# AI Core Boundary

## Formal principle

> AI Core is a research and engineering donor, not a product ceiling.
>
> Shared Research, Independent Architecture Fit, Independent Priority, Independent Implementation Depth.

AI Core is a personal development project. Organizational Memory OS / Knowledge SaaS is a company product.

They may share:

- prior art
- research
- architecture patterns
- contracts
- failure cases
- tests
- donor repositories
- lessons learned

They must not directly share by default:

- priority
- implementation depth
- staffing assumptions
- scalability assumptions
- product maturity
- SaaS tier assumptions
- deployment depth
- token/resource constraints
- parked/deferred decisions made for a single developer

## Bidirectional integration

AI Core -> Knowledge SaaS:

```text
AI Core Task / Execution
 -> Receipt / Evidence
 -> Knowledge SaaS Ingestion
 -> Candidate
 -> Review
 -> Canonical Knowledge
```

Knowledge SaaS -> AI Core:

```text
AI Core Task
 -> Identity / Permission
 -> Knowledge SaaS Retrieval
 -> Context Budget / Bounded Context
 -> Agent Execution
```

Do not create two canonical truths.

## Runtime boundary

AI Core owns/cares about:

- agent governance
- execution control
- runtime adapters
- execution receipts/evidence
- agent-team/runtime concerns
- skill/memory infrastructure used by agents

Knowledge SaaS owns/cares about:

- organizational evidence ingestion
- knowledge authority
- permission and scope
- review and acceptance
- knowledge lifecycle
- permission-aware retrieval
- context policy
- knowledge delivery
- tenant/commercial capability governance

## Priority examples

Repository Intelligence can be P2/deferred in AI Core due to existing CodeGraph and personal development sequencing while being P1 in Knowledge SaaS because engineering Q&A/repository ingestion is a formal product capability.

Telemetry may be late in AI Core while minimum tenant/token/cost telemetry is P0-minimum in SaaS because billing/margin/SLA/support depend on it.

Managed Policy Floor can be late in AI Core while P0 in SaaS because enterprise lower scopes must not expand denied authority.

Multi-Agent Runtime can remain deferred in both, while Multi-Agent Evaluation may be P1 in Knowledge SaaS.
