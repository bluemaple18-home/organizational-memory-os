# CARD-GRAPH-01｜Reviewer / Impact Navigator

日期：2026-09-07

狀態：`BACKLOG_READY / P1-B / DEFERRED_UNTIL_PREREQUISITES / NOT_CURRENT_FRONTIER`

對應裁決：`文件/Obsidian式關聯圖開源整合裁決-20260907.md`

對應草案：`規格/v0.1/graph-query-contract.draft.yaml`

---

## 問題 / 目標

目前以 Obsidian 類型全域力導向圖呈現大量筆記時，會快速退化成 edge hairball、label overlap、中心節點過度吸附與無法完成實際審核工作的畫面。

本卡不做「整間公司的宇宙圖」，而是交付一個小而有界、可追證據、權限安全的 Reviewer / Impact Navigator，協助審核者回答：

```text
這個 Candidate 從哪裡來？
它與哪些 Canonical Knowledge 衝突或重疊？
修改它會影響哪些 Procedure / Project / Repository Artifact？
誰驗證、誰接受、由哪些 Evidence 支撐？
```

---

## Product / Domain Responsibility

```text
Graph Projection
Reviewer Workflow
Impact Navigation
Permission-safe relationship exploration
```

責任分類：

```text
PROJECTION_ONLY
ENTERPRISE_GOVERNANCE at query boundary
DETERMINISTIC_FIRST for filtering / bounds / relation typing
MODEL_ASSISTED only for RelationProposal generation
```

Graph renderer、layout、client graph object 都不是 Knowledge Authority。

---

## Existing Seam

- Canonical Knowledge Single Writer
- Candidate / Canonical separation
- Permission-before-Retrieval
- Graph Projection boundary
- Reviewer Graph / Impact UI（P1-B）
- SourceAnchor / provenance
- Conflict / Supersession
- Permission / Retention / Deletion invalidation

正式資料流：

```text
Canonical entity / accepted relation
→ Graph Projection Builder
→ permission-filtered bounded subgraph
→ Sigma.js / Graphology client view
```

人工連線或 AI 推測只能產生 `RelationProposal`，不得由 UI 直接寫 Canonical Relation。

---

## Prior Art / Exact Pins

| Component | Exact pin | License | Disposition |
|---|---|---|---|
| `jacomyal/sigma.js` | `sigma@3.0.3` / `d32c4e5bfd4c5f49724ebc21bd786b01be555dac` | MIT | `ADOPT_CORE` renderer |
| `graphology/graphology` | `0.26.0` / `feb3e5c37e791d75f3dab185a56cb25d32c17de7` | MIT | `ADOPT_CORE` client graph model |
| `graphology-layout-forceatlas2` | npm `0.10.1` | MIT | `ADOPT_LAYOUT` worker layout |
| `graphology-layout-noverlap` | npm `0.4.2` | MIT | `ADOPT_LAYOUT` overlap cleanup |
| `gephi/gephi-lite` | `@gephi/gephi-lite@1.0.2` | GPL-3.0 | `REFERENCE_ONLY` UX / fixtures |
| `cytoscape/cytoscape.js` | `v3.34.2` / `93d083cd23248ed3f9ac060b07b292d8f04d74e1` | MIT | `ALTERNATIVE_ONLY` |
| `antvis/G6` | `5.1.1` / `5a5551cea13d021d12c90a87116e3c6092d53210` | MIT | `ALTERNATIVE_ONLY` |
| `cosmosgl/graph` | `v3.4.1` / `e5b502da8ff2a1767545eefe81b77c3257443f2e` | MIT | `TRIGGER_ONLY` extreme scale |

施工當天重驗 package integrity、license、security advisories、browser support 與 third-party notices。

---

## Reuse Candidate

### Direct use

- Sigma camera、WebGL renderer、node/edge reducers、pointer events、teardown。
- Graphology graph events、typed/mixed graph、components/path/community algorithms。
- ForceAtlas2 worker 與 Noverlap layout cleanup。

### Absorb as product patterns

- search → focus → one-hop highlight。
- local expansion / collapse。
- typed edge filters。
- provenance side panel。
- table/list fallback。
- stable layout snapshot。
- partial/truncated result disclosure。

---

## Do Not Absorb

- Obsidian proprietary code。
- Gephi Lite GPL-3.0 application code into proprietary SaaS bundle。
- Logseq AGPL application code into proprietary SaaS bundle。
- PKM note/page/block identity as enterprise Knowledge identity。
- client-side ACL hiding。
- graph database as Canonical Truth。
- LLM-generated relation without provenance。
- full-tenant graph download。
- unbounded automatic expansion。
- Sigma + Cytoscape + G6 parallel renderer stack。
- renderer-specific data object leaking into domain schema。

---

## Why Custom Code Is Still Needed

開源 renderer 解的是畫圖，不會替本產品完成：

- Permission-before-Graph。
- managed policy floor。
- accepted/proposed/projection-only relation authority。
- Evidence / SourceAnchor trace。
- lifecycle、conflict、supersession、freshness semantics。
- bounded server-side expansion。
- ACL / retention / deletion invalidation。
- reviewer workflow deep links。
- GraphQueryReceipt / AnswerTrace integration。

因此 custom delta 應集中在 query、governance、projection mapping 與 workflow，不重刻 renderer／layout。

---

## Preconditions / Hard Stops

本卡在以下條件前不得進 production implementation：

- [ ] Canonical Relation vocabulary / record boundary 已封。
- [ ] Permission / Retention / Deletion Contract 已封。
- [ ] ACL delta、source deletion、supersession 的 projection invalidation semantics 已封。
- [ ] `graph-query-contract.draft.yaml` 經 review 後升版。
- [ ] reviewer workflow 的 root types 與 deep-link targets 已確認。
- [ ] third-party license / notice / SBOM policy 已可執行。

本卡不阻塞 `STD-03 NormalizedDocument`、Document Adapter、Jira Adapter。

---

## Delivery Slices

### Slice A — Static renderer spike

```text
fixture JSON
→ Graphology
→ ForceAtlas2 worker
→ Noverlap
→ Sigma
→ search / select / dim / side panel / teardown
```

不接 production DB，不開 Graph Service。

### Slice B — Authorized bounded query

```text
identity + policy fixture
→ authorized entity/relation universe
→ bounded traversal
→ GraphQueryReceipt
→ no-existence-leakage tests
```

### Slice C — Reviewer / Impact workflow

Root types：

```text
CandidateKnowledge
CanonicalKnowledge
Procedure
WorkRecord
Review
Decision
Object
SourceEvidence
RepositoryArtifact
```

Initial relation types：

```text
DERIVED_FROM
CITES
SUPPORTS
CONTRADICTS
CONFLICTS_WITH
SUPERSEDES
DEPENDS_ON
IMPACTS
VERIFIED_BY
ACCEPTED_BY
LINKED_TO_OBJECT
SAME_OBJECT
SIMILAR_TO_PROJECTION
```

### Slice D — Invalidation / rebuild

```text
ACL delta / retention expiry / source deletion / supersession
→ affected node, edge, aggregate and layout cache invalidation
→ deterministic rebuild
→ verification receipt
```

---

## Default Safety Bounds

```yaml
mode: reviewer_impact
max_depth: 2
node_limit: 300
edge_limit: 1000
label_limit: 80
layout_time_budget_ms: 1500
```

Server 端必須 enforce；client 只能要求更窄，不能擴權。超限回傳 `truncated: true` 與 reason，不可靜默省略後聲稱完整。

---

## Acceptance Criteria

### Security / authority

- [ ] 未授權 node、edge、count、degree、path、cluster size、tooltip、export 均不可推得。
- [ ] edge 不可指向隱藏 node，也不可保留可辨識 placeholder。
- [ ] proposed、verified、accepted、projection-only relation 視覺與 legend 分離。
- [ ] accepted edge 可追到 Canonical Relation 或 Evidence / SourceAnchor。
- [ ] Graph UI 沒有 direct canonical writer path。
- [ ] cache key 含 tenant、principal/policy scope、projection version、filter、bounds。

### Boundedness / honesty

- [ ] depth、node、edge、label、time budget 全部由 server enforce。
- [ ] partial / truncated 明確呈現。
- [ ] path 與 centrality 只在 authorized subgraph 計算。
- [ ] global graph 不一次下載 tenant 全圖。

### Reliability / UX

- [ ] empty、single-node、disconnected、self-loop、parallel relation、high-degree、long-label、繁中/英文/emoji fixture 通過。
- [ ] route change / unmount 會 kill worker、remove Graphology listeners、destroy Sigma renderer。
- [ ] search、keyboard focus、reduced motion、screen-reader summary、list/table fallback 可用。
- [ ] click edge 可回答 `why connected?` 並顯示 provenance。
- [ ] selection/filter/update 不重跑不必要的 full layout。

### Supply chain

- [ ] production dependency exact pin，不使用 range / beta。
- [ ] lockfile integrity、MIT notices、SBOM 完整。
- [ ] GPL / AGPL donor 保持 reference-only，無不明 source copy。

---

## Verification Fixtures

```text
G-SMALL   300 nodes / 1,000 edges
G-MEDIUM  2,000 nodes / 8,000 edges
G-LARGE   10,000 nodes / 40,000 edges
G-DENSE   pathological high-degree graph
G-UNICODE Traditional Chinese / English / emoji / long labels
G-ACL     visible and hidden entities mixed
G-DELETE  source deletion and ACL downgrade
```

量測 initial render、layout worker、pan/zoom responsiveness、hover/select latency、memory high-water mark、filter/update latency、label readability 與 teardown cleanup。

`G-LARGE` 明確失敗且為真實產品需求時，才開 cosmos.gl comparison；即使換 renderer，Graph Query / Permission / Projection contract 不變。

---

## Priority

```yaml
architecture_priority: P1-B
first_delivery: NEXT_AFTER_CORE_CONTRACTS
commercial_level_initial: L1
current_frontier: false
global_explorer: P2_TRIGGER_BASED
```

本卡完成的定義不是「畫面出現節點」，而是審核者能在 authorized、bounded、traceable 的圖中完成一項 review / impact 判斷。
