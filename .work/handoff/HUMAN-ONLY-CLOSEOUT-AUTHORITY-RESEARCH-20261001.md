# 人類專屬關帳授權 — RESEARCH_ONLY 架構裁決交付包

## 0. 這一輪要你做什麼

**只做架構裁決，不要實作。**

- 不改 MCP tool surface
- 不改 host binding 契約
- 不加任何由模型填寫的 consent flag

請在 §4 的四個方案裡裁決（或提出第五個）。**交付方對 D 有傾向但沒有預設
verdict**，四個方案的分析都完整保留。

## 1. 鎖定

```
主卡       8156050   每週回顧改成 AI 訪問（維持完成，不因本卡重開）
本卡       .work/CARD-HUMAN-ONLY-CLOSEOUT-AUTHORITY-20261001.md
狀態       RESEARCH_ONLY_NEEDS_OWNER_DECISION（T3）
branch     main（**兩個 commit 暫時不 push**，等本輪 review 後再收）
```

主卡的驗收 4 已拆成 4a（完成）／4b（本卡）。**4b 未完成，不得宣稱 AI 已被
機械性禁止關帳。** Skill 內的禁止條款保留為行為規則，並已明寫現況是
「有稽核、沒有機械性禁止」。

## 2. 問題陳述

週期帳上「已完成」的意義是**使用者本人看過並做了判斷**。如果 AI 可以自己
關帳，那個紀錄就聲稱了一件沒發生的事——而 Owner 要靠它判斷「誰這週沒做」。

## 3. 已查證的事實（這是本輪最重要的部分）

### 3.1 `personal_memory_closeout` 沒有同意關卡

`lib/omos/mcp_server.rb` 的 `CloseoutTool` 在 AI 的工具清單裡
（`TOOLS = [ReadTool, WriteTool, CloseoutTool]`），`input_schema` 收一個完整的
`closeout` object，`call` 只檢查 `MCPServer.binding` 非 nil。沒有任何
「使用者同意了嗎」的檢查。

### 3.2 **AI 走 CLI 的話，稽核分不出來**（新發現，會改變 A／B 的評估）

`lib/omos/runtime.rb` 的 `authorize!`：`LOCAL_CLI` surface 要求
`binding.nil?`。也就是 CLI 路徑**完全不需要 MCP binding**。

而 AI 在 Claude Code／Codex 裡**能跑 shell**。實測：

```
$ omos-personal-memory review done --period 2026-W39     # 用 bash 跑，不經 MCP
COMMITTED urn:omos:personal-memory:review-period:2026-W39

2026-W39 NO_PROMOTION  committed_by=["LOCAL_CLI"]
```

**`LOCAL_CLI` ——與使用者自己下指令完全相同。**

所以 4a 的稽核只攔得住「AI 用 MCP 工具」這條路；AI 改用 bash 就隱形了。
交付方在主卡把 4a 描述為「讓它看得見」，**這個說法過強**，實際是
「看得見 MCP 那一條路」。本交付包更正這一點。

### 3.3 真正的 authority boundary 不在 tool surface

因為 AI 與使用者**共用同一個 shell**，任何「CLI 可達」的動作就是「AI 可達」。
把工具從 MCP 清單移除、或發一個 CLI 才能產生的 token，都在同一個信任域裡，
擋不住同一個行為者。

唯一在不同信任域的既有先例是 **Codex binding 的 `_meta.threadId`**：
由 Host 注入、位於 tool arguments 之外、模型沒有欄位可以填。
**那是目前專案裡唯一被證明「模型無法自報」的形狀。**

## 4. 四個方案

### A｜把 `CloseoutTool` 從 AI 的工具清單移除

| | |
|---|---|
| **可執行性** | 高。改 `TOOLS` 一行 |
| **真正的 authority boundary** | **無效**。§3.2：AI 用 bash 跑 CLI 一樣關得掉，而且記成 `LOCAL_CLI`，連稽核都看不出來。**比現況更糟**——移除工具會讓人以為有保護 |
| **要改的 surface** | MCP tool surface |
| **風險** | 假的安全感；AI 無法完成最後一步，使用者得自己貼指令，與「使用者什麼都不用打」衝突 |
| **驗證方式** | 反證必須證明「AI 用 bash 仍可關帳」。若反證做不出來（例如測試環境沒有 shell），這個方案的評估就不成立 |

### B｜關帳需要一個只有 CLI 能產生的短效 token

| | |
|---|---|
| **可執行性** | 中。要新增 token 產生／驗證路徑 |
| **真正的 authority boundary** | **無效**，理由同 A。AI 能跑產生 token 的那個 CLI，就能拿到 token |
| **要改的 surface** | MCP tool surface ＋ CLI ＋ 新的 token 狀態（可能需要新檔案或新表——`FORBIDDEN_BY_DEFAULT` 禁 new ledger/registry） |
| **風險** | 體積最大、保護最弱。還引入 token 過期／重放／儲存位置等新失敗面 |
| **驗證方式** | 必須先證明存在一個「AI 讀不到、但使用者讀得到」的通道。**交付方找不到這樣的通道**；若 reviewer 知道，這個方案才值得繼續 |

### C｜由 Host 注入「使用者按過確認」的訊號

| | |
|---|---|
| **可執行性** | **目前不可行**。兩個 Host 都沒有提供「人類互動」訊號 |
| **真正的 authority boundary** | **成立**。與 `_meta.threadId` 同一個形狀：Host 注入、模型無欄位可填。這是唯一真正的機械邊界 |
| **要改的 surface** | 等上游提供後才知道；可能是 host binding 契約（本輪明確劃掉） |
| **風險** | **依賴上游，不由本專案推動**。EMEM-11b 為此等了半個月，而且那次的根因還是「舊 probe 沒控制 trust 狀態」而非上游缺功能——所以「等上游」的歷史判斷可靠度不高 |
| **驗證方式** | 先做 probe：兩個 Host 的 hook／MCP 請求裡有沒有任何「這是人類觸發的」欄位。**這個 probe 本輪可以做，而且應該做**，因為它會決定 C 是不是永久不可行 |

### D｜接受不可機械阻止，改為事後對帳

| | |
|---|---|
| **可執行性** | 高。消費既有的 `committed_by` ＋ SSP-295 pilot observability 的 `P1_CANDIDATE` 規則 |
| **真正的 authority boundary** | **沒有新增邊界**——誠實地不假裝有。改為讓缺乏保護的情況**無法安靜發生** |
| **要改的 surface** | `CARD-SSP295-PILOT-OBSERVABILITY` 的 receipt 欄位（目前不含 `committed_by`）。**不改 tool surface、不改 host binding** |
| **風險** | **§3.2 的洞直接命中這個方案**：AI 用 bash 關帳會記成 `LOCAL_CLI`，對帳看不出來。所以 D 若要成立，得先回答「怎麼分辨 CLI 是人打的還是 AI 打的」 |
| **驗證方式** | 刻意用 MCP 關一期、用 CLI 關一期，斷言 receipt／對帳看得出差別；**以及**刻意用 bash 跑 CLI 關一期，斷言它**看不出來**——把這個限制寫成已知缺口，不得宣稱覆蓋 |

**交付方傾向 D**，理由：它是唯一不假裝有保護的方案，與本專案既有立場
（「journal 是證據不是保護」）一致。**但 §3.2 證明 D 的覆蓋有洞**，
所以傾向 D 不等於 D 已經足夠。

## 5. 交付方認為 reviewer 應該特別看的

1. **§3.2 是不是正確？** 如果 AI 用 bash 關帳真的無法與人區分，那 A 與 B 都
   應該直接排除，而 D 需要補一個「如何分辨 CLI 的真正行為者」的子問題。
2. **C 的 probe 要不要本輪做？** 它會決定 C 是暫時不可行還是永久不可行。
   交付方認為該做，但那超出 `RESEARCH_ONLY` 的邊界，請裁決。
3. **有沒有第五個方案？** 特別是：有沒有辦法讓「人類互動」留下一個 AI 無法
   製造的痕跡（例如 TTY 偵測、鍵盤輸入時序、作業系統層的使用者存在訊號）。
   交付方沒有找到可靠的做法，但沒有窮盡搜尋。

## 6. 明確不做（本輪）

- 不實作任何方案
- 不改 MCP tool surface、不改 host binding 契約
- 不加由模型填寫的 consent flag
- 不把 4b 的條文改寫成 4a 已達成的那件事
- 主卡 `8156050` 維持完成，不因本卡重開

## 7. 現況回歸（供對照，本輪沒有改動產品）

```text
3a 26/26  ·  3b 46/46  ·  3c 484/484  ·  40/40 validators  ·  diff --check clean
launchd 殘留 0  ·  真實 ~/.omos 不存在
交付包 ZIP SHA-256 2e7f883bd905d43cbc9722cb1eb0c22657772dcb1f24970e6b7c4415089c1bab
```
