---
id: HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001
jira: 尚無對應 ticket，需補開一張並回填此欄
status: RESEARCH_ONLY_NEEDS_OWNER_DECISION
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
