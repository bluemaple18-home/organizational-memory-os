# Architecture Constitution

This document defines the non-negotiable architecture invariants for Organizational Memory OS / Knowledge SaaS.

## A. Truth boundaries

### A1. Evidence Truth

`Evidence != Knowledge.`

Outlook email, Teams chat, Slack message, Jira ticket, document content, user action, agent output, runtime receipt, automation output and LLM summary are evidence first.

Raw evidence and derived interpretation are separated:

```text
Immutable / retained Evidence
 -> Derived Interpretation
 -> Knowledge Candidate
 -> Reviewed Knowledge
 -> Canonical Knowledge
```

Knowledge can update, supersede, reclassify, archive, and rebuild views. Raw evidence must not be rewritten by downstream knowledge changes.

### A2. Knowledge Truth

`Candidate != Canonical.`

Candidate creation does not grant publish authority. Canonical knowledge must pass required permission, conflict, verification and acceptance gates.

### A3. Mutation Truth

`Proposal != Canonical Write.`

Importer, extractor, resident agent, reviewer AI, human editor, evaluation repair and migration jobs produce candidates/mutation proposals. They must not independently mutate canonical knowledge.

Use a **Single Authoritative Writer Per Canonical Knowledge Resource**. Reuse an existing promotion/write path if present; do not introduce a second broker/writer system.

### A4. Permission Truth

`Permission-before-Retrieval.`

Forbidden:

```text
Search whole company
 -> retrieve confidential atom
 -> put in model context
 -> tell model not to reveal it
```

Required:

```text
Identity
 -> Role / Team / Group
 -> Knowledge Scope
 -> Capability
 -> Managed Policy Floor
 -> Authorized Retrieval Space
 -> Vector / Graph / Keyword Retrieval
 -> Context
 -> LLM
```

The LLM is never the authorization boundary.

### A5. Verification Truth

`Execution != Verification != Acceptance.`

Use distinct dimensions:

- execution status
- verification status
- acceptance status

Verification status vocabulary:

- PASS
- FAIL
- PARTIAL
- NOT_RUN
- STATIC_ONLY

Missing verification evidence never implies PASS.

If 20 required cases exist and only 13 are executed, aggregate verification is PARTIAL, not PASS.

### A6. Acceptance Truth

Verification success does not grant acceptance/publish authority.

Acceptance statuses may include:

- PENDING
- ACCEPTED
- REJECTED
- BLOCKED

Only proposals satisfying acceptance requirements may enter the canonical writer.

### A7. Chronology Truth

Evidence chronology is immutable. Evidence added after an answer/evaluation cannot be represented as evidence used before it existed.

Receipts should preserve:

- evidence refs actually used
- evidence snapshot time
- generated_at
- verification_started_at
- verification_completed_at
- accepted_at
- accepted_by

New evidence may trigger re-evaluation; it does not rewrite historical receipts.

## B. Knowledge vs Procedure / Skill

Knowledge answers **what is true / what we know**.

Procedure / Skill answers **how to act**.

Keep them separate and connect by relationships.

```text
Evidence
 -> Knowledge
 -> Repeated validated pattern
 -> Skill Candidate
 -> Validation
 -> Human / Policy Review
 -> Published Skill
```

Published skills should carry:

- trigger
- inputs
- procedure
- expected output
- verification
- failure path
- permissions
- version
- owner
- provenance

An AI-discovered pattern does not become a production skill automatically.

## C. Risk / Complexity / Uncertainty

Do not collapse them into one score.

- Complexity -> processing depth / model / retrieval depth.
- Risk -> verification requirement.
- Uncertainty -> additional evidence, counter-evidence, independent review or human escalation.

A low-complexity request can be high-risk.

## D. Scope model

Personal knowledge does not require a separate AI Core instance.

Shared engine, different scopes:

- PERSONAL
- TEAM
- DEPARTMENT
- COMPANY
- CLIENT
- PROJECT / WORKSPACE where needed

Scope promotion is a governed proposal, not an automatic copy.

## E. Product / engineering separation

Three dimensions must never be conflated:

1. Architecture priority: P0 / P1 / P2 / Trigger-based.
2. Delivery maturity: MVP / NEXT / NORTH STAR.
3. Commercial level: L1 / L2 / L3 / L4.

A capability can be P0 but only ship L1 in MVP.

## F. Donor boundary

Formal principle:

> Borrow the engineering, preserve the architecture.

Prefer absorbing:

1. failure cases
2. regression tests
3. algorithms
4. protocol patterns
5. adapter implementation
6. proven operational handling

Treat dependencies/storage/schema adoption carefully.

Do not import donor:

- canonical authority
- knowledge truth
- memory truth
- identity model
- permission authority
- task model
- lifecycle/FSM as product authority
- mutable runtime DB as canonical DB

## G. AI Core boundary

Formal rule:

> Shared Research, Independent Product Priority.

AI Core can share prior art, patterns, tests, failure handling and contracts. It cannot impose its single-developer resource limits, parked priorities, staffing assumptions, implementation depth, SaaS maturity or deployment constraints on this product.

AI Core is a research and engineering donor, not a product ceiling.
