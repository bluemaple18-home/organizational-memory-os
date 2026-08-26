# DeepSeek Harness 整合裁決與施工切片

日期：2026-08-26

狀態：`ARCHITECTURE_DECISION / DONOR_PINNED / NOT_MVP_BLOCKER / IMPLEMENTATION_DEFERRED`

## 1. 最終定位

DeepSeek Harness（DSH）不是 Organizational Memory OS 的第九顆 Minimal Core，也不是 Knowledge、Permission、Acceptance 或 Canonical Writer。

正式位置：

```text
Organizational Memory OS
= Domain / Knowledge Authority

AI Core
= Mission / Work / Runtime Routing / Acceptance Control

DeepSeek Harness
= Optional Agent Runtime / Executor Provider
```

核心原則：

> Everything executable may be a plugin；truth and authority boundaries must not be ordinary plugins.

可插拔：Model、Tool、Sandbox、Session implementation、Workflow、Subagent、UI、Telemetry exporter。

不可交給 DSH plugin 任意替換：Tenant Identity、Managed Policy Floor、Permission-before-Retrieval、Raw Evidence identity、Verification Requirement、Acceptance、Canonical Single Writer。

## 2. Source pin

```text
Repository: deepseek-ai/deepseek-harness
Pinned commit: b150a551b8d465e31e418e1b2eaf5e79bbb7d28e
CLI package: @deepseek-ai/dsh@0.1.1-rc.2
License: MIT main repo / CLI
Maturity: Developer Preview; compatibility-breaking changes expected
Node: ^22.19.0 || >=24.0.0
```

第三方 product provider、SDK、platform payload、MCP/plugin 仍依各自 license/terms，不因 DSH 主 Repo 為 MIT 就自動視為 MIT。

## 3. 與八顆 Minimal Core 的關係

| Minimal Core | DSH relationship | Authority decision |
|---|---|---|
| Source | DSH run/session/tool/subagent/workflow 可成為 Agent Runtime Evidence Source | Source Adapter only |
| Evidence | SessionEvent、process receipt、tool result、usage、timing可映射 RawEvidence | 高價值 donor；需 retention/redaction |
| Object / Work Context | Session/Turn/Step/Tool/Run 可連 Mission/Task/Repo/Project | Object links / projections only |
| Knowledge | DSH不擁有 Candidate/Canonical/Supersession | no authority |
| Governance | DSH permission/sandbox 是 execution governance | 不取代 Knowledge Governance |
| Projection | Trajectory/Telemetry/UI 是 runtime projection | rebuildable / inspectable |
| Retrieval Policy | DSH只能消費已授權 bounded context | no permission enforcement authority |
| Verification / Evaluation | Workflow/subagent可執行獨立核對 | executor only；不得做 Acceptance |

## 4. 三個正式 integration seam

### Seam A — Runtime Provider

由 AI Core 承接：

```text
Knowledge SaaS authorized task/context
        ↓
AI Core ExecutionContract / task card
        ↓
AI Core Execution Provider Extension
        ↓
DeepSeek Harness headless one-shot adapter
        ↓
DSH runtime
```

Knowledge SaaS 不直接管理 DSH Session、Profile、Agent Team 或 credential。

### Seam B — Execution Evidence

```text
DSH process / sanitized SessionEvent
        ↓
AI Core Harness Run Record / RunReceipt
        ↓
Organizational Memory Source Adapter
        ↓
RawEvidence(source_type=AGENT_RUNTIME)
        ↓
Object Linking
Mission / Task / Repo / Run / Session / Tool
        ↓
AnswerTrace / EvaluationReceipt projection
```

DSH event 或 final answer仍只是 Evidence：

```text
RUNTIME_COMPLETED != VERIFIED != ACCEPTED != CANONICAL_KNOWLEDGE
```

### Seam C — External Capability Admission

每個 DSH Profile / Bundle / Plugin / product subagent 必須先形成 Capability Manifest：

```yaml
origin:
  repository: deepseek-ai/deepseek-harness
  commit: b150a551b8d465e31e418e1b2eaf5e79bbb7d28e
  package: "@deepseek-ai/dsh"
  version: "0.1.1-rc.2"
license:
  main: MIT
  third_party_review_required: true
runtime:
  node_requirement: "^22.19.0 || >=24.0.0"
composition:
  profile: string
  bundles: []
  patch_digest: string
capabilities:
  filesystem: read|workspace_write|broader
  shell: bool
  network: bool
  external_mcp: bool
  subagents: []
  workflow_script: bool
  agent_teams: bool
  telemetry_mode: DISABLED|LOCAL_REDACTED|EXTERNAL
permissions:
  requested_scopes: []
  credential_route: string
  sandbox_backend: string
policy:
  tenant_scope: string
  managed_lock: bool
  admission_status: PENDING|ADMITTED|BLOCKED|REVOKED
compatibility:
  minimum_supported: string
  maximum_tested: string
```

Manifest 是 admission input，不是 Knowledge truth。

## 5. 第一版 runtime profile

只允許最小 profile：

```text
HEADLESS
ONE_SHOT
ASSIGNED_WORKTREE_ONLY
TELEMETRY_DISABLED
NO_WEB_UI
NO_EXTERNAL_MCP
NO_AGENT_TEAMS
NO_CREATOR_AUTO_MOUNT
NO_DYNAMIC_WORKFLOW
NO_NESTED_CODEX_OR_CLAUDE_SUBAGENTS
```

原因：AI Core 已負責 runtime routing。讓 DSH 再自行叫 Codex／Claude Code會產生隱藏 nested routing、credential、quota、recursion、cost與 acceptance ownership。

## 6. Evidence mapping

### 6.1 第一階段：process receipt

| Source fact | RawEvidence / AnswerTrace mapping |
|---|---|
| AI Core run id | `source_identity` / `run_ref` |
| provider/CLI/profile/version | producer / parser-runtime metadata |
| task / ExecutionContract ref | object link / provenance input |
| start/completion/exit | chronology / execution status |
| stdout result ref | payload reference |
| stderr log ref | failure evidence |
| changed paths / candidate commit | artifact refs |
| verification state | EvaluationReceipt；不得由 exit 0推導 PASS |

### 6.2 第二階段：sanitized event bridge

只有 process receipt不足以回答 tool/provenance/usage時才施工。

預設白名單：

```text
session id
seq / time / event type
turn / step
provider / model
usage
tool name / outcome
terminal reason
subagent relation
content digest / payload ref
```

預設禁止：

- system prompt全文
- user/assistant全文
- tool arguments/results全文
- file content
- credential
- local absolute path
- raw reasoning

原文只有在 tenant policy、ACL、retention tier、redaction與 explicit evidence-open action允許時另存 reference payload。

## 7. Telemetry / data handling

DSH FULL telemetry可能輸出完整 message、tool payload、system prompt、tool schema與 cwd；官方 backend不提供預設 redaction rule。

因此正式預設：

```text
telemetry = DISABLED
remote OTLP = BLOCKED
raw session import = BLOCKED
```

未來 local bridge必須通過：

- Tenant / Scope ACL
- secret / PII / path redaction
- payload retention tier
- source deletion propagation
- projection/cache cleanup
- evidence chronology
- data egress admission

## 8. Donor disposition

### ADAPT

- headless one-shot process adapter
- SessionEvent → ExecutionEvidence mapping
- Trajectory → AnswerTrace / runtime inspector projection
- Profile / Bundle / Patch effective config digest
- structured subagent result contract

### ABSORB

- Service Definition / Provider / Consumer seam
- append-only event / replay / reconstructability invariants
- fail-loud capability negotiation
- cancellation / teardown / settlement tests
- expectedRevision / DAG / tombstone / queued-delivered failure cases

### REFERENCE_ONLY

- Dynamic Workflow worker-thread engine
- Agent Teams
- Creator Mode
- Codex/Claude Code nested product providers
- Web UI

### SHOULD_NOT_ADOPT

- 把 DSH Session DB當 Canonical Knowledge DB
- 把 Everything is a Plugin套到 Authority Plane
- Agent Teams成為 default query topology
- workflow completed當 Verification PASS
- Creator output自動 enable/publish
- `writeScopes`當 filesystem authorization
- FULL raw telemetry直接進企業 observability
- DSH plugin自行擴張 tenant permission

## 9. 施工切片

### `OMOS-DSH-00` — RawEvidence Contract fixture merge

```text
Priority: P0 current frontier內的 fixture
Status: MERGE_INTO_EXISTING_RAW_EVIDENCE_CONTRACT
Delivery: MVP contract only; no DSH runtime dependency
```

在 Raw Evidence Contract 加一個 `AGENT_RUNTIME` fixture，確保 contract可表達：run、session、turn/step、tool、producer/version、ACL、payload ref、chronology。這不是另開 runtime card。

### `OMOS-DSH-01` — DSH ExecutionEvidence Source Adapter

```text
Priority: P1-A
Delivery: NEXT
Status: BLOCKED_BY_RAW_EVIDENCE_CONTRACT_AND_AI_CORE_PROVIDER
Responsibility: RUNTIME_OWNED / EXECUTOR_ONLY / DOMAIN_ADAPTER
```

交付：AI Core run record / sanitized DSH event → RawEvidence mapping、idempotency、deletion、ACL、retention、fixtures。

### `OMOS-DSH-02` — DSH Capability Admission Fixture

```text
Priority: P1-A
Delivery: NEXT
Status: MERGE_INTO_EXTERNAL_CAPABILITY_ADMISSION
Responsibility: ENTERPRISE_GOVERNANCE
```

以 DSH Profile/Bundle/Plugin作第一個複雜 runtime capability fixture，驗證 origin/version/license/capability/permission/telemetry/sandbox/managed policy。

### `OMOS-DSH-03` — Trajectory → AnswerTrace Projection

```text
Priority: P1-B
Delivery: NEXT
Status: BLOCKED_BY_ANSWERTRACE_CONTRACT
Responsibility: PROJECTION_ONLY
```

只做 trace viewer / projection；RawEvidence與AI Core RunReceipt仍是上游 authority。

### `OMOS-DSH-04` — Dynamic Workflow Evaluation Executor

```text
Priority: Trigger / P1-B candidate
Delivery: NORTH STAR / conditional
Status: DEFER
Responsibility: MODEL_ASSISTED / RUNTIME_OWNED
```

觸發：High Risk、Conflict、Low Confidence、Evidence disagreement或使用者明確要求獨立驗證。必須有獨立 sandbox、cost/depth/time cap與 structured result。

### `OMOS-DSH-05` — Agent Teams / Creator

```text
Priority: Trigger
Delivery: NORTH STAR
Status: REFERENCE_ONLY / DEFER
```

只有真實 shared-work / long-running collaboration / governed capability authoring需求才重評。不得阻塞 Knowledge MVP。

## 10. Mandatory card fields

任何後續 DSH implementation card都必須寫：

```text
問題 / 目標
Product / Domain Responsibility
Existing Seam
Pinned upstream commit / package version
Prior Art / exact donor files
Reuse Candidate
Absorb
Do Not Absorb
License / third-party terms
AI Core Priority
Knowledge SaaS Priority
Priority Rationale
Why Custom Code Is Still Needed
Deterministic First
Canonical / Projection / Executor
Permission / retention / deletion
Telemetry / data egress
Human Review Requirement
Acceptance Criteria
Rollback / removal path
```

## 11. Acceptance criteria

整合成功不是「DSH 功能都能用」。成功是：

1. 八顆 Minimal Core不變。
2. DSH unavailable / removed時 Knowledge truth不受影響。
3. AI Core provider adapter可替換且 fail-closed。
4. DSH run只產生 Evidence，不能 direct canonical write。
5. Permission-before-Retrieval仍在 DSH看到 context之前完成。
6. process receipt與 rich event bridge分期，不因 observability複製全部 raw data。
7. Advanced features預設關閉。
8. External Capability Admission能顯示 effective profile、permission、telemetry與sandbox。
9. `EXECUTED != VERIFIED != ACCEPTED`在所有 mapping保留。
10. DSH不成為 Documents + Jira MVP dependency。

## 12. Current priority decision

目前施工順序仍是：

```text
1. Raw Evidence Contract
2. Document Adapter Mapping
3. Jira Adapter Mapping
4. Permission / Retention / Deletion Contract
5. Canonical Direct-Write Audit
6. 最新互動 Architecture Canvas
```

DSH 現在只做：

- donor pin
- RawEvidence fixture merge
- backlog / seam reservation
- AI Core blocked Stage A card

不啟動 runtime implementation。
