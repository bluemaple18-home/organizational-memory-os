# MVP and Priority

## Independent priority rule

Knowledge SaaS priority is determined by enterprise product fit, security, correctness, cost, scale, SLA, support, product differentiation and commercial value — not AI Core's personal-project sequencing.

## P0 — Truth / Security / Minimum SaaS Economics

- Evidence -> Candidate -> Canonical
- Raw/derived separation
- Provenance/source traceability
- Review/Approval
- Conflict/Supersession
- Canonical Single Writer
- Permission-before-Retrieval
- Managed Policy Floor
- Verification honesty and chronology
- Evaluation failure -> correction -> re-evaluation
- Minimum tenant/model/token/cost/error telemetry

## P1-A — Highest leverage platform work

- Context Budget Contract
- Bounded Retrieval
- Retrieval routing/filtering
- Config Scope/Precedence
- External Capability / Source Admission
- Freshness / Knowledge Lifecycle
- Personal/Team/Company/Client scope
- Outlook/Teams/Jira evidence ingestion
- entitlement / scope overrides

## P1-B — Important product capabilities

- Repository Intelligence / Code Intelligence
- Multi-Agent Evaluation
- Reviewer/Impact Graph UI
- Version/Compatibility Governance
- Knowledge/Procedure separation
- deeper telemetry/cost/SLA/product analytics

## P1/P2 — Automation dependent on product levels

- Knowledge -> Skill Candidate
- Skill validation/publishing
- Skill Runtime Governance once executable-skill levels ship
- OTel projection expansion

## Trigger-based / later

- Shared Blackboard
- advanced collaboration workspace

## P2/P3 expansion

- advanced free-form graph visualization
- achievement/engagement
- skill marketplace
- high-end cross-industry automation

## Explicit non-goal for now

Do not build a custom multi-agent runtime, mailbox server, wake daemon, PTY manager or agent-room subsystem for Knowledge SaaS Phase 1.

## MVP vertical slice

MVP should prove one real end-to-end enterprise flow rather than shallowly implementing every capability:

```text
Outlook / Teams / Jira / Documents
 -> Raw Evidence + Provenance
 -> Object Linking / Work Record and/or Candidate
 -> Knowledge Staging
 -> Permission / Conflict / Review / Verification
 -> Acceptance
 -> Canonical Writer
 -> Canonical Knowledge
 -> Permission-before-Retrieval
 -> Context Budget / Bounded Retrieval
 -> PM/RD Answer with Citation
 -> Machine + Human Evaluation
 -> Failure -> Correction -> Re-evaluation
```

## MVP can ship lower commercial levels

Architecture priority does not imply full commercial depth in MVP. Example:

- Permission = P0, ship safe L1/L2 first.
- Telemetry = P0-minimum, ship cost/usage baseline before advanced dashboards.
- Context Budget = P1, ship a bounded policy before adaptive L4 routing.
- Repository Intelligence = P1-B, may be NEXT depending on first tenant use case.

## MVP exit criteria

At least:

1. No candidate can bypass canonical writer gates.
2. Unauthorized atoms cannot enter retrieval context.
3. Every answer can cite/prove source/provenance at the required level.
4. Verification states preserve PARTIAL/NOT_RUN honestly.
5. Evaluation failures can route to correction and re-run.
6. Tenant/token/cost/error baseline is observable.
7. One real PM/RD use case operates end-to-end with production/staging separation.
