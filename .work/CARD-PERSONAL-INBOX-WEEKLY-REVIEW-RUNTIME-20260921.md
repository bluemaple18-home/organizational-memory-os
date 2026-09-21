---
id: PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
status: READY_TO_IMPLEMENT
type: bounded-product-capability
priority: MVP
related:
  - SSP-323_EMEM09_ACCEPTED_GO
  - EMEM-11_DOD_MET_20260920
  - SSP-295_FULL_PRODUCT_PILOT
authority: organizational-memory-os
---

# Personal Inbox / Manual Capture + Friday Weekly Review Runtime

👉 [假設與目標確認]
- **目標**：補上目前 Personal Memory 產品真正缺的兩個使用面：
  1. 人可以把自己的知識檔案丟進來，形成可 review 的 PersonalMemoryCandidate；
  2. 每週五由本機原生排程喚起 review，而不是靠人記得手動執行。
- **邊界**：沿用既有 RawEvidenceEnvelope／SourceAnchor／MemorySupportLink／
  PersonalMemoryCandidate／weekly_review_cycle／Runtime／Store；不建第二套 Knowledge DB、
  Queue DB、workflow engine、acceptance authority 或 company upload path。
- **已出貨版本**：2026-09-21 已交給同事的 standalone zip 不回頭修改；本卡是
  **下一版 update**。既有 Personal Store 與 Host 設定升級後必須保留。

## 1. Measured gap

目前契約其實早已宣告 `manual_capture`，weekly review 也已有完整 cadence / closeout
語意，但產品面少了最後兩個 seam：

1. `omos-personal-memory write` 只接受**已完整組好的 resource JSON**，一般使用者
   沒有「上傳／丟檔案」入口；也沒有 managed personal evidence snapshot。
2. `weekly_review_cycle.cadence_policy.default_anchor = FRIDAY_AFTERNOON` 已存在，
   但該切片明文排除**排程 runtime 實作**。目前沒有東西會在週五真的觸發 review。

所以現況是「核心治理與 store 都有，但人沒有自然的入口，週五也不會自己發生」。

## 2. Slice A｜Personal Inbox / Manual Capture

### 2.1 使用面

新增最小 CLI：

```text
omos-personal-memory import <FILE> [--memory-kind KIND]
omos-personal-memory inbox list
```

v1 先收 UTF-8 `.md` / `.txt`。PDF／Office／圖片解析留既有 adapter / 後續卡，
本片不順手吸收 parser。

### 2.2 Evidence 形狀

匯入時：

```text
FILE
  → content-addressed local evidence snapshot
  → existing RawEvidenceEnvelope + SourceAnchor shape
  → MemorySupportLink
  → PersonalMemoryCandidate(PROPOSED)
```

- managed snapshot 放在 `~/.omos/personal-memory/evidence/<sha256>/`；以內容 digest
  定址，**只新增、不原地覆寫**。這是 raw evidence snapshot，不是第二套 query DB。
- snapshot 至少保留原始 bytes、SHA-256、capture time、原始檔名／來源路徑、既有
  personal evidence profile 所需 admission metadata。
- RawEvidenceEnvelope / SourceAnchor 欄位直接沿用既有 STD-01 / STD-02 與
  `personal-evidence-profile`；不得另造 personal-only schema。
- `MemorySupportLink` 與 `PersonalMemoryCandidate` 必須仍走既有
  `Runtime#write_row`，不得旁路 resource evaluator。
- CLI 若無法合法形成 Candidate（例如缺必要 memory_kind），可以留下 admitted
  evidence snapshot 並明確回 `NEEDS_CANDIDATE_INPUT`；**不得用猜的欄位偷偷補成
  accepted Record**。

### 2.3 Idempotency / failure

- 同一 bytes + 同一 owner/source 再匯入：重放，不產第二份 evidence snapshot／
  support link／candidate。
- unsupported format、非 UTF-8、讀不到檔、admission 失敗：fail loud；不得留下
  半套 Candidate。
- 原始來源檔匯入後即使被移走，managed snapshot 仍可驗證 support；不得讓
  Candidate 的 evidence 只剩一條會失效的原始路徑。
- 本片**不做** verification PASS、personal acceptance、Record creation、
  Promotion、Minimal Evidence Package、Company upload。

## 3. Slice B｜Weekly Review Queue + Friday Trigger

### 3.1 Review Queue 是 projection

不得新增 `review_queue` table。queue 每次由既有事實重算：

- PersonalMemoryCandidate
- `chronology.created_at`
- candidate lifecycle
- 同一 `review_period_id` 已存在的 closeout history

輸出是 bounded refs + display metadata；不得複製整份 Personal Store 或產
`weekly_work_summary`。

新增最小 CLI：

```text
omos-personal-memory review due
omos-personal-memory review show <review_period_id>
```

真正的 closeout writer 仍沿用既有：

```text
omos-personal-memory closeout --file <receipt.json>
```

`review due/show` 只有 read/projection 權限，不能接受 Candidate。

### 3.2 Friday trigger

macOS v1 用**原生 launchd**，不新建 daemon/runtime：

```text
omos-personal-memory schedule install
omos-personal-memory schedule status
omos-personal-memory schedule remove
```

- 預設把既有 `FRIDAY_AFTERNOON` 落成 **Friday 16:00 local time**；這只是產品
  default，允許設定其他 Friday-afternoon 時間，不改 weekly_review_cycle schema。
- LaunchAgent 只呼叫同一支 CLI 的 `review due`；執行目標走穩定的
  `~/.omos/personal-memory/current/...`，不得 pin artifact-id。
- `RunAtLoad` / catch-up 檢查必須沿用原本的 `review_period_id` 與 catch-up rule；
  missed Friday 不得生成下一週的新 period 來冒充補做。
- 重複觸發同一 period 必須 idempotent；不能產第二個 closeout／Promotion。
- scheduler 只能「準備 queue + 提醒」，**不得自動 acceptance / Record / Promotion /
  Company upload / terminal closeout**。
- 0 item 時可回報 `0 due items`，但不得自動偽造「這週完成 review」的 terminal receipt。

### 3.3 提醒

v1 可用 macOS 原生 notification 顯示：

```text
Personal Memory：本週有 N 筆待 review
```

通知失敗不得影響 queue correctness；排程與 queue 是 authoritative behavior，
notification 只是 presentation。

## 4. 與已出貨同事版本的關係

這張卡不要求重打今天已交出去的 zip。下一版 artifact 只需支援：

```text
既有安裝
→ upgrade
→ store 原樣保留
→ Host config 原樣保留
→ 新增 import / inbox / review / schedule surface
```

禁止要求同事刪 Personal Store 重裝來完成 migration。

但 **upgrade 必須以實際會發生的那條交付路徑驗收**：目前沒有 release
pipeline 也沒有自動更新，同事拿到的是一個 zip，所以下一版到他手上的方式
就是「再打一包新 zip → 解壓覆蓋舊資料夾 → 對既有安裝跑 `install`」。
這條路與抽象的 upgrade 不保證等價（覆蓋解壓會留下舊版殘檔、artifact 內容
與 receipt 的對應關係也可能改變），因此列入 Slice B 驗收第 13 項。
本卡不因此建 release pipeline——只是讓驗收對準真正會走的那條路。

同一個理由也適用於 macOS 的 quarantine：**驗收必須在帶 quarantine 的狀態下
進行**（驗收第 14 項）。自製 zip 不帶這個標記，所以本機怎麼測都測不出來，
2026-09-21 的首次實際交付就是這樣漏掉的。

## 5. Acceptance

### Slice A

1. `import note.md` 後，實際產生 content-addressed evidence snapshot，並可追到
  既有 SourceAnchor / Evidence ref。
2. 合法輸入可經既有 evaluator 寫入 MemorySupportLink + PersonalMemoryCandidate；
   Candidate 初始狀態仍是既有 lifecycle 的 `PROPOSED`，沒有 acceptance authority。
3. 刪除原始 `note.md` 後，candidate support 仍能由 managed snapshot 驗證。
4. 同一檔案重放 3 次，snapshot／support link／candidate 都不得增生第二份。
5. unsupported / malformed / admission failure 不得留下半套 Candidate。
6. 既有 `write/read/closeout` 行為與 Personal Store byte-level 資料不被 migration 破壞。

### Slice B

7. `review due` 對同一 `review_period_id` 重跑結果穩定，且只從既有 Candidate +
   closeout facts 建 projection；沒有新 queue DB。
8. Friday 16:00 trigger 可由 launchd 實際觸發；sleep/missed-window 後的 catch-up
   保留原 `review_period_id`。
9. schedule install 重跑不產第二份 LaunchAgent；remove 只移除本產品自己的 job。
10. trigger 前後 `memory_rows` / `closeouts` 不因排程本身增加任何 acceptance、Record、
    Promotion 或 terminal closeout。
11. 0 due item 明確回 0，不製造假 closeout。
12. 既有安裝做 upgrade 後，store / Host config 保留，並取得新 surface。
13. **實際交付路徑的 upgrade**：把新版打成 zip、解壓覆蓋到舊 artifact 資料夾、
    對既有安裝跑 `install`，結果必須與第 12 項等價——store 原樣保留、Host
    config 原樣保留、新 surface 可用，且不得殘留舊版檔案造成 drift gate 或
    `PACKAGED_GOVERNANCE_MISSING` 異常。覆蓋解壓若無法達成等價，必須在卡上
    明寫正確的升級步驟（例如先移除舊資料夾再解壓），不得讓使用者自己猜。
14. **交付路徑必須在帶 quarantine 的狀態下驗收**。本機自製的 zip 不會被
    標記 `com.apple.quarantine`，因此四輪本機驗證全部漏掉這個失敗模式；
    2026-09-21 首次實際交付時，同事端被 Gatekeeper 連續攔截約 10 次
    （artifact 內有 10 個未簽章的原生 `.bundle`，每個各擋一次），其中一個
    對話框的選項是「丟到垃圾桶」——按下去會直接破壞 artifact。
    因此驗收必須：
    - 對解壓後的整包**實際寫入** `com.apple.quarantine` 再跑安裝，重現攔截；
    - 確認文件記載的解除指令（`xattr -dr com.apple.quarantine <路徑>`）
      執行後，所有 `.bundle` 的 quarantine 殘留數為 **0**，且安裝與 `doctor`
      正常；
    - 確認安裝說明明確警告**不得**按「丟到垃圾桶」。

    本卡**不**因此導入簽章／notarization（需 Apple Developer 帳號，屬配送
    形式決策，仍在範圍外）。這一項只要求「已知的攔截有被文件化且實測解得開」。

### Regression

15. Personal Memory 3a / 3b / 3c conformance 全綠；既有 validators 全綠；
    `git diff --check` clean。
16. 新增至少兩個鑑別力反證：
    - 繞過 managed evidence snapshot、只引用原始路徑 → gate RED；
    - scheduler 偷做 `commit_closeout` 或 acceptance write → gate RED。

## 6. Hard stops

- Inbox / scheduler 不得直接建立 `PersonalMemoryRecord`。
- Inbox / scheduler 不得把個人資料上傳公司端。
- 不新增第二個 Knowledge DB / Evidence DB / Queue DB / workflow engine。
- 不用 model confidence 取代 verification / personal acceptance。
- 不把「週五有跑 job」當成「weekly review 已完成」；完成仍以既有 closeout
  contract 的 terminal receipt 為準。
- 不為了方便把整份 Personal Store 塞進 weekly packet。

## 7. Minimum Sufficient

- **why_not_less**：只加 folder 不接 Candidate，週五仍沒有可 review 的治理物件；
  只加 scheduler 不加 intake，排程只會固定喚醒一個空 queue。
- **why_not_more**：v1 不做 GUI、PDF/Office parser、雲端同步、手機上傳、全文搜尋、
  自動摘要、公司端 submission UI。
- **do_not_absorb**：不重開 SSP-323 weekly semantics；不重做 EMEM-11 Runtime；
  不吸收 SSP-324 Personal→Company boundary。

## 8. Delivery order

```text
A1 evidence snapshot + import
→ A2 SupportLink + Candidate wiring
→ B1 review queue projection
→ B2 launchd schedule + notification
→ upgrade regression on already-installed shape
→ zip 覆蓋解壓的實際交付路徑 upgrade（驗收 13）
→ 帶 quarantine 的交付路徑驗收（驗收 14）
→ targeted review
```
