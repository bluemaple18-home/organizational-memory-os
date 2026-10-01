---
id: WEEKLY-REVIEW-INTERVIEW-20261001
jira: 尚無對應 ticket，需補開一張並回填此欄
status: DONE（2026-10-01；驗收 4 拆出 4b 另卡）
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

---

## 6. 實作結果（2026-10-01）

### 6.1 逐條對驗收

| # | 驗收 | 結果 |
|---|---|---|
| 1 | 有未完成週期才提，沒有就不多嘴 | **PASS**。兩格分開驗：「還沒有任何週期」與「週期存在但都完成了」。只驗前者會因為「根本沒有週期」而假綠（反證 I1b RED） |
| 2 | 注入不含任何知識內容 | **PASS**。檔名／原文／`candidate` ref 都擋掉（反證 I2 RED） |
| 3 | Skill 說得出五個步驟 | **PASS**。`skills/weekly-review/SKILL.md` |
| 4a | 關帳歸屬可辨識 | **PASS**。`history` 的 `committed_by` 分得出 `LOCAL_CLI` 與 `LOCAL_STDIO_MCP` |
| 4b | 機械性禁止 AI 自行關帳 | **未完成，另卡**。見 §6.3 |
| 5 | Skill 不取得新 authority | **PASS**。純 `.md`、無權限宣告、MCP 工具清單未變 |
| 6 | Codex 不支援時照實回報 | **PASS**。`doctor` 新增 `codex_context_injection` WARN |
| 7 | 既有保證不變 | **PASS**。3a 26/26、3b 46/46、3c 484/484、40/40 validators |

### 6.2 觸發用的是既有接縫，沒有新增任何註冊

`lib/omos/entry/session_start.rb` 本來就在送
`hookSpecificOutput.additionalContext`（只說「已綁定此 session」）。本卡只在
有未完成週期時多帶一句：

```
本週（2026-W39）的回顧尚未完成，2 筆待處理；另有 2026-W38 未補。
使用者沒有主動提起時，請先問他要不要現在做這週的回顧。
```

**沒有動 host binding 契約、沒有第三種 host registration。** Skill 放在交付包
的 `skills/` 並加進 `PAYLOAD_ENTRIES`（AI 得在已安裝的路徑讀得到，否則使用者
刪掉解壓資料夾之後 Skill 就不見了）。Skill 的自動安裝／host discovery UX 另卡。

提示是 **best-effort**：store 讀不到、receipt 不存在，一律當成「沒有待辦」，
不讓一個提示把使用者的 session 弄不起來（反證 I3b RED）。

### 6.3 驗收 4 為什麼拆

`personal_memory_closeout` 在 AI 的工具清單裡，收一個完整的 `closeout`
object，呼叫時只檢查有 binding——**沒有任何同意關卡**。產品擋不住。

而「同意旗標」是假的保護：任何 `user_confirmed: true` 都是 AI 自己填的，
與本專案「身分不可自報」直接衝突（EMEM-11b 當初擋掉 Codex 半個月就是這條）。

依「驗收條文不可改寫成現在測得到的那件事」拆成：

- **4a**（本卡完成）：讓它**看得見**。`operation_journal` 本來就記 surface，
  但 `closeouts` 表沒這欄位，所以 history 看不出差別。現在 `history` 讀回
  journal 對上去，多一個 `committed_by`——**不新增欄位、不新增表**。
- **4b**（另卡 `CARD-HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001`，`RESEARCH_ONLY`）：
  研究真正不可由模型偽造的人類授權 seam。本輪**不改 MCP tool surface**。

Skill 裡「AI 不得自行關帳」保留為**行為規則**，並明寫現況是
「**有稽核、沒有機械性禁止**」——文件不得宣稱產品會阻止（反證有測試守）。

### 6.4 Codex 的實測結論

翻 codex-cli binary 確認：

- `additionalContext`（30 處）、`hookSpecificOutput`（8 處）、`hookEventName`
  （14 處）都在，hook 設定有 `additionalContextLimit` 欄位 → **Codex 確實消費
  這個欄位**。
- **0.153.2 與 0.158.0 都有**（`additionalContext=30`），所以不需要升級 Codex。
- 但 binary 同時有 `this event cannot emit additionalContext` 的錯誤路徑，
  代表有事件白名單，而**靜態字串看不出 SessionStart 在不在裡面**；產品也無法
  從外部觀測模型到底收到了沒。

所以 `doctor` 回 WARN 並指出 fallback（「做這週的回顧」主動開口），
**不因為「欄位存在」就宣稱注入成功**。既有的 WARN 封閉清單一併更新，
附上為什麼這一項只能是 WARN。

### 6.5 過程中修掉的兩個假綠與一次污染

- **I1**：「沒待辦不多嘴」原本可能只是因為 expected_periods 是空的而通過。
  補「週期存在且都完成」那一格才算數。
- **I5**：`File.file?(store)` 的早退看起來是多餘的防禦。實測發現
  `Runtime.open` 對不存在的路徑**會建出一個 45 KB 的空 db**——沒有這個早退，
  還沒安裝的人每開一次 session 就多一個資料庫。補測試釘住（I5c RED）。
- **污染**：`Support.run_session_start` 原本沒有 `home:` 參數，而 hook 會用
  `File.expand_path("~/.omos/…")` 讀 receipt 與 store——那是 process 級別的
  路徑，參數攔不住。結果在 Owner 真實家目錄建出了 `~/.omos`（45 KB 空 store
  ＋ 25 筆 journal，無 receipt、無知識資料）。已經 Owner 同意後刪除，
  並把 `home:` 改成**必填**，五個舊呼叫點全部補上沙箱 home——忘了傳會在呼叫
  當下就炸，不會安靜跑到別人家目錄。
