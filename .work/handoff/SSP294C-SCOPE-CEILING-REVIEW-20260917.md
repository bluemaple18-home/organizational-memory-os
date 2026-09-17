# SSP-294 切片 C — 大 review 交付包

## 鎖定

```
base    9864303
review  <見對話中的派工區塊>
branch  cc/ssp294-scope-ceiling
```

新增三個檔案，**未修改任何既有契約或 validator**：

```
規格/v0.1/emem-scope-ceiling.yaml                    133 行
scripts/validate_emem_scope_ceiling_contract.rb      197 行
規格/v0.1/fixtures/emem-scope-ceiling-{positive,negative}-fixtures.json
```

## 這張卡（Owner 已簽 FP-1~FP-3 = A A A）

上游「source ACL 天花板」規則目前只被驗**規則敘述裡有沒有 "cannot widen"
這句話**，從未評估過真實範圍變更。本片取代它。

## 請重播

```bash
ruby scripts/validate_emem_scope_ceiling_contract.rb   # 應 PASS (scopes=3, receipts=3)

# 綁定是活的：
#   上游新增一個 required_receipt                         → 應 FAIL
#   某範圍的 widening_requires_promotion_gate 改 false     → 應 FAIL（既有負例失效）
#   上游新增一個 scope                                     → 應 FAIL（覆蓋斷言）
# 逐 return site parity（非逐 code）→ 我的結果 7/7 全紅
```

## 請特別判斷

1. **範圍順序是推導出來的，不是上游明寫的**：從 `default_readers` 的子集
   關係推導收窄／放寬，兩個互不包含的範圍之間視為「不可比較 → 當放寬處理」。
   請判斷這個推導方式與 fail-closed 方向是否正確——是否應該反過來（不可比較
   時拒絕整個操作，而不是要求走放寬流程）。
2. **`promotion_name_collision` 的隔離是否足夠**：契約與 `hard_stops` 都寫明
   不得綁定 `ai-work-record-boundary.promotion_path`，但沒有機器斷言去確認
   *其他* 契約沒有反過來誤引用本片。請判斷這個隔離只靠文件是否足夠。
3. **`REFUSED` 永遠可接受**是否留洞。

## 送審前自己抓到的事（非 finding，記錄用）

寫說明文字時舉了具體範圍名稱當例子，被自己的「禁止重述」斷言抓到（與切片 B
review 指出的 substring 脆弱性同一類，這次發作在自己身上）。已改寫成不點名
的敘述繞開，未放寬檢查本身。

## Gate

```
ruby scripts/validate_*.rb（30 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
