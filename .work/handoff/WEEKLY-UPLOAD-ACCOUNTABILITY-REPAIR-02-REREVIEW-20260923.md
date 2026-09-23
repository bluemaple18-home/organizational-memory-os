# 週期帳 repair-02 — 定點 re-review 交付包

## 鎖定

```
base              72d87ec   Freeze C 規格（已 GO，immutable）
original_review   e12ab90   第 1 輪實作（NO_GO P1×3，immutable）
repair_01         44f4f8b   第 1 輪修復（NO_GO P1×1，immutable）
repair_02         d1809c4   本次修復
branch            main
```

定點 diff：`git diff 44f4f8b..d1809c4`

## 這一輪只收 P1-3

你上一輪確認 CLOSED 的三筆（P1-1、P1-2、foreign plist/`own?`）本輪沒有改動，
`git diff 44f4f8b..d1809c4` 不會碰到它們。

## 為什麼不是「把 cadence 補傳給 build_done」

你指出的那一行確實沒傳 cadence。但那是**同一個 blocker 的第 2 次失敗**，
而且修法形狀與上一輪相同——上一輪是「讓 `anchor_opts` 去讀 cadence」，
這一輪如果是「讓 `build_done` 去傳 cadence」，第 3 輪就會是下一個呼叫點。

實際數過：cadence 目前以**兩個散裝 kwarg** 穿過九個呼叫點，
而且**每個呼叫點各自帶預設值**，忘了往下傳不會有任何錯誤：

```
review_queue.rb   period_for · due
review_ledger.rb  expected_periods · period_from_iso_week · history · build_done
cli.rb            anchor_opts · schedule install
schedule.rb       status · notify
```

所以改結構。

## 修法

1. **`period` 自帶 cadence** — `period_for` 的回傳值加上 `anchor_hour` /
   `anchor_weekday`。拿到 period 的人就拿到了 cadence，不需要也不應該再傳一份。
2. **`ReviewQueue.cadence_of(period)`** — 缺欄位時 **raise**，不退回預設。
   靜默退回預設正是兩輪 P1-3 的共同成因。
3. **`ReviewQueue.due_for(runtime, period, surface:)`** — 拿著 period 問 due 的
   唯一入口，**簽名裡沒有 cadence 參數**，結構上沒得傳錯。`build_done` 改用它。
   `due(now:, anchor_hour:, anchor_weekday:)` 保留給「現在是哪一期」那個語意。
4. **機器可驗的防再發** — 測試掃 `lib/**/*.rb`，任何 `ReviewQueue.due(` 呼叫點
   若既沒明示 `anchor_hour:` 也沒有 `**` splat，即判 FAIL 並要求改用 `due_for`。
   這條是給未來的呼叫點用的，不必等下一輪 review 才發現。

## 你要的 E2E regression

`repair-02 已安裝週三 15:00 時 review done 必須被接受（不得 OUT_OF_SCOPE）`：

```
Schedule.install(anchor_hour: 15, anchor_weekday: 3)   ← 寫進 plist
CLI#anchor_opts({home:})            → {anchor_hour: 15, anchor_weekday: 3}
period_from_iso_week("2026-W38", **cadence) → anchor 2026-09-16T15:00（週三）
import candidate at anchor - 1h
build_done(...)                     → 必須成功，且 selected == [candidate]
```

另外斷言：closeout 的兩個 cadence 欄位綁週三 anchor（`2026-09-16` /
`2026-09-16T15:00`）而不是週五，且 payload 仍通過既有 evaluator。

鑑別力：同一個 `--period` 在兩種 cadence 下 anchor 本身就不同——
所以「有沒有成功」不是唯一的判準。

## 反證（8 個全紅）

| | 變異 | 結果 |
|---|---|---|
| S1c | `build_done` 回到 repair-01 的寫法（**你的原始重播**） | RED |
| S2e | `period_for` 不再帶 `anchor_hour` | RED |
| S6c | `period_for` 不再帶 `anchor_weekday` | RED |
| S3 | `cadence_of` 缺欄位時靜默退回預設 | RED |
| S4b | `due_for` 忽略 period 的 cadence | RED |
| S5 | `anchor_opts` 跳過已安裝 cadence（repair-01 的 R4 重跑） | RED |
| S7 | 把 cadence 從 `cli.rb` 的 due 呼叫點拿掉（打掃描器本身） | RED |
| S8 | `period_for` 的 cadence 寫死成預設值（假裝有帶） | RED |

**請注意：S1/S2/S4 第一次跑時是崩潰而不是轉紅。**
裸呼叫 `build_done` 的地方沒有收斂例外，變異一改就讓整支測試中止——
崩潰不是測試結果。已把 T-1/T-2/T-3/T-8 與 repair-01 區塊的裸呼叫全部收成值
（`rescue StandardError` 回錯誤字串、後續斷言 nil-safe），再重跑才算數。
這是測試本身的缺陷，不是產品缺陷，但它會讓反證看起來成立而其實沒有。

## 未收的 P2（仍不擋卡）

- P2-1 `ReviewLedger::TERMINAL_STATUSES` 是 upstream vocabulary 的第二份抄本
- P2-2 `schedule status` 判「採預設」只看 `anchor_hour.nil?`，會隱藏 weekday drift

## 交付方自己跑過

```
3a 26/26  ·  3b 34/34  ·  3c 421/421（repair-02 新增 14 條）
六支 validator 全 PASS  ·  git diff --check 乾淨  ·  launchd 殘留 0
```

體積：產品 +36、測試 +194（其中一部分是把既有裸呼叫改成可收斂的形狀）。

## 要求

只就 P1-3 給 GO 或 NO_GO。
若仍 NO_GO，請特別說明**是不是又是同一個根因換了一個呼叫點**——
若是，下一輪不再 repair，改開 spec-freeze 把 cadence 的傳遞契約一次凍結。
