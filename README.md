# Organizational Memory OS

Enterprise Knowledge SaaS / Organizational Memory platform.

> Evidence-first organizational knowledge, governance, retrieval, and capability platform.

This repository is the canonical handoff/workspace for the company product architecture discussed to date. It is **not** an AI Core clone and must not inherit AI Core's single-developer constraints, implementation depth, parked priorities, or runtime assumptions.

## Core principles

- **Shared Research, Independent Product Priority.** AI Core is a research/engineering donor, not a product ceiling.
- **Prior-art first. Absorb, don't copy.** Reuse mature engineering, tests, failure handling, adapters and algorithms before writing custom code; preserve Organizational Memory OS authority.
- **Borrow the engineering, preserve the architecture.** Donors must never replace canonical knowledge authority, identity, permission authority, lifecycle, task model, or mutable runtime truth.
- **Evidence != Knowledge.** Teams, Outlook, Slack, Jira, documents, user activity, agent output and execution receipts are evidence first.
- **Candidate != Canonical.** Only reviewed/accepted mutations may reach canonical knowledge.
- **Permission before Retrieval.** Unauthorized content must never enter retrieval/context and must not be filtered only after the LLM sees it.
- **Execution != Verification != Acceptance.** Doing work, verifying it, and approving it are different truths.
- **Knowledge != Procedure/Skill.** Knowing something and knowing how to do something are different resources connected by relationships.
- **One platform, many scopes.** PERSONAL / TEAM / DEPARTMENT / COMPANY / CLIENT are scopes, not separate AI Core installations.
- **Capability + Level + Scope.** Every SaaS capability is a complete capability with depth levels; customers can mix levels across capabilities and scopes.

## Canonical Knowledge Spine

```text
Evidence Sources
PDF / Word / Web / Outlook / Teams / Slack / LINE / Jira
Human Upload / Agent Runtime / System Activity / Git repositories
        |
        v
Raw Evidence
        |
        v
Normalize
        |
        v
Atomic Extraction / Object Linking
        |
        v
Work Record Projection / Knowledge Candidate
        |
        v
Knowledge Staging
        |
        +--> Permission / Provenance / Conflict / Scope
        |
        +--> AI Review / Human Review / Verification
        |
        v
Acceptance Decision
        |
        v
Canonical Knowledge Writer
        |
        v
Canonical Knowledge
        +--> Knowledge Graph / Relationships
        +--> Procedure / Skill relationships
        +--> Lifecycle / Version / Supersession
        |
        v
Identity / Permission / Managed Policy Floor
        |
        v
Authorized Retrieval Space
        |
        v
Intent / Domain Classification
        |
        v
Context Budget
        |
        v
Bounded Retrieval
        |
        v
Answer / Action
        |
        v
Usage / Feedback / Evaluation Evidence
        |
        +---------------------------> Re-evaluation / Revision Candidate
```

## Read first

Start with [`START_HERE_FOR_NEXT_MACHINE.md`](START_HERE_FOR_NEXT_MACHINE.md).

Then read:

1. [`docs/ARCHITECTURE_CONSTITUTION.md`](docs/ARCHITECTURE_CONSTITUTION.md)
2. [`docs/CANONICAL_SPINE.md`](docs/CANONICAL_SPINE.md)
3. [`docs/MVP_AND_PRIORITY.md`](docs/MVP_AND_PRIORITY.md)
4. [`docs/PERSONAL_EVIDENCE_AND_WORK_RECORD.md`](docs/PERSONAL_EVIDENCE_AND_WORK_RECORD.md)
5. [`docs/PERMISSION_POLICY_CONFIG.md`](docs/PERMISSION_POLICY_CONFIG.md)
6. [`docs/CONTEXT_RETRIEVAL.md`](docs/CONTEXT_RETRIEVAL.md)
7. [`docs/VERIFICATION_GOVERNANCE.md`](docs/VERIFICATION_GOVERNANCE.md)
8. [`docs/SAAS_CAPABILITY_LEVELS.md`](docs/SAAS_CAPABILITY_LEVELS.md)
9. [`docs/PRIOR_ART_DONOR_MAP.md`](docs/PRIOR_ART_DONOR_MAP.md)
10. [`docs/BACKLOG_RECONCILIATION.md`](docs/BACKLOG_RECONCILIATION.md)
11. [`docs/AI_CORE_BOUNDARY.md`](docs/AI_CORE_BOUNDARY.md)
12. [`docs/DO_NOT_REIMPLEMENT.md`](docs/DO_NOT_REIMPLEMENT.md)

## Current MVP north star

The MVP is a vertical slice, not the whole product:

```text
Outlook / Teams / Jira / Documents
        v
Raw Evidence + Provenance
        v
Work Record / Candidate
        v
Staging
        v
Review / Conflict / Approval
        v
Canonical Knowledge
        v
Permission-before-Retrieval
        v
Context Budget + Bounded Retrieval
        v
PM/RD Answer with Citation
        v
Machine/Human Evaluation
        v
Failure -> Correction -> Re-evaluation
```

Advanced graph UI, achievement systems, skill marketplace, blackboard and multi-agent runtime are not MVP blockers.

## Status dimensions must not be mixed

- **Architecture priority:** P0 / P1 / P2 / Trigger-based
- **Delivery maturity:** MVP / NEXT / NORTH STAR
- **Commercial capability level:** L1 / L2 / L3 / L4

A capability can be P0 while only shipping an L1 MVP initially.
