# repo #5 Canonical Direct-Write Audit — 大 review 交付包

## 鎖定

```
base    710d2c8   （Owner 簽範圍的 commit）
review  <見對話中的派工區塊>
branch  cc/canonical-direct-write-audit
```

新增兩個檔案，**未修改任何既有契約或 validator**（FP-3-A：CC 只產 findings，
不自行修）：

```
.work/evidence/CANONICAL-DIRECT-WRITE-AUDIT-20260916.md    findings
scripts/validate_canonical_promotion_binding.rb            常設防線（FP-4-B）
```

## 稽核結論

**沒有發現任何現行的 canonical direct-write 繞過路徑。** 兩筆 finding 都是
綁定／文字層的漂移風險：

- **F-01（P2）**：`personal-harness-integration.core_pipeline` 重述 canonical
  尾段但未 pointer-bind，且 `grep -rn "core_pipeline" scripts/` **零命中**
  ——沒有任何 validator 讀它。對比之下，同檔案下方幾行的 `core_invariants`
  **有**被 boundary validator 讀取斷言。目前順序與上游一致，非繞過路徑。
- **F-02（P3）**：e2e 契約的 prose 以箭頭重述路徑；但機器面綁得紮實
  （validator 實讀 boundary 的 `ordered_steps` 與 `receipts_required`），
  風險僅在文字日後不跟著上游走。

## 請重播

```bash
ruby scripts/validate_canonical_promotion_binding.rb   # 應 PASS

grep -rn "core_pipeline" scripts/        # 我的結果：零命中（F-01 的核心證據）
grep -n "core_invariants" scripts/validate_ai_work_record_boundary_contract.rb
                                         # 我的結果：263 行有讀（對比證據）

# 常設 gate 的三種漂移模式，皆應轉紅：
#   1. 移除 KNOWN_UNBOUND 裡 F-01 的登記
#   2. 新增一份含 canonical 步驟、未帶 boundary pointer 的 yaml
#   3. 在 KNOWN_UNBOUND 登記一個不存在的路徑（殭屍例外）
```

## 請特別判斷

1. **FP-2-A 判準的執行方式是否正確**：我把「重述」定義為「陣列元素與
   canonical 步驟重疊 ≥ 2 個」。請判斷這個門檻會不會漏掉真正的繞過，或
   誤抓無關清單。
2. **F-01 的嚴重度（我給 P2）是否合適**——它不是現行繞過，但相鄰 key 有綁
   而它沒綁。
3. **`KNOWN_UNBOUND` 這個機制是否恰當**：依 FP-3-A 我不能自行修 F-01，所以
   把它登記成「已知、待裁決」的例外。請判斷這是誠實登記，還是變相放行。
4. **有沒有我漏掉的稽核面**（FP-1-B 要求契約 ＋ validator 兩面）。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
