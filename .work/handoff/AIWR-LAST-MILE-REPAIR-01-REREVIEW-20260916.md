# AIWR 最後一哩 repair-01 — 定點 re-review 交付包

同一條 review line。只收 `3d3b53c` 的 P1×2 + P2×1。

## 鎖定

```
base                654313b
original_review     3d3b53c   （NO_GO，P1=2，P2=1）
repair_commit       <見對話中的派工區塊>
branch              cc/aiwr-last-mile
```

定點 diff：`git diff 3d3b53c..<repair_commit>`

## 逐筆收法

### F-01（P1）：身分收窄，fail-closed

新增 `TASK_CARD_URN = /\Aurn:omos:task-card:.+\z/`。有宣告但不是
task-card URN 時**整批拒絕**：印出錯誤的值、`exit 3`、不產出任何檔案。
不採「靜默略過」——那會讓錯誤設定被誤認成「只是沒宣告」，一直不被發現。

你用的那個值（`urn:omos:evidence:not-a-task-card`）已固定成負例。

### F-02（P1）：`event_key` 消除歧義

改用 `JSON.generate([session_id, native_correlation_ref, event])`，即你
建議的無歧義 tuple encoding。仍為決定性、不含時間戳，符合 FP-3-A。

你給的碰撞案例 `("a:b","c")` vs `("a","b:c")` 已固定成負例。

### F-03（P2）：新增常設 regression gate

新增 `scripts/validate_aiwr_capture_batch_builder.rb`（182 行），現在是
第 25 支 Ruby validator。依你指示**沒有動 SSP-301 本體**。

它不重寫 capture 規則：`hook_capture_failure`（連同
`replay_transition_failure`／`urn?`／相依常數）以機械抽取的方式綁定
`validate_ai_work_record_hook_contract.rb` 原始碼，抽不到就 fail loud
——上游結構變動時這個 gate 會紅，不會兩份實作各說各話。
builder 也加了 `if __FILE__ == $PROGRAM_NAME`，被 require 時無副作用。

## 請重播

```bash
ruby scripts/validate_aiwr_capture_batch_builder.rb   # 應 PASS

# enforcement parity：把任一 bug 放回去，gate 必須紅
#   1. event_key 改回 [..].join(":")           → 應 FAIL（碰撞、去重成一筆）
#   2. 拿掉 mis_declared 的 TASK_CARD_URN 檢查  → 應 FAIL（非 task-card 未被拒）
```

我的結果（cp 備份／還原，非 `git checkout`，還原後 `diff` 逐位元相同）：

```
join(":")                → FAIL ...實際 ["a:b:c:start", "a:b:c:start"]
                            FAIL ...不得被去重成一筆，實際 ["start"]
拿掉 TASK_CARD_URN 檢查   → FAIL ...必須被 fail-closed 拒絕，實際 nil
```

## Gate

```
ruby scripts/validate_*.rb（25 支，含新增這支）  → PASS
四支 Python schema engine                        → PASS
git diff --check                                  → clean
兩支腳本                                           → 134 / 182 行（< 400）
真人 pilot log                                     → 仍 2 筆，未受測試污染
```

## 順帶修正（非 finding，主動揭露）

卡片「已知限制」原本寫著「batch 驗證不在常設 gate 內」，被 repair-01 推翻
後我一併改掉了。這正是上一條 review line（native adapters）被 NO_GO 的同
一類問題——舊敘述沒跟著新狀態走——所以這次主動先查再送。

## 請只判斷

這三筆是否已關閉，不擴大範圍。真人帶 `OMOS_TASK_REF` 的實跑仍是下一步，
不在本卡。
