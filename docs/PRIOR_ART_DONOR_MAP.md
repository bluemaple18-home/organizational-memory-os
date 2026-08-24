# Prior-Art Donor Map

Formal principle:

> Prior-art first. Absorb, don't copy.
>
> Borrow the engineering, preserve the architecture.

This table is an implementation research map, not automatic dependency approval.

| Seam | Donor | License / note | Reuse mode | Absorb | Do not absorb / custom delta |
|---|---|---|---|---|---|
| Structured document parsing | Docling | MIT | DIRECT_REUSE / ADAPT | PDF/DOCX/PPTX/XLSX/HTML parsing, unified doc representation, layout/table, chunking | Docling document identity must not become Knowledge identity; map to RawEvidence |
| Partition/fallback ingestion | Unstructured | Apache-2.0 | DIRECT_REUSE / fallback | partition/preprocessing/connectors/failure cases | do not adopt as knowledge authority |
| Lightweight document -> Markdown | Microsoft MarkItDown | permissive Microsoft OSS; verify exact repo license before dependency | DIRECT_REUSE/LEVEL donor | fast LLM-friendly conversion for simpler tiers | do not use Markdown as canonical evidence schema; compare against Docling/Unstructured by quality/cost level |
| Fine-grained authorization | OpenFGA | Apache-2.0 | ADAPT / likely dependency | Check/ListObjects, ReBAC mechanics, authorization model tests, RAG pre-filter patterns | OpenFGA tuple store/model is not organizational permission authority; product owns scope/capability semantics |
| Policy engine comparative donor | OPA | Apache-2.0 | REFERENCE / possible dependency | policy-as-code/evaluation/testing | avoid multiple overlapping policy authorities |
| Resource policy comparative donor | Cerbos | Apache-2.0 | REFERENCE / possible dependency | resource policy/query-plan pattern | product permission authority remains ours |
| Vector/hybrid retrieval | Qdrant | Apache-2.0 | DIRECT_REUSE / ADAPT | payload filters, dense+sparse/hybrid, tenant partitions/shards | index is not knowledge truth or permission authority |
| Context engineering | OpenAI Codex | Apache-2.0 repo | ABSORB | token estimation, reserve, recent-window, compaction triggers, boundaries, tool-output limiting, failure handling | no rollout/session/task/runtime authority, state DB, memory truth |
| Context assembly / graph retrieval | Microsoft GraphRAG | MIT | ABSORB / ADAPT | token-aware mixed context, local/global search construction, entity/relationship context | no GraphRAG canonical knowledge authority |
| Machine evaluation | DeepEval | Apache-2.0 | DIRECT_REUSE | evaluation runner, G-Eval/RAG metrics/dataset patterns | evaluation result is evidence, not approval |
| Telemetry vocabulary | OpenTelemetry GenAI semantic conventions | Apache-2.0 standard | DIRECT_ADOPT | attributes/events/metrics naming | OTel is a projection, not app/knowledge/evaluation truth |
| Outlook/Teams/Calendar source | Microsoft Graph | Microsoft platform APIs | ADAPTER | delta query, change notifications, threads/messages/calendar metadata | source signal is evidence, not knowledge; inherit ACL/tenant policy |
| Teams application plumbing | Microsoft Teams SDK | MIT | ADAPTER | request validation, channel endpoint/adapter patterns | no Teams agent/runtime authority |
| Slack source plumbing | Slack Bolt | MIT | DIRECT_REUSE / ADAPTER | event/signing/socket mode plumbing | map events to RawEvidence; no Slack semantics as knowledge truth |
| Timeline/session/work-memory engineering | OpenChronicle | MIT | ABSORB / ADAPT | dedup/debounce, normalization, session manager, reducer, idempotent rebuild, failure/fallback | memory DB/classifier is not organizational truth |
| Activity -> Task/Work correlation | DayTrail | permissive donor; verify exact license at pin | ABSORB / ADAPT | link scoring, suggestion, human accept/reject | enterprise business-object semantics and confidence policy are ours |
| Object-centric event model | OCEL 2.0 | standard/model | ABSORB MODEL | multi-object event relationships, object-centric cases | WorkRecord remains our projection/contract |
| Process mining / OCEL implementation | PM4Py | AGPL-3.0 | REFERENCE / TEST DONOR | algorithms/schema/tests/ideas | do not embed in proprietary hosted SaaS without licensing decision |
| Optional desktop activity capture | ActivityWatch | MPL-2.0 | OPTIONAL ADAPTER | bucket/event/heartbeat/noise reduction | not MVP default; licensing obligations apply to modified covered files |
| Personal context architecture | MyContext | ELv2 | TEARDOWN/REFERENCE ONLY | source/context separation, checkpoints, incremental ingestion, evidence-first architecture | do not embed as hosted SaaS dependency without legal review |
| Outlook+Teams triage reference | AI Secretary | verify exact license before code reuse | TEARDOWN | thread/conversation extraction, dedup, linking, incremental sync/failure handling | no authority transfer; code reuse gated by exact license |
| Agent/runtime orchestration prior art | Munder Difflin | inspect exact license/pin | ABSORB PRINCIPLE ONLY for Knowledge SaaS | single-committer principle, circuit-breaker/failure lessons | mailbox/wake/PTY/agent lifecycle/blackboard runtime do not belong in Phase 1 Knowledge SaaS |
| Coding/execution verification semantics | codex-engineering-system-zh-tw | inspect exact license/pin | ABSORB SEMANTICS | Risk != Complexity, verification honesty, partial/not-run preservation, chronology, Execution != Verification != Acceptance | TDD/coding routing/task types/specialists are not Knowledge SaaS architecture |
| Repository intelligence / incremental code views | CodeNib | verify repo/license | ABSORB / ADAPT | lexical/dense/structural views, incremental update ideas/tests | no donor repo identity as product authority |
| Repository docs/architecture extraction | Google Code Wiki | verify repo/license | ABSORB / ADAPT | repository documentation/understanding patterns | independently prioritize for company product |
| Repository intelligence | PorunC/CodeWiki | verify repo/license | implementation donor | Lite implementation can seed lower capability levels | Lite is not product ceiling |
| Repository intelligence | FSoft-AI4Code/CodeWiki | verify repo/license | donor | repository knowledge extraction patterns | no architecture authority transfer |
| Code navigation | LSP ecosystem | protocol/open implementations vary | DIRECT_PROTOCOL / ADAPTER | definitions/references/symbol queries, efficient structural retrieval | LSP is a source/tool protocol, not knowledge truth |
| Code/repo retrieval | Lanser-CLI | verify repo/license | donor | engineering/retrieval patterns | independent product fit/priority |

## Donor evaluation checklist

For every pinned donor, capture:

- Repository URL
- Pin (commit/tag/version)
- Exact license
- Files/modules/tests being reused
- Failure cases being absorbed
- Existing product seam
- Semantic/authority mismatch
- Dependency vs vendored/ported algorithm decision
- Security/update risk
- Why custom code is still required

## Red-line rule

Do not allow a permissive license to justify architectural takeover. Legal permission to copy code is separate from semantic permission to replace organizational authority.
