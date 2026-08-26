# AI Core 邊界

## 正式原則

> AI Core 是研究與工程 donor，不是 Knowledge SaaS 的產品天花板。

> Shared Research, Independent Architecture Fit, Independent Priority, Independent Implementation Depth.

## 可以共享

- prior art
- research
- architecture patterns
- contracts
- failure cases
- tests
- donor repositories
- lessons learned

## 不得直接共享

- priority
- implementation depth
- staffing assumption
- scalability assumption
- product maturity
- SaaS tier
- deployment depth
- runtime authority

## Authority 分工

AI Core：Agent Governance、Execution Control、Runtime Adapter、Execution Evidence、Skill/Memory infrastructure。

Knowledge SaaS：Organizational Knowledge、Evidence Ingestion、Permission、Retrieval、Review、Lifecycle、Knowledge Delivery。

## Skill / Memory Authority

AI Core 的 Skill / Memory infrastructure 只可以作：

- donor / prior art
- richer Evidence Producer
- execution runtime / adapter
- receipt / telemetry producer

Knowledge SaaS 仍擁有：

- Published Skill identity
- Knowledge → Skill promotion authority
- tenant / scope permission
- version / compatibility / deprecation
- commercial Capability Level
- Canonical Knowledge 與 Procedure relationship

因此 AI Core skill、memory 或 execution receipt 都不能直接升為 Company Canonical Knowledge，也不能繞過 Knowledge SaaS 的 Acceptance / Single Writer。

## 雙向 Integration

```text
AI Core Execution
→ Receipt / Evidence
→ Knowledge SaaS Ingestion
→ Candidate
→ Review
→ Knowledge
```

以及：

```text
AI Core Task
→ Identity / Permission
→ Knowledge Retrieval
→ Bounded Context
→ Agent Execution
```

AI Core receipt 不等於 Knowledge；Knowledge SaaS 不接管 Agent Runtime。

## Priority reconciliation

共享能力要有：

```text
AI Core Priority
Knowledge SaaS Priority
Priority Rationale
```

例：Repository Intelligence 在 AI Core 可 P2，但 Knowledge SaaS 可 P1；Telemetry 在 AI Core 可晚做，但 SaaS minimum telemetry 可 P0。

## 不要把 AI Core Runtime 搬進來

一般員工不需要 Codex / Claude Code / Gemini CLI / full AI Core。Outlook、Teams、Jira、Web 等本來就是 Evidence Sources；進階 Agent 只是更高品質 Evidence Producer。
