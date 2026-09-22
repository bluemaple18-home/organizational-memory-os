---
id: LAUNCHD-BOUNDED-CONVERGENCE-REPAIR-01-REREVIEW-20260922
card: CARD-LAUNCHD-LIFECYCLE-IMPLEMENTATION-20260922
contract: CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922（OWNER_SIGNED 第二版）
repair: 01
type: rereview
verdict: GO
reviewed_commit: 6aec59e
---

# bounded convergence repair-01 再 review｜GO

| 級別 | 數量 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |

## 1. 兩筆 P1 關閉

- **SNAPSHOT_OLD**：reviewer 用**不同序列**重播。全程 `observation_error` →
  `SCHEDULE_OLD_STATE_UNOBSERVABLE`，舊 plist **byte-identical**；暫時 error
  後取得明確 `loaded` → 可正常升級（沒有矯枉過正）。
- **5 秒 deadline**：改用 **137ms** 步進（非交付方的 110ms）。
  4.795s target → PASS；**5.069s target → timeout，沒有被接受**。

## 2. 收斂迴圈只有一份

`converge` 是唯一的 polling 迴圈；`converge_to` / `converge_definite` 只是
不同的 acceptance predicate。reviewer **沒有找到第二套 polling 判斷**。

## 3. reviewer 自己的 mutation 重播

- 讓 `converge_definite` 接受 `observation_error` → 重新出現「新版 plist 被
  發布」；
- 恢復舊 deadline 順序 → 5.069s target **又變成成功**。

兩筆都有鑑別力。

## 4. reviewer 側實跑

| 項目 | 結果 |
|---|---|
| 3c | 353/353 PASS |
| `ruby -c` | PASS |
| `git diff --check` | clean |
| worktree | clean |

**`6aec59e` 可以收。下一關只剩 Acceptance 8 真 launchd 重跑；依契約
（驗收 14）需要**新的** Owner 明示授權，前一次的不算。**
