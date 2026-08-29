# Hormozi／Brunson 開源商業知識吸收研究

日期：2026-08-29

狀態：`RESEARCH_EVIDENCE / DONOR_PINNED / BRANCH_ONLY / NO_MAIN_PRIORITY_CHANGE / NO_RUNTIME_ADOPTION`

## 1. 最終結論

市面上宣稱「複製 Alex Hormozi 與 Russell Brunson 商業大腦」的產品，多半不是訓練出真正的新模型，也不是取得兩人的私人腦內知識，而是以下組合：

```text
公開書籍／影片／Podcast／課程筆記
        ↓
框架整理／Prompt／Advisor Persona
        ↓
RAG 或 Agent Skill
        ↓
以「商業大腦」包裝成顧問介面
```

目前確實存在可用的開源 donor，但沒有發現合法、完整、可驗證地包含兩人全部書籍、付費課程、內部顧問資料與逐字稿的「完整大腦」開源庫。

本次最值得採用的 primary donor 是：

```text
coreyhaines31/marketingskills
```

它提供的真正價值不是大量文本，而是：

1. source-grounded 的模擬顧問協議；
2. Hormozi 與 Brunson 的框架 dossier；
3. Hormozi Offer Design 的可執行 workflow；
4. product-marketing context schema；
5. 可重用的 eval fixtures 與反迎合規則。

正式裁決：

> Organizational Memory OS 應把這批資料視為「外部專家知識 ingestion／provenance／conflict／synthesis」案例，而不是直接把 Business Council、Offer Agent、Funnel Agent 或外部 installer 搬進 Knowledge Architecture。

> 未來若要把 framework cards 轉成可執行的 `business-council / offer / funnel` Skill，屬 AI Core 的 downstream capability candidate；Knowledge SaaS 只擁有來源、知識、權限、驗證、接受與 Knowledge → Procedure promotion authority。

---

## 2. Source pin

### 2.1 Primary donor

```text
Repository: coreyhaines31/marketingskills
Pinned commit: b1aaa3619e747f4a836c61e03084c4a531de1262
License: MIT
Primary language: Markdown / JavaScript support tooling
Primary use: AI agent marketing skills、framework dossiers、eval fixtures
```

本次實際研究 paths：

```text
LICENSE
README.md
skills/marketing-council/SKILL.md
skills/marketing-council/evals/evals.json
skills/marketing-council/references/advisor-template.md
skills/marketing-council/references/advisors/alex-hormozi.md
skills/marketing-council/references/advisors/russell-brunson.md
skills/offers/SKILL.md
skills/offers/evals/evals.json
skills/offers/references/*
skills/product-marketing/SKILL.md
skills/pricing/SKILL.md
```

授權邊界：MIT 允許使用、修改、合併、發布、散布、再授權與商用，但複製 substantial portions 時必須保留原 copyright notice 與 permission notice。

### 2.2 Secondary donor

```text
Repository: SaidLopez/MoziAI
Pinned commit: 9eb07c7f024616783ab507122fe3baa53342c79e
License: MIT
Maturity: small educational prototype
Primary use: Hormozi-style RAG implementation reference
```

MoziAI 明確沒有提交受版權保護的原始書籍，README 要求使用者自行提供有合法使用權的內容。它適合作為 document processing、embedding、retrieval、generation 與 context handling 的教學 donor，不適合作為完整知識 corpus 或 production baseline。

---

## 3. 實際開源了什麼

### 3.1 Marketing Council protocol

`skills/marketing-council/SKILL.md` 定義的是模擬顧問會議協議，而不是人物 cloning：

- `Quick take`：單一 advisor。
- `Council session`：3–5 位 advisor。
- `Full council`：完整顧問席位。
- 每次必須至少安排一位 genuine dissenter。
- 每位 advisor 必須套用其具名 framework，而不是只換名字的通用建議。
- 必須輸出 disagreement map，指出真正 trade-off 與能判定對錯的 evidence。
- 必須標示這是 simulation，不得暗示本人實際審查或背書。
- 不得捏造 direct quote。
- 活著且觀點會變動的 advisor，遇到近期問題應重新查 primary source。
- 私人 advisor 的立場必須由使用者提供，Agent 不得自行發明。

這些規則比「像某位名人說話」更有價值，因為它把 source grounding、反迎合、異議與決策合成變成可驗收協議。

### 3.2 Alex Hormozi dossier

現有 dossier 至少整理：

- Value Equation
- Grand Slam Offer
- Core Four
- Rule of 100
- CLOSER
- Money Models
- 市場、Offer、定價、獲客、回本速度等 signature questions
- 適用範圍與 blind spots

更重要的是，Hormozi 在上游不只有 advisor persona；另有獨立 `skills/offers/` execution workflow，包含：

- Value Equation 診斷
- Core deliverable
- Bonus stack
- Guarantee design
- Scarcity / urgency
- Offer naming
- Price / payment structure
- SaaS offer、service、agency、course、coaching、high-ticket B2B 等 format
- Offer eval fixture

因此 Hormozi donor 的成熟度是：

```text
advisor dossier
＋
可執行 Offer workflow
＋
references
＋
eval
```

### 3.3 Russell Brunson dossier

現有 dossier 至少整理：

- Value Ladder
- Hook–Story–Offer
- Dream 100
- Epiphany Bridge
- Perfect Webinar / Stack
- Continuity / Linchpin
- Funnel、belief change、front-end / back-end monetization 等 signature questions
- 適用範圍與 blind spots

但在 pinned commit 內，Brunson 主要仍是 advisor dossier；沒有同等成熟、獨立的 Funnel／Value Ladder execution Skill。

因此 Brunson donor 的成熟度是：

```text
advisor dossier
＋
framework summary
－
缺獨立 execution workflow
－
缺專屬 funnel eval pack
```

若未來要實作 Brunson execution，必須標成 `SOURCE-GROUNDED LOCAL ADAPTATION`，不能宣稱是上游已完整提供。

### 3.4 Product Marketing Context schema

`skills/product-marketing/SKILL.md` 提供一套共用商業上下文 schema，涵蓋：

- Product overview
- Target audience / ICP
- B2B personas
- Pain points
- Competitive landscape
- Differentiation
- Objections / anti-persona
- Switching dynamics
- Customer language
- Brand voice
- Proof points
- Goals
- Version / changelog

Schema 值得參考，但上游預設 path `.agents/product-marketing.md` 不可直接升格為 Organizational Memory OS 的 canonical location，否則會產生另一份產品真相。

---

## 4. 沒有開源的部分

目前沒有證據顯示上述 donor 合法包含：

- Hormozi 或 Brunson 的完整付費書籍全文；
- 完整付費課程與會員內容；
- 全量 Podcast／影片逐字稿；
- 私人顧問會議與內部 operating data；
- 本人授權的完整數位分身；
- 本人對使用者產品的實際 endorsement；
- 可證明價值「500 萬」的評估或資產證明。

因此「商業大腦」應被拆成以下可驗證資源，不應當作單一神祕物件：

```text
Source Evidence
Framework Claims
Advisor Projection
Decision Protocol
Procedure Candidate
Evaluation Fixtures
```

---

## 5. 對 Organizational Memory OS 的正式用途

這批資料最適合成為 external expert knowledge ingestion testcase，測試：

```text
Pinned public source
        ↓
Raw Evidence + source metadata
        ↓
Atomic framework / claim extraction
        ↓
Attribution / provenance
        ↓
Knowledge Candidate
        ↓
Conflict / limitation / recency review
        ↓
Verification against primary works
        ↓
Acceptance Decision
        ↓
Canonical Framework Card
        ↓
Relationship to Procedure / Skill Candidate
```

### 5.1 對 Knowledge Spine 的映射

| Knowledge Spine stage | 本案例內容 |
|---|---|
| Source | GitHub donor、公開官方文章、合法持有的書籍 metadata |
| Raw Evidence | pinned file、commit、license、capture time、source URL |
| Atomic Extraction | framework、claim、signature question、limitation、attribution |
| Object Linking | Person、Work、Framework、Claim、Use Case、Procedure Candidate |
| Candidate | 尚未完成 primary-source 核對的 advisor dossier 主張 |
| Staging | attribution 衝突、近期觀點、數字主張、適用性爭議 |
| Verification | 對照原書、官方文章、演講與合法來源 |
| Acceptance | 是否可升為 canonical framework card |
| Canonical Knowledge | 已核對的 framework 定義、適用條件、反例與來源 |
| Projection | advisor prompt、搜尋索引、graph relation、retrieval chunk |
| Feedback | 實際 Offer／Funnel 實驗結果，作為新的 Evidence |

### 5.2 本案例可以驗證的核心原則

- Evidence 不等於 Knowledge。
- Advisor dossier 不等於真人。
- 公開 framework 不等於本人 endorsement。
- Candidate 不等於 Canonical。
- Knowledge 不等於 Procedure / Skill。
- Procedure 的執行結果仍是 Evidence，不會自動證明 framework 正確。
- 活著的專家觀點具有 freshness requirement。
- Attribution 必須保存；例如 Dream 100 原始來源應追溯到 Chet Holmes，Brunson 是後續採用與改編者。

---

## 6. Knowledge / Procedure / Runtime authority boundary

正式責任切分：

```text
Organizational Memory OS
- Source / Evidence identity
- Provenance / attribution
- Framework claims
- Conflict / limitation / freshness
- Verification / Acceptance
- Canonical framework cards
- Knowledge → Procedure relationship
- Promotion authority

AI Core（downstream candidate）
- business-council skill
- offer-design execution
- funnel-design execution
- advisor routing
- bounded run artifacts
- eval execution

Model / Agent Runtime
- 讀取已授權 bounded context
- 執行 advisor simulation 或 workflow
- 產生 analysis / proposal / receipt
```

不可逆的語意：

```text
ADVISOR_OUTPUT != VERIFIED_KNOWLEDGE
RUNTIME_COMPLETED != ACCEPTED_DECISION
FRAMEWORK_KNOWLEDGE != EXECUTABLE_SKILL
PUBLIC_METHOD != PERSONAL_ENDORSEMENT
```

---

## 7. Source-to-local disposition

| External component | Disposition | Organizational Memory OS landing | 理由 |
|---|---|---|---|
| `marketing-council/SKILL.md` | `MINE_PROTOCOL` | research / governance reference | 吸收 grounding、dissent、disagreement、recency、no-fabricated-quote 規則；不搬 runtime router |
| Hormozi advisor dossier | `ABSORB_AS_SOURCE_EVIDENCE` | source record → framework candidates | 可加速建立 framework inventory，但需 primary source verification |
| Brunson advisor dossier | `ABSORB_AS_SOURCE_EVIDENCE` | source record → framework candidates | 同上；特別保留 attribution 與 blind spots |
| `offers/SKILL.md` | `MINE_FRAMEWORK_AND_EVALS` | Knowledge ↔ Procedure candidate relation | 不直接在 Knowledge repo 啟動成 skill |
| `offers/references/*` | `SELECTIVE_ABSORB` | candidate framework / operation pages | 只吸收可追溯、可驗證內容 |
| `offers/evals/evals.json` | `ADAPT_AS_EVALUATION_FIXTURE` | evaluation evidence candidate | 上游 assertion 仍需檢查來源與適用性 |
| `product-marketing/SKILL.md` schema | `ADAPT_SCHEMA` | product / market context candidate | 採欄位與版本概念，不採 `.agents/` canonical path |
| `pricing/SKILL.md` | `REFERENCE` | future pricing knowledge research | 不屬本次最小 scope |
| `MoziAI` RAG code | `REFERENCE_ONLY` | implementation prior art | 小型 prototype；沒有知識 corpus |
| `npx skills add` / Claude plugin | `REJECT_FOR_THIS_REPO` | none | installer 與 agent runtime 不屬 Knowledge Architecture |
| Git submodule whole-repo import | `REJECT` | none | 增加 drift、噪音與 authority 混淆 |
| 付費書籍／課程全文 | `REJECT_UNLESS_LICENSED` | private evidence store only if authorized | 版權與商業使用風險 |
| 未驗證數字與成功宣稱 | `QUARANTINE` | staging / needs verification | 不得升格為 canonical claim |
| 模仿名人口氣 | `LIMIT` | optional presentation projection | 不是知識品質核心，且有誤導風險 |

---

## 8. 需要保留的 framework conflict

不要把兩人的方法混成一個模糊「行銷大師共識」。至少保留下列衝突：

### 8.1 Offer-first vs Funnel-first

Hormozi lens：

```text
先確認市場、痛點與 Offer 足夠強，再放大流量。
```

Brunson lens：

```text
設計 Hook、Story、Belief Change、Value Ladder 與 Funnel sequence，讓客戶一路理解、相信與升級。
```

真正要判斷的是：

```text
轉換失敗的 binding constraint
= Offer 本身不夠強
or
= 市場尚未理解／相信／走進正確 sequence
```

### 8.2 Premium price vs Front-end breakeven

Hormozi 常以 premium pricing、stacked value、risk reversal 提高單筆價值。

Brunson 常把 front end 視為 acquisition mechanism，利潤可能位於 upsell、back end 與 continuity。

兩者不是必然矛盾，但必須對照：

- CAC 回收期；
- 毛利；
- 服務成本；
- Enterprise procurement；
- churn；
- 後端產品是否真實存在。

### 8.3 Volume vs Belief change

Hormozi 偏向提高 outreach／content／ads volume 並以數量創造 signal。

Brunson 偏向找出 false belief，透過 story／epiphany／sequence 轉換認知。

需要實驗判斷問題是 exposure 不足，還是 message / belief mismatch。

### 8.4 Direct response vs Enterprise trust

Bonus stacking、urgency、aggressive upsell 在部分 direct-response 市場有效，但在信任導向 B2B、地端部署、資安與長週期採購場景可能造成反效果。

Organizational Memory OS 對外銷售時，必須讓 enterprise buyer、security、legal、IT、data governance 視角成為固定 dissenter，不能只讓 direct-response framework 自我強化。

---

## 9. Hard stops

本研究不得被解讀為下列授權：

1. 不得提交或公開兩人的付費書籍、課程、會員內容與未授權逐字稿。
2. 不得宣稱系統就是 Alex Hormozi 或 Russell Brunson 本人。
3. 不得暗示本人已審查、推薦、合作或背書本產品。
4. 不得製造或杜撰 direct quote。
5. 不得把 advisor dossier 的 claim 直接升為 Canonical Knowledge。
6. 不得把未附 primary source 的數字、收入、轉換率或 churn claim 視為事實。
7. 不得因本案例而新增 Vector DB、Embedding pipeline 或完整 RAG requirement。
8. 不得安裝上游 plugin、installer、hooks、MCP 或 agent runtime 到本 repo。
9. 不得讓外部 advisor output 直接寫 Canonical Knowledge。
10. 不得把人物 persona 變成 permanent architecture subsystem。
11. 不得在本分支修改 AI Core。
12. 不得因 AI Core 將 executable candidate 排為 P2，就自動把 Organizational Memory OS 的 research、schema 或 evaluation priority 也標成 P2。
13. 不得因本研究 branch 存在，就修改 main frontier 或目前 Raw Evidence／Adapter／Permission contract 的施工順序。

---

## 10. Priority 與 downstream 裁決

### Organizational Memory OS

本文件是 research evidence，不自行取得 P0／P1／P2 admission，也不修改現行 frontier。

如果未來拿此案例驗證 external expert ingestion，必須由 Knowledge SaaS 依自己的產品需求獨立排 priority，不能繼承 AI Core 排序。

可選 future use：

```text
External Expert Knowledge Ingestion Testcase
- public source capture
- license / provenance
- framework extraction
- attribution
- conflict
- freshness
- verification
- synthesis
- Knowledge ↔ Procedure relationship
```

### AI Core

可記錄但本分支不施工的 downstream candidate：

```text
AICORE-BUSINESS-COUNCIL-GTM-SOURCE-GROUNDED-INTAKE
Priority: P2 PARKED candidate
```

可能包含：

- source-grounded business-council Skill；
- Hormozi / Brunson advisor projections；
- Offer execution leaf；
- Brunson Funnel / Value Ladder local execution adaptation；
- dissent / conflict / no-fabricated-quote eval；
- Company Knowledge OS 真實 GTM use case。

這只是 cross-repo downstream note，不是本 repo 的 backlog authority，也不是現在修改 `aicore` 的授權。

---

## 11. 未來若 admission，建議最小切片

### Slice A — Source capture

只捕捉 pinned donor files、license、commit、source URL 與 capture metadata。

Acceptance：每個 claim 可回到 exact repo / commit / path。

### Slice B — Framework candidates

建立 Hormozi 與 Brunson framework inventory，分開保存：

- framework name；
- source work；
- accurate definition；
- documented positions；
- signature questions；
- best-for；
- blind spots；
- recency requirement；
- attribution note。

Acceptance：advisor voice 與 framework claim 分離。

### Slice C — Conflict synthesis

產生 `offer-first-vs-funnel-first` synthesis，保留適用條件、反例、evidence requirement 與能推翻建議的 falsifier。

Acceptance：不可輸出「兩人都建議你提升價值與漏斗」之類無法決策的共識句。

### Slice D — Knowledge / Procedure link

只建立 relationship candidate：

```text
Framework Knowledge
        ↓ informs
Procedure Candidate
        ↓ executed by
AI Core / Runtime
        ↓ emits
Execution / Evaluation Evidence
```

Acceptance：Procedure 執行成功不會自動回寫 Canonical Knowledge。

### Slice E — Eval fixture

以 Organizational Memory OS 自身 GTM 為真實題目：

- 哪個 Value Equation lever 最弱？
- Value Ladder 每層承擔什麼任務？
- Offer 與 Funnel 對問題根因是否有不同判斷？
- 缺乏外部客戶 proof 時是否會誠實標記 evidence gap？
- 是否出現 enterprise trust 的反對者？
- 是否捏造 quote、背書或數字？

---

## 12. Verification checklist

- [ ] 所有 donor references 包含 repo、commit、path。
- [ ] License 與第三方內容授權分開判定。
- [ ] Source Evidence、Claim、Synthesis、Advisor Projection、Procedure Candidate 分離。
- [ ] Hormozi 與 Brunson 不被合併成同一個 persona。
- [ ] Dream 100 attribution 保存 Chet Holmes 原始來源關係。
- [ ] Living advisor 的近期立場需要 freshness check。
- [ ] Unsourced number 留在 staging，不得 canonicalize。
- [ ] 沒有完整書籍或課程內容進 public repo。
- [ ] 沒有 Business Council runtime 或 installer 進 Knowledge repo。
- [ ] 沒有直接寫 main。
- [ ] 沒有修改 `bluemaple18-home/aicore`。
- [ ] 沒有改變 Organizational Memory OS 現行 frontier。

---

## 13. Pinned source links

Primary donor：

- [Repository at pinned commit](https://github.com/coreyhaines31/marketingskills/tree/b1aaa3619e747f4a836c61e03084c4a531de1262)
- [MIT License](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/LICENSE)
- [Marketing Council](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/marketing-council/SKILL.md)
- [Marketing Council evals](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/marketing-council/evals/evals.json)
- [Advisor template](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/marketing-council/references/advisor-template.md)
- [Alex Hormozi dossier](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/marketing-council/references/advisors/alex-hormozi.md)
- [Russell Brunson dossier](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/marketing-council/references/advisors/russell-brunson.md)
- [Offer Design Skill](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/offers/SKILL.md)
- [Offer evals](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/offers/evals/evals.json)
- [Product Marketing Context Skill](https://github.com/coreyhaines31/marketingskills/blob/b1aaa3619e747f4a836c61e03084c4a531de1262/skills/product-marketing/SKILL.md)

Secondary donor：

- [MoziAI at pinned commit](https://github.com/SaidLopez/MoziAI/tree/9eb07c7f024616783ab507122fe3baa53342c79e)
- [MoziAI README](https://github.com/SaidLopez/MoziAI/blob/9eb07c7f024616783ab507122fe3baa53342c79e/README.md)
- [MoziAI MIT License](https://github.com/SaidLopez/MoziAI/blob/9eb07c7f024616783ab507122fe3baa53342c79e/LICENSE)

---

## 14. 最終裁決

```text
Primary donor value
= Council Protocol
+ Hormozi Offer Workflow
+ Hormozi / Brunson Framework Dossiers
+ Product Marketing Context Schema
+ Eval Fixtures

Not included
= Complete copyrighted corpus
+ Private operating data
+ Official digital clone
+ Proven endorsement

Organizational Memory OS action
= Preserve as branch-only research evidence
+ Treat as future external expert ingestion testcase
+ Do not change current frontier

AI Core downstream
= P2 PARKED executable capability candidate
+ No implementation in this branch
```

這份研究的核心價值不是「複製名人的口氣」，而是示範 Organizational Memory OS 如何把外部人物知識拆成有來源、可驗證、有衝突、有適用條件、可連到 Procedure、但不越過 Acceptance 與 Single Writer 的知識資產。