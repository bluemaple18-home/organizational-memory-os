# SSP-294 切片 B — 大 review 交付包

## 鎖定

```
base    8334020
review  4b5924d
branch  cc/ssp294-promotion-policy
```

新增三個檔案，**未修改任何既有契約或 validator**：

```
規格/v0.1/emem-promotion-policy.yaml                  129 行
scripts/validate_emem_promotion_policy_contract.rb    222 行
規格/v0.1/fixtures/emem-promotion-policy-{positive,negative}-fixtures.json
```

## 這張卡

上游宣告 15 個升格決策格，實際只有一格的 3 條條件被驗——而且驗的是「條件有
沒有列在清單裡」，不是「升格時有沒有滿足」。本切片讓每一格都 load-bearing。

## 請重播

```bash
ruby scripts/validate_emem_promotion_policy_contract.rb   # 應 PASS (cells=15)

# 綁定是活的（本檔一行不改）：
#   把某個 DENY 格改成 CONDITIONAL        → 應 FAIL（缺成功升格 fixture）
#   上游新增一個 actor                     → 應 FAIL（新格缺 fixture）
#   某 CONDITIONAL 格新增一條 required     → 應 FAIL（既有正例缺該條件）
# 逐 return site parity（非逐 code）→ 我的結果 10/10 全紅
```

## 請特別判斷

1. **決策感知覆蓋**是本輪我自己發現並補的：只驗「每格被踩過」時，把 `DENY`
   放寬成 `CONDITIONAL` 會無聲通過。現在要求 `CONDITIONAL` 格必須有成功升格
   的正例。請判斷這個規則有沒有反過來造成維護負擔或誤殺。
2. **fixture 自帶 policy** 的機制：只給「健康上游產不出的輸入」用（decision
   無法辨識、`required_conditions` 非清單），且排除在覆蓋斷言之外。請判斷這
   是否被濫用的風險，或該不該更嚴格地限制它。
3. **`DENIED` 永遠可接受**：拒絕升格不檢查任何條件。請判斷是否留洞。
4. **已知重複**（與切片 A 相同的兩行型別／URN 檢查）我刻意沒抽共用 helper，
   理由寫在契約 `known_duplication`。請裁決這個取捨。

## Gate

```
ruby scripts/validate_*.rb（29 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
