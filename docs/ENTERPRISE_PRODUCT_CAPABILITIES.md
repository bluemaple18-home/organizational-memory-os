# Enterprise Product Capabilities Reconciliation

This file captures enterprise capabilities that must be prioritized independently from AI Core.

## Repository Intelligence / Code Intelligence

AI Core priority does not transfer. For Knowledge SaaS, repository intelligence can be a formal P1 product capability for GitHub/GitLab ingestion, RD knowledge, engineering Q&A, code impact analysis, architecture understanding and coding-agent context.

Target product shape:

```text
Git Repository
 -> Code Intelligence Ingestion Adapter
 -> Lexical View
 -> Structural View
 -> Dense View
 -> Hybrid Retrieval
 -> Developer Knowledge / Engineering Q&A
```

Prior art to reuse/teardown includes CodeNib, Google Code Wiki, PorunC/CodeWiki, FSoft-AI4Code/CodeWiki, LSP and Lanser-CLI. A Lite donor can seed lower commercial levels but is not the product ceiling.

## Knowledge Graph / Visualization

Separate graph semantics from graph UI.

Graph relationships may include:

- Knowledge -> Evidence
- Knowledge -> Source
- Knowledge -> Owner
- Knowledge -> Version
- Knowledge -> Conflict
- Knowledge -> Procedure
- Knowledge -> Answer citations
- Knowledge -> Impacted resources

Visualization is always a projection, not canonical truth.

Prioritize a **Reviewer / Impact Navigator** earlier than a purely decorative graph explorer. Reviewer UI should answer:

```text
Current Knowledge
 -> supporting evidence
 -> counter-evidence
 -> previous/superseding version
 -> procedures using it
 -> answers that cited it
 -> downstream impacted knowledge/resources
```

Advanced free-form graph exploration can remain later.

## Multi-Agent Evaluation

Multi-Agent Evaluation may be P1 even when Multi-Agent Runtime is not.

Knowledge SaaS owns an EvaluationStrategy contract with:

- roles
- input scopes
- expected outputs
- authority
- verification criteria

Providers/runtimes may be Codex, Claude, Gemini, API calls or other adapters. Do not build mailbox/wake/agent-room infrastructure for this.

## Telemetry / Usage / Cost

SaaS minimum telemetry may be P0-minimum because billing/margin/SLA/support require visibility.

Minimum:

- tenant
- capability
- provider/model
- input/output tokens
- retrieval latency
- LLM latency
- request status/error
- estimated cost

P1/full:

- knowledge hit rate
- citation rate
- retrieved/filtered chunks
- evaluation quality
- cost per successful answer
- cost per capability
- SLA/capacity metrics

Use OpenTelemetry/GenAI semantic conventions as projection vocabulary.

## External Capability / MCP Governance

Potential sources/capabilities:

- Google Drive
- Microsoft 365
- Outlook
- Teams
- Slack
- Jira
- Confluence
- GitHub/GitLab
- CRM/ERP
- internal APIs
- MCP servers

Admission should consider source identity/origin, declared capability, requested permissions, trust class and tenant policy before enabling adapters.

## Configuration Governance

Enterprise hierarchy can include Platform -> Organization -> Tenant -> Department -> Team -> User, plus Client/Project/Workspace. Effective configuration must preserve source, authority, precedence, managed locks and decision traces.

## Skill Runtime Governance

When commercial capability levels progress from procedure representation to executable skills, governance must extend:

```text
Candidate -> Validate -> Publish
 -> Install -> Enable -> Authorize -> Execute -> Observe -> Deprecate
```

Relevant metadata:

- skill_origin
- owner
- trust_class
- version
- tenant_scope
- enabled
- shell_allowed
- network_allowed
- external_write_allowed
- managed_lock
- runtime_compatibility

This becomes a required dependency of capability levels that execute skills; it need not be built before those levels exist.

## Version / Compatibility Governance

Track producer/consumer compatibility for connectors, runtimes, skills, MCP servers, models, embedding models and client agents.

Useful fields/statuses:

- minimum_supported
- maximum_tested
- producer_version
- consumer_version
- SUPPORTED
- DEGRADED
- UNKNOWN
- UNSUPPORTED

This supports rollout, SLA and customer support.

## Prior-art freshness

Do not copy AI Core's scan cadence. Use risk-based freshness:

- security-critical dependency: high frequency
- core runtime/connector: medium
- research donor: low
- reference-only donor: very low

Cadence is an operational policy, not a fixed architecture rule.

## Shared Blackboard

Remain trigger-based. Do not implement merely because the company has more resources. Require real evidence of long-running shared hypotheses/blockers/multi-agent or human-agent collaborative workspaces.
