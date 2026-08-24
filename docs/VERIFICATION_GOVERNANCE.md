# Verification Governance

This document absorbs the useful verification primitives from coding/execution governance research without importing coding workflow/task semantics.

## Core separation

```text
EXECUTION != VERIFICATION != ACCEPTANCE
```

An agent successfully executing a query proves only execution. An evaluation completing proves only that evaluation work ran. A reviewer/policy decision determines acceptance.

## Status dimensions

### Execution
Product-specific values may vary, but keep execution separate from verification and acceptance.

### Verification
Use explicit truth-preserving states:

- PASS
- FAIL
- PARTIAL
- NOT_RUN
- STATIC_ONLY

Rules:

- Missing verification never implies PASS.
- If required verification is only partially executed, preserve PARTIAL.
- Do not collapse NOT_RUN into success.

### Acceptance
Suggested states:

- PENDING
- ACCEPTED
- REJECTED
- BLOCKED

Verification success does not automatically publish a candidate.

## Risk / Complexity / Uncertainty

Keep three independent axes:

```text
Complexity  -> processing/model/retrieval depth
Risk        -> verification requirement
Uncertainty -> extra evidence / counter-evidence / independent review / human escalation
```

Do not combine them into one opaque score.

## Verification Requirement

A Knowledge Operation should compile to required verification. Candidate fields may include:

- required_source_count
- required_authority
- required_freshness
- counter_evidence_required
- machine_eval_required
- human_review_required
- minimum_eval_coverage
- optional independent-review strategy

Then compare required verification with actual verification evidence.

Example:

```text
Required cases = 20
PASS = 13
NOT_RUN = 7
=> verification = PARTIAL
=> if full coverage is required, acceptance = BLOCKED
```

## Evidence chronology

A later-added evidence item cannot retroactively support an earlier answer/decision.

Receipts should snapshot:

- evidence refs used
- evidence snapshot time
- generated time
- verification start/end
- acceptance time/actor

New evidence can trigger a new verification receipt/revision proposal.

## Multi-Agent Evaluation

Multi-Agent Evaluation is a verification strategy, not a multi-agent runtime requirement.

```text
Evaluation Case
 -> Primary Answer
 -> Independent Reviewer
 -> Evidence Hunter
 -> Counter-evidence Reviewer
 -> Compare
 -> Conflict / confidence / verification evidence
```

Knowledge SaaS defines:

- role
- input scope
- expected output
- authority
- verification

Execution can use existing providers/runtimes (Codex, Claude, Gemini, standard APIs). Do not build mailbox, wake daemon, agent room or process manager merely to implement evaluation.

## Canonical writer gate

```text
Mutation Proposal
 + Permission satisfied
 + Verification requirements satisfied
 + Acceptance satisfied
 -> Canonical Writer
```

No producer/evaluator gets direct canonical write authority merely because its work completed successfully.
