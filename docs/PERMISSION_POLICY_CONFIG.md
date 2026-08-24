# Permission, Policy and Configuration Governance

## Permission-before-Retrieval

Architecture invariant:

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

Never search the whole company and rely on the LLM to hide confidential content.

## Capability vocabulary

At minimum consider:

- discover
- retrieve
- answer-with
- view-source
- upload
- propose-change
- approve
- publish
- export
- admin

## Atom-level permission

Do not stop at document ACL. A single Jira ticket/email/document may contain atoms with different sensitivity.

Potential atom permission metadata:

- tenant_id
- source_acl
- effective_scope
- role_scope
- team_scope
- user_scope
- client/project scope
- sensitivity
- sharing_policy

## Permission inheritance

```text
Source ACL
 -> Evidence ACL
 -> Candidate Scope
 -> Promotion Authority
 -> Canonical Permission
```

Derivation cannot silently broaden access. A private Teams chat producing a generally useful product fact remains restricted by default; broadening to COMPANY requires an authorized promotion/review decision.

## Managed Policy Floor

Enterprise policy is not simple “lower scope wins”.

Scopes may include:

```text
Platform
 -> Organization
 -> Tenant
 -> Department
 -> Team
 -> User
```

and optionally:

- Client
- Project
- Workspace

Hard rule:

> Lower scopes may restrict but cannot expand authority that an upper scope denies.

Examples:

```text
Company: external_ai = DENY
Department: external_ai = ALLOW
Effective: DENY
```

```text
Company: document_export = ALLOW
Department: document_export = DENY
Effective: DENY
```

Apply policy floors to:

- external model access
- export
- connector access
- MCP/external capability execution
- network access
- external writes
- skill execution
- knowledge visibility

## Configuration precedence

Configuration governance is a P1 architecture primitive for enterprise SaaS.

Effective configuration should retain:

- authority
- allowed scope
- merge semantics
- override direction
- managed lock
- effective value
- source
- decision trace

Do not equate configuration precedence with authorization precedence.

## External Capability / Source Admission

Enterprise connectors and external capabilities should pass an admission boundary:

```text
External Source / MCP / API
 -> Identity / Origin
 -> Declared Capability
 -> Permissions Requested
 -> Trust Class
 -> Tenant Policy
 -> Admission Decision
 -> Enabled Adapter
```

This is not an AI Core runtime-admission subsystem; it is the Knowledge SaaS connector/capability governance seam.

## Prior art

### OpenFGA — Apache-2.0
Strong donor for fine-grained authorization engine and RAG pre-filter/ListObjects patterns.

Absorb/adapt:

- relationship-based authorization mechanics
- Check/ListObjects
- authorization model tests
- SDK/server plumbing

Do not absorb:

- OpenFGA tuple store as organizational permission authority
- donor object model as canonical product semantics

Our custom delta:

- organization/tenant/team/client scope semantics
- capabilities
- evidence ACL inheritance
- atom-level mapping
- policy floors

### Qdrant — Apache-2.0
Use payload filters / tenant partition / hybrid retrieval as authorized retrieval execution. Qdrant is not permission authority or knowledge truth.

### OPA / Cerbos
Comparative donors for policy evaluation / ABAC/resource policy. Do not install multiple policy engines without a semantic need.
