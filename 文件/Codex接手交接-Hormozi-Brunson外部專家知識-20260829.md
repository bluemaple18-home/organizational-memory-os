# Codex 接手交接｜Hormozi／Brunson 外部專家知識案例｜2026-08-29

狀態：

```text
BRANCH_ONLY_HANDOFF
RESEARCH_BASELINE_COMPLETE
IMPLEMENTATION_NOT_STARTED
NO_MAIN_MERGE_AUTHORITY
NO_CURRENT_FRONTIER_CHANGE
NO_AICORE_MUTATION
```

Repository：

```text
bluemaple18-home/organizational-memory-os
```

工作分支：

```text
research/hormozi-brunson-business-brain-intake
```

研究起點 commit：

```text
90dc00a25a077a9b194d7ee704790cbe5d544c84
```

主要研究文件：

```text
文件/Hormozi-Brunson開源商業知識吸收研究.md
```

---

## 1. 一句話接手要求

不要重新做「Hormozi／Brunson 有沒有開源、開源了什麼、該放 AI Core 還是 Knowledge SaaS」的概念研究。

這些已完成。

Codex 的預設下一步是：

```text
讀取既有研究
→ 對 source pin、license、能力範圍、authority boundary 做 exact review
→ 判斷是否足以進入 bounded source-pack candidate
→ 回報缺口
```

預設不是：

```text
開始實作 Business Council
開始做 RAG
安裝外部 Skill
建立 Vector DB
修改 main backlog
修改 aicore
```

---

## 2. 目前做到什麼程度

| 工作面 | 狀態 | 說明 |
|---|---|---|
| Primary donor 定位 | `COMPLETE` | 已鎖定 `coreyhaines31/marketingskills` |
| Primary donor commit pin | `COMPLETE` | `b1aaa3619e747f4a836c61e03084c4a531de1262` |
| Primary donor license | `COMPLETE` | MIT；已記錄 attribution 邊界 |
| Secondary donor 定位 | `COMPLETE` | `SaidLopez/MoziAI`，只作小型 RAG prior art |
| Secondary donor commit pin | `COMPLETE` | `9eb07c7f024616783ab507122fe3baa53342c79e` |
| Marketing Council protocol teardown | `COMPLETE` | grounding、dissenter、disagreement、recency、no fabricated quote 已整理 |
| Hormozi capability teardown | `COMPLETE` | advisor dossier + offers workflow + references + eval 已拆清楚 |
| Brunson capability teardown | `COMPLETE` | advisor／framework 已整理，並確認缺獨立 funnel execution pack |
| Product Marketing Context schema | `COMPLETE_AS_REFERENCE` | 欄位可吸收，`.agents/product-marketing.md` authority path 不採 |
| Organizational Memory OS mapping | `COMPLETE` | 已映射 Source／Evidence／Candidate／Conflict／Verification／Acceptance／Projection |
| Knowledge／Procedure／Runtime boundary | `COMPLETE` | 已明確禁止 advisor output 直接 canonicalize |
| Source-to-local disposition | `COMPLETE` | MINE／ABSORB／ADAPT／REFERENCE／REJECT／QUARANTINE 已列 |
| Framework conflict map | `COMPLETE` | Offer-first vs Funnel-first 等四組衝突已保留 |
| Copyright／persona hard stops | `COMPLETE` | 不收付費全文、不假冒本人、不捏造背書／quote／數字 |
| Future slices | `COMPLETE_AS_PLAN` | Source capture、framework candidate、conflict、relationship、eval 已拆 |
| Exact primary-work verification | `PARTIAL` | 尚未逐條回到每本書／官方內容確認全部 framework statement |
| OMOS canonical package | `NOT_STARTED` | 尚未建立 manifest／assertions／evidence links／receipts |
| Machine-readable fixtures | `NOT_STARTED` | STD-00 尚未正式鎖定，不應搶先造正式 fixture |
| Business Council runtime／Skill | `NOT_STARTED / OUT_OF_SCOPE` | 若未來施工，屬 AI Core downstream candidate |
| Backlog admission | `NOT_GRANTED` | 本分支不改 Organizational Memory OS 現行 frontier |
| Merge／PR | `NOT_STARTED` | branch only；不得自行開 PR 或合併 main |

整體判斷：

```text
Donor research / architecture intake：足以接手，不需要重查
Knowledge asset implementation：尚未開始
Runtime / Skill implementation：尚未開始，而且不屬本 repo
```

---

## 3. 必讀順序

先讀 branch：

1. `文件/Hormozi-Brunson開源商業知識吸收研究.md`

再讀 main authority：

2. `README.md`
3. `下一台電腦從這裡開始.md`
4. `文件/架構憲章.md`
5. `文件/最小核心重基準.md`
6. `文件/核心知識主幹.md`
7. `文件/知識庫標準文件規格-v0.1-草案.md`
8. `文件/STD-00-Schema-Vocabulary-Freeze-v0.1-提案.md`
9. `文件/AI-Core邊界.md`
10. `文件/禁止重刻政策.md`
11. `文件/待辦重整.md`

不要只讀本交接文件就施工。

---

## 4. 不可翻案的 authority boundary

```text
Evidence != Knowledge
Candidate != Canonical
Verification != Acceptance
Knowledge != Procedure / Skill
Projection != Truth
Advisor Projection != Real Person
Public Framework != Personal Endorsement
Runtime Completed != Accepted Decision
```

責任分工：

```text
Organizational Memory OS
- source identity
- evidence
- provenance / attribution
- framework claims
- conflicts / limitations / freshness
- verification / acceptance
- canonical framework knowledge
- Knowledge → Procedure relationship
- promotion authority

AI Core（只有未來 downstream candidate）
- advisor routing
- business-council execution
- offer workflow
- funnel workflow
- bounded run artifacts
- executable eval

Model / Runtime
- 只消費已授權 bounded context
- 只產 analysis / proposal / receipt
```

若任何提案讓外部 advisor、模型、Skill 或 runner 直接寫 Canonical Knowledge，判定為 `BLOCK`。

---

## 5. Codex 預設任務：唯讀驗證

### 5.1 驗證 source pins

逐一確認：

```text
coreyhaines31/marketingskills
commit b1aaa3619e747f4a836c61e03084c4a531de1262

SaidLopez/MoziAI
commit 9eb07c7f024616783ab507122fe3baa53342c79e
```

確認研究文件列出的 exact paths 在 pinned commit 存在。

### 5.2 驗證授權

確認：

- 主 repo license 與檔案內容沒有矛盾。
- MIT 只涵蓋 donor repo 自身內容，不自動授權 donor 引用的書籍／課程／第三方素材。
- 任何 substantial copy 都保留原 copyright notice 與 permission notice。
- 未授權付費 corpus 不得進 public repo。

### 5.3 驗證能力描述

確認：

- `marketing-council` 確實有 simulation、dissent、grounding、recency、no fabricated quote 規則。
- Hormozi 確實不只有 dossier，另有 `offers` execution material。
- Brunson 在 pinned commit 確實沒有同等成熟的獨立 funnel／value-ladder execution Skill。
- `product-marketing` 提供共用 context schema，但不應成為 OMOS canonical path。
- MoziAI 沒有合法附完整書籍 corpus。

### 5.4 驗證研究是否越權

確認研究文件沒有：

- 修改 main priority；
- 把 AI Core P2 priority 偷渡成 Knowledge SaaS priority；
- 把 Agent／Persona 變成 Knowledge architecture subsystem；
- 把 framework summary 當 primary source；
- 把未驗證數字當 canonical fact；
- 授權 runtime／installer／RAG 實作。

---

## 6. Codex 回覆格式

預設只回 review，不改檔：

```text
VERDICT: READY_FOR_BOUNDED_SOURCE_PACK | AMEND_RESEARCH | BLOCK

LOCKED-AS-IS
- ...

FINDINGS
- ID:
  Severity: BLOCKER | HIGH | MEDIUM | LOW
  File:
  Section:
  Source repo / commit / path:
  Problem:
  Authority impact:
  Minimal amendment:

SOURCE COVERAGE
- Confirmed:
- Unconfirmed:
- Incorrect / stale:

IMPLEMENTATION READINESS
- Source capture pack: READY | NOT_READY
- Framework candidate inventory: READY | NOT_READY
- Conflict synthesis fixture: READY | NOT_READY
- Canonical package: BLOCKED_BY_STD_00 | READY
- AI Core downstream handoff: READY | NOT_READY

NEXT BOUNDED ACTION
- ...
```

Finding 必須指向 exact section、repo、commit、path；不要只寫「可再完整一點」。

---

## 7. 若使用者另行授權 branch-only candidate pack

只有使用者明確說可以施工後，才進此段。

### 7.1 允許的最小範圍

可建立 branch-only candidate artifacts，用來驗證 external expert knowledge intake：

```text
A. source manifest candidate
B. framework claim inventory candidate
C. attribution / conflict inventory candidate
D. evaluation fixture candidate
E. Knowledge ↔ Procedure relationship candidate
```

### 7.2 在 STD-00 未鎖定前

不得宣稱任何 artifact 是正式 OMOS conformance package。

只能標：

```text
DRAFT
CANDIDATE
NOT_CANONICAL
SCHEMA_PENDING
NO_CANONICAL_WRITE
```

不得搶先建立或宣告：

- accepted Canonical Knowledge；
- Verification PASS；
- AcceptanceReceipt；
- Canonical Writer receipt；
- production schema migration；
-正式 fixture authority。

### 7.3 Candidate 最低欄位

每個 source／claim candidate 至少要保存：

```text
source repository
source commit
source path
source URL
license
capture time
claim kind
claim statement
source anchor
attribution
scope / applicability
limitations / blind spots
freshness requirement
verification status
canonicality = CANDIDATE
acceptance = PENDING
```

### 7.4 Exact anchor

GitHub donor 使用：

```text
repository
commit SHA
path
line range（若可穩定取得）
blob SHA（若可取得）
```

不能只引用 repo 首頁。

---

## 8. 暫時禁止的施工

本分支禁止：

1. 修改 `main`。
2. 開 PR 或 merge，除非使用者另行明確授權。
3. 修改 `bluemaple18-home/aicore`。
4. 建立 Business Council runtime。
5. 建立 Offer／Funnel Agent。
6. 安裝 `npx skills add`、Claude plugin、hooks、MCP、submodule。
7. 新增 Vector DB、Embedding pipeline 或完整 RAG。
8. 提交書籍、課程、會員內容或未授權逐字稿。
9. 宣稱真人背書、合作或本人數位分身。
10. 使用捏造 quote。
11. 將 unsourced number 標成 FACT／METRIC。
12. 修改現行 Raw Evidence／Document／Jira／Permission frontier。
13. 因本案例建立新 canonical registry、ledger、FSM 或 authority store。
14. 直接把上游 schema 或 `.agents/product-marketing.md` 搬成 OMOS authority。

---

## 9. Stop conditions

遇到以下狀況停止並回報，不自行補洞：

- pinned commit／path 不存在或內容與研究描述不符；
- license／third-party rights 不清楚；
- claim 只能從二手 summary 找到，找不到 primary source；
- 需要付費／私人內容才能驗證；
- STD-00 尚未鎖定，但任務要求正式 canonical package；
- 任務開始要求 runtime、Agent、Skill execution；
- 任務要求改變 Knowledge SaaS current frontier；
- 任務要求修改 aicore；
- 需要真人 acceptance authority；
- 需要公開、發布、合併 main 或開 PR。

---

## 10. 這份交接如何節省開發

Codex 不需要再花時間完成：

- 搜尋「商業大腦」開源 repo；
- 判斷哪個 donor 最接近需求；
- 重查 marketing-council 目錄；
- 重拆 Hormozi 與 Brunson 能力差異；
- 重做 license baseline；
- 重做 Knowledge／Procedure／Runtime 邊界；
- 重畫 source-to-local disposition；
- 重想 framework conflict；
- 重列版權與 persona red lines；
- 重拆未來最小 slices。

Codex 只需從：

```text
exact verification
→ bounded gap amendment
→ 經授權後的 candidate artifact
```

繼續。

---

## 11. 完成定義

預設唯讀 review 完成條件：

- pinned sources 已核對；
- license boundary 已核對；
- capability descriptions 已核對；
- authority leak 已檢查；
- findings 具 exact path／section；
- 明確裁決是否能進 bounded candidate pack；
- 沒有任何 repo mutation。

若未來獲授權建立 candidate pack，另需：

- 所有 artifacts 明確標示 `DRAFT / CANDIDATE / NOT_CANONICAL`；
- 每個 claim 可追到 exact source anchor；
- attribution、conflict、limitation、freshness 分離；
- 沒有 unsourced FACT／METRIC；
- 沒有 runtime 或 aicore 變更；
- 沒有改 main priority；
- diff 僅限本研究分支與明確批准的 paths。
