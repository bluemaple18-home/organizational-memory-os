---
id: EMEM11B-CODEX-CROSS-HOST-UNBLOCK-20260929
status: ACCEPTED_GO
date: 2026-09-29
card: CARD-EMEM11B-CODEX-CROSS-HOST-20260920
---

# EMEM-11b｜Codex identity channel 重測與解封證據

👉 [假設與目標確認]
- 目標：重測 2026-09-20 的 Codex blocker，只有證據顯示 identity channel 成立才改產品。
- 邊界：probe 使用隔離 `CODEX_HOME`／`/private/tmp`，未修改使用者正式 Codex 設定。
- 驗收：MCP server 能取得模型不可自報的 native session identity；Codex／Claude Code 雙向 same-store；既有治理／安裝／rollback 全回歸。

## 根因更正

2026-09-20 的 probe 結論「SessionStart mcp_tool 沒有 `tools/call`，所以沒有可信 identity channel」不完整。2026-09-29 重跑時先用 `hooks/list` 檢查，發現 user hook 具有 trust gate：未 trusted 時 handler 不會執行。把同一組隔離 hook 標成 trusted 後，0.153.2 與 0.158.0-alpha.2.1 都會真的送出 `tools/call`。

因此 blocker 的根因不是 Codex 缺功能，而是舊 probe 沒控制 hook trust 狀態。

## 真 Host probe

實測 binary：

- `/Users/matt/.local/bin/codex` → `codex-cli 0.153.2`
- `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` → `codex-cli 0.158.0-alpha.2.1`
- 補充：當時 PATH 的 `/usr/local/bin/codex` 為 `0.148.0-alpha.9`，所以後續證據必須同時記 binary path + version。

兩版共同觀察：

1. MCP process 的 `CODEX_* / SESSION_* / MCP_*` env 仍為空集合。
2. trusted SessionStart command hook 收到 Host 原生 `session_id`。
3. 同一次 trusted SessionStart mcp_tool 真的送 `tools/call`。
4. `tools/call.params._meta.threadId` 與 command hook 的 `session_id` 完全相同。
5. `_meta.threadId` 位於 tool arguments 外，由 Host 注入；產品不接受 caller 以 argument 自報 session id。

0.158.0-alpha.2.1：

```text
command session_id = 01a0ec30-9e13-7c41-8bbc-25f40feeab66
mcp _meta.threadId = 01a0ec30-9e13-7c41-8bbc-25f40feeab66
```

0.153.2：

```text
command session_id = 01a0ec31-bb32-7de2-acd4-fe40033ff1f1
mcp _meta.threadId = 01a0ec31-bb32-7de2-acd4-fe40033ff1f1
```

受控環境無法連到 OpenAI sampling endpoint，所以 `codex exec` 在 hook 之後的模型取樣失敗；但兩個 SessionStart handler 都已由真 Codex Host 在 startup 階段實際觸發，這不影響本次 identity-channel 判定。

## 採用的最小改動

- `native_session_id_source.Codex`：`UNAVAILABLE` → `MCP_REQUEST_META(threadId)`。
- Codex 重新加入 `supported_hosts_v1`；`blocked_hosts_v1` 目前為空。
- SessionStart command handler 先寫 `(host, session_id, cwd)` SessionState。
- 同 group 新增 `mcp_tool` handler `personal_memory_bind_session`；server 只讀 Host request `_meta.threadId`，再以 `(host, threadId)` 讀同一筆 SessionState 建 binding。
- bind 前、缺 metadata、threadId 找不到 state 均 fail closed。
- Claude Code 的既有 `CLAUDE_CODE_SESSION_ID` PROCESS_ENV 路徑不變。
- doctor 新增 Codex bind-handler presence 與 hook trust 檢查；untrusted／無法觀測為明確 WARN，不再誤判 upstream blocker。

## 驗收

- `3a conformance`: **26/26 PASS**
- `3b conformance`: **43/43 PASS**
  - bind 前 `MCP_HOST_BIND_REQUIRED`
  - 缺 `_meta.threadId` → `MCP_REQUEST_THREAD_ID_MISSING`
  - threadId 無 session state → `MCP_NO_SESSION_RECORD`
  - 正確 Host `_meta.threadId` → `BOUND`
  - Codex → Claude Code same-store：PASS
  - Claude Code → Codex same-store：PASS
- `3c conformance`: **436/436 PASS**
  - 預設雙 Host install／upgrade／uninstall、原子 rollback、standalone package、doctor 全通過。
- `scripts/validate_*.rb`: **40/40 PASS**
- `git diff --check`: clean。

## EMEM-11b acceptance mapping

1. Codex → Claude Code same-store：**PASS**（3b 明確斷言）。
2. Claude Code → Codex same-store：**PASS**（3b 明確斷言）。
3. Codex SessionStart 由真 Host 實際觸發：**PASS**（0.153.2 + 0.158.0-alpha.2.1 trusted probe）。
4. `codex_no_shadow`：Codex project scope 目前只有 `trust_level`，沒有可觀測的 project-level MCP override source，因此維持 **WARN / not observable**；doctor 明確回報，沒有宣稱已掃描。這符合本卡「或說明為何不可能」的驗收條文。

## 結論

**ACCEPTED_GO。** `BLOCKED_UPSTREAM_IDENTITY_CHANNEL` 對 Codex 的適用已撤銷。舊 2026-09-20 handoff／scope freeze 保留為歷史證據，但不得再拿來描述目前支援狀態。
