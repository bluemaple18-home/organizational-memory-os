---
id: EMEM11-SLICE-C-STANDALONE-PACKAGING-EVIDENCE-20260921
card: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921
slice: C
type: evidence
status: READY_FOR_REVIEW
---

# Slice C 證據包｜Standalone packaging closure

本包只記錄**本 session 實際跑出來**的結果。每一項都寫清楚「驗的是什麼」
與「怎麼證明它有鑑別力」——一個永遠綠的檢查不算證據。

## 1. 交付內容與行數

| 檔案 | +/- |
|---|---|
| `product/personal-memory/lib/omos/installer.rb` | +73 / -4 |
| `product/personal-memory/lib/omos/cli.rb` | +12 / -0 |
| `product/personal-memory/test/conformance_3c.rb` | +315 / -10 |
| `product/personal-memory/test/support.rb` | +22 / -1 |
| `scripts/validate_packaged_governance_drift.rb`（新，第 40 支 validator） | +77 |
| `product/personal-memory/governance/`（新，9 個位元組相同的副本） | 9 檔 |

產品程式碼淨增 **+81 行**，其餘為測試（+326）與一支 validator（+77）。
測試多於實作是刻意的：本切片的交付物**就是**「證明它離得開 repo」。

## 2. 驗收逐項

### 驗收 1｜workspace B（無 source checkout）

- build 在 workspace A（repo 來源）→ artifact `85d74fdf…9321a`
- 送到 `/tmp/omos-wsB.CrljpL/omos-artifact`（只有 artifact 本體 ＋ `test/`）
- B 內與其祖先目錄**皆無** `規格/v0.1` 與 `scripts/lib` 原件（實測 find 計數 0）
- B 內解析結果：`GOVERNANCE_ROOT=<B>/omos-artifact/governance`，
  `ARTIFACT_LOCAL_GOVERNANCE=true`，`REPO_ROOT=/private/tmp`（`規格/v0.1` 不存在）
- 四個交付面在 B 全部可用：install / CLI `status` / SessionStart hook /
  MCP `initialize` / `doctor`（18 OK / 2 WARN / 0 FAIL）
- **未改名或移走主工作區**——B 是 `mktemp -d` 的新目錄

### 驗收 5｜3a／3b／3c 在 workspace B 全數通過

| suite | repo | workspace B |
|---|---|---|
| 3a | 26/26 | 26/26 |
| 3b | 34/34 | 34/34 |
| 3c | 124/124 | 122/122（3 項 N/A） |

B 的 3 項 N/A 是「與 repo 原件逐位元組相同」——B 沒有原件可比，
本機**無從驗證**。這 3 項在報表上印成 `N/A` 而不是 PASS，並指名由 repo 側
的 drift gate 負責。把驗不到的東西報成通過，正是本產品一路在防的假成功。

### 驗收 2｜drift gate 雙向有效

三個方向都實測轉紅、還原後轉綠：

| 方向 | 結果 |
|---|---|
| 改 repo 原件、未重新打包 | `FAIL 漂移：規格/v0.1/common-vocabulary.yaml`，exit 1 |
| 竄改 package 內副本 | `FAIL 漂移：scripts/lib/runtime_log_oracle.rb`，exit 1 |
| package 內多一個檔 | `FAIL package 內有非預期的檔案`，exit 1 |
| 還原後 | `PASS … (9 files byte-identical)` |

### 驗收 3｜packaged governance 缺檔／損壞 → fail closed

- 從已安裝的 artifact 刪掉 `governance/scripts/lib/personal_memory_host_binding.rb`
  → artifact 的 CLI 直接失敗，訊息含 `PACKAGED_GOVERNANCE_MISSING`，
  **不回退 repo**。
- **鑑別力反證**：把 `contract.rb` 的 `if ARTIFACT_LOCAL_GOVERNANCE` 改成
  `if false`（即「缺檔就偷偷用 repo 的治理」）→ 該項立刻 FAIL（123 → 122）。
- 竄改一個位元組 → 重算的 artifact identity 不再等於 receipt 記的那一份。

### 驗收 4｜rollback 只切 pointer、不重寫 Host 設定

- `rollback` 的目標**只**能是 receipt 的 `previous_artifact_id`，且該版
  實物必須還在；不存在就 `ROLLBACK_ARTIFACT_MISSING` 明確失敗，
  不重新下載、不猜 SHA，且 `current` 不被動到。
- 三個 Host 設定檔的 **內容／inode／mtime** 在 rollback 前後完全相同。
- 額外把三個設定檔設為 `0444`：rollback 仍然成功。「Host 設定不可寫時仍能
  回退」本身就是 pointer-only 的意義。
- 前提不足一律明確失敗：`ROLLBACK_NO_RECEIPT`、`ROLLBACK_NO_PREVIOUS_ARTIFACT`。

## 3. 鑑別力反證（每一項都實跑過）

| 反證（把修法退掉） | 結果 |
|---|---|
| 私有 `abort_install` 改回 `rollback`（與 public 同名） | suite 中止：`private method 'rollback' called` |
| `previous_artifact_id` 照抄上一次安裝 | FAIL「同內容重裝不會把 previous 填成自己」 |
| rollback 順便 `writer_for(h).install` | FAIL ×5，首發 `Errno::EACCES`（唯讀守衛擋下） |
| `ARTIFACT_LOCAL_GOVERNANCE` 守衛關掉 | FAIL「artifact 少一份治理檔 → 直接失敗，不回退 repo」 |

第 3 項值得記一筆：**只比對設定檔內容抓不到這個缺陷**——`writer.install`
是 idempotent 的，多餘的重寫會產生位元組完全相同的檔案。是加上 inode／mtime
指紋與唯讀守衛之後才有鑑別力。這條在第一次寫的時候確實漏掉了。

## 4. 本切片順帶修掉的兩個缺陷（非新功能）

1. **方法同名覆蓋**：新增的 public `#rollback` 被既有的私有
   `rollback(backups, …)` 覆蓋（Ruby 無 overload），CLI 一呼叫就爆。
   私有那支改名 `abort_install`，名字也更符合它做的事。
2. **同內容重裝會把 previous 填成自己**：`materialize_artifact` 對相同內容
   重用既有目錄，照抄 `previous["artifact_id"]` 會讓 previous == current，
   rollback 變成回報成功卻什麼都沒換的 no-op，真正能回退的那一版還會被
   GC 當成無人引用而刪掉。

## 5. 全域回歸

- 3a 26/26、3b 34/34、3c 124/124（repo）
- 40 支 validator 全綠（含新增的第 40 支）
- `git diff --check` 無輸出
