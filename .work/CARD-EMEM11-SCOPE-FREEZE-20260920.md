---
id: EMEM11-SCOPE-FREEZE-20260920
status: OWNER_SIGNED
signed_at: 2026-09-20
signature: FP-1 A / FP-2 C / FP-3 A
type: scope_freeze
tier: T3
implements_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
jira: SSP-295_FULL_PRODUCT_PILOT 前置
---

# EMEM-11 切片 3 — Owner 範圍裁決（Codex host 能力與契約衝突）

👉 [假設與目標確認]
- 目標：repair-02 的 correctness 已由 reviewer 定點 GO（P0=0 / P1=0 / P2=0）。
  剩下的唯一 P1 是**產品範圍矛盾**，那不是 CC 能自己收的，做成可以用字母
  簽掉的選項交給 Owner。
- 邊界：本文件**只做範圍裁決**，不改任何契約、不改主卡、不再補 session
  workaround。reviewer 已明確指示停止 repair 線。
- 驗收：Owner 簽三個字母（FP-1／FP-2／FP-3）。

## 已鎖定的事實（不是推測，有 session evidence）

1. **Codex 沒有可信的 native session identity 管道。** codex-cli 0.153.2 端到端
   實測：MCP server 為 per-session 單一進程，但該進程可見的 `CODEX_*` /
   `SESSION_*` / `MCP_*` 環境變數為空集合；整個 session 期間只收到
   `initialize`、`notifications/initialized`、`tools/list`，**沒有任何
   `tools/call`**，`mcp_tool` 型 SessionStart hook 並未叫到它。
2. **因此 Codex 的 Personal Memory read／write／closeout 三個 tool 結構性永遠
   回 `MCP_NATIVE_SESSION_ID_UNAVAILABLE`**（fail closed，不退回 cwd 或任何
   代理鍵猜測）。這在 conformance_3b 已有明確斷言，是設計結果、不是 bug。
3. **Claude Code 這一側是通的**：`CLAUDE_CODE_SESSION_ID`（PROCESS_ENV）本機
   實測存在，hook 與 MCP server 同為其子行程，read／write／closeout 全部可用。

## 因此產生的三處白紙黑字衝突

| # | 位置 | 現行條文 | 與事實的衝突 |
|---|---|---|---|
| 1 | `規格/v0.1/personal-harness-integration.yaml:2102` | `supported_hosts_v1: [Codex, Claude Code]` | 其中一個 Host 的能力永遠拒絕 |
| 2 | 主卡「Cross-host acceptance」第 1、2 項 | 「Codex → Claude Code 使用同一 Local Personal Store」「反向同理」 | 這兩條目前無法實測 |
| 3 | 主卡「驗收組 C 跨 Host 與跨專案」＋ §7 `why_not_less` | 「Codex 寫入 → Claude Code 從同一 Store 讀回，反向亦然」「兩個 Host 真人實測」 | conformance_3c 已改成「同 Host 兩個並行 session」，與條文不符 |

**reviewer 立場**：建議 A1（收斂 v1 為 Claude Code，Codex 標
`BLOCKED_UPSTREAM_IDENTITY_CHANNEL`）；明確**不接受** A2（「註冊得到但永遠
不能用」仍算支援 Host）。

---

## FP-1：`supported_hosts_v1` 怎麼處理？

- **(A)** 收斂成 `[Claude Code]`；Codex 另列
  `blocked_hosts_v1: [Codex]`＋原因 `BLOCKED_UPSTREAM_IDENTITY_CHANNEL`，
  上游提供可信 session identity 管道後再重新納入。
  **← reviewer 建議，CC 同意**。理由：契約宣告的是「這個版本真的支援什麼」，
  不是「我們想支援什麼」；宣告一個永遠拒絕的 Host，等於把契約降級成願望清單。
- **(B)** 維持 `[Codex, Claude Code]` 不動，把 Codex 的 fail closed 寫成
  known limitation。**reviewer 已明確否決**，列在這裡只為留下選項完整性。
- **(C)** 兩者都不做，整張卡退回 `BLOCKED_AWAITING_UPSTREAM`，等 Codex 上游
  提供 identity 管道再繼續。代價：EMEM-11 無限期停在切片 3，SSP-295 連帶卡住。

## FP-2：主卡 DoD 與驗收組 C 怎麼同步？

（FP-1 選 A 才需要回答；選 B／C 則本題自動維持原條文。）

- **(A)** 把「Cross-host acceptance 第 1、2 項」與「驗收組 C 的跨 Host 條文」
  改寫成 **「同一 Host 兩個並行 session（同 cwd，不同 native session id）共用
  同一 Local Personal Store」**，並把跨 Host same-store 實證移進 Codex 解封後
  的後續卡。§7 `why_not_less` 的「兩個 Host 真人實測」同步改為「Claude Code
  真人實測」。**← CC 建議**。理由：conformance_3c 現況就是這樣，且這組測試
  實際涵蓋的風險（並行 session 不得互相覆蓋 identity）比原本的跨 Host 往返
  更貼近 repair-02 修掉的真實缺陷。
- **(B)** 條文全部保留原樣，額外加一段「Codex 部分 deferred」註記。代價：主卡
  DoD 永遠不會被滿足，這張卡在帳面上永遠 NO_GO。
- **(C)** 拆卡：EMEM-11 只收 Claude Code，另開一張 EMEM-11b 專收 Codex，
  待上游解封才啟動。

## FP-3：SSP-295 的進入條件？

- **(A)** 以收斂後的**單 Host（Claude Code）DoD** 作為進入 SSP-295 的條件；
  Codex 不列為 pilot 前置。**← CC 建議**。理由：pilot 的目的是驗產品閉環，
  單一可用 Host 已足以驗；用一個結構性走不通的 Host 擋 pilot 是拿上游問題
  懲罰自己的進度。
- **(B)** 維持原條件（兩 Host 真人實測才進 SSP-295）。代價：SSP-295 與
  EMEM-11 一起等上游。
- **(C)** SSP-295 照原條件走，但先以 Claude Code 單 Host 跑一次**有限範圍的
  pilot**，不視為正式 SSP-295 進入。

---

## 簽核結果（2026-09-20）

**FP-1 A／FP-2 C／FP-3 A。**

FP-2 Owner 選 C 並**明確否決 CC 建議的 A**，理由值得記下來：

> 「A 最大的問題是把原本的『Cross-host acceptance』直接改名成『同 Host 並行
> session』。後者值得驗……但它**不是 cross-host**。這會把一個原本存在的產品
> 能力需求偷偷換成另一個能力。」

因此正確做法是：EMEM-11 v1 收斂為 Claude Code；Codex 與真正的 cross-host 能力
整條搬到 `CARD-EMEM11B-CODEX-CROSS-HOST-20260920`（BLOCKED，上游觸發，
**現在不排不做**）；EMEM-11 保留已成立的 same-store／parallel-session／
cross-project／retry／restart 驗收，但**改掉會誤導的名字**，不再叫 cross-host。

## 追加裁決：contract evaluator 的 seam（同日）

實作 FP-1 A 時撞到一個原本沒看見的機械後果：
`scripts/lib/personal_memory_host_binding.rb` 的 `scenario_failure` 是單一 gate
chain，`supported_hosts` 檢查排在最頂層，**在所有設定面判定之前**。直接收斂
`supported_hosts_v1` 會讓 Codex 的設定探索／安裝合併評估一併短路——validator
當場 47 FAIL，44 個以 Codex 為 base 的負例（含純設定面的
`HBV1_NEG_CODEX_MCP_SHADOWED_SAME_PAYLOAD`）全部變成 `HBV1_HOST_NOT_SUPPORTED`。
那正是上面 FP-2 要避免的型態：為了讓帳面變綠而把覆蓋換掉。

Owner 裁決 **B：additive seam，不重排已驗收的 evaluator gate**。

- `known_hosts = host_profiles.keys`——認識、能評估設定面的 Host，Codex 仍屬於
  這裡；頂層閘與 `HBV1_HOST_NOT_SUPPORTED` 的語意完全不變。
- `delivered_hosts = supported_hosts_v1`——這一版真的能產出可信
  `HostSessionBinding` 的 Host，只在 bootstrap 最後一關檢查。
- known-but-not-delivered 回新碼 **`HBV1_HOST_BLOCKED_UPSTREAM`**，與
  「根本不認識這個 Host」分得開。新碼已納入雙向 error-contract 與 return-site
  coverage。
- 既有 44 個 fixture 的期望結果**一個都沒有改**（這是選 B 的主要理由）。
