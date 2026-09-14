# Organizational Memory OS Backlog｜分類與優先級視圖

更新：2026-09-14。

這份檔案負責「分類與現在先做什麼」。完整 capability inventory、施工狀態、Owner blocker、Jira/CC lane、fixed SHA、review evidence 與規範債仍完整保留在 [`文件/待辦重整.md`](文件/待辦重整.md)，本次不刪、不壓縮原 current truth。若狀態細節衝突，以原主檔為準；若只是排程先後，以本檔為準。

2026-09-14 donor 研究增補見 [`文件/待辦重整-Donor增補-20260914.md`](文件/待辦重整-Donor增補-20260914.md)。Donor 不取得獨立 backlog、Knowledge authority 或新的 subsystem。

## 1. 分類

| 類別 | 既有責任 | 目前內容 |
|---|---|---|
| A. Truth / Governance | Evidence、Candidate/Canonical、Single Writer、Permission、Retention、Acceptance | Permission/Retention/Deletion、Canonical Direct-Write Audit、Managed Policy Floor、AnswerTrace |
| B. Source / Admission | source adapters、normalize/validate、Object/Work context | Documents/Jira、Outlook/Teams next tranche、ObjectLink、WorkRecord |
| C. Retrieval / Lifecycle | Context Budget、Bounded Retrieval、freshness、projection invalidation | SimpleMem/EvolveMem donors、OpenViking context hierarchy donor |
| D. Conflict / Provenance / Impact | conflict、supersession、provenance、reviewer graph | Semantica donor、W3C PROV、Graph Projection |
| E. Verification / Evaluation | verification、acceptance、repair/re-eval、quality trace | EvaluationReceipt、risk-based review、multi-agent escalation only |
| F. AIWR / Personal Runtime | personal evidence/work record、native adapters、conformance/pilot | SSP-307/308/309/310、ai-memory failure patterns |
| G. Executor / Capability | model/runtime/provider、local embedding/reranker、cost evidence | llmfit、oMLX、Switchyard；executor only |
| H. Projection / UX | vector/search/graph/context summaries、Architecture Canvas、review UI | PROJECTION_ONLY；不可取得 truth authority |

## 2. 優先級分成兩條：Owner Decision Queue 與 Executable Queue

這樣 blocked 的 P0 不會消失，也不會把所有可施工工作凍住。

### P0 Owner Decision Queue

1. **Permission / Retention / Deletion Contract** — `BLOCKED_AWAITING_OWNER_SPEC_FREEZE`。先封 retention state、deletion semantics、legal hold、ACL delta、projection/cache cleanup。
2. **Canonical Direct-Write Audit** — `BLOCKED_AWAITING_OWNER_SCOPE_DECISION`。先定 audit scope、pass/fail 判準、finding disposition。
3. 上述兩項仍是 `SSP-294` Promotion 的前置，不因 donor 插隊。

### P0/P1 Executable Queue｜等待 Owner 決策期間可做

1. **SSP-307 / AIWR Codex Native Adapter Runtime Probe** — 既有 frontier；只把 ai-memory 的 delivery/replay failure cases 併入 acceptance，不建第二 memory runtime。
2. **SSP-308 / Claude Code Native Adapter Runtime Probe** — 有第二施工者才平行；否則接續 307。
3. **SSP-309 Conformance** — 307/308 通過後才做。
4. **SSP-310 PM Pilot / Rollback** — 309 通過後才做；一人、一任務、一平台、先 dry-run。
5. **Architecture Canvas** — 保留既有順序與 Minimal Core 邊界；不因 OpenViking/Semantica 改架構，只反映已接受 contract。

### P1-A｜治理閉環後的 retrieval / lifecycle 強化

6. **Context Budget + Bounded Retrieval**：把 OpenViking 的 L0/L1/L2、typed query、hierarchical descent、stop/convergence 吸進既有 ContextPolicy / retrieval seam；L0/L1 永遠是 rebuildable projection。
7. **Knowledge Lifecycle**：source update/delete/撤權後，vector/graph/context summary/cache 必須失效或重建。
8. **Conflict / Supersession**：Semantica 的 detect/analyze/source-track/provenance 可吸收；resolver 只作 advisor，不取得 Acceptance/Canonical authority。
9. **Provenance / Reviewer Graph / Impact**：Semantica/W3C PROV 只作 projection 與 reviewer workflow，不把 graph 升格為 truth。
10. **Mutation Receipt**：吸收 OpenViking memory-diff 的 audit pattern，直接強化既有 Proposal → Verification → Acceptance → Single Writer seam，不建新 Memory Diff subsystem。

### P1-B｜來源與產品能力擴充

11. Outlook / Teams ingestion、Config Scope/Precedence、External Capability Admission、Outline Production Role。
12. Repository Intelligence、Knowledge/Procedure split、Reviewer/Impact UI。
13. Multi-Agent Evaluation 維持 escalation-only；沒有 High Risk / Conflict / Low Confidence 等條件不 fan-out。

### P2 / Later

- 全景 Knowledge Graph explorer、Shared Blackboard、Multi-Agent Runtime、Skill marketplace 等 trigger/later 項。
- oMLX / Switchyard 只有真實 executor consumer 才做 spike；不升成 Knowledge Architecture。

## 3. Donor 對應

| Donor | Existing Seam | 裁決 |
|---|---|---|
| OpenViking | Context Budget / Bounded Retrieval / Mutation Receipt | `ADAPT_ALGORITHMS / REFERENCE_CODE_UNTIL_LICENSE_ADMISSION` |
| Semantica | Conflict / Provenance / Reviewer Graph | `ADAPT` |
| ai-memory | AIWR native-event reliability | `ABSORB_FAILURE_PATTERNS_ONLY` |
| llmfit | Executor capability evidence | `AI_CORE_PRODUCES_RECEIPT / OMOS_CONSUMES` |
| oMLX | local embedding/reranker executor | `CONDITIONAL_SPIKE` |
| Switchyard | executor recommendation | `RESEARCH_SPIKE_ONLY` |

## 4. 規則

1. 原 backlog item 不刪；completed、blocked、parked、open、regression debt 全保留在詳細主檔。
2. 分類是 view，不是第二套 domain model；八顆 Minimal Core 與 Truth Boundary 不翻案。
3. Blocked P0 保留最高 business priority，但不佔可施工 queue；等待 Owner 時只做不衝突工作。
4. Donor 不插隊，只能補 Existing Seam、降低 custom code、增加 failure/acceptance evidence。
5. Graph、Vector、Chunk、L0/L1 summary、cache 永遠是 projection；Agent/Model/Runtime 永遠是 executor。
6. 只有 Existing Seam 無法承載且能說明 Why Custom Code Is Still Needed，才允許新 subsystem/card family。

閱讀順序：先看本檔排程，再去 [`文件/待辦重整.md`](文件/待辦重整.md) 查完整 current truth。