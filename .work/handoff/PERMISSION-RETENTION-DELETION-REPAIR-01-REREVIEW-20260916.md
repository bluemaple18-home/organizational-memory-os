# repo #4 repair-01 — 定點 re-review 交付包

同一條 review line。只收 `12b7c90` 的 P1×2。

## 鎖定

```
base                23e6a95
original_review     12b7c90   （NO_GO，P1=2）
repair_commit       <見對話中的派工區塊>
branch              cc/permission-retention-deletion
```

## 收法

兩個 finding 是同一類病：加了欄位但讓 caller 自己宣告，等於沒綁。

**F-01**：改由**歷史重放**當權威。新增 `retention_history_failure`，重放
有序轉移、要求連續性、在進 `LEGAL_HOLD` 時記下當時狀態，離開時必須回到
**歷史記錄的那個值**；run 自己宣告的 `pre_hold_state` 不算數。

**F-02**：改綁 **STD-01 的 `access.acl_snapshot_ref`**。run 必須帶
`decision_acl_snapshot_ref` 與 `current_acl_snapshot_ref`（pattern 直接從
schema 讀，不手抄）；兩者不同 → 必定 stale；任一缺失或格式不對 →
fail closed（未知不視為新鮮）。

## 請重播（你的兩個 exploit）

```ruby
# 案例1
{"transitions"=>[
  {"from_state"=>"RETAINED","to_state"=>"RETENTION_EXPIRED"},
  {"from_state"=>"RETENTION_EXPIRED","to_state"=>"LEGAL_HOLD"},
  {"from_state"=>"LEGAL_HOLD","to_state"=>"RETAINED","pre_hold_state"=>"RETAINED"}]}
# 我的結果：PRD_HOLD_RELEASE_CONTRADICTS_HISTORY（修正前 nil）

# 案例2
{"permission_decision_ref"=>"urn:omos:permission-decision:x","access_granted"=>true}
# 我的結果：PRD_PERMISSION_FRESHNESS_UNKNOWN（修正前 nil）
```

## 主動揭露：parity 方法本身也有同一個洞

第一次跑 code 層級 parity 時，**這輪新增的兩個 code 顯示「未被測到」**——
每個 code 有兩個 return 位置，負例只打到一個，另一個仍會攔住。這跟你指出
的空轉是同一類問題，只是出現在測試方法上。

已改成**逐 return site** 探測並補兩個缺的負例：**19 個 site 全紅，無遺漏**。
建議你重播時也用逐 site 的方式，而不是逐 code。

## Gate

```
ruby scripts/validate_*.rb（26 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
validator 294 行 / 契約 215 行 / 負例 19 筆
```

## 請只判斷

這兩筆 P1 是否已關閉，以及「歷史重放」與「綁 acl_snapshot_ref」這兩個
綁定是否真的拿掉了自述空間。
