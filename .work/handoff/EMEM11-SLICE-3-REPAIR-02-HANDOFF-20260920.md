# EMEM-11 切片 3 repair-02 — Handoff Packet

- 前一輪：repair-01 交付 `19f061a`，re-review packet `7c1ab15`（reviewer 尚未回覆裁決前，這輪的 WIP 已在分支上）
- **repair-02 交付 SHA：`756f005fe5120191c4975d8804cc7556ae2d8b0c`**（分兩個 commit：`a8bfbd6` 核心修復、`756f005` 補 Owner 要求的驗證）
- 分支：`cc/emem11-slice3-repair-01`（沿用，未開新分支）
- 未 push；未動 main

## 0. 這輪的起點

分支上有 5 檔未提交的 WIP（`session_state.rb` / `mcp_server.rb` / `host_config.rb` /
`host_config_writer.rb` / 規格 yaml），已經把 session identity 從 cwd 改成
`(host, native_session_id)`、把 hook 辨識從前綴命中改成精確相等。接手時先跑
conformance：3a 26/26、**3b 17/26、3c 直接 crash**。

## 1. Repair correctness：這輪關掉的問題

### 1.1 新收的 bug（不是 P1/P2 本身，是精確比對曝露出的舊洞）

`HostConfigWriter#initialize` 裡：

```ruby
@command_map = { mcp_command => ..., hook_command => ... }
@command_map[hook_invocation] = @command_map[hook_command]   # ← 這裡呼叫 hook_invocation
...
@hook_command = hook_command                                  # ← 這裡才賦值
```

`hook_invocation` 讀的是 `@hook_command`（實例變數），呼叫當下還是 `nil`，
所以存進 map 的鍵少了命令本體、只剩參數字串。舊版用 `start_with?` 前綴命中，
剛好會撞到 hash 裡另一筆「裸 `hook_command` → command_ref」而蒙混過關；
repair-02 改精確比對後，這個鍵永遠對不上，`install`/`uninstall` 直接
`HBV1_POST_WRITE_VERIFY_MISMATCH`（3c 崩潰的真正原因）。

**修法**：把 `@mcp_command`/`@hook_command`/`@env` 的賦值搬到建 `@command_map`
之前。純粹的賦值順序修正，沒有動任何判定邏輯。

### 1.2 P1-1 / P1-2（session identity 不再用 cwd）—— CLOSED

- `SessionState` 鍵改為 `(host, native_session_id)`；`read` 額外檢查
  `record["host"]`/`record["session_id"]` 與呼叫端自洽（防重放）。
- `MCPServer.native_session_id(host)` 依契約的 `native_session_id_source`
  取值；Claude Code 用 `ENV["CLAUDE_CODE_SESSION_ID"]`（PROCESS_ENV，本機
  實測存在，值為 UUID，hook 與 MCP server 同為其子行程）；Codex 該機制標
  `UNAVAILABLE`，一律 `MCP_NATIVE_SESSION_ID_UNAVAILABLE` fail closed，不
  退回 cwd 或任何代理鍵猜測。
- 驗證（conformance_3c 群組 C）：同一 cwd 兩個並行 Claude Code session
  （不同 `native_session_id`）各自讀寫互不覆蓋、互相看得到對方寫的列；
  換成第三個**從沒跑過 hook**的 session，讀回 `MCP_NO_SESSION_RECORD`，
  不會撿到前兩個 session 的 identity。

### 1.3 P2（hook 辨識改精確相等）—— CLOSED

- `command_ref_of`（讀取端，兩個 Host 共用）與 `own_group?`（Claude Code
  JSON 寫入端）都改成精確字串比對，不再用 `start_with?` 前綴命中。
- 新增 adversarial 測試（conformance_3c 群組 A）：構造一個以本產品 hook
  命令當前綴的第三方 hook（`...-foreign ...`）：
  - `install` 後兩組並存，沒有被誤認合併成一組；
  - `uninstall` 只移除本產品自己那組，第三方那組原封不動；
  - `doctor` 在第三方 hook 存在下，仍正確認得出本產品自己的 hook——維持
    既有的已知 `WARN`（形狀對但未經真 Host 觸發，repair-01 就有這條），
    **沒有**因為認錯人而退化成 `FAIL`（=「以為沒裝」）。
  - Codex 側因為卸載走 TOML 哨兵區塊外科式編輯（`strip_managed` 直接按
    界線刪，不靠 command 比對識別身分），這個 collision 風險本來就只存在
    於「讀取／判定」路徑（`command_ref_of`），不存在於「卸載寫入」路徑；
    上面這組測試選 Claude Code（JSON）是因為那裡的 `own_group?` 才是真正
    控制安裝/卸載會不會動錯東西的地方。

### 1.4 Owner 要求的 7 項驗證 —— 逐項對應

| # | 要求 | 對應驗證 | 結果 |
|---|---|---|---|
| 1 | 同 cwd 兩個並行 Claude Code session 不互相覆蓋 | 3c 群組 C：`c1`/`c2` 同 cwd 不同 session_id，雙向讀寫 | PASS |
| 2 | 換 session 後不得讀到另一 session 的 identity | 3c 群組 C：`c3`（從沒跑過 hook）在同 cwd 下讀回 `MCP_NO_SESSION_RECORD` | PASS |
| 3 | Codex 三個 tool 全部 fail closed | 3b：read/write/closeout 三個都斷言 `MCP_NATIVE_SESSION_ID_UNAVAILABLE` | PASS |
| 4 | Claude Code 正常 session read/write/closeout 可用 | 3b（read/write）+ 3c 群組 C（write/read/closeout） | PASS |
| 5 | 模型不能用 tool args/cwd/state filename 偽造 identity | 3b「模型硬塞 binding 參數被忽略」＋設計上 native_session_id 只認 trusted env、cwd 只從 hook 記錄取得（`mcp_server.rb` 已不呼叫 `Dir.pwd`）、檔名是 `SHA256(host, session_id)` 不可由呼叫端指定 | PASS（結構性保證 + 既有測試） |
| 6 | `...session-start-foreign` 不得被 install/uninstall/doctor 誤認 | 3c 群組 A 新增三段（見 1.3） | PASS |
| 7 | 3a/3b/3c、全庫 validators、`git diff --check` 全部重跑 | 見下方驗收表 | PASS |

## 2. 順手清掉的一處未接線程式碼

WIP 裡有一個 `SessionState.clear!(host, session_id)`，註解寫「SessionEnd hook
用」，但這輪、也包括 repair-01，都沒有 SessionEnd hook 的安裝/執行路徑——
沒有任何呼叫端。既然叫不到，就不留著等以後接：已刪除。如果之後要做
session 結束清理，那是新功能，需要先有 SessionEnd hook 的安裝與測試，不
是免費夾帶在這裡。

## 3. Scope conflict —— 留給 reviewer / Owner 裁決，這輪沒有動

`規格/v0.1/personal-harness-integration.yaml` 的 `supported_hosts_v1` 仍是
`[Codex, Claude Code]`，**這輪沒有改**。但現在的**執行事實**是：Codex 的
Personal Memory MCP（read/write/closeout）一律 fail closed，因為它沒有官方
管道讓 server 獨立取得 native session id（`native_session_id_source.Codex.
mechanism: UNAVAILABLE`，repair-01 已用真 codex-cli 0.153.2 端到端探針證實：
per-session 單一進程、可見環境變數為空集合、整個 session 期間只收到
`initialize`/`notifications/initialized`/`tools/list`，沒有任何
`tools/call`）。

也就是「契約宣告支援兩個 Host」與「其中一個 Host 的能力在目前 runtime 下
永遠拒絕」這兩件事同時成立。這不是 repair-02 能力範圍內能收的東西：

- 不會自行把 Codex 從 `supported_hosts_v1` 移除——那是產品範圍，屬 Owner。
- 也不會把「宣稱支援但永遠拒絕」當成最終產品結論寫死——目前的 fail closed
  是誠實反映 runtime 現狀，不是設計終點；上游若提供可信 native session
  identity 管道，這裡隨時可以收斂回真的支援。

請 reviewer / Owner 針對這一項單獨裁決：維持現狀（契約寫兩個 Host、Codex
那條路徑先天走不通）、收斂 `supported_hosts_v1`、還是要求別的緩解方案。
規格裡已經留了 `scope_note` 註記這一點屬於 Owner 裁決範圍。

## 4. 驗收

| 套組 | repair-01 交付時 | 這輪起點（WIP） | repair-02 交付 |
|---|---|---|---|
| conformance_3a | 26/26 | 26/26 | **26/26** |
| conformance_3b | 26/26 | 17/26 | **27/27**（+1：Codex 三 tool 全 fail closed） |
| conformance_3c | 38/38 | crash | **45/45**（+7：hook collision ×3、同 cwd 並行 session ×2、Codex 三 tool、既有跨 Host 場景改寫成跨並行 session） |
| 全庫 `scripts/validate_*.rb`（39 支） | 39/39 | 未跑 | **39/39** |
| `git diff --check` | clean | — | **clean** |

## 5. 未收治（維持原 packet 的揭露，這輪沒有新進展也沒有讓它更糟）

- 產品尚未可獨立安裝。
- 主卡 DoD 的「兩個 Host 都有真人實測」仍未完成——這輪反而把「Codex 是否
  算完成」變成一個更明確的問題（見 §3），不是進度倒退，是把原本含糊的
  「WARN，尚待真人測」收斂成「這條路徑目前結構性走不通」。
- `codex_session_start_hook_present`／`claude_code_session_start_hook_present`
  仍是 WARN（形狀對，未經真 Host 觸發）；`codex_no_shadow` 仍是 WARN
  （Codex 沒有可觀測的專案層覆寫來源）——兩者都不是這輪範圍。

## 6. 請 review 針對這些下手

1. §1.1 的初始化順序修法是否還有其他呼叫路徑受影響（我只驗證了
   install/uninstall 兩條路徑，`command_map` 的 reader 方法本身沒有其他呼叫端）。
2. §1.4 第 5 項是「結構性保證＋既有測試」而非新增的專門攻擊測試——如果
   reviewer 認為需要更直接的偽造嘗試（例如經 tool args 塞 cwd／session_id
   類欄位、驗證 schema 確實擋掉），這是下一輪可以收的項目。
3. §3 的 scope conflict 裁決本身。
