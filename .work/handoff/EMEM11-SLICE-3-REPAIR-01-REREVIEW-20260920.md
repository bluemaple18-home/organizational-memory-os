# EMEM-11 切片 3 repair-01 — 再 review Handoff Packet

- 原交付：`806cfba`（NO_GO，P1×3 / P2×1 / P3×1）
- **repair-01 交付 SHA：`19f061a36e99cab295b291215f912d89133e3961`**
- 分支：`cc/emem11-slice3-repair-01`（依裁決從目前 main 開，**未** reset/revert main）
- **正確的 baseline 是 `50be05c`**（P3 已確認：`50be05c..` 的 `git diff --check` clean，
  `251a0d8..` 會報切片 2 舊文件的 whitespace）

## 0. 先更正我在原 packet 裡的一個錯誤結論

原 packet §5.1 我寫「沒有任何證據顯示 Codex 支援 SessionStart」。**那是錯的。**
從本機 codex-cli 0.153.2 的 binary 取出的事件列表明確包含 `SessionStart`：

```
PreToolUse / PermissionRequest / PostToolUse / PreCompact / PostCompact /
SessionStart / SessionEnd / SubagentStart / SubagentStop / Interrupt
```

我先前只看了使用者現有設定裡「碰巧出現過」的 `Interrupt`，就推論事件不存在——
那是把「沒觀察到」當成「不存在」。reviewer 的判斷正確，本輪不再把 Codex 標成
未知或 BLOCKED。

## 1. 本輪取得的官方 schema（實證，非文件記憶）

**MCP 註冊**——`codex mcp add <name> --env K=V -- <command>` 在隔離 HOME 實際寫出：

```toml
[mcp_servers."omos.personal-memory"]
command = "<abs>"

[mcp_servers."omos.personal-memory".env]
OMOS_HOST = "Codex"
```

**沒有 `transport`**（stdio 由 command 判定，HTTP 才用 `--url`），env 在巢狀 `.env` 表。

**Hook**——binary 內的型別定義顯示三層結構：

```
internally tagged enum HookHandlerConfig:
  type / command / commandWindows / timeout / async / statusMessage / mcp_tool / ...
MatcherGroup: matcher + hooks
```

即 `[[hooks.<Event>]]`（MatcherGroup）→ `[[hooks.<Event>.hooks]]`（HookHandlerConfig[]），
**handler 沒有 `id`，也沒有 `env`**。Claude Code 同為三層。

以上全部寫進規格 `host_profiles.<host>.config_discovery.registration_shape`
與 `bootstrap_contract.host_native_stdin_fields`，產品不再憑記憶實作。

## 2. 四筆收治

### P1-A 註冊形狀（兩個 Host 都錯）

Codex 受管區塊現在寫出：

```toml
[mcp_servers."omos.personal-memory"]
command = "…/exe/omos-personal-memory-mcp"

[mcp_servers."omos.personal-memory".env]
OMOS_HOST = "Codex"
OMOS_RUNTIME_SCOPE_MODE = "EMPLOYEE_PRIVATE"
OMOS_PERSONAL_MEMORY_STORE = "…"

[[hooks.SessionStart]]

[[hooks.SessionStart.hooks]]
type = "command"
command = "…/exe/omos-personal-memory-session-start --host \"Codex\" --runtime-scope-mode EMPLOYEE_PRIVATE"
```

Claude Code：`{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"…"}]}]}}`。

因為 handler 沒有 id，本產品改以 **command 前綴**辨識自己的註冊；讀取端把三層攤平後
仍以契約的 `own_hook_id` 呈現，**切片 2 的既有 evaluator 一行都沒改**。

### P1-B SessionStart 吃真 Host input

entry 改吃真 stdin（`session_id` / `cwd` / `hook_event_name` / `source`）。
Host 不提供的 `host` 與 `runtime_scope_mode` 由 installer 注入：
MCP server 走官方 `.env` 表，hook 因為 **HookHandlerConfig 沒有 env 欄位**，
只能走命令列參數（設定檔本身即信任邊界）。

實測：

| 輸入 | 結果 |
|---|---|
| 真 Host stdin + installer 注入的參數 | 成功，輸出 `hookSpecificOutput` |
| stdin 缺 `session_id` | `REFUSED MISSING_HOST_SESSION_ID` |
| 缺可信 authority 參數 | `REFUSED MISSING_TRUSTED_AUTHORITY_INPUT` |

`project_ref` 改由 cwd 決定，不接受呼叫端提供。

### P1-C HostSessionBinding 的 authority

**`host_session_binding` 已從 tool schema 完全移除**——模型連可以填的欄位都沒有。
server 自行從兩個模型碰不到的來源建構：

1. installer 寫進 MCP 註冊的 `.env`（`OMOS_HOST` / `OMOS_RUNTIME_SCOPE_MODE`）
2. SessionStart hook 落地的 session 記錄（新檔 `lib/omos/session_state.rb`，
   以 `realpath(cwd)` 為鍵；SessionStart 的 stdout 只進模型 context，不是可信通道）

三種 fail closed 實測：`MCP_NO_SESSION_RECORD_FOR_CWD`、
`MCP_MISSING_TRUSTED_AUTHORITY_ENV`、`MCP_SESSION_RECORD_HOST_MISMATCH`。
另有一條負例證明**模型硬塞 `host_session_binding` 參數會被忽略**，server 一律
用自己建構的那份。

### P2 移除非官方的 `transport` 欄位

實測 codex 自行回報 `transport: stdio`——那是它推導出來的，不是設定檔欄位。

## 3. Host 端驗證（直接回答「post-write 複驗只是自我一致」）

conformance 新增一項：把假 HOME 交給**實際安裝的 codex CLI** 解析我們寫出的設定。

```
$ codex mcp get omos.personal-memory
omos.personal-memory
  enabled: true
  transport: stdio
  command: …/exe/omos-personal-memory-mcp
  env: OMOS_HOST=*****, OMOS_PERSONAL_MEMORY_STORE=*****, OMOS_RUNTIME_SCOPE_MODE=*****
```

這不再是「我讀得回我寫的」，而是 Host 自己解析成功。

## 4. 證據

| 套組 | 前 | 後 |
|---|---|---|
| `conformance_3a` | 26/26 | **26/26** |
| `conformance_3b` | 23/23 | **26/26** |
| `conformance_3c` | 38/38 | **41/41** |
| `doctor` | 21 OK / 3 WARN / 0 FAIL | **21 OK / 3 WARN / 0 FAIL** |
| 全庫 Ruby validator | 39/39 | **39/39** |

`git diff --check` clean。conformance 的 Host fixture 也一併改成原生三層形狀——
原本測試與產品用同一套錯誤 schema 形成自我一致，這是 reviewer 指出的根因。

## 5. 仍為 WARN 的三項（誠實保留）

- `codex_session_start_hook_present` / `claude_code_session_start_hook_present`：
  形狀已對齊官方 schema，MCP 註冊那側也由真 codex CLI 確認，**但這個 hook 尚未
  由真 Host 實際觸發過**。「寫得對」與「真的會被叫起來」還差一次真人實測。
- `codex_no_shadow`：Codex 的 `[projects."<path>"]` 只帶 `trust_level`，
  無可觀測的專案層 MCP 覆寫來源。

## 6. 未收治（維持原 packet 的揭露）

- 產品尚未可獨立安裝（spec 與共用 evaluator 路徑仍指向 repo 內）。
- **主卡 DoD 的「兩個 Host 都有真人實測」仍未完成**，因此本片仍不足以進 SSP-295。
- §7 流程偏差依裁決不回退 main；本輪已改在 repair branch 上進行。

## 7. 請 review 針對這些下手

1. 三層形狀與 command 辨識是否符合兩個 Host 的官方 schema（我以 binary 型別
   定義與 CLI 實測為憑，但 Claude Code 側只有文件依據）。
2. P1-C 的 authority 鏈（installer env + hook 落地記錄 + realpath(cwd) 為鍵）
   是否還有模型可介入的縫隙。
3. `SessionState` 以 cwd 為鍵的假設——同一 cwd 同時只有一個 Host session——
   在真實使用下是否成立。
