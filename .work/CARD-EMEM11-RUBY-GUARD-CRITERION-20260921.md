---
id: EMEM11-RUBY-GUARD-CRITERION-20260921
status: CONFIRMED_DEFECT_READY_TO_IMPLEMENT
unblocked_by: CARD-EMEM11-Q7-ACTIVATION-RUNTIME-PROFILE-20260921（2026-09-21 凍結）
severity: TBD（P1／P2 待裁）
type: product-defect
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
discovered_via: .work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md §4
target_shape: Q7 §0.3（runtime profile guard 四項，定義已收緊）
# 與 stale-hook P1 同層，皆為 packaging 實作的前置：
prerequisite_for: PENDING_PACKAGING_IMPLEMENTATION_CARD
peer_prerequisite: CARD-EMEM11-STALE-HOOK-RELOCATION-20260920
found_in: fa0959a
authority: organizational-memory-os
---

# `pinned-ruby.sh` 驗的是版本字串，但真正的前置條件不是版本字串

> **判準已於 2026-09-21 由 Q7 §0.3 凍結，blocker 解除，可實作。**
> 本卡原本等的是「runtime profile 怎麼定」——現已定案，見下方「判準」一節。

## 缺陷

`bin/pinned-ruby.sh` 的判準是 `RUBY_VERSION` 字串等於 `.ruby-version`
（目前 exact `3.4.10`），不符即 `exit 78`。

但 Q6 Part 1 已證明：產品能不能在某個 Ruby 上跑，實際取決於
**編譯進原生擴充的絕對 dylib 路徑是否存在，以及 ABI 目錄是否相同**。

`bigdecimal.bundle`（production 會載入）硬連
`/opt/homebrew/opt/ruby@3.4/lib/libruby.3.4.dylib`；Ruby 的 C extension ABI
目錄在整個 3.4 系列皆為 `3.4.0`。

因此現行 guard **在兩個方向上同時失準**：

| 方向 | 情境 | 現行 guard | 實際 |
|---|---|---|---|
| **過嚴** | Homebrew 升到 3.4.11（opt symlink 重指、dylib 路徑與 ABI 皆不變） | `exit 78` 拒絕 | artifact 其實可用 |
| **過鬆** | rbenv／PATH 上剛好是 3.4.10、但裝在別的路徑 | 放行 | 載入原生擴充時 `LoadError` |

過鬆那一格的失敗方式已實證：把 `bigdecimal.bundle` 的 libruby load command
改寫成不存在的路徑後載入，得到
`LoadError: Library not loaded ... no such file`、exit 非零、訊息明確指出
缺哪個路徑。**失敗是大聲的、不是靜默的**——所以這不是安全性風險，是
**診斷時機錯誤**：本該在 guard 當場擋下並說清楚，卻延後到載入原生擴充才炸。

## 判準（**已裁決**，Q7 §0.3 於 2026-09-21 凍結）

guard 改驗四項，**不得**再由 `RUBY_VERSION == "3.4.10"` 決定：

1. 記錄**實際選中的 Ruby executable**（不是「版本符合就好」）。
2. 對 artifact 宣告的**全部 production native dependencies** 驗 loader
   resolution ——**不只 `bigdecimal`**。
3. 用該 Ruby 對**這一份 artifact 自己的 native extensions** 做**真實 load
   probe**；目前至少涵蓋 `bigdecimal` ＋ `sqlite3`。
4. 比對 **qualified runtime profile**，該 profile 至少綁：

```
artifact build identity
+ OS / architecture
+ Ruby implementation
+ Ruby ABI
+ native linkage / profile
```

**「load probe 成功」≠「qualified」**：前者是「這台機器能跑」，後者是
「我們承諾支援這個組合」。能跑但未 qualified 的組合必須是**明確可辨識的
狀態**，不得靜默放行。

guard 必須 **fail closed 並給明確錯誤**——錯誤訊息要指出實際缺的是什麼
（哪個 native dependency、哪一項 profile 不符），不是只說版本不符。

## 驗收（啟動後才適用）

1. Homebrew patch 升級（3.4.x → 3.4.y，路徑與 ABI 不變）後，產品**仍可用**，
   guard 不得誤拒。
2. 指向一個裝在不同路徑的 Ruby 3.4.10 時，**guard 當場擋下**並說明原因，
   不得放行到載入原生擴充才 `LoadError`。
3. 完全不相容的 Ruby（例如系統 2.6）維持現行行為：當場失敗、不靜默改用別的。
4. 錯誤訊息必須指出**實際缺的是什麼**（路徑／ABI），不是只說版本不符。

## 不在本卡範圍

不決定 packaging 格式、不實作 build pipeline、不處理 stale hook
（`CARD-EMEM11-STALE-HOOK-RELOCATION-20260920`）。
