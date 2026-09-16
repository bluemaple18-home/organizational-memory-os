# AIWR E2E evidence repair-01 — 定點 re-review 交付包

同一條 review line。只收 `7ce9bfb` 的那一筆 P2。

## 鎖定

```
base                f35de26
original_review     7ce9bfb   （NO_GO，P2=1）
repair_commit       <見對話中的派工區塊>
branch              cc/aiwr-e2e-evidence
```

定點 diff：`git diff 7ce9bfb..<repair_commit>` —— **只動
`.work/evidence/AIWR-END-TO-END-REAL-CAPTURE-20260916.md` 的文字**，
沒有改任何程式碼、契約、或入庫的 batch／log 資料。

## 收法

你指出的沒錯：我自己在後面寫了「不對應任何真實 task card」，前面卻寫
「單一 task card」與「task-card 狀態：OPEN → IN_REVIEW」——同一份文件
自相矛盾，而且前段讀起來像真有卡片被改了狀態。

逐處改：

| 位置 | 原文 | 改後 |
|---|---|---|
| 開頭 | 「第一次產出端到端的真實 capture batch」 | 「第一次用真實事件走完整條鏈路」＋明寫「事件是真的，task-card 身分是合成的」「沒有任何真實卡片被建立或改變狀態」 |
| 鏈路圖 | `task-card 狀態：OPEN → IN_REVIEW` | `契約 replay 對應 OPEN → IN_REVIEW（只是 evaluator 的轉移重放，沒有任何真實卡片被改狀態）` |
| 證據範圍 | 「單一 task card」 | 「單一『宣告的 synthetic task-card URN』」 |
| 驗證區 | `序列 → ... → OPEN → IN_REVIEW` | `轉移重放（evaluator） → ... 對應 OPEN → IN_REVIEW` |

## 一併收斂 FP-1-A 的推論（你也點名了）

原文把「2026-09-15 那兩筆被略過」寫成「FP-1-A 在真實資料上生效的證明」。
已改成你給的較窄敘述：證明的是 **builder 對真實歷史資料中缺
`declared_task_ref` 的 record 會略過**；並明寫**不能**由此推論「使用者
刻意不宣告的 opt-out 流程已真人實測」——那兩筆沒有歸屬是因為機制當時
還不存在，真正的 opt-out 情境目前仍只有合成案例覆蓋。

## 請重播

```bash
grep -n "task-card 狀態\|單一 task card\|FP-1-A 在真實資料上生效" \
  .work/evidence/AIWR-END-TO-END-REAL-CAPTURE-20260916.md
# 我的結果：無命中

grep -n "OPEN → IN_REVIEW" .work/evidence/AIWR-END-TO-END-REAL-CAPTURE-20260916.md
# 我的結果：兩處，都已標明是「契約 replay／evaluator 轉移重放」
```

資料本身未動，所以你上一輪已確認的 byte-identical 比對與
`hook_capture_failure=nil` 仍然成立，無須重驗（若要重跑，指令與上一份
交付包相同）。

## Gate

```
ruby scripts/validate_*.rb（25 支）  → PASS
git diff --check                      → clean
未改動任何 .rb／契約／設定檔／證據資料
```

## 請只判斷

措辭是否已收斂到位，不擴大範圍。
