# 個人知識庫補救 — 雙線並行切分（整合文件）

**目的**：把交付落差的補救工作切成兩條**可同時進行**的線，並鎖定檔案所有權，
讓兩邊不會互撞。
**狀態**：**CONDITIONAL_GO（GPT 2026-10-01）**，四項修訂已於 rev-2 補入，可開工。
**前置事實**：見 `.work/handoff/EMEM-DELIVERY-GAP-AUDIT-20261001.md`（已補正，見 §0）。

---

## 0. 報告的兩處補正（GPT 指出，已逐項重驗）

### 0.1 `NO_IMPLEMENTATION_AUTHORIZATION` — 原報告 §2.4 **錯誤，撤回**

```
$ git show 2ed2705:文件/待辦補充-個人知識庫Harness-20260830.md | head
# 待辦補充｜公司員工個人記憶標準｜2026-08-30
狀態：
    OWNER_SCOPE_CORRECTED
    COMPANY_KNOWLEDGE_PREPARATION
    DRAFT_REGISTERED
    REVIEW_REQUIRED
    NO_IMPLEMENTATION_AUTHORIZATION
```

**該宣告確實在原始版本的同一份文件裡**，9/18 reconciliation 才被改成
`ACTIVE_MVP_BACKLOG / CURRENT_TRUTH_RECONCILED_20260918`。

原報告只查 working tree、沒重播歷史版本，結論錯誤。**撤回該段。**

### 0.2 generic write 偽造 Record — 原報告 §2.5「未能重現」**撤回，缺口成立**

repo 自己的測試就是那條路徑，而且被當成**正常成功案例**：

```
test/conformance_3a.rb:50
  rt.write_row(kind: "PersonalMemoryRecord", resource: F.record_body(R1, L1), ...)

test/support.rb:119-124（record_body）
  candidate_snapshot: { candidate_status: "ACCEPTED_FOR_RECORD",
                        verification_status: "PASS", acceptance_status: "ACCEPTED" }
  governance:         { verification_status: "PASS", acceptance_status: "ACCEPTED",
                        verification_receipt_ref: "urn:omos:verification-receipt:vr-001",
                        personal_acceptance_ref:  "urn:omos:personal-acceptance:pa-001" }
```

- 那兩個 receipt ref **全 repo 只出現在 `support.rb` 這兩行**，是憑空字串。
- 寫 Record 之前**沒有建立任何 Candidate**（只建了一個 `MemorySupportLink`）。
- evaluator 只做存在檢查：

```
governance/scripts/lib/personal_memory_resource_evaluator.rb
  227  assert(present?(governance["verification_receipt_ref"]), ...)
  228  assert(present?(governance["personal_acceptance_ref"]), ...)
  247  assert(present?(governance["verification_receipt_ref"]), ...)
  248  assert(present?(governance["personal_acceptance_ref"]), ...)
```

**`present?` 只看非空，不解析。** 原報告的探測失敗只是因為手刻 fixture 欄位不全；
repo 的 fixture 形狀正確，直接通過，而且 `conformance_3a` 26/26 全綠。

**裁決：authority ceiling 缺口成立。先止血，不等 red-team 做完。**

---

## 1. 切分原則

1. **按寫入／讀取切**，不按功能切——這樣產品碼完全不重疊。
2. **檔案所有權明確**，每個檔案只有一條線能改。
3. **不設專職 reviewer**，改為**交付點互審**（Owner 的 token 預算限制）。
4. **Recall 不在本輪**，它必須等 A 線封完才能做（否則讓可偽造的 Record 更易擴散）。

---

## 2. A 線 — 寫入權威（P0，止血）

> **由 Claude Code 承接。**

### 2.1 檔案所有權（只有 A 能改）

```
lib/omos/runtime.rb
lib/omos/materializer.rb                                   ← 新增
governance/scripts/lib/personal_memory_resource_evaluator.rb
test/conformance_3a.rb
test/support.rb                                            ← 見 §4.2 時序
規格/v0.1/personal-harness-integration.yaml                 ← 僅 authority 相關區塊
規格/v0.1/fixtures/personal-memory-*-negative-fixtures.json
```

### 2.2 工作項

**依賴順序已更正（GPT 裁決 §1）**：原稿把 A3／A4 排在 A5／A6 之前，依賴反了——
沒有合法的 receipt issuance，就沒有東西可以驗證、也沒有東西可以餵給 materializer。

```
A1 / A2  止血
   ↓
A5 / A6  建立合法的 receipt issuance
   ↓
A3       驗證 receipt 存在、綁定與防重放
   ↓
A4       materializer 成為唯一合法的 Record 路徑
```

| # | 項目 | 說明 |
|---|---|---|
| A1 | **封 generic write** | `write_row` 禁止 `kind: "PersonalMemoryRecord"`，fail closed。禁止 caller 自行把 Candidate 寫成 `ACCEPTED_FOR_RECORD` |
| A2 | **改掉偽造範本** | `support.rb` 的 `record_body` 與 `conformance_3a:50`——那條目前是「正常成功案例」，要改成**必須被擋**的負例。完成後設 checkpoint 通知 B（§4.2） |
| A5 | **Verification runtime** | 產生不可偽造的 VerificationReceipt |
| A6 | **Personal Acceptance issuance** | 見 §2.4 的裁決。**E 方案定案前一律 fail closed**，不得發明臨時 PIN／布林欄位／自報確認字串 |
| A3 | **receipt 必須解析** | 不是 `present?`：receipt 要存在、subject == candidate、owner／tenant 相符、未被重放到別的 candidate |
| A4 | **專用 materializer** | Candidate → Record 的唯一路徑。materializer 完成前，Record 建立一律 fail closed |
| A-seam | **提供 B1 的授權讀取 seam** | 見 §4.5。**這一項要早做**，否則 B1 會被迫在 `mcp_server.rb` 自己做 ACL |

### 2.4 A6 的裁決：一套 Human Authority Provider，兩個獨立 consumer

GPT 裁決（§2）：

> Personal Acceptance 與 Closeout **使用同一套人類授權證明機制**，
> 但保留**不同的 action、receipt schema、policy 與驗收**。
> **不做「簡化版 acceptance」讓 AI／caller 自報已接受。**

因此：

- 底層 provider 與 `CARD-HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001` 的 E 方案合流。
- **A6 與 closeout 不揉成同一張卡。**
- E 方案尚未定案前：A1～A3 可先止血，**A6 的 issuance 一律 fail closed**。
- 不得另外發明臨時 PIN、布林欄位或自行確認字串。

### 2.3 A 線驗收

1. 任何 surface（CLI／MCP）都無法直接建立 `PersonalMemoryRecord`；反證：
   現行 `conformance_3a:50` 那條必須轉紅。
2. 偽造的 receipt ref 必須被拒，錯碼指出是哪一項解析不到。
3. receipt 綁定錯 candidate／owner／tenant 時拒絕，各有獨立負例。
4. materializer 之外沒有第二條 Record 產生路徑（原始碼層斷言）。
5. 既有回歸全綠。

**測試政策（GPT 裁決 §3）：覆蓋不得下降，不預先接受數字下降。**

A2 要做的不是「刪掉一條正例」，而是：

- 舊的偽造正例**明確退休**（不是消失）
- 同一路徑改成命名清楚的 `expect_rejected` 負例
- **另外增加**六條負例：Candidate 不存在／receipt 不存在／candidate 不符／
  owner 不符／tenant 不符／receipt 重放／generic Record write

**測試總數應維持或增加。** 若 runner 的計數機制仍造成下降，交付 receipt 必須列：

```
retired checks   <清單>
added checks     <清單>
新 baseline      <數字>
行為覆蓋沒有下降的證據
```

**不得只報新的 `x/x PASS`。**

---

## 3. B 線 — 讀取與內容面（P1 前置）

> **由 Codex 承接。**

### 3.1 檔案所有權（只有 B 能改）

```
lib/omos/mcp_server.rb
lib/omos/inbox.rb
lib/omos/cli.rb
lib/omos/review_ledger.rb
lib/omos/review_queue.rb
test/conformance_3b.rb
test/conformance_3c.rb
skills/
```

### 3.2 工作項

| # | 項目 | 說明 |
|---|---|---|
| B1 | **`personal_memory_read` 回內容** | 目前只回 `kind` + `row_id`。**B 只負責把 A 提供的 seam 回傳出去，不得在 `mcp_server.rb` 自己做 ACL 過濾**（§4.5） |
| B2 | **`personal_memory_capture`** | 新 MCP 工具。**必須薄接既有 `Inbox#import`，不得另建 capture pipeline**（§4.6） |
| B3 | **`MEMORY_KINDS` 單一來源** | `inbox.rb:58` 硬寫死，契約有 `memory_kinds_phase_1`。這是 drift bug，不是缺口 |
| B4 | **真正的 historical comparison** | 目前 closeout 接受 caller 自報分類，沒有真的執行比較。契約 `historical_comparison` 只被讀了 category 清單 |
| B5 | **`review due` 可讀輸出** | 目前只印 8 碼前綴，看不出是什麼 |

### 3.3 B 線驗收

1. `personal_memory_read` 回得出內容，且**先過權限再取資料**——
   但那個判定在 A 提供的 seam 裡；B 的驗收是「**有呼叫 seam、沒有自己濾**」
   （原始碼層斷言：`mcp_server.rb` 不得出現 ACL／owner／scope 的過濾邏輯）。
2. `capture` 一步完成，且**原始碼層證明它呼叫的是 `Inbox#import`**，
   不是自己重寫一條快照／Candidate 路徑。
3. `MEMORY_KINDS` 在產品碼中**只剩一處**，且來源是契約；反證：改契約，產品行為跟著變。
4. historical comparison 真的比對既有資料；反證：caller 傳錯分類必須被更正或拒絕。
5. 既有回歸全綠。

### 3.4 B 線明確不做

- **Recall 本身**（等 A）
- 任何 `PersonalMemoryRecord` 的建立路徑（那是 A 的）
- `規格/` 底下的任何檔案（要改契約提給 A）

---

## 4. 接觸點與規矩

### 4.1 `lib/omos/contract.rb`：**單一 writer = A 線**（GPT 裁決 §1）

原稿「兩邊各自加方法」仍是並行雙寫風險，**撤回**。

> **本輪 `contract.rb` 只有 A 能改。**
> B 需要 accessor 時，以明確需求交給 A 加，A 加完通知 B。

`lib/omos/runtime.rb` 同理，**維持 A 單一所有權**，B 不得修改。

### 4.2 `test/support.rb`（時序相依）

`record_body` 現在**就是那條偽造路徑的範本**，A 線 A2 要改它。

> **A 線先改，改完通知 B。在那之前 B 不要動 `support.rb`。**

B 線若需要新 fixture，先在自己的 conformance 檔裡 local 定義，等 A 改完再搬進
`support.rb`。

### 4.3 `規格/v0.1/personal-harness-integration.yaml`

**只有 A 能改**（authority 相關）。B 要改契約 → 提需求給 A。

### 4.5 B1 的授權讀取 seam（A 提供，B 消費）

B1「先權限判定、再取資料」的**實際控制點在 `runtime.rb`**，那是 A 的檔案。
不能讓 B 在 `mcp_server.rb` 自己做一份 ACL——那就是第二份 authority。

> **A 線要早期交付一個 seam**（例如 `Runtime#read_rows_with_content(surface:, binding:)`），
> 由它在取資料**之前**完成權限判定。
> **B 只呼叫它、把結果回傳，不做任何過濾。**

這一項列入 A 的工作表（`A-seam`），**排在 A1／A2 之後、不晚於 A5**，
否則 B1 會被阻塞或被迫違規。

### 4.6 B2 必須薄接 `Inbox#import`

`capture` 不得另建 pipeline。它走的證據快照、Candidate 建立、Runtime 治理
必須**與 CLI `import` 完全同一條路徑**，差別只在入口形狀（接文字而非檔案）。

驗收以原始碼層斷言：`capture` 的實作必須呼叫 `Inbox#import`（或 A 同意後
抽出的共用入口），不得出現第二套 `EvidenceSnapshot` 或 Candidate 組裝。

### 4.4 Candidate 狀態轉移

B 碰的 candidate 只到 `PROPOSED`（`inbox.rb:180`、`review_queue.rb:152`）。
A 要封的 `ACCEPTED_FOR_RECORD` 目前只在 evaluator 與 `support.rb` fixture。
**產品碼不重疊。** A 若需要在 `review_ledger.rb` 加狀態檢查 → 提需求給 B。

---

## 5. Review 方式（取代專職 reviewer）

Owner 的 token 預算不允許「一邊開發一邊 review」。改成：

- **平常**：每條線自己跑反證，變異必須轉紅才算數；不互相打擾。
- **交付點**：完成一個工作項 → 寫定點交付包 → 交給**另一條線**審 →
  審完繼續自己的工作。
- **交付包只鎖自己的檔案**，審的人不要順手改對方的檔案（見
  `dont-decide-for-a-parallel-work-line` 的教訓）。

---

## 6. 隔離與時序

### 6.1 兩線必須各自使用獨立 worktree／branch（GPT 裁決 §4）

> **不以「檔案清單不同」取代隔離。**

```
共同基準 SHA   85be146
A 線           worktree 知識庫-emem-a   branch cc/emem-a-write-authority
B 線           worktree 知識庫-emem-b   branch codex/emem-b-read-surface
```

現有 worktree：`知識庫`（main）、`知識庫-taskref`（cc/native-adapters-task-ref-correlation）。
B 線的檔案目前**全部乾淨、無未提交修改**（已核）；工作區的 dirty 檔只有
`CLAUDE.md` 與簡報產物，與 B 線無重疊。

### 6.2 時序

```
A 線  ━━▶ A1 A2 ━━▶ A-seam ━━▶ A5 A6 ━━▶ A3 ━━▶ A4
             │          │
       checkpoint-1  checkpoint-2
             ↓          ↓
B 線  ━━▶ B3 B5 ━━━━━━━━━━━━━━▶ B1 ━━▶ B2 ━━▶ B4
                                              ↓
                                   checkpoint-3（最終整合驗收）
                                              ↓
                                     兩線完成後才開 Recall
```

**checkpoint-1（A2 完成）**：`support.rb` 與 `conformance_3a` 的新基底就緒。
B 把它整合進自己的分支後，才可以動 `support.rb`。

**checkpoint-2（A-seam 完成）**：授權讀取 seam 就緒，B1 才能開始。

**checkpoint-3**：A／B 都完成後的最終整合驗收，由兩線互審。

### 6.3 可以同時開工的部分

B 的 **B3（MEMORY_KINDS 單一來源）** 與 **B5（review due 可讀輸出）**
不依賴任何 checkpoint，**第一天就能開始**。
B1 等 checkpoint-2，B2 等 B1，B4 等 B2。

## 6.4 `traces_to` preflight（GPT 裁決 §1-6）

> **A1～A6、B1～B5 都要補 `traces_to`，連回 EMEM-06 的原始成功條件；
> 沒有 trace preflight 不得開工。**

每個工作項在卡片上要寫出它對應 `文件/待辦補充-個人知識庫Harness-20260830.md`
EMEM-06 成功指標的哪一條，例如：

```yaml
A3:
  traces_to: "底層 Candidate acceptance 可追溯"
B1:
  traces_to: "Recall 有 citation / freshness / gap notice（前置：讀得到內容）"
```

**沒有 trace 的工作項不得進入施工** —— 那表示它不是在補原始缺口，
而是又一次局部最佳化。

---

## 7. 本輪不做（留待後續）

依 GPT 的修補順序，以下在 A／B 兩線完成後才處理：

- **P1** Recall（MemoryContextPack、citation、freshness、gap notice）
- **P1** Correction／Supersession 專用流程
- **P2** Evidence Profile admission、L1～L4 capability level 接入產品
- **P2** Minimal Evidence Package producer、Promotion proposal／submission
- **最後** 完整 E2E closure：重播 EMEM-06 全部原始成功條件，
  不再以「所有子卡 GO」代替「產品閉環完成」

---

## 8. 裁決結果（GPT，2026-10-01）

**CONDITIONAL_GO** —— 四項修訂已於 rev-2 全部補入：

| # | 裁決 | 本稿處理 |
|---|---|---|
| 1 | 切分方向可用，但「產品碼完全不重疊」**不成立** | §4.1 改 `contract.rb`／`runtime.rb` 為 A 單一 writer；§4.5 A 提供 B1 的授權讀取 seam；§4.6 B2 薄接 `Inbox#import` |
| 2 | A 線依賴順序**反了** | §2.2 改為 A1/A2 → A5/A6 → A3 → A4 |
| 3 | 不預先接受 `conformance_3a` 數字下降 | §2.3 改為「覆蓋不得下降」，要列 retired／added／新 baseline |
| 4 | 兩線不得共用 `main` checkout | §6.1 各自獨立 worktree／branch，共同基準 `85be146` |

另補：§2.4 A6 的裁決（一套 Human Authority Provider、兩個獨立 consumer、
E 定案前 issuance fail closed）、§6.4 `traces_to` preflight。

GPT 另確認：**B 線的檔案與 Codex 現有工作無衝突**，可以交給 Codex。

## 9. 開工前的最後檢查

- [ ] 兩個 worktree 建好，基準 SHA 都是 `85be146`
- [ ] A1～A6、B1～B5 的 `traces_to` 都填好（§6.4）
- [ ] 兩線都知道 checkpoint-1／2／3 的意義（§6.2）
- [ ] 兩線都知道 `contract.rb`／`runtime.rb`／`規格/` 只有 A 能改
