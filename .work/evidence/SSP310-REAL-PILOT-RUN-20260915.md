# SSP-310／AIWR-12 — 真人 pilot 實跑證據

日期：2026-09-15　執行者：Owner（matt，擔任本次 pilot 的 PM 角色）
平台：Claude Code v2.1.272　任務：一件真實的小任務（查詢本 repo 的分支現況）

這是本條 lane（`SSP-298`～`SSP-310`）**第一次有真實 runtime 事件被擷取**。
在此之前全部是契約與 validator，沒有任何程式真的跑在任何人的機器上。

## 啟動方式（opt-in，未動任何預設設定）

```
cd /Users/matt/Documents/ChatGPT/知識庫 && cc --settings .claude/settings.pilot.json
```

`cc` 是 Owner `~/.zshrc` 裡既有的啟動函式。`--settings` 是明示帶入，
不加就完全不生效。

## 擷取到的原始記錄

`.work/evidence/ssp310-pilot-runtime-log.jsonl`（本輪兩筆，逐字保留）：

```
UserPromptSubmit → MAPPED / start          10:17:38Z
Stop             → MAPPED / submit_review  10:19:11Z
```

`session_id` = `f8b7146e-66c4-4978-9421-5f0c61f0bbe2`
`native_correlation_ref` = `3de6480b-b1c1-4cc1-a9b4-f4f59840076d`（兩筆相同）

## 驗證

### 1. 合規：餵回既有 evaluator

用機械抽取（非手抄）的
`validate_claude_code_native_adapter_contract.rb` 的
`claude_code_mapping_failure`，把兩筆真實 record 餵進去：

```
record 0: UserPromptSubmit/start   -> VALID (nil)
record 1: Stop/submit_review       -> VALID (nil)
```

### 2. FP-1-A 的核心假設在真實環境成立

兩筆事件的 `native_correlation_ref` **完全相同**（`unique count = 1`），
確認 `prompt_id` 真的能把同一個 turn 的 `UserPromptSubmit` 與 `Stop`
綁在一起——這正是 `SSP-307`／`SSP-308` 兩輪被判「per-turn cadence 不
安全」的根因，也是 Owner 簽 FP-1-A 時所依據的假設。**現在有真實資料
支持，不再只是文件推論。**

### 3. 轉移序列合法

`start → submit_review` 對應 `ai-task-card-record.yaml` 的
`lifecycle_event_to_status`：`OPEN → IN_REVIEW`，在
`allowed_status_transitions` 裡是合法邊。同一個
`native_correlation_ref` 底下 `start` 與 `submit_review` 各只出現一次，
沒有重複終態。

### 4. FP-2-A 分支未誤觸

`Stop` 的 `stop_hook_active` 為 `false`（真實終態），正確 MAPPED。本輪
沒有觸發 Stop hook 阻擋，所以 `true` 的情境未在真實環境出現——該情境
的拒絕行為已在負例與 dry-run 覆蓋。

### 5. 停用／回退驗證（Acceptance #5）

`debug log` 為空——本輪沒有任何跳過或錯誤。

更強的證據：在同一段時間內，這台機器上**還有其他 Claude Code session
正在同一個 repo 運作**（包含 Owner 與 CC 進行本卡工作的那個 session），
它們都**不是**用 `--settings .claude/settings.pilot.json` 啟動的，而
log 檔自始至終只有 pilot session 那一個 `session_id` 的兩筆記錄。這在
真實併行條件下證明了 hook 確實只對明示啟用的 session 生效，其餘 session
完全不受影響——停用等同「不加那個 flag」，沒有殘留狀態、沒有背景
process、不需要任何回退動作。

## 過程中發現的環境問題（與本設計無關，已解決）

從 `~/Documents` 底下啟動 Claude Code 會失敗，錯誤訊息宣稱
「possibly due to low max file descriptors」，實際原因是 macOS 的隱私權
保護（TCC）擋住「終端機」讀取「文件」資料夾，回報為
`EPERM: operation not permitted`。給終端機「完全取用磁碟」權限後解決。
這與本 hook、本契約完全無關，但記錄下來，避免下次有人重蹈。

另外本輪順手把 hook 改為用自身檔案位置定位 repo（`__dir__` 往上兩層），
不再依賴 `CLAUDE_PROJECT_DIR`——這樣從任何目錄啟動 session，記錄都會
正確寫回本 repo（commit `997df68`）。
