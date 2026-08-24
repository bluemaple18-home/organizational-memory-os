# SaaS Control Plane

## Purpose

Enterprise administrators/FDEs need to control:

- which capabilities a tenant has
- each capability's product level
- scope overrides by department/team/user/client/project
- who can use each capability
- managed policy floors
- usage/cost limits
- dependencies and compatibility

## Model

```text
Tenant
 -> Capability Portfolio
 -> Capability
    -> Enabled
    -> Default Level (L1-L4)
    -> Scope Overrides
    -> Advanced Sub-capability Overrides
    -> User/Group Entitlements
    -> Usage / Cost Limits
    -> Managed Policy Locks
    -> Dependency Requirements
    -> Compatibility Status
```

## Distinguish entitlement from knowledge permission

Capability entitlement answers: **may this tenant/user use this product capability?**

Knowledge permission answers: **may this identity access/use this specific knowledge/evidence?**

Do not collapse them.

Example:

```text
RD Team
Repository Intelligence = L3 enabled
but
Client-B repository scope = DENY
```

The capability is entitled while specific data remains inaccessible.

## Commercial flexibility

A tenant does not need one global level.

Example:

```text
Ingestion              L2
Personal Knowledge     L3
Permission             L4
Retrieval              L3
Evaluation              L2
Knowledge Graph         L1
Repository Intelligence L3
```

Scope override example:

```text
PM Team: Personal Knowledge L3
Sales: Personal Knowledge L1
Client-A Workspace: External AI DENY
```

## Managed policy floor

The Control Plane must show both requested and effective values when higher-level policy restricts a lower-level override.

Example:

```text
Organization external_ai = DENY
Department external_ai = ALLOW
Effective = DENY
Reason = organization managed policy
```

UI should expose source/decision trace, not just the final toggle.

## Dependency awareness

Capabilities/levels may depend on others. Example:

```text
Personal Knowledge L3
requires Evidence Core
requires Permission floor
requires Provenance
may require Microsoft Graph adapter
```

Control Plane should prevent impossible configurations and explain dependency consequences.

## Cost drivers

Commercial levels should align with real cost/complexity drivers such as:

- connector sync volume
- storage/retention
- embeddings
- LLM calls
- evaluation frequency
- graph processing
- number of users/scopes
- real-time vs batch processing
- model quality tier

Do not create arbitrary levels that do not correspond to product value/operational cost.

## Dashboard direction

Admin view should support at least:

```text
Company/Tenant
 -> capability list
 -> enabled/disabled
 -> current/default level
 -> scope/user overrides
 -> dependencies
 -> effective policy
 -> usage/cost summary
 -> compatibility/health
```

The Control Plane is a management projection; it must not become canonical knowledge truth or permission truth itself.
