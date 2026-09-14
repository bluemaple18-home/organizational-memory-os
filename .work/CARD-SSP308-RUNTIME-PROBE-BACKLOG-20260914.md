---
id: SSP308-RUNTIME-PROBE-BACKLOG-20260914
status: BACKLOG
type: implementation
tier: T1
jira: SSP-308（AIWR-10，後續強化）
origin: "SSP-308 kickoff：Owner 選定本輪不做 runtime probe，先寫靜態分類契約"
---

# SSP-308 Runtime Probe（後續強化）

## 為什麼延後

`claude-code-native-adapter.yaml` 目前的完整性驗證是對照**公開文件**的封閉
hook 事件集合（9 個名稱），不是對照真實觸發過的 session 語料。這對「事件
名稱要不要分類」是足夠的，但對兩件事沒有覆蓋：

1. **真實 payload 形狀**——例如 `SessionEnd` 的 `reason` 欄位實際會出現哪些值
   （clear／logout／exit／other／…），本卡因此無法判斷是否該把某些 reason
   值視為終態。契約裡的 `session_end_note` 明講了這個限制。
2. **文件與實際行為是否一致**——公開文件記載的 9 個 hook 名稱，實際觸發時
   是否真的只有這些、有沒有欄位層級的差異。

## 修法（等有真實觸發環境時）

沿用 `codex-native-adapter.yaml` 的 runtime probe 模式：

1. 實際配置一組 hook（`SessionStart`／`Stop`／`SessionEnd` 至少各一次），
   在真實 Claude Code session 中觸發，取得真實 payload。
2. 只萃取受控欄位（hook 名稱、`reason` 等 discriminator），不擷取任何訊息
   內容、工具輸出、檔案內容——比照 SSP-307 的做法，先問過 Owner 再讀。
3. 凍結成 `claude-code-native-adapter-runtime-sample.json`，比照
   `codex-native-adapter.yaml` 的 `measured_native_vocabulary` 加上
   `codex_runtime_sample_failure`-style 雙向相等 evaluator（記取 SSP307-F-04
   的教訓，從一開始就做雙向比對，不要重演單向漏洞）。
4. 若 `SessionEnd` 的 `reason` 值顯示某些原因確實不可恢復，重新評估是否該
   拆成多個更細的 native_event_type（例如 `SessionEnd.logout` vs
   `SessionEnd.clear`）。

## 不做

不在本卡實際配置或觸發任何 hook；不讀取任何真實 session 內容。
