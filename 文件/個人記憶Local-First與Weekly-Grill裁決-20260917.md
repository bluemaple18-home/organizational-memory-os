# 個人記憶 Local-First 與 Weekly Grill Owner 裁決｜2026-09-17

狀態：`OWNER_DECIDED / MVP_AMENDMENT / NO_SECOND_ARCHITECTURE`

對應 Jira：

```text
SSP-323 / EMEM-09 Weekly Personal Knowledge Harness
SSP-324 / EMEM-10 Minimal Evidence Package
SSP-295 / EMEM-06 Product Department Pilot
SSP-286 / MVP closure
```

本文件不是新 Personal Memory 架構。它只把 2026-09-17 Owner 裁決正式掛回既有 Employee Personal Memory Standard，並說清楚 AI Core donor 與 Organizational Memory OS authority 的關係。

---

## 1. Authority

```text
Organizational Memory OS
= employee/company Personal Memory product authority

Employee Personal Memory Standard
= shared contract / lifecycle / permission / promotion authority

AI Core
= primary internal donor for proven memory/harness governance patterns

Employee AI Platform
= optional/replaceable executor
```

不得倒置：AI Core、ChatGPT、Claude、Gemini、Agent、Model、Skill 都不能取得 Personal/Company Canonical authority。

---

## 2. 直接沿用，不重做

### Organizational Memory OS 已有 contract

- Raw Evidence / SourceAnchor
- Object / ObjectLink / WorkRecord
- PersonalMemoryCandidate / PersonalMemoryRecord
- Verification / Acceptance
- Permission / Retention / Deletion
- Recall / MemoryContextPack
- Correction / Supersession
- Personal → Shared Promotion
- Canonical Single Writer
- Permission-before-Retrieval

### AI Core donor

可吸收：

```text
local snapshot / local evidence boundary
immutable evidence → candidate
candidate != canonical
memory gate
dedup / history preservation
bounded recall / context discipline
runtime/model-neutral executor
vendor projection replaceability
```

不搬：

```text
task / branch / worktree
runtime session identity
developer-only milestone taxonomy
deploy / code-review specific semantics
AI Core complete runtime per employee
```

---

## 3. Local-first Personal truth

Owner 裁決：

```text
PERSONAL_STORE_IS_LOCAL_PRIMARY_TRUTH
AI_PLATFORM_MEMORY_NE_PERSONAL_SOURCE_OF_TRUTH
MODEL_AGENT_RUNTIME_REPLACEABLE
PERSONAL_MEMORY_PORTABLE_ACROSS_AI_PLATFORMS
PLATFORM_SWITCH_REQUIRES_NO_CANONICAL_MEMORY_MIGRATION
```

完整 Personal Evidence、WorkRecord、Personal Memory 預設留在員工本機。

公司端不得建立持續同步整份 Personal Store 的路徑。

一般員工不需要完整 AI Core；公司只提供 Harness／Skill／規範，員工使用自己的 AI 平台處理本機資料。

---

## 4. Weekly Grill

Weekly Grill 不是固定問卷，也不是逐 Candidate 問一句、按一次 Accept。

```text
This Week Evidence / WorkRecord
+ Historical WorkRecord / Personal Memory
        ↓
Dedup / Recurrence / Conflict / Change detection
        ↓
Knowledge Recovery
+ Knowledge Discovery
        ↓
Dynamic Grill
        ↓
Disposition
```

### Weekly cadence / reminder

Owner 裁決：

```text
MVP default = 每週五下午
missed / holiday / leave / work conflict
→ 下一個工作日補做
```

這是組織層的 cadence policy，不是核心 Personal Memory lifecycle 常數：

- Tenant / Company 可依工作週調整 weekly anchor，不需要改 Personal Memory contract。
- 未指定精確鐘點時只要求「下午」回顧窗口，不硬編碼固定時間。
- 補做仍針對原 review period 收口，避免跨週後把新資料混成同一週重複回顧。
- 同一 review period 只能有一個有效 closeout；retry / catch-up 必須去重。
- 週五未完成且仍待下一工作日補做，不等於 `SKIPPED`；`SKIPPED` 必須是明確的最終處置。

### Knowledge Recovery

從本週與歷史工作中找回已經形成、但尚未正式外化的：

- reusable conclusion
- decision rationale
- repeated workaround
- stable rule / definition
- lesson
- procedure pattern
- applicability boundary

### Knowledge Discovery

只針對高資訊價值缺口動態追問：

- 為什麼這次這樣決定？
- 哪些條件下這個結論不成立？
- 同樣問題是否反覆出現？
- workaround 是否已變成事實上的流程？
- 舊記憶是否被新 evidence 推翻？
- 是否有明顯缺少的 evidence / rationale？

本人可回答的問題，當次 Grill 應持續追問到能做明確 disposition，不任意拖到下一週。

本人確實不知道／缺外部 evidence，但仍有高組織價值：

```text
NEEDS_ORG_FOLLOWUP
```

`suggested_expert` optional；不知道哪個同事能回答不構成 blocker。

---

## 5. Batch UX，逐 Candidate governance

Owner 裁決：員工不逐條按 Accept。

Weekly Grill 產生一份整合 review bundle；員工可：

- 修正 AI 誤解
- 補 context / Evidence
- 標 sensitivity
- 要求 redaction
- 說明 applicability

最後一次確認整包。

但底層仍必須逐 Candidate 保留：

```text
candidate identity
evidence support
verification
acceptance
correction / supersession history
```

`Weekly Bundle != PersonalMemoryRecord`。

---

## 6. Historical comparison / resend rule

至少能表達以下狀態或等價語意：

```text
UNSEEN
UNCHANGED
NEW_EVIDENCE
MATERIALLY_CHANGED
CONTRADICTED
```

規則：

```text
UNCHANGED
→ no resend

NEW_EVIDENCE with no material effect
→ local recurrence/support history only

NEW_EVIDENCE with material effect
→ evidence update / revision

MATERIALLY_CHANGED
→ correction / supersession proposal

CONTRADICTED
→ correction / conflict proposal
```

不得每週因同一知識再次發生就重送 duplicate Promotion。

---

## 7. Organizational Value Assessment

`Organizational Value Assessment != Promotion Eligibility`

Assessment 不是假精準單一總分；至少可解釋：

- repeatability
- impact scope
- reusability
- cost of not knowing / rework / error
- decision rationale value
- scarcity
- stability
- evidence strength
- sensitivity / permission constraint

高價值仍可能因 source ACL、privacy、policy、verification 不足而不能 Promotion。

---

## 8. Personal vs Company ownership / veto

正式 invariant：

```text
physical_local_storage != employee_private_ownership
```

### COMPANY_MANAGED_PERSONAL / SHARED_WORK_CONTEXT

對公司工作資料：

- 員工可 correction
- 可補 Evidence / context
- 可標敏感
- 可要求 redaction
- 可說明 applicability

但不能只以「我不想傳」取代公司既有 organizational-value / policy gate。

這不等於自動 Canonical；仍需既有：

```text
source ACL
promotion gate
redaction
verification
review
canonical single writer
```

### EMPLOYEE_PRIVATE

未經本人 consent 不得送公司，必須 fail closed。

---

## 9. Personal → Company Minimal Evidence Package

公司只收到明確 promotion/follow-up payload 與最小必要 Evidence Package：

```text
content / statement
evidence_refs
minimal evidence excerpts / bounded artifact subset
source anchor / provenance
source identity / version
timestamp / integrity hash
source ACL snapshot
ownership / visibility / sensitivity
redaction record
organizational value reasons
uncertainty / missing evidence
employee annotation
suggested_expert: optional
```

禁止：

```text
whole Personal Store dump
continuous PERSONAL sync
company reverse browse
company reverse search
company pull / remote-query / remote-mount
```

若公司 verification 後需要更多 evidence，只能形成新的明確 submission/revision；公司不能直接進員工本機查。

---

## 10. Evidence Package 不是公司知識

```text
Evidence Package != Company Knowledge
Promotion Candidate != Company Knowledge
NEEDS_ORG_FOLLOWUP != Company Knowledge
```

Evidence Package 只作：

- review support
- verification support
- audit / dispute / provenance 備查

不得自動進正式 company retrieval / RAG / LLM corpus。

正式 Retrieval 仍只消費通過 Governance + Acceptance + Canonical Single Writer 的 Shared Canonical Knowledge。

---

## 11. Immutable package / revision

每次 package 保留：

- identity
- timestamp
- hash
- provenance
- redaction state

後續 correction / new evidence / sensitivity / policy change 不得原地覆寫舊 package。

重用既有 Correction / Supersession lifecycle；不建立第二套 revision workflow。

---

## 12. Company weekly status boundary

公司可以知道每週知識 closeout 的輕量狀態，例如：

```text
COMPLETE
FAILED
SKIPPED
NO_PROMOTION
```

公司不需要、也不應要求 Personal Harness 額外上傳「這週做了哪些工作」摘要來推估完整公司 Knowledge Boundary。

未知的未知不能被假裝成 gap metric。

---

## 13. Personal / Organizational responsibility split

### Personal layer 可以

- local capture / personal store
- Evidence → ObjectLink / WorkRecord
- Personal Memory Candidate / Record
- Weekly Grill
- correction / annotation / sensitivity
- Organizational Value Assessment
- Promotion Candidate
- NEEDS_ORG_FOLLOWUP
- bounded Minimal Evidence Package submission

### Personal layer 不可以

- 跨員工 route 問題
- 決定 company taxonomy / domain owner
- cross-person conflict resolution
- Team / Company Acceptance
- Canonical write
- browse/search other employees' Personal Store

### Organizational layer 負責

- 收 Promotion Candidate / follow-up lead
- company-side classification / object / domain linking
- provenance / ACL / evidence check
- cross-person follow-up / expert routing
- verification / review / acceptance
- Canonical Single Writer
- Shared Canonical Knowledge

---

## 14. Current implementation binding

```text
SSP-323 / EMEM-09
→ Weekly Personal Knowledge Harness delta

SSP-324 / EMEM-10
→ Minimal Evidence Package / upload boundary delta

SSP-295 / EMEM-06
→ 真人產品部 E2E pilot

SSP-286
→ MVP closure
```

`SSP-294` 已完成的 A/B/C promotion governance 不回退、不重做。

---

## 15. Hard stops

- no second Personal Memory DB
- no second Knowledge DB
- no second Workflow Engine
- no per-employee AI Core requirement
- no mandatory vendor AI runtime
- no vendor memory as Personal truth
- no WorkRecord → Memory direct promotion
- no model confidence → verification/acceptance
- no reverse company access to Local Personal Store
- no Evidence Package as company searchable canonical corpus
- no Personal Harness Canonical Writer authority
- no default cross-person agent routing inside Personal layer
