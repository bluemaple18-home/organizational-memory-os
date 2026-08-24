# SaaS Capability Levels

## Product rule

Every customer-facing capability is a complete capability with depth levels. Do not only differentiate pricing by feature on/off.

Shared language:

- **L1 Foundation** — complete basic capability, more manual/control-oriented.
- **L2 Automation** — automates repetitive work.
- **L3 Intelligence** — cross-source reasoning, quality judgment, proactive recommendations.
- **L4 Autonomy** — continuous monitoring/proposals/closed-loop behavior, always bounded by permission and approval gates.

Levels are cumulative by default: L3 should normally include L1+L2 unless a capability has an explicit exception.

## Customer flexibility

A tenant may mix levels:

```text
Ingestion              L2
Personal Knowledge     L3
Governance             L2
Permission             L4
Retrieval               L3
Evaluation              L2
Knowledge Graph         L1
Repository Intelligence L3
```

The same capability may have scope overrides:

```text
PM Team   Personal Knowledge = L3
RD Team   Repository Intelligence = L4
Sales     Personal Knowledge = L1
Client-A  External Model = DENY
```

Advanced overrides may tune sub-capabilities without forcing the whole tenant to one level.

## Control plane model

```text
Tenant
 -> Capability Portfolio
 -> Capability
    -> Enabled
    -> Default Level
    -> Scope Overrides
    -> Optional Sub-capability Overrides
    -> Usage/limits
    -> Policy / managed lock
```

## Examples

### Ingestion

- L1: manual/basic document upload and parse
- L2: scheduled/batch source sync
- L3: source-change detection, freshness, routing/fallback
- L4: policy-driven discovery/admission and proactive source maintenance

### Personal Knowledge

- L1: evidence capture -> knowledge with explicit/manual confirmation
- L2: automatic Outlook/Teams/Jira evidence collection
- L3: cross-source object linking/work correlation/closeout assistance
- L4: continuous distillation, missing-evidence prompts, scope-promotion proposals

### Permission

Security floor is mandatory for every level. Higher levels add granularity/management, not weaker safety.

- L1: basic role/group/scope access
- L2: team/client/capability-aware policies
- L3: atom-level policy, inheritance, advanced approval
- L4: dynamic managed policy and enterprise governance controls

### Retrieval

- L1: basic semantic/keyword retrieval
- L2: hybrid retrieval + reranking
- L3: context budget + authority/freshness/source routing
- L4: adaptive graph/multi-source retrieval and learning

### Evaluation

- L1: basic golden-question suite
- L2: machine + human evaluation
- L3: failure classification + regression + counter-evidence strategies
- L4: continuous evaluation and repair proposals

### Governance

- L1: manual review/approval
- L2: duplicate/conflict/provenance assistance
- L3: freshness/lifecycle/supersession workflows
- L4: proactive governance recommendations

### Knowledge Graph

- L1: basic relationships
- L2: entity/topic/source/version relationships
- L3: temporal/evidence/impact graph
- L4: advanced relationship discovery/reasoning

### Knowledge -> Skill

- L1: procedure representation
- L2: skill candidate + validation/publish
- L3: install/enable/authorize/execute/observe governance
- L4: repeated-pattern discovery and governed promotion proposals

## Safety floor

Do not monetize by weakening correctness/security. These are platform floor capabilities:

- tenant isolation
- minimum Permission-before-Retrieval
- provenance floor
- canonical single-writer discipline
- audit minimum

Paid levels can increase granularity, retention, workflow sophistication, automation and analytics.

## Three orthogonal dimensions

Do not mix:

- Architecture Priority: P0/P1/P2
- Delivery Maturity: MVP/NEXT/NORTH STAR
- Commercial Capability Level: L1-L4

A P0 capability may initially ship L1 in MVP while deeper levels arrive later.
