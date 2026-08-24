# SaaS 能力等級

## 核心產品原則

所有 Capability 都是完整功能，但每個 Capability 有自己的能力深度 Level。不能只用「有沒有這個功能」區分方案，也不能要求整家公司全部同一 Level。

統一 Level 語言：

- L1 基礎：完整可用、偏人工控制
- L2 自動化：重複工作自動化
- L3 智慧化：跨資料關聯、判斷、品質與主動建議
- L4 自治化：持續監測、主動行動、閉環學習，但仍受 Authority Gate 約束

## 每顆 Capability 可獨立 Level

例：

```text
某 Tenant
Ingestion              L2
Personal Knowledge     L3
Governance             L2
Permission             L4
Retrieval              L3
Evaluation             L2
Knowledge Graph        L1
Channels               L2
Knowledge→Skill        L1
```

同一 Capability 還可以依 Scope override：PM Team=L3、Sales=L1、特定 Client=L2。

## Capability 內部也可有少量 Advanced Override

對外保持單一 Level；對內可讓 FDE / Admin 對必要子能力微調，例如 Retrieval=L3，但 Graph=L1、Freshness=L3、Context Budget=L2。

不要把產品做成十幾個 slider；Level 是主要商業語言，Override 是進階控制。

## Capability 範例

### Personal Knowledge
- L1：Evidence → 個人 Knowledge，偏人工確認
- L2：Outlook / Teams / Jira 自動 Evidence
- L3：Cross-source Work Correlation / WorkRecord / Closeout / Scope Suggestion
- L4：主動沉澱、補 Evidence、Personal→Team→Company promotion proposal

### Retrieval
- L1：基本 semantic / keyword
- L2：Hybrid + Rerank
- L3：Context Budget + authority/freshness routing
- L4：Adaptive graph / multi-source learning retrieval

### Evaluation
- L1：Golden Questions
- L2：Machine + Human Eval
- L3：Failure Classification + Regression
- L4：Continuous Evaluation + Repair Proposal

### Governance
- L1：人工 Review / Approve
- L2：Duplicate / Conflict / Provenance 輔助
- L3：Lifecycle / Freshness / Supersession
- L4：主動治理建議與持續巡檢

## 不可做付費牆的 Safety Floor

基本 Permission-before-Retrieval、Tenant isolation、最低 Provenance/Audit、Canonical Single Writer 不因方案較便宜而取消。可收費的是更細粒度政策、更長 audit retention、更進階 workflow，而不是降低安全底線。

## 工程與商業分離

工程 Backlog 可以拆很細；客戶看到的是 Capability + Level。工程 boundary、成本 boundary、權限 boundary、商業 boundary 應盡量對齊，但不能為收費硬切不自然的系統邊界。