# repo #4 Permission / Retention / Deletion closeout — 大 review 交付包

## 鎖定

```
base    23e6a95   （Owner 簽核凍結卡的 commit）
review  <見對話中的派工區塊>
branch  cc/permission-retention-deletion
```

新增四個檔案，**未修改任何既有契約或 validator**：

```
規格/v0.1/permission-retention-deletion.yaml                     179 行
scripts/validate_permission_retention_deletion_contract.rb       229 行
規格/v0.1/fixtures/permission-retention-deletion-{positive,negative}-fixtures.json
```

## 背景

`CARD-PERMISSION-RETENTION-DELETION-CONTRACT-20260909`（repo #4）自
2026-09-09 起 `BLOCKED_AWAITING_OWNER_SPEC_FREEZE`。本輪先把五個凍結點
攤成可簽選項，Owner 簽 `A A A A A` 後才實作。凍結卡見
`.work/CARD-PERMISSION-RETENTION-DELETION-SPEC-FREEZE-20260916.md`。

鎖的是 STD-01 裡三個「欄位早就存在、語意從未定義」的欄位：
`payload_retention_state`、`deletion_confirmation_ref`、
`permission_decision_ref`。

## 請重播

```bash
ruby scripts/validate_permission_retention_deletion_contract.rb   # 應 PASS

# guard parity：逐一把 return "PRD_..." 中和成 return nil，每個都應轉紅
# 我的結果：12/12 全紅，無未被測到的 guard

# STD-01 綁定：把契約的 allowed_retention_transitions 刪掉任一狀態
# （或加一個 STD-01 沒有的狀態）→ 應 FAIL
```

## 請特別判斷

1. **`pre_hold_state` 是否算擴大範圍**（我主動揭露的判斷）。FP-1-A 只寫
   「解除後回到原階段」，沒有指定欄位。我認為不記錄原階段就無法阻止
   `LEGAL_HOLD → RETAINED` 把已 `RETENTION_EXPIRED` 的證據倒退、重置保留
   期；但這確實是簽核文字沒明說的新欄位，請裁決。
2. **FP-3-A 的雙重保證是否恰當**：轉移表沒有 `LEGAL_HOLD → 刪除` 的邊，
   evaluator 另外獨立擋 `legal_hold_active`。請判斷第二道是必要的
   defence-in-depth，還是冗餘。
3. **FP-4-A 的範圍**：本契約只驗「宣告 stale 卻仍放行」與「完全沒有
   decision」，不驗 decision 的內容、也不判斷 decision 何時變 stale。
   請判斷這個切法是否讓 FP-4-A 失去實質約束力。
4. **狀態集合綁 STD-01 的方式**：讀 JSON Schema 的 enum 並要求完全相同。
   請判斷是否有漏掉的耦合（例如 STD-01 之後新增狀態值時，這裡會紅——
   這是預期行為）。

## Gate

```
ruby scripts/validate_*.rb（26 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
validator                             → 229 行（< 400）
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
