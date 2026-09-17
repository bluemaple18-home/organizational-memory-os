# SSP-294 切片 A — evidence

日期：2026-09-17　branch：`cc/ssp294-promotion-gate`　base：`3706d09`

## 研究：本卡的性質是強制，不是設計

`grep` 確認上游 `personal-harness-integration.yaml` 早已宣告完整政策：

```
promotion_widening_gate.required  : 6 項
promotion_widening_gate.forbidden : 3 項
actor_action_policy.PROMOTE       : 15 個決策格（5 actor × 3 材料類別）
```

而目前的強制程度：

- gate 的 6 個 required —— 只有 1 個被驗（`reviewer_approval` 要在清單裡）
- gate 的 3 個 forbidden —— 零
- 15 個決策格 —— 只驗「每格存在」＋ 1 條具體條件

本卡收 gate 這一段；決策格是切片 B。

## 交付

```
規格/v0.1/emem-promotion-gate.yaml                    89 行
scripts/validate_emem_promotion_gate_contract.rb     157 行（< 400）
fixtures 正例 3 筆 / 負例 7 筆
```

## 綁定而非重述（實測）

契約不寫 required／forbidden 的內容；validator 另有一道斷言禁止本契約文字裡
出現任何上游條件名稱。效果：

```
上游 required 新增 newly_added_upstream_condition（本檔一行未改）
  → FAIL PROMO_POS_ALL_CONDITIONS_SATISFIED 預期 allow，實際被拒：
         PROMOTION_GATE_CONDITION_UNSATISFIED

上游 forbidden 新增 reviewed_shared_publication（本檔一行未改）
  → FAIL PROMO_POS_ALL_CONDITIONS_SATISFIED 預期 allow，實際被拒：
         PROMOTION_FORBIDDEN_PATH_DECLARED
```

兩者都證明綁定是活的：上游一動，這裡立刻跟上。

## 一個刻意的順序決定

`forbidden` 檢查放在 `outcome == PROMOTED` 判斷**之前**，所以宣告禁止路徑的 run
無論 outcome 寫什麼都會被擋，也不可能靠「把 6 個 required 都備齊」贖回。
負例 `PROMO_NEG_FORBIDDEN_PATH_NOT_REDEEMED_BY_APPROVALS` 就是釘這件事。

## 逐 return site parity

第一次跑時 site 3 未被測到——`PROMOTION_GATE_CONDITION_UNSATISFIED` 有兩個
return 位置，我的負例只打到「缺條件」，沒打到「`satisfied_conditions` 根本不是
map」。補上負例後：

```
6 個 return site → 6/6 全紅，未被測到：無
```

（今天已經因為「逐 code 而非逐 site」被抓過一次，所以這輪一開始就用逐 site 探測，
自己先抓到自己。）

## Gate

```
ruby scripts/validate_*.rb（28 支，含新增這支）  → PASS
四支 Python schema engine                         → PASS
git diff --check                                   → clean
```

## 順手校正的過時文件

- `CARD-SSP294-PROMOTION-20260909.md` 的 blocker 表停在 9/9，標 #2/#3「未開工」，
  實際上 9/10 就已 merge（`ebeaab2`／`0ac8c09`）。已校正並補上三切片的規劃。
- `文件/待辦重整.md` 兩句過時（「仍待 Owner：repo #4/#5」、「唯一待辦是 Owner 對
  #5 的 finding 裁決」）。已校正。
