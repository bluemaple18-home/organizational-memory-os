---
id: PERSONAL-INBOX-SLICE-A-EVIDENCE-20260921
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
slice: A
type: evidence
status: READY_FOR_REVIEW
commits: 8b49d16（匯入本體）、8d1227a（身分解析）
---

# Slice A 證據包｜Personal Inbox / Manual Capture

只記錄**本 session 實際跑出來**的結果。每一項都附鑑別力反證——一個永遠綠的
檢查不算證據。

## 1. 交付內容與行數

| 檔案 | +/- |
|---|---|
| `lib/omos/evidence_snapshot.rb`（新） | +148 |
| `lib/omos/inbox.rb`（新） | +168 |
| `lib/omos/cli.rb` | +145 / −2 |
| `lib/omos/installer.rb` | +33 / −1 |
| `test/conformance_3c.rb` | +249 |
| 卡片 | +32 |
| 合計 | **+775 / −3** |

產品碼 494 行中：**程式 337、註解 99、空白 58**。測試 249 行、61 項檢查。

## 2. 做了什麼

```text
FILE → managed evidence snapshot → MemorySupportLink → Candidate(PROPOSED)
```

新增 `import FILE [--memory-kind KIND]` 與 `inbox list`。**不新增任何資源
型別、不新增 table**。

三個設計決定：

- **managed snapshot 而不是只記原始路徑**。來源檔是使用者的檔案，隨時可能
  被改名或刪掉，而失效是安靜的。匯入當下複製 bytes 進
  `~/.omos/personal-memory/evidence/<sha256>/`。
- **id 由內容 digest 決定**（確定性 UUIDv7 形狀）。冪等不靠「查有沒有寫過」，
  而是同樣的輸入本來就算得出同樣的 id。
- **`memory_kind` 檢查在 capture 之前**。打錯字或夾帶
  `not_long_lived_by_default` 的 kind 都不該讓內容先被收進來。缺 kind
  （還沒決定）與 kind 錯誤（決定錯了）分開：前者留 snapshot 回
  `NEEDS_CANDIDATE_INPUT`，後者連收都不收。

## 3. 個人身分（Owner 裁決 2026-09-21）

```text
明確參數 > install receipt 的 personal_identity > （測試／暫時相容）環境變數 > fail closed
```

- `install --owner/--tenant` 設定一次，之後 `import note.md` 裸跑即可。
- receipt **只保存已明確設定過的值**，不是 identity authority，欄位名沿用既有
  `employee_owner_ref`／`tenant_id`，不新增第二套 vocabulary。
- **upgrade 原樣保留**；只有明確重新指定才覆寫。
- `install` 只給一半 → `INSTALL_IDENTITY_INCOMPLETE`，不寫半組身分。
- 缺身分 → `INBOX_OWNER_IDENTITY_REQUIRED`，且**不留 evidence snapshot**。

**不從 SessionStart 推**：HostSessionBinding 只有 `executor_ref`／
`executor_session_ref`／`cwd`／`project_ref`／`effective_scope`，沒有
`employee_owner_ref` 與 `tenant_id`。

## 4. 驗證結果

| suite | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | **195/195 PASS**（Slice A 新增 61 項） |
| validator（40 支） | 40 PASS / 0 FAIL |
| `git diff --check` | clean |

### 鑑別力反證（單點反轉，還原後全綠）

| 反轉 | 結果 | 轉紅的內容 |
|---|---|---|
| snapshot 改成非 content-addressed | 3c **177/185** | 重放增生、原檔移走後驗不到、失敗路徑留下孤兒 snapshot，共 8 項 |
| candidate 偷帶 `verification PASS` | 3c **184/185** | 「匯入不得自帶 verification／acceptance 權威」 |
| upgrade 洗掉身分 | 3c **194/195** | 「upgrade 必須原樣保留 identity」 |
| 身分缺失時改成用猜的 | 3c **192/195** | fail closed／不留 snapshot／訊息說得出怎麼補，共 3 項 |

第二筆特別說明：原本把 `governance` 改成 `PASS`/`ACCEPTED` 會讓測試**整包
炸掉**（既有 evaluator 直接 raise），而不是某一項轉紅。因此補了一條
`expect_rejected`，讓「匯入不得自帶 acceptance 權威」成為可反證的斷言。

## 5. 交付方主動揭露（請 reviewer 重點打）

**`Inbox.import` 是 library API，身分由參數傳入。** 解析與強制（explicit >
receipt > env > fail closed）發生在 **CLI 層**（`CLI#import_identity`）。
因此：

- 目前唯一的呼叫者是 CLI，MCP 與 SessionStart 都沒有暴露匯入面；
- 但**若日後有第二個呼叫者直接呼叫 `Inbox.import` 並自報 owner/tenant，
  就繞過了解析**。這是真實的形狀，不是假設。

請 reviewer 判定：解析是否應該下沉到 `Inbox`／`Runtime` 層，或維持在 CLI
並以「唯一呼叫者」作為約束。**交付方不預先實作任一方向。**

## 6. 沒有驗到的東西

- **真 Host 觸發**：本片不新增 Host 面，doctor 的 2 個 WARN 維持原狀。
- **非 macOS**：不在範圍。
- **大檔案**：目前沒有 size 上限測試；v1 只收 `.md`/`.txt`，但沒有機械上限。
  若 reviewer 認為需要，請指定門檻，交付方不自行決定。
- Slice B（`review due`、launchd、通知）**完全未實作**，本包不涉及。
