---
id: EMEM11B-CODEX-CROSS-HOST-20260920
status: BLOCKED_UPSTREAM_IDENTITY_CHANNEL
trigger: UPSTREAM_ONLY
jira: NOT_CREATED
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
scope_decision: .work/CARD-EMEM11-SCOPE-FREEZE-20260920.md
type: mvp-product-capability
priority: DEFERRED
authority: organizational-memory-os
---

# EMEM-11b｜Codex Host 與 Cross-host Same-store 驗收

> **這張卡現在不排、不做、不派工。** 它存在的唯一目的，是讓 EMEM-11 v1 收斂時
> 被移出去的能力需求**留下紀錄而不是蒸發**。解除條件由上游觸發（見下），在那
> 之前不得進入任何排程、不得當成「正在進行的工作」。

## 為什麼從 EMEM-11 移出來

EMEM-11 原本的 v1 範圍是 Codex + Claude Code 雙 Host，並要求 cross-host
same-store 實測（Codex 寫 → Claude Code 讀，反向亦然）。切片 3 repair-02 期間
以 codex-cli 0.153.2 端到端實測確認：

1. Codex 的 MCP server 是 per-session 單一進程，但該進程可見的
   `CODEX_*` / `SESSION_*` / `MCP_*` 環境變數為空集合；
2. 整個 session 期間該 server 只收到 `initialize`、`notifications/initialized`
   與 `tools/list`，**沒有任何 `tools/call`**——`mcp_tool` 型 SessionStart hook
   並未叫到它；
3. 因此 MCP server 無法獨立、可信地得知自己屬於哪一個 native session。

沒有可信的 native session identity，就無法建立 `HostSessionBinding`；退回用
cwd、最近一次 session 或 state file 猜測都會讓模型有介入空間，已在 repair-02
一併封死。

Owner 於 2026-09-20 裁決（FP-1 A／FP-2 C／FP-3 A）：v1 收斂為 Claude Code，
Codex 移入 `personal_memory_runtime.blocked_hosts_v1`，原能力需求整條搬到本卡。
**原條文沒有被改寫成別的能力**——「同一 Host 兩個並行 session 共用同一 store」
留在 EMEM-11 並改了名字，因為它本來就不是 cross-host。

## 解除條件（上游觸發，不由本專案推動）

上游（Codex CLI）提供**可由 MCP server 獨立取得、且模型無法自報**的 native
session identity channel。例如：把 session id 放進 MCP server 進程的環境變數、
或提供一條 server 可辨識來源的 hook 呼叫。

解除後才啟動本卡；屆時需要：

1. 把 Codex 從 `blocked_hosts_v1` 移回 `supported_hosts_v1`（host profile 一直
   都在，不需要重建）。
2. 移除 `HBV1_HOST_BLOCKED_UPSTREAM` 對 Codex 的適用，並補上該路徑的負例。
3. 補齊本卡的驗收（見下）。

## 驗收（解除後才適用）

1. Codex → Claude Code 使用同一 Local Personal Store，不做 memory migration。
2. Claude Code → Codex 同理。
3. Codex 端 SessionStart hook 由**真 Host** 實際觸發過（不是只有形狀寫對）。
4. Codex 的 `codex_no_shadow` 從 WARN 收斂成可觀測的判定，或說明為何不可能。

## 現況保留的資產（不要重做）

- `personal_memory_host_binding_v1.host_profiles.Codex`：Codex 的設定形狀、
  MCP 註冊形狀（`codex mcp add` 實測）、三層 hook 結構，全部已實證並保留。
- conformance 3b／3c 仍在跑 Codex 的**設定面**覆蓋（探索、install/uninstall、
  shadow、health），以及「Codex 產不出 binding」的負例。
- 因此本卡解除時要補的是 **binding／cross-host 那一段**，不是整個 Codex 支援。
