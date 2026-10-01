# 個人知識庫補救 — 雙線並行切分（整合文件）

**目的**：把交付落差的補救工作切成兩條**可同時進行**的線，並鎖定檔案所有權，
讓兩邊不會互撞。
**狀態**：提案，**待 Owner 與 GPT 核可後才開工**。
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

| # | 項目 | 說明 |
|---|---|---|
| A1 | **封 generic write** | `write_row` 禁止 `kind: "PersonalMemoryRecord"`，fail closed。禁止 caller 自行把 Candidate 寫成 `ACCEPTED_FOR_RECORD` |
| A2 | **改掉偽造範本** | `support.rb` 的 `record_body` 與 `conformance_3a:50`——那條目前是「正常成功案例」，要改成**必須被擋**的負例 |
| A3 | **receipt 必須解析** | 不是 `present?`：receipt 要存在、subject == candidate、owner／tenant 相符、未被重放到別的 candidate |
| A4 | **專用 materializer** | Candidate → Record 的唯一路徑。materializer 完成前，Record 建立一律 fail closed |
| A5 | **Verification runtime** | 產生不可偽造的 VerificationReceipt |
| A6 | **Personal Acceptance** | 人類授權 receipt。**與 `CARD-HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001` 的 E 方案同源**，不要做出第二套 |

### 2.3 A 線驗收

1. 任何 surface（CLI／MCP）都無法直接建立 `PersonalMemoryRecord`；反證：
   現行 `conformance_3a:50` 那條必須轉紅。
2. 偽造的 receipt ref 必須被拒，錯碼指出是哪一項解析不到。
3. receipt 綁定錯 candidate／owner／tenant 時拒絕，各有獨立負例。
4. materializer 之外沒有第二條 Record 產生路徑（原始碼層斷言）。
5. 既有回歸全綠；**A2 會讓 3a 的數字改變，那是預期的**。

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
| B1 | **`personal_memory_read` 回內容** | 目前只回 `kind` + `row_id`，AI 拿到一串 URN 看不出是什麼。這是 Recall 的硬前置 |
| B2 | **`personal_memory_capture`** | 新 MCP 工具：給文字＋類型，一步完成證據快照與 Candidate。目前 AI 要嘛自組 schema、要嘛先寫檔案再跑 CLI |
| B3 | **`MEMORY_KINDS` 單一來源** | `inbox.rb:58` 硬寫死，契約有 `memory_kinds_phase_1`。這是 drift bug，不是缺口 |
| B4 | **真正的 historical comparison** | 目前 closeout 接受 caller 自報分類，沒有真的執行比較。契約 `historical_comparison` 只被讀了 category 清單 |
| B5 | **`review due` 可讀輸出** | 目前只印 8 碼前綴，看不出是什麼 |

### 3.3 B 線驗收

1. `personal_memory_read` 回得出內容，且**先過權限再取資料**（不是取完再濾）。
2. `capture` 一步完成，產出的 Candidate 與 CLI `import` 走同一條 Runtime 治理路徑，
   沒有旁門。
3. `MEMORY_KINDS` 在產品碼中**只剩一處**，且來源是契約；反證：改契約，產品行為跟著變。
4. historical comparison 真的比對既有資料；反證：caller 傳錯分類必須被更正或拒絕。
5. 既有回歸全綠。

### 3.4 B 線明確不做

- **Recall 本身**（等 A）
- 任何 `PersonalMemoryRecord` 的建立路徑（那是 A 的）
- `規格/` 底下的任何檔案（要改契約提給 A）

---

## 4. 接觸點與規矩

### 4.1 `lib/omos/contract.rb`（兩邊都會讀）

**只能加新方法，不能改既有方法的簽名或回傳形狀。**
要改既有方法 → 停下來協調，不要單方面動。

### 4.2 `test/support.rb`（時序相依）

`record_body` 現在**就是那條偽造路徑的範本**，A 線 A2 要改它。

> **A 線先改，改完通知 B。在那之前 B 不要動 `support.rb`。**

B 線若需要新 fixture，先在自己的 conformance 檔裡 local 定義，等 A 改完再搬進
`support.rb`。

### 4.3 `規格/v0.1/personal-harness-integration.yaml`

**只有 A 能改**（authority 相關）。B 要改契約 → 提需求給 A。

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

## 6. 時序

```
A 線  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▶  A1 A2 → A3 A4 → A5 A6
B 線  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▶  B1 B2 B3 → B4 B5
            ↑
      A2 完成後通知 B 可動 support.rb
                                           ↓
                                    兩線完成後才開 Recall
```

**可以同時開工。** 唯一的時序相依是 §4.2 的 `support.rb`。

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

## 8. 要 Owner／GPT 裁決的

1. **切分方式是否同意**（按寫入／讀取切，而非按功能切）。
2. **A6 與 `CARD-HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001` 的 E 方案同源**——
   是否併成一條線做，還是先做簡化版的 acceptance receipt、Touch ID 另外排。
3. **A2 會讓 `conformance_3a` 的數字下降**（偽造案例改成負例）。
   這是預期的，但要先說好，不然下次看到「26/26 變了」會以為是 regression。
4. **B 線交給 Codex** 是否可行——B 的檔案清單是否與 Codex 現有工作衝突。
