# 研究包 D｜SimpleMem / EvolveMem / Omni-SimpleMem 與 bounded executor patterns

日期：2026-09-06

狀態：`P1 PRIOR ART / RESEARCH COMPLETE / NOT CURRENT FRONTIER / NO IMPLEMENTATION AUTHORITY`

Source baseline：`organizational-memory-os main@8ac5c24c92ed70640612641734c33f90efa6374f`

---

## 0. 結論

本研究只補 Organizational Memory OS 已有的：

- Evidence Projection
- Context Budget / Bounded Retrieval
- Evaluation → Repair → Re-eval
- Source/Batch Executor reliability

不建立第二套 Memory Runtime、Knowledge DB、Retrieval Planner Agent、AutoResearch Service、Job Engine 或 lifecycle/FSM。

SimpleMem / EvolveMem 很有 donor 價值，但它們自己的 `memory store`、SQLite/FTS、vector backend、consolidation lifecycle 都不能取得本產品的 Knowledge Authority。

固定邊界：

```text
Raw Evidence / Canonical Knowledge = authority
Dense / BM25 / metadata / graph / synthesis = rebuildable projection
LLM diagnosis = proposal
Acceptance / Canonical Writer = existing governance
```

本輪不改目前施工順序：Raw Evidence Contract → Document Adapter → Jira Adapter → Permission/Retention/Deletion → Canonical Direct-Write Audit → Architecture Canvas。

---

# 1. Existing project seams：不是從零設計

本研究先對齊現有文件，不另造 backbone。

| Existing seam | Current file | 已有原則 | 本研究 delta |
|---|---|---|---|
| Canonical backlog | `文件/待辦重整.md` | Domain Core / Projection / Runtime-owned 已分離；Context Budget、Bounded Retrieval、Evaluation 已在 backlog | 只補 pinned prior art 與 exact absorption disposition |
| Prior-art-first | `文件/禁止重刻政策.md` | 必須保存 repo、URL、commit/tag、license、Absorb/Do Not Absorb；custom code 要有理由 | 本研究依此格式封存 SimpleMem family / OMP source |
| Context Budget | `文件/上下文預算與檢索.md` | Permission-before-Retrieval → Intent/Domain → Context Budget → Bounded Retrieval | SimpleMem adaptive/multi-view/progressive pattern只補 retrieval implementation/eval idea |
| Verification governance | `文件/驗證治理.md` | `EXECUTED != VERIFIED != ACCEPTED`；missing evidence 不等於 PASS；failure 先定位 layer | EvolveMem diagnosis 只能生成 config proposal + offline eval，不直接 production mutate |
| Minimal Core | `文件/最小核心重基準.md` | Evidence / Knowledge / Governance / Projection / Retrieval Policy / Verification 分責 | SimpleMem memory unit 不可升級成 Canonical Knowledge |

---

# 2. External source / license ledger

## 2.1 aiming-lab/SimpleMem — primary OSS donor

- Repository：https://github.com/aiming-lab/SimpleMem
- Pinned commit：`db80b6a7c591e0ea730a058e9f5fc4eb06572299`
- Commit date：2026-07-24。
- Root license：MIT (`LICENSE`)。
- Paper：**SimpleMem: Efficient Lifelong Memory for LLM Agents**
- arXiv：https://arxiv.org/abs/2601.02553
- Paper date：2026-01-05。
- Adoption：`ABSORB / ADAPT_ALGORITHM / ADAPT_FIXTURES`，不採其 memory store 作 truth。

Pinned exact donor files：

| Capability | File | Evidence / reusable pattern |
|---|---|---|
| Atomic structured extraction | `simplemem/core/memory_builder.py` | keywords、absolute timestamp、location、persons、entities、topic 等 typed extraction |
| Coreference + temporal anchoring | `MCP/reference/core/memory_builder.py` | Atomic Entries、pronoun/coreference resolution、relative→absolute time |
| Package-level design | `README.md` | structured atomic memory → index → retrieve 的三階段產品實作參考 |
| Vector backend abstraction | latest pinned root code under `simplemem/` | backend interface 是 projection implementation donor，不是 authority donor |

Paper claims（只作 donor benchmark evidence，不作本產品承諾）：SimpleMem 主張 Semantic Structured Compression、Recursive Memory Consolidation、Adaptive Query-Aware Retrieval；論文 benchmark 報告的 F1/token improvement 必須視為其資料集結果，不直接成為 Organizational Memory OS acceptance threshold。

### License handling

若後續 copy SimpleMem root bounded code：遵守 MIT notice。現在只建立研究/backlog 文件，未複製 source implementation。

---

## 2.2 EvolveMem — same repository, evaluation/config optimization donor

- Code location：`aiming-lab/SimpleMem/EvolveMem/`
- Pinned repository commit：`db80b6a7c591e0ea730a058e9f5fc4eb06572299`
- No separate license file observed under `EvolveMem/` at this pin；以 repository root MIT 為本輪可見 licensing basis。若未來 copy code，implementation card 必須再做 path-level license recheck。
- Paper：**EvolveMem: Self-Evolving Memory Architecture via AutoResearch for LLM Agents**
- arXiv：https://arxiv.org/abs/2605.13941
- Paper date：2026-05-13。
- Adoption：`ABSORB_EVAL_LOOP / ADAPT_FAILURE_FIXTURES / REFERENCE_CONFIG_SEARCH`。

Pinned exact donor files：

- `EvolveMem/README.md`
- `EvolveMem/run_evolution.py`
- `EvolveMem/run_benchmark.py`
- `EvolveMem/evolvemem/diagnosis.py`
- `EvolveMem/evolvemem/evolution.py`
- `EvolveMem/evolvemem/config.py`
- `EvolveMem/evolvemem/candidate.py`

README / paper 明確的閉環：

```text
Evaluate held-out QA
→ per-question failure logs
→ Diagnose root cause
→ Propose targeted config changes
→ Guard / revert on regression
→ stop/explore by bounded condition
```

EvolveMem 自身也有 SQLite+FTS5、LLM extraction、consolidation、multi-view retrieval 與 self-evolution engine；本產品只吸 evaluation/config proposal pattern，不吸其 store/lifecycle 作 Knowledge truth。

其自報 LoCoMo/MemBench improvement 只作研究證據，不能外推到本產品資料。

---

## 2.3 Omni-SimpleMem — multimodal future donor, not current frontier

- Code location：`aiming-lab/SimpleMem/OmniSimpleMem/`
- Pinned repository commit：`db80b6a7c591e0ea730a058e9f5fc4eb06572299`
- **Subproject license：Apache-2.0** (`OmniSimpleMem/LICENSE`)；不要誤用 root MIT 覆蓋此子目錄。
- Pinned README：`OmniSimpleMem/README.md`
- Scope：text/image/audio/video multimodal memory implementation。
- Adoption：`REFERENCE_ONLY_NOW / FUTURE_SOURCE_ADAPTER_AND_PROJECTION_DONOR`。

目前 Phase-1 是 Documents/Jira；Omni-SimpleMem 不插隊。若未來正式支援影像/音訊/影片 evidence，再以 Source Adapter → Raw Evidence → Projection 邊界重新評估。

---

## 2.4 Stencil — The Harness Playbook（secondary engineering literature）

- URL：https://stencil.so/blog/harness-playbook
- 作者：Can Bölük
- 日期：2026-09-02
- 類型：工程文獻，不是 Knowledge OSS dependency。
- License：N/A for code reuse；只吸 bounded work / state ownership / lifecycle discipline。
- Adoption：`REFERENCE / ABSORB_EXECUTOR_PRINCIPLES`。

不引入 Harness subsystem / Session DOM / replacement runtime。

---

## 2.5 can1357/oh-my-pi（secondary executor donor）

- Repository：https://github.com/can1357/oh-my-pi
- Pinned commit：`1c929b95a2c42384b7fedd52ed4f374f1be65f6c`
- Commit date：2026-09-05
- License：MIT (`LICENSE`)
- Adoption：`COPY_SCHEMA_PATTERN / ADAPT_FAILURE_FIXTURES` only。

Exact relevant donor files：

- `packages/coding-agent/src/task/workpool-yield.ts`
- `packages/coding-agent/src/prompts/tools/workpool-batch.md`
- `packages/coding-agent/src/prompts/tools/yield.md`
- `packages/coding-agent/src/task/workpool.ts`

可吸：per-item machine-readable incremental result / bounded delivery pattern。

不吸：WorkPool runtime、Agent Core、Session Manager、Job Manager、memory backend、TUI、provider runtime。

---

# 3. K1 — Evidence Projection absorption

這不是新 Knowledge layer；對應現有 Projection responsibility。

## 3.1 AtomicEvidenceProjection

從 SimpleMem 吸收的候選 extraction pattern：

```yaml
projection_id: ...
source_evidence_id: ...
source_span: ...
normalized_statement: ...
timestamp: ...
persons: []
entities: []
locations: []
keywords: []
topic: ...
extractor_version: ...
confidence: ...
```

必要 invariants：

- source evidence 永遠保留 identity/provenance；Projection 可刪重建。
- coreference resolution / timestamp normalization 是 derived extraction，不可改寫 Raw Evidence。
- `normalized_statement` 不是 Canonical Knowledge。
- model/extractor version 必須可追。

## 3.2 Multi-view Projection

SimpleMem/EvolveMem 的 multi-view pattern 對應：

```text
Lexical  → BM25 / FTS / sparse
Semantic → dense embedding
Structured → person/entity/location/time/topic metadata
Graph → only when justified by existing Graph Projection use case
```

共同來源仍是同一 Evidence / Canonical source。禁止三套 truth DB。

## 3.3 Semantic density / consolidation

可用 density/relevance 決定「現在是否值得建立某個 projection/candidate」，不能決定 Raw Evidence retention。

SimpleMem/EvolveMem consolidation 若用於本產品，只能產生：

```text
DerivedSynthesisProjection
→ source ids/spans
→ derivation/model/prompt version
→ confidence
```

要成為正式知識仍必須：Candidate → Verification → Acceptance → Canonical Writer。

---

# 4. K2 — Authorized Bounded Retrieval absorption

Existing order 不變：

```text
Identity
→ Permission
→ Authorized Retrieval Space
→ Intent / Domain
→ Retrieval
→ Context Budget
→ Answer
```

任何 SimpleMem query analysis / decomposition / reflection 都只能在 Authorized Retrieval Space 內工作。

## 4.1 Intent-aware query analysis

可吸：person/entity/time/location/topic、query complexity、query decomposition 等 analysis pattern。

不能吸：讓 LLM planner 自己擴權找未授權 source。

## 4.2 Progressive retrieval

把固定 `top_k` 的單一路徑改為 **可評估的 bounded candidate policy**：

```text
Stage 1 exact / structured high-confidence
↓ insufficient
Stage 2 lexical + dense
↓ insufficient
Stage 3 graph / broader authorized query when justified
↓ budget exhausted
STOP
```

Budget 至少可表達：

- max_queries
- max_rounds
- max_candidates
- max_context_tokens
- stop reason

這是 `Context Budget / Bounded Retrieval` 的 implementation/evaluation donor，不建立 Retrieval Planner Agent subsystem。

## 4.3 Fusion / config

BM25/dense/structured fusion weights、RRF/weighted fusion、per-query/per-category overrides都只能是 `RetrievalConfig` / projection policy；不是 knowledge truth。

---

# 5. K3 — Evaluation + Executor Reliability absorption

## 5.1 Failure classification before optimization

EvolveMem 的 failure-log → diagnose pattern只能在本產品既有 failure taxonomy 後執行。

最低分類：

```text
SOURCE_ERROR
PARSE_ERROR
EXTRACTION_ERROR
OBJECT_LINK_ERROR
KNOWLEDGE_ERROR
PERMISSION_ERROR
RETRIEVAL_MISS
RANKING_ERROR
CONTEXT_BUDGET_ERROR
GENERATION_ERROR
FRESHNESS_ERROR
```

只有真正屬於 retrieval/config 的 failure 才可進 EvolveMem-style config optimization；例如 `PERMISSION_ERROR` 不能靠調 fusion weight 修。

## 5.2 RetrievalConfigProposal only

允許：

```text
Evaluate
→ Diagnose
→ RetrievalConfigProposal
→ Offline/Held-out Eval
→ Regression Guard
→ Accept / Reject
```

禁止：

```text
LLM diagnosis
→ directly rewrite production config
```

Auto-revert/explore/converge pattern可作 offline evaluation donor；production config writer/authority仍由本產品既有 governance 決定。

## 5.3 BatchItemReceipt

從 OMP incremental yield pattern只吸 schema：

```yaml
item_id: ...
stage: ...
attempt: ...
status: terminal | error | unknown
artifact_ref: ...
result: ...
error: ...
```

適用：Document batch parse、Jira ingestion、embedding/index rebuild、evaluation batch、re-verification batch。

不要建立 WorkPool Service。

## 5.4 Lifecycle-bound connector/executor work

Source connector / parser / projection rebuild / evaluation batch 都必須有 owner、cancel/timeout、cleanup、terminal state；不可 fire-and-forget。

這是 Executor Contract，不是第二 Job Engine。

## 5.5 Mutation retry

- Pure source read/fetch：依 adapter semantics 做 bounded retry。
- Proposal/candidate creation：需要 stable idempotency identity。
- Canonical write / external mutation：不能因 timeout/response loss就盲重送；必須先 reconcile effect / use idempotency proof。

此原則對齊本產品 Single Writer / idempotency / evidence chronology，不需要引入 OMP session retry policy。

---

# 6. Prior-art adoption matrix

| Capability | Existing seam | Donor | Disposition |
|---|---|---|---|
| Atomic structured extraction | Projection / future extraction contract | SimpleMem | `ADAPT_SCHEMA_AND_TESTS` |
| Coreference / temporal anchoring | Projection normalization | SimpleMem | `ADAPT` |
| Dense + lexical + structured | Projection / Bounded Retrieval | SimpleMem / EvolveMem | `DIRECT_PATTERN` |
| Query-aware retrieval | Context Budget / Retrieval Policy | SimpleMem | `ADAPT_ALGORITHM` |
| Query decomposition | Retrieval Policy | EvolveMem discovered config dimension | `EVAL_CANDIDATE` |
| Failure-driven config optimization | Evaluation → Repair → Re-eval | EvolveMem | `ADAPT_OFFLINE_LOOP` |
| Auto-revert on regression | Evaluation guard | EvolveMem | `ABSORB_GUARD_PATTERN` |
| Per-item batch receipts | Executor contract | oh-my-pi | `COPY_SCHEMA_PATTERN` |
| Bounded/lifecycle-owned work | Executor contract | Harness / OMP | `ABSORB_PRINCIPLE` |
| Multimodal memory | future source/projection | Omni-SimpleMem | `REFERENCE_ONLY_NOW` |

---

# 7. DO NOT ADOPT

明確禁止：

- SimpleMem `MemoryEntry` / vector store / SQLite store 作 Canonical Knowledge
- EvolveMem SQLite+FTS5 store 作本產品 truth
- automatic semantic merge / consolidation 直接覆寫 Canonical
- automatic config evolution 直接寫 production
- Omni-SimpleMem memory runtime 作 Knowledge backbone
- OMP memory backend / Session Manager / WorkPool runtime
- Harness Session DOM / replacement runtime
- universal Retrieval Planner Agent
- AutoResearch service / second Job Engine
- second Knowledge DB / lifecycle DB / FSM
- permission enforcement 由 model/retrieval planner決定

---

# 8. Backlog placement / priority

本研究只登錄：

```text
P1 PRIOR ART
NOT CURRENT FRONTIER
DOES_NOT_CHANGE_CURRENT_BUILD_ORDER
```

未來 consumer：

1. Atomic Extraction / Projection card → 直接引用 K1，不重新概念研究。
2. Context Budget / Bounded Retrieval card → 直接引用 K2 + pinned donor files/papers。
3. Evaluation / Repair card → 直接引用 K3 / EvolveMem guarded loop。
4. Batch ingestion / connector execution → 只引用 BatchItemReceipt + lifecycle-bound executor pattern。

目前施工順序維持：

```text
1 Raw Evidence Contract
2 Document Adapter Mapping
3 Jira Adapter Mapping
4 Permission / Retention / Deletion Contract
5 Canonical Direct-Write Audit
6 最新繁中 Architecture Canvas
7 再依 canonical backlog 派工
```

---

# 9. Future implementation gate

實際施工時每張卡仍須回答：

- Existing Seam
- Exact donor path / paper / commit
- License at copied path
- Reuse Candidate
- Absorb
- Do Not Absorb
- Why Custom Code Is Still Needed
- Canonical / Projection boundary
- Permission-before-Retrieval proof
- deterministic-first decision
- regression / failure fixtures

若只是因 donor architecture 很完整而想建立 permanent subsystem：`SHOULD_NOT_ADOPT`。

成功標準是：prior art、tests、failure coverage、retrieval quality提升，而 custom code / permanent architecture 不膨脹。