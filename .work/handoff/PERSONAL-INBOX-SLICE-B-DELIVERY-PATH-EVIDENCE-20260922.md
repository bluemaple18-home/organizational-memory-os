---
id: PERSONAL-INBOX-SLICE-B-DELIVERY-PATH-EVIDENCE-20260922
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
type: evidence
status: READY_FOR_REVIEW
scope: 主卡驗收 12（upgrade regression）、13（zip 覆蓋解壓）、14（quarantine）
blocked_item: 驗收 8（真 launchd 實證，需 Owner 明示）
---

# Slice B delivery-path 證據包

只記錄**本 session 實際跑出來**的結果。

## 驗收 12｜既有安裝 upgrade 後狀態保留 — **PASS**

做法：用 `8d1227a`（Slice A 版，無 `review`／`schedule`）建立既有安裝，
匯入兩筆內容，再覆蓋成現行版並跑 `install`。

| 檢查 | 結果 |
|---|---|
| Personal Store 逐位元組相同 | **是** |
| `.claude/settings.json` 逐位元組相同 | **是** |
| receipt 的 `personal_identity` 保留 | `emp-001 / t-acme` |
| evidence snapshot 保留 | 2 筆，未變 |
| 新 surface `review due` | 可用 |
| `doctor` | 18 OK / 2 WARN / **0 FAIL** |

## 驗收 13｜實際交付路徑的 upgrade — **PASS（但須指定正確步驟）**

### 13.1 `unzip -o` 覆蓋可以跑，`cp -R` 不行

先用 `cp -R` 覆蓋時，vendor 內的**唯讀 gem 檔**大量 `Permission denied`。
`unzip -o` 沒有這個問題（它 unlink 後重建）。**交付路徑用的是 unzip，所以
這一點不阻塞**，但值得記下來：任何用 `cp`／`rsync` 覆蓋的做法會失敗。

覆蓋解壓後：store 逐位元組相同、identity 保留、evidence 保留、`review due`
可用、`doctor` 0 FAIL、repo 側 drift gate `PASS (9 files byte-identical)`。

### 13.2 **殘留舊檔會改變 artifact identity**

覆蓋解壓**不會**刪掉新版已經沒有的舊檔案。實測種兩個殘留檔
（`lib/omos/obsolete_module.rb`、`governance/scripts/lib/obsolete_evaluator.rb`）：

| 情況 | artifact_id |
|---|---|
| 有殘留檔 | `fabb0b309233e148…` |
| 清掉殘留後 | `44d977dc67539ac4…` |
| 先刪資料夾再解壓 | `44d977dc67539ac4…`（與乾淨安裝**完全一致**） |

後果：同一個產品版本，殘留檔不同的使用者會得到**不同的版本編號**；每次覆蓋
升級還會在 `versions/` 多累積一份。

**已安裝副本本身是乾淨的**（殘留檔沒有被複製進 `versions/<id>/`），
`doctor` 也維持 0 FAIL——所以這不是正確性缺陷，是 identity 的環境相依。

### 13.3 因此卡上指定的正確步驟

> **先把舊資料夾整個刪掉，再解壓新版**，不要直接覆蓋。

已寫進交付包的 `INSTALL.md`（新增「升級到新版」一節，含為什麼、以及
「你的資料不會受影響」的實測說明），zip 已重打。

## 驗收 14｜帶 quarantine 的交付路徑 — **部分達成**

| 子項 | 結果 |
|---|---|
| 對整包實際寫入 `com.apple.quarantine` | **做到**：10 個 `.bundle` 被標記 |
| **重現 Gatekeeper 攔截** | **未做到**，見下 |
| 解除指令後殘留數為 0 且安裝／doctor 正常 | **做到**：殘留 0、`INSTALLED`、0 FAIL |
| 安裝說明警告不得按「丟到垃圾桶」 | **做到**：INSTALL.md 出現 2 次 |

### 為什麼攔截沒重現（交付方揭露）

用 `xattr -w` 人工寫上的 quarantine 屬性，在本機**不會**真的觸發
Gatekeeper 攔截——`doctor` 照常通過。同事端 2026-09-21 的實際攔截來自
**真正經過 Teams 傳輸**的檔案，其 provenance 與人工寫入的不同。

因此驗收 14 的第一個子項**在本機無從達成**。**條文不改寫**——把「重現攔截」
降格成「寫得上 xattr」正是假成功。

可行的補法只有一種：**把 zip 真的傳出去再傳回來**（例如經 Teams／
瀏覽器下載），取得帶真實 provenance 的檔案後再驗。這需要 Owner 決定要不要
做，交付方不自行外送檔案。

## 尚未進行

- **驗收 8｜真 launchd 實證**：`schedule install` → `launchctl print` →
  `schedule remove` → `launchctl print` 不存在。會在 Owner 機器上真的註冊
  LaunchAgent，**需 Owner 明示**。
