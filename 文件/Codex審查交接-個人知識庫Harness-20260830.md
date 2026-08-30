# Codex 審查交接｜Personal Memory Harness｜2026-08-30

狀態：

```text
READ_ONLY_REVIEW
MEMORY_SCOPE_ONLY
NO_AI_CORE_CARVE_OUT
NO_IMPLEMENTATION_AUTHORIZATION
NO_GIT_MUTATION_AUTHORIZATION
NO_RUNTIME_INSTALL_AUTHORIZATION
NO_SCHEMA_ACCEPTANCE_AUTHORITY
```

Repo：

```text
bluemaple18-home/organizational-memory-os
```

請先重新讀取 `main` 並回報 actual HEAD。

Cross-repo evidence：

```text
bluemaple18-home/aicore
reviewed HEAD in proposal:
87f6a16cf22642513730ea56530a8b5b1ce4ee99
```

---

# 1. Owner intent

本計畫不是拆出或複製完整 AI Core。

正式 intent：

> 只盤點並補強 AI Core 的個人記憶能力；AI Core 的 Work、Task、Runtime、Review、Rules、Skills、Agent與工程治理全部保留原 owner與現況。

任何將本案重新擴張成：

```text
Personal AI Core
Universal Runtime
Provider Registry
Task Lifecycle
Runtime Adapter Platform
Hermes／DSH integration project
```

的建議，應判定為 scope drift。

---

# 2. Review targets

主要審查：

```text
文件/個人知識庫Harness提案查核與整合裁決-20260830.md
規格/v0.1/personal-harness-integration.yaml
文件/待辦補充-個人知識庫Harness-20260830.md
```

補讀 OMOS authority：

```text
文件/最小核心重基準.md
文件/個人證據與工作紀錄.md
文件/權限政策與設定治理.md
文件/驗證治理.md
文件/STD-00-Schema-Vocabulary-Freeze-v0.1-提案.md
```

AI Core current-truth evidence：

```text
.memory/**
.founder-vault/**
docs/ai-core-canonical-architecture.md
config/work_lifecycle_contract.json
```

AI Core Work／Task／Runtime文件只用來確認 boundary，不是本輪要重設計的對象。

---

# 3. Review purpose

判斷提案是否正確做到：

1. AI Core保持完整，不被Personal Memory Harness取代或拆走。
2. `.memory/**` 與 `.founder-vault/**` 被先當作待audit的current／legacy／projection surfaces，而不是靠檔名猜authority。
3. 記憶團隊只負責Capture、Consolidate、Govern／Promote、Recall／Correct。
4. AI Core Work Closeout只作上游signal，不被記憶團隊接管。
5. Founder Vault／memory-summary被限制為personal curated surface／projection。
6. Personal Memory仍遵守Evidence→Candidate→Acceptance→Single Writer。
7. Personal→Team／Company仍需Proposal＋Review。
8. 下一步只開read-only `PMEM-00` authority audit。

---

# 4. Hard invariants

審查不得推翻：

```text
AI Core remains complete
Personal Memory Harness != AI Core replacement
WorkRecord != Memory
Work state != Memory state
Captured != Accepted Memory
Runtime COMPLETE != Memory Verified
Personal Memory != Company Canonical Knowledge
Founder Vault taxonomy != Canonical schema
memory-summary.md = rebuildable projection
User correction creates revision evidence, not destructive overwrite
```

---

# 5. Required checks

## A. Scope

確認所有文件都沒有要求記憶團隊建立：

- Task Card schema replacement。
- Work lifecycle。
- Runtime provider interface／registry。
- ExecutionRequest platform。
- Runtime-native event platform。
- Codex／Claude／Hermes／DSH adapter。
- Global hook。
- Worktree／branch／review／merge governance。

## B. Current memory surfaces

確認至少覆蓋：

```text
.memory/logs/ai_core_memories.jsonl
.memory/archive/source_memories.jsonl
.memory/archive/legacy_canonical_memories.jsonl
.founder-vault/**
.founder-vault/memory-summary.md
```

並檢查：

- 名稱含 `canonical` 是否被錯當current authority。
- Founder Vault curated file與projection是否仍有待audit區分。
- `memory-summary.md` 是否明確可重建且需source refs。

## C. Memory pipeline

確認：

```text
AI Core source refs
→ RawEvidence semantics
→ Personal Memory Candidate
→ Governance／Acceptance
→ Personal Canonical Memory
→ Founder Vault／Recall projections
→ Correction／Supersession
```

沒有繞過Candidate／Acceptance／Single Writer。

## D. Memory kinds

確認Phase-1 kinds合理：

```text
PREFERENCE
WORKING_STYLE
PRINCIPLE
LESSON
DECISION
PROJECT_CONTEXT
PERSON_CONTEXT
PROCEDURE
LONG_LIVED_CONSTRAINT
```

並確認 transient task status、command output、branch/worktree state不會自動升長期記憶。

## E. Work boundary

確認：

- Task Card／Work status只作source ref。
- Work accepted不自動等於memory accepted。
- Closeout由AI Core擁有。
- 記憶團隊不修改 `.work` 或task card。

## F. Projection／Recall

確認：

- Founder Vault folder是view，不是schema authority。
- summary有source refs與build semantics。
- mixed-scope memory不會產生unrestricted global summary。
- recall有context budget／freshness／scope／gap notice。

## G. Backlog

確認：

```text
PMEM-00
= read-only memory surface／authority audit
```

是唯一可準備的下一步；PMEM-01之後全部正確blocked／deferred。

---

# 6. Output format

請只回：

```text
VERDICT: ACCEPT | AMEND | BLOCK

SCOPE-CONFIRMED
- AI Core remains complete: YES | NO
- Memory-only capability slice: YES | NO

LOCKED-AS-IS
- ...

FINDINGS
- ID:
  Severity: BLOCKER | HIGH | MEDIUM | LOW
  File:
  Section / field:
  Problem:
  Evidence:
  Authority impact:
  Proposed amendment:
  Fixture/test required:

OPEN DECISIONS
- ...

READY NEXT
- PMEM-00 read-only authority audit: YES | NO
- PMEM-01 Personal Memory Contract: YES | NO
- Runtime/provider work belongs here: YES | NO
- Reason:
```

`Runtime/provider work belongs here` 的正確預期是 `NO`；若 reviewer主張 `YES`，必須證明沒有擴張Owner intent，也沒有建立第二套 AI Core。

---

# 7. BLOCK threshold

只有以下任一成立才可 `BLOCK`：

- 提案仍會切出／複製完整 AI Core。
- 記憶團隊可修改 AI Core Work authority。
- Legacy檔名可繞過current authority audit。
- Runtime event可直接寫Personal Canonical Memory。
- Founder Vault projection取得不可重建的canonical authority。
- Personal Memory可無review升Company Knowledge。
- PMEM-00需要production mutation才能完成。

一般欄位不足或命名問題只能 `AMEND`，不得重建整套架構。

---

# 8. Forbidden actions

本輪禁止：

- 修改任何repo檔案。
- 建branch／commit／PR。
- 修改AI Core。
- 清理／遷移 `.memory`。
- 改寫Founder Vault。
- 安裝或執行runtime。
- 建Task／Work／Provider／Hook平台。
- 把本提案自行標成Canonical。
