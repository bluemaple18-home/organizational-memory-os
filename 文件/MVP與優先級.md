# MVP 與優先級

## 三個維度分離

1. 架構優先級：P0 / P1 / P2 / Trigger-based
2. 交付成熟度：MVP / NEXT / NORTH STAR
3. 商業能力等級：L1 / L2 / L3 / L4

三者不可混用。P0 不代表第一版要做到 L4；NORTH STAR 也不代表架構位置不需要先保留。

## MVP 來源範圍裁決

來源能力與實際交付批次不得混成同一件事：

- **Architecture Source Scope**：文件、Jira、Outlook、Teams 等來源都必須收斂到同一 Raw Evidence Contract。
- **First Delivery Tranche**：文件 + Jira。
- **Next Source Tranche**：Outlook + Teams。

因此 Microsoft 365 仍屬正式 architecture scope，但不與第一個 vertical slice 同時施工。

## MVP 垂直閉環

```text
文件 / Jira（第一交付批次）
Outlook / Teams（下一來源批次）
→ Raw Evidence + Provenance
→ Work Record / Candidate
→ Staging
→ Conflict / Review / Approval
→ Canonical Knowledge
→ Permission-before-Retrieval
→ Context Budget / Bounded Retrieval
→ PM/RD Answer + Citation
→ Machine/Human Evaluation
→ Failure → Correction → Re-evaluation
```

## P0：Truth / Security

- Permission-before-Retrieval
- Raw Evidence Contract
- Evidence → Candidate → Canonical Knowledge
- Raw Evidence / Derived separation
- Provenance / source traceability
- Canonical Knowledge Single Writer
- Immutable Governance Decision / Acceptance Audit Trail
- Conflict / Supersession
- Evaluation failure → correction → re-evaluation
- Managed Policy Floor
- Verification honesty：PARTIAL / NOT_RUN 不得視為 PASS
- Evidence chronology
- Permission / Retention / Deletion Contract
- Canonical direct-write audit
- 基本 SaaS telemetry：tenant、token、latency、cost、error

## P1-A：最大效能 / 成本 / 平台槓桿

- Context Budget Contract
- Bounded Retrieval
- Retrieval filtering / routing
- Source Freshness
- Knowledge Lifecycle
- Config Scope / Precedence
- External Capability Admission
- Document / Jira adapter mapping（第一交付批次）
- Outlook / Teams adapter mapping（下一來源批次）
- Personal / Team / Department / Company / Client scopes

## P1-B：正式產品競爭力

- Repository Intelligence / Code Intelligence
- Multi-Agent Evaluation（不是 Runtime）
- Reviewer Graph / Impact Navigator
- Version / Compatibility Governance
- Knowledge / Procedure separation
- Knowledge → Skill Candidate

## P2 / Trigger-based

- Advanced Knowledge Graph Exploration UI
- Achievement / Engagement
- Skill Marketplace
- Collaboration UI
- Shared Blackboard：只有真正出現多人/多 Agent 長時間共享工作空間需求才做
- Multi-Agent Runtime：目前不自建

## AI Core Priority 不傳遞

每個共享 research item 必須同時記錄：

- AI Core Priority
- Knowledge SaaS Priority
- Priority Rationale

AI Core P3 可以對 Knowledge SaaS 是 P0/P1；反之亦然。
