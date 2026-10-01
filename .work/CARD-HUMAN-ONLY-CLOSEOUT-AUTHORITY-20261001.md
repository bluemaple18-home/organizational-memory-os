---
id: HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001
jira: 尚無對應 ticket，需補開一張並回填此欄
status: RESEARCH_ONLY｜裁決已下（A/B Reject · D=audit fallback · C probe 完成 · E 首選）
tier: T3
parent: WEEKLY-REVIEW-INTERVIEW-20261001
---

# 人類專屬的關帳授權：研究不可由模型偽造的 seam

👉 [假設與目標確認]
- **目標**：找出一個**模型無法自報、無法偽造**的接縫，讓「這週的回顧由本人
  確認過」這件事在機械層面成立。
- **邊界**：本卡 `RESEARCH_ONLY`。**不實作、不改 MCP tool surface、
  不加任何由模型填寫的 consent flag。**
- **出口**：一份選項比較 ＋ 交付方建議，交 Owner 裁決後才另開實作卡。

## 1. 這張卡從哪裡來

`CARD-WEEKLY-REVIEW-INTERVIEW-20261001` 的驗收 4 原文是
「AI 不得在沒有使用者明確同意下呼叫 `review done`」。實作時確認那**做不到**，
於是依「驗收條文不可改寫成現在測得到的那件事」拆成兩半：

- **4a attribution／audit**：已完成。`review history` 的 `committed_by`
  分得出 `LOCAL_CLI`（使用者自己下指令）與 `LOCAL_STDIO_MCP`（AI 經 MCP 提交）。
- **4b mechanical prevention**：**本輪未完成**。本卡承接。

**不得宣稱 AI 已被機械性禁止關帳。** Skill 也照實寫了「有稽核、沒有強制」。

## 2. Measured gap

`lib/omos/mcp_server.rb` 的 `CloseoutTool`（`personal_memory_closeout`）在
AI 的工具清單裡，`input_schema` 收一個完整的 `closeout` object，呼叫時只檢查
有 binding，**沒有任何同意關卡**。所以 AI 可以自己組一份 payload 把該週期
關成 terminal。

為什麼不能用「同意旗標」解決：任何 `user_confirmed: true` 之類的欄位都是
**AI 自己填的**。那與本專案的核心原則（身分不可自報）直接衝突，也與
`EMEM-11b` 當初擋掉 Codex 半個月的理由是同一條——**沒有可信來源的宣稱不是證據**。

## 2.1 新發現：AI 走 CLI 的話稽核分不出來

`runtime.rb` 的 `authorize!` 要求 `LOCAL_CLI` surface 的 `binding` 為 nil——
也就是 CLI 路徑**不需要 MCP binding**。而 AI 在兩個 Host 裡都能跑 shell。

實測：用 bash 跑 `review done` 關帳，`committed_by` 記成 `["LOCAL_CLI"]`，
**與使用者自己下指令完全相同**。

所以 4a 的稽核只攔得住「AI 用 MCP 工具」那一條路。主卡把 4a 描述為
「讓它看得見」**說法過強**，實際是「看得見 MCP 那一條」。這也直接否定了
下面的選項 A 與 B——它們都在同一個信任域裡擋同一個行為者。

詳見 `.work/handoff/HUMAN-ONLY-CLOSEOUT-AUTHORITY-RESEARCH-20261001.md`。

## 3. 待研究的選項（不預先裁決）

| | 做法 | 疑慮 |
|---|---|---|
| A | 把 `CloseoutTool` 從 AI 的工具清單移除；關帳只能走 CLI | AI 無法完成最後一步，使用者得自己貼指令——與「使用者什麼都不用打」衝突 |
| B | 關帳需要一個**只有 CLI 能產生**的短效 token（AI 讀不到產生它的通道） | 要有一個 AI 讀不到的通道；若 AI 能跑 shell，它就能跑那個 CLI → 可能無效 |
| C | 用 Host 注入的接縫（像 Codex binding 的 `_meta.threadId`）承載「使用者按過確認」 | 需要 Host 真的提供「人類互動」訊號；目前兩個 Host 都沒有 |
| D | 接受「不可機械阻止」，改為**事後對帳**：`committed_by=LOCAL_STDIO_MCP` 的關帳在公司端一律標 `P1_CANDIDATE` 待查 | 不阻止，但讓它無法安靜發生。與 SSP-295 pilot observability 同一個形狀 |

**交付方傾向 D**，理由：A 破壞剛做好的 UX；B 在「AI 能跑 shell」的前提下站不住；
C 依賴上游提供目前不存在的訊號（EMEM-11b 等了半個月的教訓）。
D 不假裝有保護，而是讓缺乏保護的情況**可被發現**，與本專案既有的
「journal 是證據不是保護」立場一致。

## 4. 明確不做

- 不加任何由模型填寫的 consent flag。
- 不在研究完成前改 MCP tool surface。
- 不把 4b 的條文改寫成 4a 已經做到的那件事。

## 5. Owner 要裁決的

1. 選 A／B／C／D 或其他。
2. 若選 D，公司端對帳是否納入 `CARD-SSP295-PILOT-OBSERVABILITY` 的
   `P1_CANDIDATE` 規則（那張卡目前的 receipt 欄位不含 `committed_by`）。

---

## 6. Owner 裁決（2026-10-01）

> **A = Reject；B = Reject；D = 保留 audit/fallback（不算 4b）；
> C = 立即做 bounded probe；E = 目前 4b 的首選實作方向。**
>
> §3.2 沒有誤判。
>
> **TTY 偵測、輸入時序、滑鼠／鍵盤事件、frontmost app 都不要採** ——
> 它們只能當 observation，不能當 authority。

主卡 `8156050` 維持完成；本卡保持 `RESEARCH_ONLY`，下一步只補 C probe ＋
E feasibility，**還不要改產品**。

### 6.1 Owner 補的事實更正

本卡 §3 原本寫「兩個 Host 都沒有人類互動訊號」——**過時了**。
兩邊現在都有 `UserPromptSubmit` hook（Codex 給 session_id／turn_id／prompt，
Claude Code 給 session_id／prompt_id／prompt），也都有 MCP 的使用者互動／
elicitation 路徑（Codex app-server 的 `mcpServer/elicitation/request`、
Claude Code 會在 MCP server 要求輸入時開互動 dialog）。

但那**不等於**取得了不可偽造的人類同意——見下面的 probe。

## 7. C 的 bounded probe（本輪完成）

方法：靜態檢查 codex-cli 0.158.0 的 binary 字串，以及本機
`~/.claude/cache/changelog.md`。**沒有改動任何產品碼。**

### 7.1 Q1：UserPromptSubmit 的呼叫有沒有 server 端可驗、模型無法製造的 provenance？

**目前的答案：沒有找到。**

Codex binary 確認存在這些 hook 輸出 wire 型別：

```
PreToolUseHookSpecificOutputWire       PostToolUseHookSpecificOutputWire
SessionStartHookSpecificOutputWire     SubagentStartHookSpecificOutputWire
UserPromptSubmitHookSpecificOutputWire PermissionRequestHookSpecificOutputWire
```

也有 `turn_id`／`turnId`／`codex_turn_source`／`turn_trigger` 這些 turn 層級的
欄位。但這些是**Host 告訴我們「這是哪一個 turn」**，不是「這個 turn 是人類
發起的，而且他同意了這件具體的事」。
`UserPromptSubmit` 會在有 prompt 被送出時觸發——它證明「有東西送了 prompt」，
不證明「人類同意關掉 2026-W39 這一期」。

### 7.2 Q2：MCP elicitation 的 accept，server 能不能分辨真人 UI 與程式化 accept？

**答案：不能。** 這一條有決定性證據。

本機 `~/.claude/cache/changelog.md`：

```
5454: Added new `Elicitation` and `ElicitationResult` hooks to intercept and
      override responses before they're sent back
  42: Fixed {"decision":"block"} returned by Elicitation and ElicitationResult
      hooks being ignored; it now declines the MCP elicitation
```

hook 可以**攔截並覆寫** elicitation 的回應，而 hook 就是設定檔裡的一行指令
——AI 能跑 shell 就能寫、能改。所以 MCP server 收到的 accept 無法分辨來源。

Codex 端也有 `decisionSource` 這個欄位，但它記的是哪一條決策路徑，不是
「人類有沒有真的按下去」；而且同樣在 AI 可觸及的設定域內。

### 7.3 Probe 結論

**C 正式淘汰。** 不是「等上游」，是**上游提供的互動事件本身就可被程式化
回覆**，所以它永遠無法承載不可偽造的人類授權。不要再把 C 列為待觀察。

## 8. E 的 feasibility（本輪初步）

### 8.1 Owner 的方案

在 macOS Secure Enclave 建一把**不可匯出**的 signing key，私鑰設成需要
Touch ID／生物辨識才能使用；每次 closeout 對 `period + dispositions + nonce`
簽章，CLI 與 MCP 兩條路都必須帶同一份簽章才准 terminal closeout。

AI 可以用 bash **叫出**確認視窗，但**產不出合法簽章**——authority boundary
因此真正移出「AI 與人共用的 shell」。

### 8.2 初步查到的事（支持 E 可行）

Codex binary 裡**已經有生物辨識簽章的形狀**：

```
credentialId · signature · algorithm · publicKey · proof
credentialMissing · biometricsUnavailable · providerUnavailable · userCancelled
biometricInfo · biometrics · promptHash
```

旁邊是 `pairingCode`／`manualPairingCode`／`deviceType`／`installationId`，
所以它很可能是用在**裝置配對／remote control 授權**，不是 per-action 同意。

**意義**：E 要的原語在這個平台上是成熟的、而且同類產品已經在用。
不是我們要發明一個新機制。

### 8.3 還沒回答的（下一輪要查）

1. Codex／Claude Code 有沒有把這個簽章能力**暴露給第三方 MCP server**？
   初步看是沒有（它服務於自己的 auth flow），那 E 就需要我們自己的
   native helper。
2. native helper 的體積與 lifecycle：建 key、換機、備份、key 遺失時的復原，
   以及「沒有 Touch ID 的 Mac」怎麼辦（降級到什麼？降級會不會打回原點？）
3. 交付包目前是純 Ruby ＋ vendored gem。加一個 native helper 會動到
   `native-dependencies.json` 與 `runtime-profile.json` 的 qualification，
   以及 Gatekeeper 簽章（現在是靠使用者 `xattr` 解隔離——**一個未簽章的
   native helper 會讓那個問題變嚴重**）。
4. 這是 **macOS-specific**。目前交付範圍就是 macOS，但要寫清楚它讓產品
   更難離開 macOS。

### 8.4 明確不採（Owner 裁決）

TTY 偵測、輸入時序、滑鼠／鍵盤事件、frontmost app。
它們只能當 observation，不能當 authority——AI 都能模擬。

## 9. 下一輪的範圍

仍然 `RESEARCH_ONLY`：補完 §8.3 的四個問題，產出 E 的實作提案
（含體積、lifecycle、降級路徑、對 Gatekeeper 與 qualification 的影響），
**然後才由 Owner 決定要不要開實作卡。**
