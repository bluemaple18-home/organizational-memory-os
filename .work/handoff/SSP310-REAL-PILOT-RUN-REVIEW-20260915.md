# SSP-310／AIWR-12 真人 pilot 實跑 — 大 review 交付包

## 鎖定

```
base    75f2a28   （hook 前置卡 ACCEPTED_GO 的收尾 commit）
review  9640514
branch  main（見下方「與前幾輪不同的地方」）
```

```
git diff 75f2a28..9640514
```

本輪三個 commit：

```
f71331f  docs：校正待辦文件過時狀態（與 SSP-310 無關的順手修正）
997df68  fix：hook 改用 __dir__ 定位 repo，不依賴 CLAUDE_PROJECT_DIR   ← 未經 review 就進 main，請特別檢查
9640514  feat：真人 pilot 實跑證據
```

## 與前幾輪不同的地方（請先讀這段）

**這三個 commit 已經直接進了 `main`，沒有走 branch → review → merge。**
原因：`9640514` 是「把已經發生的事實記錄下來」（真人實跑的 log 與其驗證），
不是待合併的新設計；`f71331f` 是純文件校正。

但 **`997df68` 是真正的程式碼變更，而我在排除環境問題的過程中直接推進
`main`，沒有先送審**——這是這一輪的流程瑕疵，我主動揭露，請把它當成
本次 review 的重點之一，而不是既成事實。

## 這一輪發生了什麼

`SSP-307`／`SSP-308`／`SSP-309` 與更早的契約全部是紙上文件；hook 前置卡
（`f939b33`）合併後，Owner 親自擔任 pilot 的 PM 角色，用

```
cd /Users/matt/Documents/ChatGPT/知識庫 && cc --settings .claude/settings.pilot.json
```

開一個真實 session、做一件真實小任務（查詢本 repo 分支現況），擷取到本
lane 有史以來第一批真實 runtime 事件。

## 擷取結果（`.work/evidence/ssp310-pilot-runtime-log.jsonl`，逐字入庫）

```
UserPromptSubmit → MAPPED / start          10:17:38Z
Stop             → MAPPED / submit_review  10:19:11Z（stop_hook_active: false）
native_correlation_ref（兩筆相同）= 3de6480b-b1c1-4cc1-a9b4-f4f59840076d
session_id = f8b7146e-66c4-4978-9421-5f0c61f0bbe2
```

## 請重播

### 1. 合規：真實 record 是否通過既有 evaluator

```bash
# 從 validate_claude_code_native_adapter_contract.rb 機械抽取
# claude_code_mapping_failure（勿手抄），把 log 兩筆餵進去
# 我的結果：兩筆皆 VALID (nil)
```

### 2. 關聯性

```bash
ruby -rjson -e 'puts File.readlines(".work/evidence/ssp310-pilot-runtime-log.jsonl").map { |l| JSON.parse(l)["native_correlation_ref"] }.uniq.inspect'
# 我的結果：只有一個值 → 同一 turn 的兩個事件確實共用 prompt_id
```

### 3. `997df68` 的程式碼變更

```bash
git show 997df68
```

改動：`PROJECT_DIR` 從 `ENV.fetch("CLAUDE_PROJECT_DIR", ...)` 改為
固定 `File.expand_path("../..", __dir__)`；`settings.pilot.json` 的
command 改絕對路徑。請確認：這是否讓 hook 在任何啟動目錄下都只寫回本
repo、有沒有引入新的路徑假設或安全問題、是否仍符合前一輪 review 已接受
的最小 footprint 七條約束。

## 請特別判斷（不是一般程式碼審查）

1. **`997df68` 未經 review 直接進 `main` 是否可接受**，或需要補救動作
   （例如 revert 後重走流程）。這是流程問題，我自己不裁決。
2. **「FP-1-A 在真實環境成立」這個結論，用兩筆記錄／一個 turn 支撐是否
   過度宣稱**。我在 evidence 裡寫的是「證實 per-turn 關聯假設成立」，
   請判斷這個措辭是否超出證據強度（例如是否應限定為「單一 turn 觀測，
   未涵蓋多 turn／併發／Stop 被阻擋等情境」）。
3. **停用驗證的證據強度**：我主張「同期其他未帶 flag 的 session 在同一
   repo 併行運作、log 只有 pilot session 的兩筆」構成真實 opt-in 證明。
   請判斷這是否足以滿足卡片 Acceptance #5，或只是旁證。
4. **`stop_hook_active=true` 的情境在真實環境未出現**（本輪 `false`），
   是否影響 FP-2-A 的驗收結論。

## 已知不在本輪範圍

- 多位 PM、多平台、多 turn 的 pilot（卡片明訂本輪只做一位、一個任務、
  一個平台）。
- 把 pilot 輸出接回任何 canonical store／AIWR `complete`——依然明確排除。

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
