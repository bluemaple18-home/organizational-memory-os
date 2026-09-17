# SSP-294 切片 C — evidence

日期：2026-09-17　branch：`cc/ssp294-scope-ceiling`　base：`9864303`
Owner 簽核：`FP-1: A / FP-2: A / FP-3: A`

## 起始狀態

`validate_personal_memory_scope_contract.rb:137`：

```ruby
assert(contract.dig("source_acl_inheritance", "rule").to_s.include?("cannot widen"), ...)
```

只驗規則的**敘述文字**裡有沒有那句話，從未評估過一次真實的範圍變更。

## 推導範圍順序（非發明）

上游只給 `default_readers`，用子集關係推導：

```
SELF_ONLY {owner}                                    ⊂ EMPLOYEE_AND_POLICY_SYSTEM {owner, policy_bound_system}
SELF_ONLY {owner}                                    ⊂ WORK_CONTEXT_PARTICIPANTS {owner, source_acl_participants, reviewer}
EMPLOYEE_AND_POLICY_SYSTEM ↔ WORK_CONTEXT_PARTICIPANTS：互不包含 → 不可比較
```

裁決：不可比較的移動一律當放寬處理。理由記在契約 `scope_ordering.rule`。

## 交付

```
規格/v0.1/emem-scope-ceiling.yaml                    133 行
scripts/validate_emem_scope_ceiling_contract.rb      197 行（< 400）
fixtures：正例 4 筆／負例 9 筆
```

## 又踩到一次 substring 陷阱（送審前自己抓到）

寫 `scope_ordering.rule` 的說明文字時，舉了 `EMPLOYEE_AND_POLICY_SYSTEM` 與
`WORK_CONTEXT_PARTICIPANTS` 當具體例子——結果被自己的「禁止重述」斷言抓到。
改寫成不點名具體範圍的敘述（「至少有一對範圍互不可比較」），繞開陷阱本身，
而不是放寬檢查。

這是切片 B 那筆 backlog（substring 掃描偏脆）**第二次在自己身上發作**。兩次
都是「解釋規則時舉了真實例子」觸發，而不是真的想抄一份清單——這個具體型態
值得補進那筆 backlog 的描述，但不擴大處理範圍。

## 逐 return site parity ＋ 三個上游變動探測

```
7 個 return site → 7/7 全紅

上游新增一個 required_receipt        → FAIL（既有正例缺該 receipt）
某範圍的 widening_requires_promotion_gate 改 false → FAIL（該範圍的缺 gate 負例通過了，等於旗標鬆綁沒被抓到）
上游新增一個 scope                   → FAIL（覆蓋斷言：新範圍缺負例）
```

第二個特別值得記：如果只驗「範圍存在」，不驗「gate 旗標真的被強制」，上游
把某個範圍的旗標從 `true` 改 `false`（放寬治理）會無聲通過——這正是切片 B
那次「決策感知覆蓋」教訓的同型應用，這次用在 boolean 旗標上而非 decision 值。

## Gate

```
ruby scripts/validate_*.rb（30 支，含新增這支）  → PASS
四支 Python schema engine                         → PASS
git diff --check                                   → clean
```
