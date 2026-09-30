---
id: WEEKLY-REVIEW-INTERVIEW-20261001
jira: 尚無對應 ticket，需補開一張並回填此欄
status: READY_TO_IMPLEMENT
tier: T1
parent: SSP295-FULL-PRODUCT-PILOT-20260921
---

# 每週回顧改成 AI 訪問

👉 [假設與目標確認]
- **目標**：使用者不用看清單、不用打指令、不用知道 URN。AI 先把這週的東西
  讀完比對完，再帶著結論來找他，只問真正需要人判斷的部分。
- **邊界**：AI 可以**提議**分類，但**不得代替使用者關帳**；不動 launchd
  生命週期；不新增 writer／DB；不碰 promotion（那條路還沒實作）。
- **驗收**：見 §4。

## 1. Owner 的原話與修正

> 「不是就是要用訪問的方式篩選出未釐清的知識」
> 「我沒有要使用者自己看有哪些東西誒」
> 「不是一筆一筆問吧　LLM 要先自行消化」

交付方原本提的方向（讓 `review due` 印檔名與摘要，方便使用者自己判斷）
**是錯的**——那仍然是「使用者讀清單」。本卡取代它。

## 2. Measured gap

實測目前的每週流程：

1. 週五 16:00 launchd 跑 `review due --notify --scheduled-trigger`，
   跳一個 macOS 通知「本週有 N 筆待 review」。**然後就沒了。**
2. **沒有任何東西告訴 AI「該做回顧了」。** 裝進 Host 的只有 MCP server
   與 SessionStart hook，沒有 Skill、沒有工作指引。
3. 使用者要自己 `review due` 看 8 碼編號（看不出是什麼），再手打三串完整
   URN 才關得了帳。實測：`review due` 的輸出無法直接用於 `review done`。

也就是說「一週一次、漏了可以補」這個政策在程式裡成立，在使用者手上不成立。

## 3. 改動

### 3.1 觸發：SessionStart 注入待辦（Owner 選 B）

`lib/omos/entry/session_start.rb` 已經在送 `hookSpecificOutput.additionalContext`
（目前只說「已綁定此 session」）。**沿用這個既有接縫**，在有未完成週期時
多帶一句，例如：

```
本週回顧尚未完成（2026-W40，7 筆待處理；另有 2026-W39 未補）。
```

不新增 hook、不新增 channel。Codex 端若不支援注入，退回 A（使用者主動開口），
並由 doctor 照實回報，不得假裝有。

### 3.2 方法：一份 Skill 定義「訪問」怎麼做

AI 拿到那句話之後要知道做什麼。Skill 的內容是**先消化再開口**：

1. 讀完本期所有待回顧項目的內容；
2. 與既有知識比對，自己得出 `UNCHANGED` / `NEW_EVIDENCE` /
   `MATERIALLY_CHANGED` / `CONTRADICTED`——**這四個是比對結論，機器做**；
3. 分組、找重複、找矛盾，用人話講出這週的樣子；
4. **只問需要人判斷的**：矛盾要不要確認、哪些該標 `NEEDS_ORG_FOLLOWUP`；
5. 使用者點頭後才去下 `review done`。

### 3.3 紅線：AI 不得代替使用者關帳

AI 自己讀完、自己標完、自己關帳的話，週期帳上那個 `v` 就沒有人參與過。
這與本專案「身分不可自報」是同一條原則。**關帳必須有使用者的明確同意**，
哪怕只是一句「可以」。

### 3.4 明確不做

- 不碰 promotion／上傳（合約有定義但未實作，另卡）。
- 不動 launchd 生命週期（已 freeze）。
- 不做 `--all <分類>` 這種一行跳過的捷徑——Owner 明確指出那是在幫人跳過。
- 不改 `review due` 成「給人讀的清單」——那是被取代掉的方向。

## 4. Acceptance

1. 有未完成週期時，SessionStart 的 `additionalContext` 帶得出「哪一期、
   幾筆、另外欠哪幾週」；沒有未完成週期時**不得**多嘴。
2. 注入的內容**不含任何知識內容**（只有週次、筆數），與 receipt 同一條界線。
3. Skill 存在且說得出 §3.2 的五個步驟；AI 照它走得出「先消化再開口」的結果。
4. **AI 不得在沒有使用者明確同意下呼叫 `review done`**；反證：拿掉這條約束
   的版本必須轉紅。
5. `review done` 仍然要求每一筆都有分類（T-3 不變），AI 提議的分類走的是
   同一條路徑，沒有旁門。
6. Codex 若不支援注入，`doctor` 照實回報，不得顯示健康。
7. 既有保證不變：3a／3b／3c 全綠、40 支 validator 全綠、launchd 殘留 0。

## 5. Minimum Sufficient

- **why_not_less**：少了 3.1 就沒人告訴 AI 該做；少了 3.2 AI 不知道怎麼做。
- **why_not_more**：沿用既有 `additionalContext` 接縫，不新增 hook／channel／
  DB；分類與關帳仍走既有 CLI 與 evaluator。
- **do_not_absorb**：不吸收 promotion／上傳、不吸收 host presence detection、
  不吸收 `review done` 的 CLI 化簡（短 id／預設週期那三項另議，且優先度降低
  ——使用者本來就不該打那些指令）。
