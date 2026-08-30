# Codex 審查交接｜公司員工個人記憶標準｜2026-08-30

狀態：

```text
READ_ONLY_REVIEW
COMPANY_KNOWLEDGE_PREPARATION
NO_IMPLEMENTATION_AUTHORIZATION
NO_GIT_MUTATION_AUTHORIZATION
NO_SCHEMA_ACCEPTANCE_AUTHORITY
```

Repo：

```text
bluemaple18-home/organizational-memory-os
```

請先重新讀取 `main` 並回報 actual HEAD。

---

## 1. Owner intent

本計畫不是把完整 AI Core 切出去，也不是為每位員工建立 Personal AI Core。

真正目標：

> 為公司每位員工定義同一套 Personal Memory contract、lifecycle、permission、correction、recall 與 promotion 規格；不同角色只替換 source／role profile與capability level。

AI Core只作：

```text
Developer-specific donor / advanced source adapter
```

不得把 AI Core 的 task、branch、worktree、runtime、review、merge、deploy或folder layout升為公司員工共用記憶 schema。

---

## 2. Review targets

主要審查：

```text
文件/個人知識庫Harness提案查核與整合裁決-20260830.md
規格/v0.1/personal-harness-integration.yaml
文件/待辦補充-個人知識庫Harness-20260830.md
```

補讀 authority：

```text
文件/個人證據與工作紀錄.md
文件/SaaS能力等級.md
文件/最小核心重基準.md
文件/核心知識主幹.md
文件/權限政策與設定治理.md
文件/STD-00-Schema-Vocabulary-Freeze-v0.1-提案.md
規格/v0.1/common-vocabulary.yaml
```

AI Core只作 donor fact check；不是本輪設計 authority。

---

## 3. Hard invariants

不得推翻：

```text
Every employee uses the same core memory contract
General employees do not need complete AI Core
Raw Evidence != Personal Memory
WorkRecord != Personal Memory
Candidate != Accepted Personal Memory
Personal Canonical Memory is canonical only within PERSONAL scope
Personal Memory != Company Canonical Knowledge
Permission-before-Retrieval
ObjectLink != Permission Expansion
Correction must preserve history
Personal → Shared requires Proposal + Review + Single Writer
Role Profile != Core Schema Authority
Agent / Model / Harness = Optional Executor
```

---

## 4. Required checks

### A. Product scope

確認整份提案是否清楚表達：

```text
one employee personal memory standard
not one AI Core per employee
```

確認 AI Core只被放在developer adapter／donor位置。

### B. Same spec vs different role

確認能同時做到：

- PM、RD、MD、Sales來源不同。
- 所有來源進同一 RawEvidence contract。
- 所有角色使用同一 Candidate／Memory／Correction／Promotion lifecycle。
- Role extension不會產生第二套identity或permission。

### C. Personal scope ownership

檢查：

```text
EMPLOYEE_PRIVATE
COMPANY_MANAGED_PERSONAL
SHARED_WORK_CONTEXT
```

是否需要分開；如果需要，指出 exact contract缺口。

特別檢查：

- admin是否可能預設讀取全部personal memory。
- offboarding／export／delete／legal hold是否有位置。
- personal scope是否可能被誤當company-owned searchable pool。

### D. Memory lifecycle

確認：

```text
Evidence
→ ObjectLink / WorkRecord
→ PersonalMemoryCandidate
→ Verification
→ Personal Acceptance
→ PersonalMemoryRecord
→ Recall / Correction
→ optional PromotionProposal
```

沒有把WorkRecord、runtime result或task state直接當Memory。

### E. Memory kinds

檢查Phase-1 kinds是否足以涵蓋一般公司員工，而不是只適用developer。

確認 transient／one-off／task state被排除於long-lived memory default。

### F. Recall

確認 `MemoryContextPack`：

- permission first。
- applicability與freshness可表達。
- context budget可表達。
- citation／source refs保留。
- omission／gap可揭露。

### G. Correction

確認 correction不是直接overwrite，且有：

```text
new evidence
proposal
decision
supersession / invalidation
history
```

### H. Promotion

確認 PERSONAL → TEAM／DEPARTMENT／COMPANY／CLIENT：

- 不是copy。
- 需要permission／scope check。
- 需要evidence support。
- 需要review。
- 只能由Canonical Single Writer完成。

### I. L1–L4

確認四個Level共享同一contract，只改automation depth。

不要擅自裁決所有員工預設L2；Default Level仍是product／policy decision。

### J. Deployment

確認普通員工可只使用Outlook／Teams／Jira／Documents／Web，不需要本機AI Core或agent daemon。

### K. Machine-readable consistency

檢查：

```text
規格/v0.1/personal-harness-integration.yaml
```

與主文件：

- terminology一致。
- contract registry一致。
- scope modes一致。
- backlog一致。
- hard stops一致。

---

## 5. Required output

請只回：

```text
VERDICT: ACCEPT | AMEND | BLOCK

CURRENT-TRUTH-CONFIRMED
- ...

LOCKED-AS-IS
- ...

FINDINGS
- ID:
  Severity: BLOCKER | HIGH | MEDIUM | LOW
  File:
  Section / field:
  Problem:
  Product impact:
  Authority / privacy impact:
  Proposed bounded amendment:
  Fixture/test required:

OPEN PRODUCT DECISIONS
- ...

READY NEXT
- EMEM-00 Scope / Ownership / Privacy Contract: YES | NO
- EMEM-01 Personal Memory Contract: YES | NO
- Reason:
```

每個 finding必須指出 exact section或machine-readable field。

---

## 6. Valid BLOCK reasons

只有以下情況可用 `BLOCK`：

- 同一個employee memory無法隔離。
- personal scope ownership語意無法表達。
- role profile會改寫核心schema。
- Evidence／WorkRecord／Memory authority混淆。
- correction會抹除history。
- promotion可繞過review或single writer。
- 일반員工仍被迫依賴AI Core／runtime。
- Phase-1 PM／RD／MD／Sales fixture無法共用同一contract。

不要因想增加更多框架、Graph、Agent或Runtime而使用 `BLOCK`。

---

## 7. Forbidden actions

本輪禁止：

- 修改任何檔案。
- 建branch／commit／PR。
- 修改AI Core。
- 盤點或搬移AI Core `.memory`／`.founder-vault`內容。
- 建立Task Card schema或Runtime Provider Interface。
- 安裝／執行Codex、Claude、Hermes、DSH。
- 建立connector、DB、migration、agent daemon。
- 將提案自行標成Canonical。
- 把AI Core physical folder直接搬成公司標準。

---

## 8. Review emphasis

這次最重要的問題不是「AI Core memory怎麼切」。

而是：

> 一套工具中立、角色中立、runtime中立的Personal Memory Standard，能否讓每位員工使用同一生命週期，又能保留角色來源差異、個人隱私與升公司知識的治理邊界？
