# Organizational Memory OS｜企業組織記憶作業系統

企業 Knowledge SaaS / Organizational Memory 平台。

> 以 Evidence 為起點，把公司每天的工作、文件、訊息、決策與執行結果，轉成可治理、可追溯、可檢索、可持續更新的企業知識與能力。

這個 Repo 是目前 **企業知識 SaaS 的架構、研究、Backlog 與跨機器交接 authority**。它不是 AI Core clone，也不得繼承 AI Core 的單人開發限制、資源假設、parked priority 或 runtime authority。

## 核心原則

- **共享研究，產品優先級獨立。** AI Core 是研究/工程 donor，不是產品天花板。
- **先找先例，吸收成熟工程，不重新發明。** 能直接重用、包 adapter、吸演算法/tests/failure handling，就不要自己重刻。
- **借工程、保架構。** Donor 不得取代 Knowledge Authority、Identity、Permission Authority、Lifecycle 或 Canonical Truth。
- **Knowledge Architecture ≠ Agent Architecture。** Agent / Model / Worker / Runtime 是可替換 executor，不因名稱而自動成為 permanent subsystem。
- **Deterministic First。** 能用 hash、rule、schema、ACL propagation、parser、version compare、projection rebuild 解的事，不要先包 Agent / LLM。
- **Evidence ≠ Knowledge。** Outlook、Teams、Slack、Jira、文件、人的操作、Agent 輸出與 execution receipt 首先都是 Evidence。
- **Candidate ≠ Canonical。** 只有通過 Verification 與 Acceptance 的 Mutation Proposal 才能進正式知識。
- **Permission-before-Retrieval。** 未授權資料不得先被 Search/LLM 看見再過濾。
- **Execution ≠ Verification ≠ Acceptance。** 做過、驗過、批准過是三件不同的事。
- **Knowledge ≠ Procedure / Skill。** 知道什麼與怎麼做是不同資源，以 relationship 連結。
- **Projection ≠ Truth。** Vector / Embedding / Chunk / Search / Graph / Cache 都應可重建。
- **一個平台，多種 Scope。** PERSONAL / TEAM / DEPARTMENT / COMPANY / CLIENT 是資料與權限空間，不是每人各一套 AI Core。
- **Capability + Level + Scope。** 每顆 SaaS Capability 都是完整功能，但有 L1-L4 深度，且可依 Team/User/Client 做 override。

## 核心 Knowledge Spine

```text
Evidence Sources
PDF / Word / Web / Outlook / Teams / Slack / LINE / Jira / Git
人工上傳 / Agent Runtime / System Activity
        ↓
Source Adapters
        ↓
Raw Evidence
        ↓
Normalize / Parse / Validate
        ↓
Atomic Extraction / Object Linking
        ↓
Work Record Projection / Knowledge Candidate
        ↓
Knowledge Staging
        ↓
Permission / Provenance / Conflict / Scope / Freshness
        ↓
Verification Requirement / Actual Verification
        ↓
Acceptance Decision
        ↓
Canonical Knowledge Writer
        ↓
Canonical Knowledge
        ↓
Rebuildable Projections
Vector / Search / Graph / Chunk
        ↓
Permission-before-Retrieval
        ↓
Authorized Retrieval Space
        ↓
Intent / Domain Classification
        ↓
Context Budget
        ↓
Bounded Retrieval
        ↓
Answer / Action + Citation / Trace
        ↓
Usage / Feedback / Evaluation Evidence
        ↺ Re-evaluation / Revision Candidate
```

## 2026-08-26 Minimal Core Rebaseline

最新調整不是把 Knowledge OS 退回傳統 RAG，而是重新區分：

- **保留** Evidence、Object/Work Context、Knowledge、Governance、Projection Boundary、Retrieval Policy、Verification/Evaluation。
- **降級** Resident Agent、Conflict Agent、Review Agent、Ingestion Agent、Evaluation Agent 等 Agent-as-architecture；它們只是 executor。
- **保留企業治理** ACL、Provenance、Conflict、Freshness、Single Writer、Permission-before-Retrieval、Context Budget、Retention、Source Deletion。
- **Multi-Agent** 改為 High Risk / Conflict / Low Confidence 時的 escalation strategy，不是 default topology。

完整裁決：[`文件/最小核心重基準.md`](文件/最小核心重基準.md)

## 接手請先讀

第一份讀：[`下一台電腦從這裡開始.md`](下一台電腦從這裡開始.md)

之後依序：

1. [`文件/架構憲章.md`](文件/架構憲章.md)
2. [`文件/最小核心重基準.md`](文件/最小核心重基準.md)
3. [`文件/核心知識主幹.md`](文件/核心知識主幹.md)
4. [`文件/MVP與優先級.md`](文件/MVP與優先級.md)
5. [`文件/個人證據與工作紀錄.md`](文件/個人證據與工作紀錄.md)
6. [`文件/權限政策與設定治理.md`](文件/權限政策與設定治理.md)
7. [`文件/上下文預算與檢索.md`](文件/上下文預算與檢索.md)
8. [`文件/驗證治理.md`](文件/驗證治理.md)
9. [`文件/SaaS能力等級.md`](文件/SaaS能力等級.md)
10. [`文件/SaaS控制平面.md`](文件/SaaS控制平面.md)
11. [`文件/先例技術來源地圖.md`](文件/先例技術來源地圖.md)
12. [`文件/待辦重整.md`](文件/待辦重整.md)
13. [`文件/企業產品能力.md`](文件/企業產品能力.md)
14. [`文件/AI-Core邊界.md`](文件/AI-Core邊界.md)
15. [`文件/禁止重刻政策.md`](文件/禁止重刻政策.md)
16. [`文件/未決問題與已定裁決.md`](文件/未決問題與已定裁決.md)

## MVP North Star

MVP 是一條最小垂直閉環，不是整個產品：

```text
Jira / 文件為主，Outlook / Teams 作下一步來源
→ Raw Evidence + Provenance
→ Object / Work Context / Candidate
→ Staging
→ Review / Conflict / Approval
→ Canonical Knowledge
→ Permission-before-Retrieval
→ Context Budget + Bounded Retrieval
→ PM/RD Answer + Citation
→ Machine/Human Evaluation
→ Failure → Correction → Re-evaluation
```

Advanced Graph UI、Achievement、Skill Marketplace、Shared Blackboard、Multi-Agent Runtime 都不是 MVP blocker。

## 三個狀態維度不可混用

- **架構優先級**：P0 / P1 / P2 / Trigger-based
- **交付成熟度**：MVP / NEXT / NORTH STAR
- **商業能力等級**：L1 / L2 / L3 / L4

一個 Capability 可以是 P0，但第一版只交付 L1。
