---
id: PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
status: SLICE_A_ACCEPTED_GO_SLICE_B_IN_PROGRESS
slice_a: ACCEPTED_GO @ 77e11e0（8b49d16 匯入本體、8d1227a 身分解析、d24ca37 repair-01、77e11e0 repair-02）
slice_a_review_round_3: GO（2026-09-21，P1 皆 0；P2×1 residual 已於收片時一併收；.work/handoff/PERSONAL-INBOX-SLICE-A-REPAIR-02-REREVIEW-20260921.md）
slice_a_review_round_1: NO_GO（2026-09-21，P1×3：身分拼接＋格式未驗／跨時間重匯不冪等／content-only dedup 黏合 provenance；P2×1：identity validation 未下沉）→ repair-01 已修
slice_a_review_round_2: NO_GO（2026-09-21，P1×2：owner ref 仍允許多段冒號／provenance conflict 在跨 process race 下可繞過；P2×1：tmp 目錄名只含 pid）→ repair-02 已修
slice_b: B1_B2_READY_FOR_REVIEW（d6fce24 B1、86a5103 B1 repair、22c8ab9 B2；證據包 .work/handoff/PERSONAL-INBOX-SLICE-B-B1B2-EVIDENCE-20260921.md）
slice_b_remaining: 驗收 8（真 launchd 實證，需 Owner 明示）；驗收 14 的「重現攔截」需真實傳輸的檔案
slice_b_delivery_path: 驗收 12 PASS、13 PASS（指定「先刪資料夾再解壓」）、14 部分達成；證據包 .work/handoff/PERSONAL-INBOX-SLICE-B-DELIVERY-PATH-EVIDENCE-20260922.md
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

### 2.2.1 個人身分的來源（Owner 裁決 2026-09-21）

Candidate 的 `tenant_id` 與 `employee_owner_ref` 是必填，但產品原本**沒有任何
地方存過員工身分**——`write` 一直由呼叫端在 resource JSON 自己帶。`import`
不能每次都要使用者重打一遍，也不能猜。

裁決的解析順序：

```text
明確參數（--owner/--tenant）
  > install receipt 的 personal_identity
  > （測試／暫時相容）環境變數
  > fail closed（INBOX_OWNER_IDENTITY_REQUIRED）
```

三條硬規則：

1. **receipt 只保存「已明確設定過」的 identity value**，不是 identity
   authority，也不新增 vocabulary——欄位名沿用既有的
   `employee_owner_ref`／`tenant_id`。
2. **upgrade 必須原樣保留 identity**，新版 install 不得洗掉；只有明確重新
   指定才覆寫。
3. `import --owner/--tenant` 保留作明確 override／測試／首次 migration；
   裸跑 `import note.md` 預設讀 receipt。缺就 fail closed，**絕對不猜**。

**不從 SessionStart 推**：HostSessionBinding 只有 `executor_ref`／
`executor_session_ref`／`cwd`／`project_ref`／`effective_scope`，沒有
`employee_owner_ref` 與 `tenant_id`。從那裡硬推等於造一份假的 mapping。

環境變數不作為正式預設來源——它太容易隨 shell／session 漂移；只在沒有
receipt 身分時採用，且會在 stderr 出聲說明。

### 2.2.2 repair-01（2026-09-21）：review round 1 的 3×P1 ＋ 1×P2

| # | 缺陷 | 修法 |
|---|---|---|
| P1-1 | 身分逐欄 fallback 會**拼接**：receipt=`emp-A/t-A` 時 `import --owner emp-B` 得到 `emp-B/t-A`，rc=0 靜默寫入；且 owner/tenant 格式**完全沒驗**（`NOT-A-URN` 照收） | 身分是一組 **tuple**：明確參數必須兩個一起給，否則 `INBOX_OWNER_IDENTITY_INCOMPLETE`，不往下一個來源補。格式驗證移到 capture **之前** |
| P1-2 | 跨時間重匯不冪等：`chronology.created_at`（以及 link 的 `provenance.created_at`、`validity_interval.effective_from`）吃呼叫端當下的 `now`，隔幾秒 canonical 就變，撞 `PMR_IN_PLACE_ROW_OVERWRITE`。原本「連跑 3 次」落在同一秒，**假綠** | 三個時間欄位全部改取 envelope 的 `captured_at`——第一次 capture 的時間，重放時沿用 |
| P1-3 | content-only dedup：`emp-A` 先匯入、`emp-B` 再匯入相同 bytes，第二次回報「重放成功」但 provenance 仍是 `emp-A` | digest 已存在但 owner/tenant 或來源路徑不同 → **fail closed**，兩個分開的錯誤碼，不靜默沿用第一份 |
| P2 | `Inbox.import` 直接吃 caller 傳來的身分 | 裁決採納：receipt lookup 留在 CLI，**驗證下沉到 `Inbox`**，在寫 snapshot 前驗 resolved tuple |

#### 身分格式驗到什麼程度

以**契約實際宣告的**為準，不自行發明：

- `employee_owner_ref`：common-vocabulary 的
  `identifiers.omos_generated.ref_template` 是
  `urn:omos:{resource-kind}:{uuid}`，因此至少必須是 `urn:omos:<kind>:<id>`。
  **不**強制 UUIDv7——既有資料與 fixture 用的是
  `urn:omos:employee:emp-001`，強制會把既有安裝打掛。
- `tenant_id`：契約**沒有宣告任何 shape**（只有 `tenant_id_required: true`）。
  因此只驗「非空、不含空白與控制字元」，**不自行發明 tenant regex**。
  真正的 tenant 形狀應由契約決定——**這是一個 open gap，列在此處備查**。

### 2.2.3 repair-02（2026-09-21）：review round 2 的 2×P1 ＋ 1×P2

| # | 缺陷 | 修法 |
|---|---|---|
| P1-1 | `OWNER_REF` 後半是 `[^\s:][^\s]*`——只禁了**第一個**字元是冒號，`urn:omos:employee:alpha:extra` 照樣通過，不符合 repair-01 自己宣告的 `urn:omos:<kind>:<id>` 形狀 | id 整段改為 `[^\s:]+`。**不**擴張成 UUIDv7——契約沒有為 employee ref 宣告那個強度 |
| P1-2 | provenance 檢查在**跨 process race** 下被繞過：兩個 process 同時第一次 capture，輸掉 `rename` 的一方直接回既有 envelope，**沒有重新驗 provenance**——P1-3 的併發版本 | 抽出 `adopt_existing`，早期路徑與 race 路徑走**同一個**入口。採用既有那份的前提永遠是 provenance 相同，不因為「我是輸的那一方」而放寬 |
| P2 | tmp 目錄名只含 `Process.pid`，同 process 兩個 thread 拿到同一個 digest 會互相 `rm_rf`／`rename` | 加上 `SecureRandom.hex(8)`。CLI 目前單執行緒，但 `capture` 是 library seam |

`capture(before_rename:)` 是注入的測試接縫，與既有 `install(fail_after:)`／
`rollback(fail_before_receipt:)` 同一做法。理由：真實的跨 process race 無法在
測試裡穩定製造，而那條路徑正是 P1-2 的缺陷所在。**待 reviewer 裁定可否收。**

#### contract gap（reviewer 裁決：不阻塞 Slice A）

`tenant_id` 上游確實沒有 shape；`employee_owner_ref` 的精確 employee identity
形狀也沒有足夠一致的 normative 定義。**本片不自行發明更強的 schema**，
只守住修法自己宣告的最低 URN 形狀。另登 P2 contract gap。

#### review round 3（2026-09-21）：GO

P1 皆 0。`capture(before_rename:)` 測試接縫**收**——bounded deterministic
race injection，形狀與已接受的 `rollback(fail_before_receipt:)` 一致，
production caller 未使用。reviewer 另以真實兩個 process 重播 race、並單獨
撤掉 `adopt_existing` 的 provenance 驗證，確認兩個修法**彼此獨立**、不是
互相遮蔽——這正是交付方主動揭露的疑點。

reviewer 留下一筆 P2 residual（不阻塞）：tmp uniqueness 的常設 regression
只驗名字形狀，對「同 process 併發」鑑別力弱。**收片時一併收掉**，改成真正的
兩-thread barrier 測試；退回固定 tmp 名時連續三次都重現 `Errno::ENOENT`，
不是 flaky。

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

    **2026-09-22 實測結果：部分達成。** 寫得上 xattr、解除後殘留 0、安裝與
    doctor 正常、說明有警告——但**攔截本身在本機重現不了**：人工 `xattr -w`
    上去的 quarantine 不會真的觸發 Gatekeeper，同事端的攔截來自真正經過
    Teams 傳輸的檔案，provenance 不同。條文不改寫；要完成只能把 zip 真的
    傳出去再傳回來，需 Owner 決定。

    **驗收 13 的實測補充**：覆蓋解壓不會刪掉新版已無的舊檔，而殘留檔會改變
    artifact identity（實測 `fabb0b30…` vs 乾淨的 `44d977dc…`）。因此指定的
    正確步驟是**先移除舊資料夾再解壓**，已寫進交付包 INSTALL.md 的「升級到
    新版」一節。另記：`cp -R` 覆蓋會在 vendor 的唯讀 gem 檔上大量失敗，
    `unzip -o` 不會。

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
