# 個人知識庫交付落差 — 事實核對報告

**目的**：把「契約簽了、產品沒做」這個落差查清楚，並核對一份外部分析的每一項指控。
**狀態**：**純查核，沒有改動任何產品碼。**
**產出**：哪些成立、哪些不成立、哪些沒能重現。

---

## 0. 一句話結論

> **契約 `ACCEPTED_GO` 被當成了產品能力交付；`EMEM-11` 的基礎設施 DoD 被當成了完整 runtime 交付。**

27 個契約區塊，產品實際實作 6 個。

---

## 1. 可量化的落差

### 1.1 契約區塊 vs 產品實作

對 `規格/v0.1/personal-harness-integration.yaml` 的 27 個能力區塊，
逐一檢查 `product/personal-memory/lib/` 是否實作：

| 類別 | 數量 | 區塊 |
|---|---|---|
| **真正實作** | **6** | `personal_memory_host_binding_v1`、`personal_memory_runtime`、`weekly_review_cycle`、`historical_comparison`、`runtime_policy`、`memory_kinds`（但見 §3.1） |
| 只讀一個鍵／只有註解 | 3 | `capability_safety_floor`（註解）、`correction_flow`（註解）、`personal_memory_resource_contracts`（只讀 id_templates） |
| 有驗證器但產品不產出 | 2 | `minimal_evidence_package`（載入 shape validator，CLI 無任何指令可產出）、`evidence_package_revision` |
| **完全沒有** | **16** | `recall_context_pack`、`promotion_flow`、`core_pipeline`、`core_pipeline_promotion_binding`、`personal_memory_record_minimum`、`capability_levels`、`capability_matrix`、`level_transitions`、`organizational_value_assessment`、`employee_memory_profile_minimum`、`source_profiles`、`role_profiles`、`work_record`、`projection_views`、`personal_memory_governance`、`company_side_evidence_boundary` |

### 1.2 MCP 工具面

`lib/omos/mcp_server.rb`：`TOOLS = [ReadTool, WriteTool, CloseoutTool]`
（Codex 另加 `BindSessionTool`）。

`personal_memory_read` 的回傳只有 `kind` 與 `row_id`，**不含內容**。

---

## 2. 外部分析的逐項核對

### 2.1 ✅ 成立：原始規劃早就包含這些能力

`文件/待辦補充-個人知識庫Harness-20260830.md`（EMEM-06 Pilot 成功指標，原文）：

```
- 一次 batch confirmation，但底層 Candidate acceptance 可追溯。
- Recall 有 citation / freshness / gap notice。
- Correction 不破壞 history。
- `UNCHANGED` 不重送；material change 才 revision／update。
- Promotion 無法跳過既有 review / ACL / redaction / writer。
- 公司只收到 Minimal Evidence Package，不取得完整 Personal Store。
- 公司不得 reverse browse / search / pull 員工 Local Personal Store。
```

Pilot 的業務流程也完整畫出 `Jira + Documents Evidence → ObjectLink / WorkRecord
→ Weekly Grill → Batch Review → Personal Memory / Promotion Candidate
→ Minimal Evidence Package → Organizational Layer`。

**這些需求從未被移除，至今仍在 current 文件裡。** 不是後來才想到。

### 2.2 ✅ 成立（最關鍵）：EMEM-11 自己宣告過七個 MCP surface，DoD 一項都沒追蹤

`CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918.md` §4
「Local STDIO MCP 是 v1 Host access surface，共用一個 namespaced
Personal Memory MCP contract，**至少承載**」：

| 宣告的 surface | 產品實際 |
|---|---|
| resolve / create host-session binding | ✅ |
| **permission-aware bounded recall** | ❌ 不存在 |
| **capture Evidence / WorkRecord input** | ❌ 不存在（只有 CLI `import`） |
| create / update PersonalMemoryCandidate path | ⚠️ 只有 generic `write` |
| **correction / supersession proposal path** | ❌ 不存在 |
| weekly review **due** / closeout operations | ⚠️ 只有 `closeout`，`due` 沒有 MCP 面 |
| **health / version / capability query** | ❌ 不存在（`doctor` 只有 CLI） |

同一張卡的 DoD（§「DoD」）九條：

```
- Slice 1/2/3 全部 machine-readable contract / fixtures / validators 完成
- installer / doctor 有 deterministic acceptance
- 已交付 Host（Claude Code）有真人實測
- 同一 Store 在並行 session 下 / permission-narrowing / review-period idempotency
- blocked host（Codex）在三個層級都真的擋得住
- no direct DB access path
- no second lifecycle / second Personal authority
- repo regression 全綠
- independent review GO
```

**九條全部是基礎設施，§4 宣告的七個 surface 一條都沒進 DoD。**

這是可證實的事故點：**同一張卡宣告了能力面，驗收只驗了基礎設施面，然後判 `DOD_MET`。**

### 2.3 ✅ 成立：下游把 DoD_MET 當成能力完成

`CARD-SSP295-FULL-PRODUCT-PILOT-20260921.md` 的 `depends_on` 只看卡片狀態
（`SSP-323_ACCEPTED_GO`、`SSP-324_ACCEPTED_GO`、`EMEM11_DOD_MET_20260920`），
**沒有重播 EMEM-06 原始成功條件**，因此被標成
`ENTRY_CONDITIONS_MET_READY_TO_PLAN`。

### 2.4 ❌ 不成立：`NO_IMPLEMENTATION_AUTHORIZATION` 不在那份檔案裡

該字串**不存在**於 `文件/待辦補充-個人知識庫Harness-20260830.md`。
它出現在 2026-08-28／30 的三份研究包：

```
文件/DeepSeek-Harness整合裁決-current-truth修正-20260830.md
文件/研究包C-ObjectContext與WorkRecord-20260828.md
文件/研究包A-RawEvidence身份時間序與溯源-20260828.md
```

所以「原始規劃宣告不授權實作」這點指的是**研究包**，不是 Harness 待辦文件。
結論方向可能仍對，但引用位置要更正。

### 2.5 ⚠️ 未能重現：「generic write 可偽造 verification=PASS / acceptance=ACCEPTED」

做了一次 bounded 嘗試：以 `LOCAL_CLI` surface 直接
`write_row(kind: "PersonalMemoryRecord", …)`，填入
`verification_status: "VERIFIED"`、`acceptance_status: "ACCEPTED"`
與自己編造的 `verification_ref` / `personal_acceptance_ref`。

**每一次都被擋下來**，依序是：

```
PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE
PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT: 缺 required field origin_candidate_ref
PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT: 缺 required field content
（仍在繼續要求欄位，嘗試中止）
```

`ResourceEvaluator` 做的檢查比該分析假設的多。

**這項指控沒有被重現，不能算成立；但也沒有被推翻**——嘗試是在補齊欄位的
過程中主動中止的，沒有試到底。**要定案需要一次完整的 red-team。**

### 2.6 ✅ 成立：`PersonalMemoryRecord` 是 `write_row` 接受的 kind

```
id_templates.keys =
  ["PersonalMemoryCandidate", "PersonalMemoryRecord",
   "MemorySupportLink", "MemoryConflictSet"]
```

也就是**沒有「只有專用 materializer 能建 Record」這種 writer ceiling**。
是否擋得住偽造，取決於 resource evaluator 的欄位檢查厚度（見 §2.5）。

---

## 3. 本次查核另外發現的問題

### 3.1 `MEMORY_KINDS` 是第二份實作

`lib/omos/inbox.rb:58` 有一份**硬寫死**的 `MEMORY_KINDS` 清單，而契約有
`memory_kinds_phase_1` 區塊。契約改了，產品不會跟著改。

這正是本專案一路在 review 裡被罰的「第二份實作」。**這是 bug，不是缺口。**

### 3.2 `minimal_evidence_package` 有守衛、沒有門

`Contract` 載入了 `minimal_evidence_package_shape` 驗證器，但 CLI 的 21 個
指令裡**沒有任何一個能產出 evidence package**。驗證器在那裡，沒有東西餵給它。

---

## 4. 哪些是後來新增、不是原始規劃漏掉

為了公平，這些是 9 月中後才出現的需求，原始規劃沒有：

Weekly Grill／Friday cadence、週期帳（誰本週做了沒）、Codex／Claude Code
host binding、SQLite local runtime、installer／doctor／rollback／packaging、
cross-host same-store、AI 主動訪問式回顧、人類專屬 closeout（Touch ID）、
clean-macOS qualification。

它們本身是對的工作，而且都通過了獨立 review。**問題是優先序**：
9/18 之後的全部施工都在把「Store ＋ Host ＋ 週期帳 ＋ 安裝」做穩，
原始主幹 `Verification → Acceptance → Record → Recall` 停在契約。

---

## 5. 根因

```
Contract ACCEPTED_GO        →（被當成）→  Product capability delivered
EMEM-11 infrastructure DoD  →（被當成）→  完整 Personal Memory runtime delivered
```

沒有任何機制會顯示這個落差：

- 卡片追蹤的是**卡**，不是**能力鏈**
- `文件/待辦重整.md` 列各卡狀態，沒有「完整能力 = 哪幾格」的圖
- 驗收是每卡自己的 DoD，**沒有跨卡的完整度閘門**
- EMEM-11 §4 宣告的 surface 與 §DoD 之間**沒有交叉檢查**

交付方的責任：連續十四天、十餘張卡都在同一個子系統打磨，
**每次收工只報該卡驗收，從未報「整條鏈走到第幾格」。**

---

## 6. 建議 GPT 覆核的三件事

1. **§2.5 要不要做完整 red-team？** 「generic write 能不能偽造 Record」是本報告
   唯一未定案的指控，而它決定「是否存在 authority ceiling 缺口」這個結論。
2. **§2.4 的引用更正**是否影響該分析的其他推論。
3. **修補順序**：交付方傾向先 Recall（獨立、契約形狀已定、做完立刻讓既有資料
   有用），但那是價值判斷，不是事實判斷，請一併覆核。

---

## 7. 現況（供對照）

```
產品：3a 26/26 · 3b 46/46 · 3c 484/484 · 40/40 validators · diff --check clean
交付包 ZIP SHA-256 2e7f883bd905d43cbc9722cb1eb0c22657772dcb1f24970e6b7c4415089c1bab
repo 已同步至 557f09a；本報告未改動任何產品碼
```
