# Canonical Knowledge Spine

This is the canonical logical spine. Extend by adapters/capabilities; do not create parallel truth pipelines.

```text
Evidence Sources
  Files / Web / Outlook / Teams / Slack / LINE / Jira / Git
  Human Upload / Agent Runtime / System Activity
        |
        v
Raw Evidence
  immutable/retained identity + provenance
        |
        v
Normalize / Atomic Extraction / Object Linking
        |
        +--> Work Record Projection (work memory)
        |
        v
Knowledge Candidate / Mutation Proposal
        |
        v
Knowledge Staging
        |
        +--> Permission / Scope
        +--> Provenance
        +--> Duplicate / Conflict / Supersession
        +--> Verification Requirement
        +--> AI Review / Human Review
        |
        v
Verification Evidence
        |
        v
Acceptance Decision
        |
        v
Canonical Knowledge Writer
        |
        v
Canonical Knowledge
        +--> Evidence relationships
        +--> Source / Owner / Version / Conflict
        +--> Knowledge Graph projection
        +--> Procedure / Skill relationships
        +--> Lifecycle / Freshness / Supersession
        |
        v
Identity / Permission / Managed Policy Floor
        |
        v
Authorized Retrieval Space
        |
        v
Intent / Domain / Source Routing
        |
        v
Context Budget
        |
        v
Bounded Retrieval
        |
        v
Answer / Action / Agent Context
        |
        v
Usage / Feedback / Evaluation Evidence
        |
        +--> failure classification / correction
        +--> lifecycle/freshness signals
        +--> revision candidate / re-evaluation
```

## Evidence record requirements

At minimum preserve:

- evidence_id
- source/source_type
- source identity/reference
- timestamp(s)
- producer
- tenant/scope
- source ACL snapshot/reference
- content hash/reference
- extraction version
- model/rule version where applicable
- provenance chain
- source state (active/changed/deleted/unavailable)

Full payload retention may be policy-driven; evidence identity/provenance should remain stable enough to audit derivation.

## Canonical mutation path

All producers create candidates/proposals. Only the authoritative writer mutates canonical resources after gates are satisfied.

```text
Producer
 -> Candidate / Mutation Proposal
 -> Permission / Conflict / Verification / Acceptance
 -> Canonical Writer
 -> New canonical version + audit/provenance
```

## Outline boundary

Outline is treated primarily as the production knowledge consumption/collaboration surface — similar to a company Notion/wiki. Candidate and conflict/test material belongs in staging or clearly isolated non-production areas so normal retrieval cannot mistake it for approved knowledge.

## Lifecycle

Enterprise knowledge is not memory cache eviction.

Suggested lifecycle:

```text
CANDIDATE
 -> ACTIVE
 -> LOW_USAGE
 -> STALE_CANDIDATE
 -> REVIEW_REQUIRED
 -> SUPERSEDED / ARCHIVED
```

Usage/recency may adjust retrieval/context priority, trigger review, or recommend archive; usage alone has no delete authority.
