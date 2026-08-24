# Open Questions and Locked Decisions

## Locked decisions

### Product identity
- Company product / SaaS. Not constrained by AI Core single-developer sequencing.
- Knowledge is first capability, not final product ceiling.

### Truth model
- Evidence != Knowledge.
- Candidate != Canonical.
- Proposal != Canonical write.
- Execution != Verification != Acceptance.
- Knowledge != Procedure / Skill.

### Personal/employee model
- General employees do not need Codex/CC/Gemini/full AI Core.
- Outlook/Teams/Jira/Documents/Web can act as evidence sources.
- One shared platform with PERSONAL/TEAM/DEPARTMENT/COMPANY/CLIENT scopes.
- Power-user runtimes are advanced evidence producers only.

### Retrieval/security
- Permission-before-Retrieval is mandatory.
- LLM is never authorization boundary.
- Managed Policy Floor: lower scope may restrict but cannot expand denied authority.

### SaaS model
- Every customer-facing capability has levels L1-L4.
- Customers may mix levels per capability and override by scope/team/client.
- Security/correctness floor is not an optional paid feature.

### Prior art
- Prior-art first; absorb, don't copy.
- Card must justify custom code.
- AI Core is research donor, not product ceiling.

## Open product-contract questions

These are bounded decisions, not reasons to redesign the system.

### 1. WorkRecord correlation thresholds
Need final confidence policy for deterministic link vs embedding/LLM vs human clarification.

Base ordering currently favored:
1. explicit business IDs/direct links
2. business objects such as Jira/order/client/project
3. thread identity
4. document/URL/repository links
5. participants/team
6. time proximity
7. semantic similarity

### 2. Raw evidence payload retention
Evidence identity/provenance should persist; full payload retention may be tenant/source-policy dependent. Need product retention matrix for mail/chat/transcript/attachment/document/runtime evidence.

### 3. Scope broadening authority
Need exact rules for promoting a restricted evidence-derived candidate into broader TEAM/COMPANY knowledge while preventing source ACL leakage.

### 4. Closeout policy
Need initial heuristics/thresholds for email/chat-centric work without explicit Jira close. AI may propose closeout but should not silently assert completion.

### 5. MVP knowledge taxonomy
Likely minimal set: FACT / DECISION / FAILURE / KNOW_HOW plus separate PROCEDURE_CANDIDATE. Product/industry/role/client likely facets. Confirm before schema freeze.

### 6. Existing canonical write-path audit
Before implementing a new writer, inspect whether current resident agent/human editor/import/migration/evaluation repair paths can bypass promotion. Reuse a unified existing writer if one exists.

### 7. Commercial level definitions
L1-L4 shared semantics are locked, but each capability needs its own cumulative level matrix, dependency graph, cost drivers and entitlement rules.

## Deferred until evidence exists

- Shared Blackboard
- custom Multi-Agent Runtime
- mailbox/wake/process manager
- achievement system as MVP requirement
- marketplace
- advanced free-form graph explorer

These may be added later based on product demand, not donor enthusiasm.
