---
id: PERSONAL-INBOX-ACCEPTANCE-8-RERUN-20260922
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
contract: CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922（OWNER_SIGNED 第二版）
implementation: CARD-LAUNCHD-LIFECYCLE-IMPLEMENTATION-20260922（ACCEPTED_GO @ 6aec59e）
type: evidence
verdict: PASS
authorized_by: Owner「跑」2026-09-22（新授權；首次授權不沿用）
---

# 驗收 8｜真 launchd 實證（重跑）— **PASS**

前一次（同日）FAIL，根因是 `launchctl bootout` 非同步；契約補 §1.0 bounded
convergence 並由 Owner 重新簽署後實作，本次重跑。

產品安裝留在隔離目錄，只有 `launchctl` 用真實 session（`gui/501`）——比授權
範圍更小，未動 `~/.claude`。

## 實跑結果

| 步驟 | 結果 |
|---|---|
| 0 前置 | `ABSENT` ✓ |
| 1 `schedule install` | `SCHEDULE_INSTALLED`、`已載入: 是`、rc=0 ✓ |
| 2 `launchctl print` | **`PRESENT`** ✓ |
| 3 `schedule status` | 已安裝且已載入、anchor 週五 16:00、period `2026-W38` ✓ |
| 4 `schedule remove` | **`SCHEDULE_REMOVED`**、rc=0 ✓ |
| 5 `launchctl print` | **`ABSENT`** ✓ |
| 6 plist 檔案 | 已移除 ✓ |

## 與前一次的差別

前一次第 4 步失敗：

```text
SCHEDULE_BOOTOUT_FAILED: launchctl bootout 回報成功（exit=0），
但 gui/501/… 仍在載入中
```

原因是複查是**瞬時**的，而 `bootout` 的效果是 eventual。本次第 4 步直接
`SCHEDULE_REMOVED`——有界收斂在真實 launchd 上生效，**這是替身測不出來的那一格**。

## 收尾

```text
launchctl print gui/501/com.omos.personal-memory.weekly-review → ABSENT ✓
~/Library/LaunchAgents → 無 omos 檔案 ✓
~/.claude → 未被本次動過（產品安裝在隔離目錄）
```
