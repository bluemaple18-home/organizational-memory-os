# AIWR 最後一哩 closeout repair-01 — evidence

回應 `3d3b53c` 大 review NO_GO（P1×2 + P2×1）。三筆全收。

## F-01（P1）：`task_ref` 只驗泛型 OMOS URN

屬實。`hook_capture_failure` 只驗 `urn:omos:<kind>:<rest>` 這個泛型格式，
所以 `urn:omos:evidence:...` 之類的別種 entity 會被當成 task card 收下去，
而我這一層——**正是把 `declared_task_ref` 轉成 Hook envelope `task_ref` 的
那一層**——沒有把身分收窄。分層概念成立不代表邊界有被鎖住，reviewer 指得
準確。

修法：新增 `TASK_CARD_URN = /\Aurn:omos:task-card:.+\z/`。有宣告但不是
task-card URN 時**整批拒絕**（印出錯誤的值、`exit 3`、不產出任何檔案），
不靜默略過——靜默略過會讓人誤以為只是「沒宣告」，錯誤設定會一直不被發現。

## F-02（P1）：`event_key` 會把不同 turn 誤併

屬實，而且我在上一輪 Acceptance #4 直接宣稱「不同 turn 不會誤併」，卻用了
`[a, b, c].join(":")` 這種會碰撞的編碼：`("a:b","c")` 與 `("a","b:c")` 都
得到 `a:b:c:start`。

修法：改用 `JSON.generate([session_id, native_correlation_ref, event])`，
分隔語意由 JSON 的引號與跳脫負責，含 `:` 的值不再造成歧義。仍然是決定性
的、不含時間戳，符合 FP-3-A。

## F-03（P2）：builder 沒有常設 regression gate

屬實——上面兩個錯誤被 24 支既有 validator 全數放行，證明這不是理論缺口。

修法：新增 `scripts/validate_aiwr_capture_batch_builder.rb`（182 行），
進入常設 gate（現在共 25 支 Ruby validator）。依 reviewer 指示**沒有動
SSP-301 本體**。

關鍵設計：**不重寫一份 capture 規則**。驗證用的 `hook_capture_failure`
（連同 `replay_transition_failure`／`urn?`／相依常數）以機械抽取的方式綁定
`validate_ai_work_record_hook_contract.rb` 的原始碼，抽不到就 fail loud
——上游結構若變動，這個 gate 會紅，而不是兩份實作各說各話。builder 也加了
`if __FILE__ == $PROGRAM_NAME` 保護，被 require 時不產生副作用。

涵蓋案例：
- 正例：兩個 turn ＋ 重放 ＋ 另一張卡 ＋ 一筆未宣告 → 2 個 batch、
  raw 5 去重成 4、每個 batch 的 `task_ref` 唯一、皆通過
  `hook_capture_failure`。
- 負例 1（F-01）：`urn:omos:evidence:not-a-task-card` → 必須非 0 拒絕。
- 負例 2（F-02）：`("a:b","c")` 與 `("a","b:c")` → 必須產生不同
  `event_key`、不得去重成一筆。

## Enforcement parity（cp 備份／還原，非 git checkout）

逐一把兩個 bug 放回去，確認新 gate 真的會紅：

```
event_key 改回 join(":")      → FAIL ...實際 ["a:b:c:start", "a:b:c:start"]
                                 FAIL ...兩個不同 turn 不得被去重成一筆，實際 ["start"]
拿掉 TASK_CARD_URN 檢查        → FAIL ...非 task-card URN 必須被 fail-closed 拒絕，實際 nil
```

還原後 `diff` 確認與備份逐位元相同，gate 回到 PASS。

## Gate

```
ruby scripts/validate_*.rb（25 支，含新增這支）  → PASS
四支 Python schema engine                        → PASS
git diff --check                                  → clean
build_aiwr_capture_batch.rb                       → 134 行（< 400）
validate_aiwr_capture_batch_builder.rb            → 182 行（< 400）
真人 pilot log                                     → 仍 2 筆，未受測試污染
```

## reviewer 已收的兩點（未改動）

- 未宣告 `OMOS_TASK_REF` 時「照記 mapping_run、不進 batch」符合 FP-1-A。
- happy path 行為維持不變（reviewer 已獨立重播確認）。
