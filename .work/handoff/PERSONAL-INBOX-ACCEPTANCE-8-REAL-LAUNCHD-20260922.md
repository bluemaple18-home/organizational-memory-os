---
id: PERSONAL-INBOX-ACCEPTANCE-8-REAL-LAUNCHD-20260922
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
contract: CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922
type: evidence
verdict: FAIL
status: CONTRACT_GAP_FOUND
authorized_by: Owner「跑驗收8」2026-09-22
---

# 驗收 8｜真 launchd 實證 — **FAIL**

Owner 明示授權後於**真實 session**（`gui/501`）執行。產品安裝留在隔離目錄，
只有 `launchctl` 用真實 session——這比授權範圍更小，不動 `~/.claude`。

## 1. 實跑結果

| 步驟 | 結果 |
|---|---|
| 0 前置 | `ABSENT` ✓ |
| 1 `schedule install` | `SCHEDULE_INSTALLED`、`已載入: 是` ✓ |
| 2 `launchctl print` | **`PRESENT`** ✓，`state = running`（`RunAtLoad` 已觸發） |
| 3 `schedule status` | 已安裝且已載入、anchor 週五 16:00、period `2026-W38` ✓ |
| 4 `schedule remove` | **`SCHEDULE_BOOTOUT_FAILED`** ✗ |
| 5 `launchctl print` | `PRESENT`（仍殘留）✗ |
| 6 plist | 保留未刪（guard 正確拒絕製造孤兒 job）✓ |

**這是第一次取得真 launchd 的 bootstrap 成功路徑**——先前 reviewer 在本機
只撞到 `Bootstrap failed: 5: Input/output error`，conformance 全程注入替身。

## 2. 根因：`launchctl bootout` 是**非同步**的

`remove` 的錯誤訊息是：

```text
launchctl bootout 回報成功（exit=0），但 gui/501/…weekly-review 仍在載入中
```

收尾清理時證實了它：再跑一次 `bootout` 回
`Boot-out failed: 3: No such process`——**第一次其實成功了**，job 只是還沒
卸載完；`sleep 1` 之後就查不到了。

所以：

- `bootout_and_verify` 在 `bootout` 後**立刻**複查 `loaded?`，看到 job 還在
  收尾，判成「假成功」象限；
- guard 因此拒絕刪 plist（**這部分是對的**——它正確地不製造孤兒 job）；
- 但 `remove` 於是**在真實環境下永遠無法完成**。

## 3. 這是契約缺口，不是再補一個 if

已簽契約 §1.1／§1.2 的四象限**假設狀態是瞬時的**：每一格都是「exit code ×
當下的 `loaded?`」。真實 launchd 的狀態有**時間維度**——命令回傳與狀態收斂
之間有延遲。

契約沒有定義：

- 複查前要不要等待？等多久？
- 「仍在載入中」與「還沒收斂完」怎麼區分？
- 逾時後算失敗還是繼續等？
- `bootstrap` 那一側是否有對稱的延遲問題？（本次未觀察到，但契約同樣沒說）

**交付方不自行加 `sleep` 或 retry。** 依 Hard Stop 的教訓：連續幾輪修法都
是「再補一次 post-condition 複查」就是同一個根因——在複查外面包一層等待，
形狀相同。這一格應該由契約定義，而不是在呼叫點補。

## 4. 建議

契約補一節「狀態收斂語意」，至少定義：有界等待的上限、輪詢間隔、逾時後的
分類（歸入哪一象限）、以及 `bootstrap`／`bootout` 是否對稱適用。
定義完成後再改實作。

## 5. 收尾

真實 session 已清乾淨：

```text
launchctl print gui/501/com.omos.personal-memory.weekly-review → ABSENT ✓
~/Library/LaunchAgents → 無 omos 檔案 ✓
```

`~/.claude` 未被改動（產品安裝在隔離目錄）。
