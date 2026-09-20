# EMEM-11 切片 3｜Store / Runtime / CLI / MCP / Installer / Doctor — Handoff Packet

- **交付範圍**：`251a0d8..<本 packet 之前的 HEAD>`（見下方「交付 SHA」）
- **分支**：`main`（**流程偏差，見 §7**）
- 產品路徑：`product/personal-memory/`
- 收治：主卡切片 3（Cross-Host Conformance / Installer / Doctor）全部範圍

## 1. 交付對照（相對於開工前的盤點）

開工前盤點的四項能力**全部是 NOT_IMPLEMENTED**（無 `bin/`、無套件宣告、
`sqlite` 唯一命中是契約字串值、`command_ref` 只是符號 token）。現況：

| 能力 | 開工前 | 現在 |
|---|---|---|
| 本機 Store 與讀寫入口 | NOT_IMPLEMENTED | `lib/omos/store.rb`＋`runtime.rb`。真的開 SQLite、WAL、`BEGIN IMMEDIATE`、migration 鏈＋不可變 receipt；UPDATE/DELETE 由資料庫 trigger 擋 |
| 本機 MCP 與 CLI | NOT_IMPLEMENTED | `exe/omos-personal-memory{,-mcp,-session-start}`。CLI 無一行直接 SQL；MCP 為官方 `mcp` gem 的 stdio server，與 CLI 共用同一個 Runtime |
| Host 啟動與設定整合 | 全部是 fixture | `lib/omos/host_config.rb` 真的讀 `~/.codex/config.toml` 與 `~/.claude.json` / `~/.claude/settings.json`；`session_start.rb` 產出 HostSessionBinding |
| Installer／Doctor | NOT_IMPLEMENTED | `installer.rb`（含備份／複驗／回滾／receipt）、`doctor.rb`（24 項對實物） |

## 2. 核心設計約束的落地

**治理在落地之前**（Owner 明示）：所有判定都在 `store.transaction` 之外、之前；
被拒絕的寫入完全不進交易。conformance 每一條拒絕案例都**直接查實際資料表**
確認沒落地，不看 runtime 的自我回報。

**不新寫治理邏輯**：判定一律委派 `scripts/lib` 既有 evaluator——
`personal_memory_resource_evaluator`（本體）、`host_session_binding_shape`（binding）、
`weekly_closeout_history`（closeout）、`personal_memory_host_binding`（安裝 merge／
遮蔽／scope 推導）、`runtime_log_oracle`（journal 事後 conformance）。
CLI 的拒絕訊息就是既有 evaluator 原樣吐出的句子。

**operation journal 是證據不是保護**：`runtime.rb` 不引用 journal oracle，
conformance 有機器檢查守住這條邊界。

## 3. 證據

| 套組 | 結果 |
|---|---|
| `test/conformance_3a.rb`（Store/Runtime/CLI） | **26/26 PASS** |
| `test/conformance_3b.rb`（MCP stdio／SessionStart／設定探索） | **23/23 PASS** |
| `test/conformance_3c.rb`（三組驗收） | **38/38 PASS** |
| `doctor`（安裝後，假 HOME） | **21 OK / 3 WARN / 0 FAIL** |
| 全庫 Ruby validator | **39/39 PASS** |
| `git diff --check` | clean |

全部以 `product/personal-memory` 鎖定的 Ruby 3.4.10 + Bundler 執行。

**三組驗收的關鍵證據**

- **A**：Codex 設定在 uninstall 後**位元組完全相同**；注入中途失敗後兩個 Host
  的設定全數復原且無殘留 receipt；reinstall／upgrade 不動個人資料。
- **B**：未安裝時 `mcp_handshake=OK` 但 config／store=FAIL——**三種結果彼此獨立**
  是實測而非宣稱。遮蔽（含 payload 完全相同）、hook 移除、executable 不存在
  各有實測失敗案例。
- **C**：真的**同時跑兩個 MCP 子進程對同一個 store 往返**（Codex ↔ Claude Code
  雙向）；切換專案不得擴權；Codex 開的週期由 Claude Code 接續收尾且第二次
  terminal 被拒；跨 Host retry 換 promotion identity 被拒；重啟後重放是 no-op；
  install→upgrade→uninstall→reinstall 後資料不變。

## 4. 過程中實測到、值得單獨記錄的發現

1. **SQLite 版本三個來源不同**：同一台機器上系統 `sqlite3` CLI 與 Python stdlib
   都是 **3.51.0**（低於 WAL-reset 修復的 3.51.3），Ruby gem 實際連線是
   **3.53.2**。證實必須由產品實際開啟的連線查 `SELECT sqlite_version()`。
   此項已進 `Store#assert_sqlite_version!` 與 doctor。
2. **TOML 不能 parse→dump**：用真實的 `~/.codex/config.toml` 實測，round-trip
   後 288 行/8,643 bytes → 203 行/8,100 bytes，**3 個註解全失**。因此採哨兵
   區塊外科式編輯。
3. **`#!/usr/bin/env ruby` 在乾淨 PATH 下 SIGILL（exit 132）且毫無輸出**，
   而 Ruby 端的版本守衛救不了——含新語法的檔案在 2.6 會先 parse 失敗。
   入口改為 POSIX sh wrapper，版本解析移到 Ruby 之外。
4. **MCP gem 會 deep-symbolize JSON 參數**，但治理 evaluator 比的是字串鍵；
   不正規化會讓合法 binding 被誤判成 `UNKNOWN_FIELD`。

## 5. 已知缺陷（請 review 優先打這裡）

### 5.1 P1 — SessionStart hook 的條目形狀未經 Host 驗證，且 Codex 是否支援該事件無證據

這是我自己發現並主動揭露的，**尚未修**。

- **Codex**：真實 `~/.codex/config.toml` 的 hook 是**巢狀**結構——
  `[[hooks.Interrupt]]` + `[[hooks.Interrupt.hooks]]`，帶 `type` / `command` /
  `timeout`，**沒有 `id`**（Codex 以位置識別，如 `interrupt:0:0`），另有
  `[hooks.state."<path>"]` 的 `trusted_hash` 信任機制。
  我的 installer 寫的是**扁平**的 `{id, command}`，形狀不符。
  更根本的是：**真實設定裡只出現過 `Interrupt` 事件，沒有任何證據顯示 Codex
  支援 `SessionStart`**。該事件來自切片 2 的 fixture 宣告，我實作時未驗證它存在。
- **Claude Code**：`SessionStart` 事件確實存在（repo 自己的官方 hook 事件快照有列，
  來源 `https://code.claude.com/docs/en/hooks`），但其 settings 條目 schema
  未經驗證；我寫的同樣是扁平 `{id, command}`。

**為什麼既有檢查抓不到**：post-write 複驗是拿「我寫的形狀」跟「我用同一套假設
算出的期望」比對，**自我一致但對真實 Host 可能是錯的**。這正是前幾輪 review
反覆抓到的「欄位名對得上、資料形狀不對」那一族，只是這次發生在產品與外部
Host 的邊界上。

**已做的誠實處置**（不猜形狀硬修，依 `EVIDENCE_LIMIT` 與 `DEFAULT_DECISION`）：
doctor 的該項由 `..._hook_active`（會誤報 OK）改為 `..._hook_present`，狀態
降為 **WARN**，訊息明寫「已寫入，但 hook 條目形狀未經 Host 實際驗證」。

**建議裁決**：這一項需要 Host 端的 schema 證據才能正確實作。在取得證據前，
Codex 的 SessionStart 註冊應視為 **BLOCKED**，不應宣稱切片 3 的 Host 整合完成。

### 5.2 P2 — Codex 的遮蔽偵測無可觀測來源

`~/.codex/config.toml` 的 36 個 `[projects."<path>"]` 只帶 `trust_level`，
沒有專案層 MCP 覆寫。doctor 對 Codex 回 **WARN「無可觀測來源」**，不假裝掃過。
Claude Code 側可正常偵測（實測 `HBV1_MCP_SHADOWED`，含 payload 完全相同的情況）。

### 5.3 P2 — 產品尚未可獨立安裝

`lib/omos/contract.rb` 的 spec 與共用 evaluator 路徑指向 repo 內
（`規格/v0.1/`、`scripts/lib/`）。把它們打包進可散佈的產物尚未做
（程式內已明記 NOT_IMPLEMENTED）。同理，取得與鎖定 Ruby 3.4 的方式在目標
電腦上也**尚未實測**——預編譯 gem 在本機可用不代表同事的機器可用。

### 5.4 主卡 DoD 尚未滿足的項目

- **「Codex 與 Claude Code 兩個 Host 都有真人實測」— 未完成。** 本片所有
  MCP 往返都是 conformance harness 自己 spawn 的子進程，**沒有任何一次是由
  真正的 Codex 或 Claude Code 啟動的**。§5.1 的 hook 形狀問題正是這個缺口的
  直接後果。
- 因此本片**不足以宣稱可進 SSP-295 full pilot**。

## 6. 交付量測

| 類別 | 行數 |
|---|---|
| 產品程式（`lib` / `exe` / `bin`） | 2,032 |
| conformance（3a / 3b / 3c ＋ 共用 support） | 890 |
| 規格增修（`config_discovery`、`higher_precedence_sources`） | 49 |
| 共用 oracle 抽取（搬移，非新寫） | 252 |

開工前預估 2,030–2,550，實際產品＋測試 **2,922 行，超出約 15%**。主因：
installer 的備份／複驗／回滾三段、doctor 從 13 項長成 24 項、三組驗收各需真實子進程。

**依 `rules/07` 與 `rules/02 §2` 做過的精煉**：最長方法 46 行程式（8 個契約
必要判定），無「50 行邏輯寫成 200 行」；註解 12%、空行 13%；已移除 6 處死碼
（含宣告後從未 raise 的 `ImmutabilityViolation`）。規則 07 明文禁止為行數
犧牲可讀性，故未再壓縮。

## 7. 流程偏差（主動揭露）

切片 3 的開發**直接在 `main` 上進行**，沒有依前兩片的慣例開 feature branch
再 review 後合併。這是我的疏失。目前 `main` 已含全部切片 3 內容；若 review
判定需要回退，`251a0d8` 是切片 3 之前的最後一個 commit。

## 8. 請 review 針對這些下手

1. §5.1 的 hook 形狀與 Codex SessionStart 存在性——我認為是 P1，請裁決處置方式。
2. post-write 複驗的自我一致性問題：是否需要一個「對真實 Host 生效」的驗證方式，
   還是只能靠真人實測補上。
3. §7 的流程偏差是否需要補救（例如把切片 3 回退成 branch 再走一次流程）。
4. 三組驗收的覆蓋是否足夠，或有哪一條主卡要求我漏了。
