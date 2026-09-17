# SSP-294 切片 A — 大 review 交付包

## 鎖定

```
base    3706d09
review  <見對話中的派工區塊>
branch  cc/ssp294-promotion-gate
```

新增三個檔案 ＋ 校正兩處過時文件：

```
規格/v0.1/emem-promotion-gate.yaml                    89 行
scripts/validate_emem_promotion_gate_contract.rb     157 行
規格/v0.1/fixtures/emem-promotion-gate-{positive,negative}-fixtures.json
.work/CARD-SSP294-PROMOTION-20260909.md               blocker 表校正（停在 9/9）
文件/待辦重整.md                                        兩句過時狀態校正
```

**未修改任何既有契約或 validator。**

## 這張卡的性質

`SSP-294` 研究後發現：**政策早就宣告完整，但幾乎沒有被強制**。

| 上游宣告 | 實際被驗到 |
|---|---|
| gate 6 required | 只有 1 個（`reviewer_approval` 要在清單裡）|
| gate 3 forbidden | **零** |
| 15 個 PROMOTE 決策格 | 只驗「每格存在」＋ 1 條具體條件 |

所以切成三片：A（gate 組成，本卡）／B（15 決策格重放）／C（傳遞語意 ＋
canonical writer，可能需 T2）。

## 請重播

```bash
ruby scripts/validate_emem_promotion_gate_contract.rb   # 應 PASS (required=6, forbidden=3)

# 綁定是活的（本檔一行不改）：
#   上游 promotion_widening_gate.required 新增一項    → 應 FAIL
#   上游 promotion_widening_gate.forbidden 新增一項   → 應 FAIL
# 逐 return site parity（非逐 code）→ 我的結果 6/6 全紅
```

## 請特別判斷

1. **「不重述」的斷言做法**：我用「本契約文字裡不得出現任何上游條件名稱」來擋
   複製。請判斷這會不會誤殺——例如日後某條件名稱剛好是常見英文詞。
2. **forbidden 先於 outcome 檢查** 的順序：宣告禁止路徑的 run 不管 outcome
   是什麼都被擋，也不能靠備齊 required 贖回。請判斷這個嚴格度是否正確。
3. **`satisfied_conditions` 是 map（條件 → receipt URN）而非名稱清單**：我認為
   bare list 等於讓 caller 空口宣稱。但 receipt 真實性本層驗不了（已在
   `provenance_boundary` 宣告）。請判斷這個折衷是否恰當。
4. **`DENIED` 不檢查條件** 是否留洞。

## Gate

```
ruby scripts/validate_*.rb（28 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
