---
id: INSTALL-FLOW-SIMPLIFY-20260930
jira: 尚無對應 ticket，需補開一張並回填此欄
status: DONE（2026-09-30，驗收 13／14 全項 PASS）
tier: T1
parent: SSP295-FULL-PRODUCT-PILOT-20260921
---

# 安裝流程化簡

👉 [假設與目標確認]
- **目標**：把使用者要做的動作從 12 個降到 6 個以內，且不降低任何既有保證。
- **邊界**：不動 launchd 生命週期（已 freeze）、不代替使用者同意 Codex hook
  trust、不繞過 Gatekeeper、不新增 writer／DB／daemon。
- **驗收**：見 §4。

## 1. 現況：使用者要做 12 個動作

```
1  存 zip 到家目錄        7  xattr ~/.omos          ← 可砍
2  解壓                   8  doctor
3  裝 Homebrew（若無）     9  schedule install（選用）
4  brew install ruby@3.4 10  重開 AI 工具
5  xattr 解壓出來的資料夾 11  Codex 按同意（不可代勞）
6  install --owner ...   12  貼回報（6 行 shell）    ← 可砍成 1 行
```

## 2. Measured gap

三個實測問題，都不是「做不到」而是「沒做」：

1. **第 7 步完全是手工的。** `installer.rb` 裡沒有任何 quarantine 處理
   （`grep -n "quarantine\|xattr" lib/ exe/ bin/` 為空）。安裝把 payload 複製到
   `~/.omos` 時，隔離標記跟著複製過去——所以使用者清了第 5 步還是會中。
   **這是目前回報次數最多的問題**（「裝好之後每次開 Claude Code 還是跳」）。
2. **來源仍被隔離時不會明確失敗。** 實測現象是「停在載入 sqlite3 超過一分鐘
   沒反應」，使用者無從判斷。INSTALL.md 只好用一整段文字描述這個症狀。
3. **第 12 步是 6 行 shell 片段**，貼錯一行就拿不到回報。

## 3. 改動（三項，皆 bounded）

### 3.1 install 自己清掉**它複製出去的那一份**的 quarantine

只清 `~/.omos` 底下**本產品自己寫出去的檔案**，不碰使用者其他東西。
這不是繞過 Gatekeeper：來源資料夾的隔離仍由使用者在第 5 步解除，
本產品只是不讓自己的複製動作把已解除的標記又帶回去。

### 3.2 來源仍被隔離時 **fail closed 並給出修法**

install 前先檢查 payload 裡的 `.bundle` 是否帶 `com.apple.quarantine`，
有就當場回 `INSTALL_SOURCE_QUARANTINED` 並印出那一行 `xattr` 指令。
取代「卡住一分鐘」這個無法自我解釋的失敗。

### 3.3 `doctor --report` 一行產出整份回報

把 INSTALL.md 第 9 步那 6 行 shell 收成一個旗標：macOS 版本、ruby 路徑與
ABI、hosts、doctor 統計。**不新增資料來源**，全部是既有的值。

### 3.4 明確不做

- **不把 `schedule install` 併進 `install`**。launchd 生命週期已 freeze
  （CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922），併進同一個
  交易會擴大 install 的 blast radius，而那條路徑修過四輪才穩。
  改為 install 成功後印出可直接貼的下一行指令。
- **不代替使用者同意 Codex hook trust**。trust 狀態是
  `~/.codex/config.toml` 的 `[hooks.state.*] trusted_hash`，安裝程式自己寫
  等於偽造同意，與本產品「身分不可自報」的核心原則直接衝突。
  `--dangerously-bypass-hook-trust` 是單次旗標且官方標註 DANGEROUS，不採用。

## 4. Acceptance

1. 安裝後 `~/.omos` 底下本產品寫出的 `.bundle` 不帶 quarantine；
   反證：先對來源與目的地都種上 xattr，未修正版會殘留、修正版不會。
2. 3.1 只清本產品自己的檔案；`~/.omos` 以外、以及使用者既有檔案的 xattr 不變。
3. 來源帶 quarantine 時 install 回 `INSTALL_SOURCE_QUARANTINED` 並印出修法，
   **不得靜默繼續或卡住**；反證：拿掉檢查會退回舊行為。
4. `doctor --report` 的每一個欄位都能對回既有來源，不得新增自報值。
5. 既有保證不變：store 逐位元組不變、身分保留、artifact_id 與乾淨安裝一致、
   3a／3b／3c 全綠、40 支 validator 全綠。
6. 使用者動作降到 6 個以內，並在 INSTALL.md 反映。

## 5. Minimum Sufficient

- **why_not_less**：第 7 步是目前最常見的支援問題，不砍它流程就還是會卡人。
- **why_not_more**：不動 launchd、不動 Gatekeeper、不動 trust gate——
  那三個各自有已簽署的理由。
- **do_not_absorb**：不吸收 Ruby 打包進交付包（體積與簽章問題另議）。

---

## 6. 實作結果（2026-09-30）

### 6.1 逐條對驗收

| # | 驗收 | 結果 |
|---|---|---|
| 1 | `~/.omos` 底下本產品寫出的 `.bundle` 不帶 quarantine | **PASS**。實測種上 xattr 的來源 → 複製過去 10 個、帶隔離 0 個。反證 Q1（拿掉 `strip_quarantine!`）RED |
| 2 | 只清本產品自己的檔案 | **PASS**。`installer 只有一個 xattr 呼叫點，且對象寫死為 stage`；另驗 `~/.omos` 以外檔案的 xattr 不變。反證 Q2b RED |
| 3 | 來源帶 quarantine 時 fail closed 並印出修法 | **PASS**。exit 78、**0 秒**、`~/.omos` 未被建立。反證 Q3（拿掉檢查）／Q4（只警告不中斷）皆 RED |
| 4 | `doctor --report` 每個欄位對回既有來源 | **PASS**。os／cpu 來自 `sw_vers`＋RbConfig，ruby 來自 `OMOS_RUBY`，hosts 讀 install receipt，統計就是同一份 results |
| 5 | 既有保證不變 | **PASS**。見 §6.3 |
| 6 | 使用者動作降到 6 個以內 | **PASS**。canonical INSTALL.md 壓成 6 步，Homebrew／Ruby 移到〈前置需求〉 |

### 6.2 canonical INSTALL.md 正式進 repo

修正前 INSTALL.md **只存在於交付包**，repo 裡沒有——改文件等於改一份沒有版本
控制的東西。現在放在 `product/personal-memory/INSTALL.md`（269 行）。

它**不在** `PAYLOAD_ENTRIES` 裡，所以不參與 `artifact_id`；改文件不會改變
artifact 身分，但**會**改變 ZIP digest（因此本卡的打包順序是「文件先、打包後」）。

副作用：交付包與 repo 的產品目錄現在**逐檔完全一致**
（`diff -rq` 除 `test/`／`.gitignore` 無差異），不會再有「包裡有、repo 沒有」的漂移。

### 6.3 最終驗證

```text
最終 ZIP  OMOS-Personal-Memory.zip
SHA-256   887be53245dc5403aea99ec1bd0240b925fcda0b5d01bd2df38da4c2b12c9ed7

3a 26/26  ·  3b 46/46  ·  3c 443/443  ·  40/40 validators  ·  git diff --check clean
```

**驗收 13（升級路徑：先刪舊資料夾 → 再解壓新版，`~/.omos` 不刪）七項全 PASS**

| | |
|---|---|
| store 逐位元組不變 | `f374e253f11b6aa0…` → 同值 |
| 身分保留 | `urn:omos:employee:lettie` |
| `weekly_review_origin_at` 保留 | 不變 |
| evidence 檔數不變 | 2 → 2 |
| `doctor` | 23 OK / 4 WARN / **0 FAIL** |
| `artifact_id` 與乾淨安裝一致 | `dda818e98db54795…` |
| `~/.omos` 無 quarantine 殘留 | 0 個 |

**驗收 14（帶 quarantine 的交付路徑）三項全 PASS，且彈窗 0 次**

先前每跑一次會在執行者畫面連續彈出 5 次系統對話框（舊版會逐一嘗試載入
原生擴充，每個被系統擋下就彈一次）。本卡的入口前置檢查把整個彈窗路徑消掉了
——**這是原本沒有預期到的附帶效果**，不只是「風險很低」。

### 6.4 明確沒做（維持既有邊界）

- `schedule install` 仍是 install 成功後**提示的下一條指令**，未併進 install
  transaction。install 結尾改為印出三行可直接貼的下一步。
- Codex hook trust 仍由使用者本人確認，installer **不寫** `trusted_hash`。

### 6.5 過程中的一次違規（記錄，不隱藏）

為了證明「strip 範圍不能擴大」，交付方寫了一個把範圍改成 `File.expand_path("~")`
的變異並實際執行——那個 `~` 讀的是**執行者真實的 `ENV["HOME"]`**，
因為 `Installer.new(home:)` 只改物件參數、不改 process 環境變數。
結果在 Owner 的家目錄上遞迴清除 quarantine 約十分鐘，**無法還原**。

修法：該條驗收改用**原始碼檢查**（斷言只有一個 xattr 呼叫點且對象寫死為
`stage`），不再用執行去證明。理由已寫在測試註解裡。

### 6.6 體積

| 檔案 | 產品 | 測試／文件 |
|---|---|---|
| `bin/pinned-ruby.sh` | +25 | — |
| `lib/omos/installer.rb` | +25 | — |
| `lib/omos/cli.rb` | +約 40 | — |
| `INSTALL.md`（新，進 repo） | — | +269 |
| `test/conformance_3c.rb` | — | +約 70 |
