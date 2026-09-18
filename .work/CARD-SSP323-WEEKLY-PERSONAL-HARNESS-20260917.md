---
id: SSP323-WEEKLY-PERSONAL-HARNESS-20260917
status: READY
jira: SSP-323
parent_jira: SSP-286
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-323｜EMEM-09 員工個人知識每週沉澱 Harness

## 目標

不是替每位員工建立另一套 AI、AI Core、Memory Runtime 或中央 Personal DB。

目標是把既有 Employee Personal Memory Standard 與 AI Core 已驗證的 memory/harness 原則，泛化成員工可交給自己既有 ChatGPT／Claude／Gemini／其他 AI 平台執行的 Personal Memory Harness／Skill。

```text
Employee Existing AI Platform
        ↓ executor only
Company Personal Harness / Skill
        ↓
Local Personal Evidence / WorkRecord / Personal Memory
        ↓
Weekly Grill
        ↓
Personal Memory / Promotion Candidate / NEEDS_ORG_FOLLOWUP
```

## 直接重用，不重做

### Organizational Memory OS authority

直接沿用：

- `規格/v0.1/personal-harness-integration.yaml`
- `RawEvidenceEnvelope / SourceAnchor / Object / ObjectLink / WorkRecord`
- `PersonalMemoryCandidate / PersonalMemoryRecord`
- `VerificationReceipt / AcceptanceReceipt`
- `MemoryCorrectionProposal / MemorySupersessionReceipt`
- `MemoryPromotionProposal`
- `EMPLOYEE_PRIVATE / COMPANY_MANAGED_PERSONAL / SHARED_WORK_CONTEXT`
- Permission-before-Retrieval、Provenance、Candidate != Record、Personal != Company Canonical。

### AI Core primary donor

只吸收可泛化能力，不搬 developer baggage：

- local snapshot / local evidence boundary
- immutable evidence → candidate
- candidate != canonical
- memory gate
- dedup / history preservation
- bounded recall / context discipline
- runtime/model-neutral executor
- vendor projection 可替換

不搬：task／branch／worktree／runtime session／developer review／deploy identity。

## Contract delta

### 1. Platform-neutral / portable Personal truth

- AI 平台只是 executor，不是 Personal Memory authority。
- ChatGPT／Claude／Gemini／其他相容 executor 可替換。
- vendor memory/cache/context 不得成唯一 truth。
- Personal Evidence、WorkRecord、Personal Memory、Weekly Grill history、Promotion history 必須有平台中立本機持久層或可攜格式。
- 更換 AI 平台不得要求改寫 Personal Memory lifecycle 或 knowledge migration。

### 2. Local-first boundary

- 完整 Personal Evidence／WorkRecord／Personal Memory 預設留本機。
- 禁止持續同步完整 PERSONAL data 到公司端。
- 不新增第二套中央 Personal Memory DB、workflow engine 或常駐 Agent Runtime。
- 公司端只得到明確送出的 promotion/follow-up package 與 weekly closeout receipt。

### 3. Weekly Grill

每週深度沉澱必須先做整合，再提問：

```text
This Week Evidence / WorkRecord
+ Historical Personal Memory / WorkRecord
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

要求：

- 不使用固定問卷當核心流程。
- 優先問高資訊價值缺口：反覆模式、矛盾、被推翻結論、缺 decision rationale、適用條件、長期 workaround、隱性 procedure 等。
- 本人可回答的問題，當次 Grill 追問到能明確處置；不把可完成的尾巴任意拖到下週。
- 真正無法回答／缺外部 evidence，而仍有高組織價值時，輸出 `NEEDS_ORG_FOLLOWUP`。
- `suggested_expert` 只是 optional hint；`null` 合法。

#### Cadence / schedule policy

MVP 預設節奏：

```text
每週五下午
→ 提醒員工啟動 Weekly Grill
→ 若當日因休假、國定假日、工作衝突或未完成
→ 順延到下一個工作日補做
```

規則：

- 「週五下午」是 MVP 的預設組織政策，不是 Personal Memory core lifecycle 的硬編碼。
- Tenant / Company 可透過組織政策調整 weekly anchor（例如週四、其他工作週最後一天）；不得因此 fork Personal Memory contract。
- 未指定精確時刻時只表達 afternoon window，不在核心契約硬寫固定 clock time。
- 補做時仍關閉原本應回顧的週期，不把下一個工作日的新資料混成第二次同週回顧。
- 同一 review period 最多產生一個有效 weekly closeout；retry / catch-up 不得造成 duplicate Promotion 或 duplicate closeout。
- `SKIPPED` 必須是明確處置，不可把「週五沒做、下一工作日待補」提前記成永久略過。

### 4. Batch acceptance UX

- 員工不逐條按 Accept。
- 一次 Weekly Knowledge Bundle review：修正 AI 誤解、補 context/evidence、標敏感、要求 redaction，最後一次確認。
- UX batch 不代表資料合併：底層每筆 Candidate／Record 仍有獨立 identity、support、verification、acceptance、correction/supersession history。
- 禁止把整份 weekly report 壓成一條 Personal Memory。

### 5. Historical comparison / dedup

允許等價命名，但至少能表達：

- `UNSEEN`
- `UNCHANGED`
- `NEW_EVIDENCE`
- `MATERIALLY_CHANGED`
- `CONTRADICTED`

規則：

- `UNCHANGED` 不重送 Promotion。
- recurrence 可留在本機 supporting history。
- 新 Evidence 只有實質改變 evidence strength、applicability、risk、conflict、redaction requirement 或 conclusion 時才建立 update/revision。
- Material change 沿用既有 Correction / Supersession，不另建 revision workflow。

### 6. Organizational Value Assessment

`Organizational Value Assessment != Promotion Eligibility`

Assessment 至少可說明：

- repeatability
- impact scope
- reusability
- cost of not knowing / rework / error
- decision rationale value
- scarcity
- stability
- evidence strength
- sensitivity / permission constraint

不要求假精準單一分數；必須輸出可讀 reasons。

### 7. Employee correction / veto boundary

- 員工可 correction、補 evidence/context、標 sensitivity、要求 redaction、說明 applicability。
- `COMPANY_MANAGED_PERSONAL` / `SHARED_WORK_CONTEXT` 等公司工作資料：不能只靠「我不想傳」阻止符合公司 policy 的 organizational-value proposal。
- 上述不等於自動 promotion；仍受 source ACL、policy、redaction、verification、review、single writer。
- `EMPLOYEE_PRIVATE` 未經本人 consent 不得送公司，fail closed。
- Physical location != ownership：資料在員工電腦上不代表自動屬於 EMPLOYEE_PRIVATE。

### 8. Weekly closeout receipt

公司端最多接收輕量狀態：

- COMPLETE
- FAILED
- SKIPPED
- NO_PROMOTION

或等價語意。

不得要求額外上傳「本週做了什麼」摘要來推估公司完整 Knowledge Boundary。

## 不屬本卡

- 公司 taxonomy/domain 建立
- 跨員工 expert routing
- Organizational conflict resolution
- Team/Company Acceptance
- Canonical Writer
- 公司 Knowledge Boundary coverage 推估
- 新 AI UI / chatbot

## Acceptance

1. 同一份 Personal Store 可由至少兩種 executor fixture 處理，核心 Candidate/Record 語意不因 vendor 改變。
2. 換 AI executor 不需 migration Personal truth。
3. Weekly Grill 先整合後問、動態追問，不以固定 questionnaire 冒充完成。
4. 一次 batch confirmation，但逐 Candidate support/acceptance trail 可追。
5. `UNCHANGED` 不重送；material change 走既有 revision/correction/supersession。
6. `NEEDS_ORG_FOLLOWUP` 在 `suggested_expert=null` 時合法且不得升為 Knowledge。
7. COMPANY_MANAGED/SHARED work material 的 simple veto 不能取代 policy gate；EMPLOYEE_PRIVATE 無 consent fail closed。
8. Company receipt 不包含完整 Personal Store 或 weekly work summary。
9. MVP 預設每週五下午觸發 review window；未完成時順延下一工作日，且同一 review period 不得重複 closeout／Promotion。

## Hard stops

- no second Knowledge DB
- no second workflow engine
- no per-employee AI Core
- no mandatory vendor AI runtime
- WorkRecord != Personal Memory
- model confidence != verification
- vendor memory != Personal truth
- Personal Harness 不取得 Company Canonical authority

## Pilot binding

SSP-295 必須用真人 + 既有 AI 平台驗證本卡，而非只靠 synthetic schema fixture。
