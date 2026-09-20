---
id: DOCTOR-SESSION-HOOK-EVIDENCE-20260920
status: BACKLOG_NOT_SCHEDULED
severity: P2
type: diagnostic-improvement
origin: .work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md §C-5
related_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
authority: organizational-memory-os
---

# P2｜Doctor 的 SessionStart hook 診斷落後於事實

> **不是 correctness blocker，不擋 SSP-295。** EMEM-11 維持
> `ACCEPTED_GO @ e66707a`（真人驗收 18 OK / 2 WARN / 0 FAIL）。這張卡只是把
> 一個「顯示文字落後於事實」的診斷缺口登記下來，**現在不排、不做**。

## 現況

`Doctor#host_checks` 對 `claude_code_session_start_hook_present` 的判定只有
兩種結果：hook 有沒有**寫進設定檔**。有寫就回 WARN，文字是

> 「已依官方 schema 寫入；尚未由真 Host 實際觸發過」

但 2026-09-20 的真人驗收**已經證明它確實被真 Host 觸發過**
（hook 收到真 stdin、落地 session 記錄、session_id 與 MCP server 所見相同）。
也就是說：doctor 不讀這份 runtime evidence，所以它的文字永遠停在
「尚未觸發過」，驗收成功也不會變。

## 為什麼當初不順手改

Owner 於 2026-09-20 裁決：真人驗收卡**只記錄、不改產品**。理由是順手改
doctor 會把一張已完成的驗收卡重新變成產品開發卡，而且會牽出一組新語意需要
定義（見下）。那些語意不該在驗收當下臨時決定。

## 真要修的話，硬性約束（不得便宜行事）

**禁止**「看到任何 session-state 檔就回 OK」。舊 session 的記錄目前沒有清理
路徑、會一直累積（驗收當天就留下 3 份），這種作法會讓殘留檔把 doctor 騙成
綠燈——那比現在的 WARN 更糟，因為它會**謊報健康**。

判定至少要同時綁三件事：

1. **Host**：記錄的 `host` 必須等於正在診斷的那個 Host。
2. **Native session identity**：必須對應**當前這個** session 的 native
   session id，不是「存在某一份記錄」。這牽涉到 doctor 自己能不能取得當前
   session id——doctor 通常是從一般 shell 跑的，未必在 Host session 內。
   這一點要先想清楚，不然無解。
3. **Freshness**：什麼樣的 `recorded_at` 才算「這次」而不是上週那次。

第 2 點是真正的難處：**doctor 的執行情境與 MCP server 不同**，它不一定看得到
`CLAUDE_CODE_SESSION_ID`。所以可能的結論是「在 Host session 外執行時，這一項
本來就無法觀測」——那樣的話維持 WARN 反而是**誠實**的，只是文字要改成描述
「無法觀測」而不是斷言「尚未觸發過」。

**先做研究再決定實作**：可能的結果之一是「不改判定，只改文字」。那也算收治。

## 關聯的既有缺口（一併考慮，不要各修各的）

`.work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md` §G 還記著：
**session state 檔沒有清理路徑**。這兩件事是同一組語意的兩面——什麼叫「還
活著的 session」。若要修 doctor 的 freshness 判定，會需要先回答這個問題；
反之若做了清理機制，doctor 的判定也會變簡單。建議合併成一張卡處理，不要
分開各做一半。

## 驗收（啟動後才適用）

1. 有當前 session 的有效記錄 → 該項回 OK（或明確說明為何仍不能回 OK）。
2. **只有舊 session 的殘留記錄** → **不得**回 OK。
3. hook 未寫入設定 → 維持 FAIL。
4. 在 Host session 外執行 doctor → 回報「無法觀測」，措辭不得斷言事實。
