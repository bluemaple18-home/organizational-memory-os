# repo #4 repair-01 — evidence

回應 `12b7c90` 大 review NO_GO（P1×2）。兩筆都收。

兩個 finding 是同一類病：**我加了欄位，但讓 caller 自己宣告，等於沒綁。**

## F-01（P1）：`pre_hold_state` 沒綁到 hold-entry 的事實

屬實。原本只比對 release run 自己填的 `pre_hold_state == to_state`，
caller 想寫什麼就寫什麼，`RETENTION_EXPIRED` 進 hold 後照樣能宣稱
`pre_hold_state=RETAINED` 倒退回去、重置保留期。

修法：**改由記錄下來的歷史當權威**。新增 `retention_history_failure`，
重放一串有序轉移：
- 連續性——每一步的 `from_state` 必須等於上一步的 `to_state`，不得跳階。
- 進 `LEGAL_HOLD` 時記下當時的 `from_state`。
- 離開 `LEGAL_HOLD` 時，`to_state` 必須等於**歷史記錄的那個值**；run 自己
  宣告的 `pre_hold_state` 不算數，兩者衝突以歷史為準。

`pre_hold_state` 保留為單筆 run 的宣告（便宜的 sanity check），但綁定力
來自歷史重放。

## F-02（P1）：FP-4-A 只擋「caller 自己承認 stale」

屬實。省略 `permission_decision_stale` 就能拿到 `nil`——實質語意變成
「你承認 stale 我才擋」。

修法：**綁 STD-01 自己的 access 欄位**。retrieval run 必須帶
`decision_acl_snapshot_ref`（decision 當時的快照）與
`current_acl_snapshot_ref`（現行快照），兩者都要符合 STD-01
`access.acl_snapshot_ref` 的 pattern——**該 pattern 直接從 schema 讀出來，
不手抄**。
- 兩者不同 → decision 必定 stale → 放行即違規
  （`PRD_STALE_ACL_DECISION_HONOURED`）。
- 任一缺失或格式不對 → 無法證明新鮮度 → fail closed
  （`PRD_PERMISSION_FRESHNESS_UNKNOWN`）。未知一律不視為新鮮。

原本的 `permission_decision_stale` 仍會擋，但降級為附加訊號。

## 重播 reviewer 的兩個 exploit

```
案例1（expired 進 hold，release 自稱 pre_hold_state=RETAINED）
  → PRD_HOLD_RELEASE_CONTRADICTS_HISTORY   （修正前：nil）

案例2（省略 permission_decision_stale，access_granted=true）
  → PRD_PERMISSION_FRESHNESS_UNKNOWN       （修正前：nil）
```

## Guard parity 改成逐 return site，不是逐 code

第一次跑完 code 層級的 parity 時，**這輪新增的兩個 code 顯示「未被測到」**
——因為每個 code 有兩個 return 位置，負例只打到其中一個，另一個仍會攔住，
整體看起來仍然紅不起來。這正是 reviewer 指出的同一類空轉問題，只是換個
地方出現。

改成**逐 return site** 探測（第 N 個 `return "<CODE>"` 單獨中和），並補上
兩個缺的負例（空 transitions 陣列、沒有記錄 entry 就 release）：

```
19 個 return site → 19/19 全紅，未被測到的 site：無
```

## Gate

```
ruby scripts/validate_*.rb（26 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
validator                             → 294 行（< 400）
契約 YAML                             → 215 行
負例                                   → 19 筆
```

未改動任何既有契約或 validator。
