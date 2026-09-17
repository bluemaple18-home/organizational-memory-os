---
id: CORE-PIPELINE-PROMOTION-BINDING-20260917
status: AWAITING_BIG_REVIEW
type: implementation
tier: T1
closes_finding: "repo #5 稽核 F-01（P2）"
owner_disposition: "2026-09-17 Owner 裁決：F-01 不長期停留 KNOWN_UNBOUND，在 SSP-294 開工前以小卡收掉；F-02 維持 P3 不處理。"
---

# 收 repo #5 稽核 F-01：`core_pipeline` pointer-bind 回 canonical 權威

👉 [假設與目標確認]
- 目標：讓 `personal-harness-integration.core_pipeline` 明確宣告它重述了
  canonical 升格路徑的哪一段，並由 validator 驗證那一段仍對得上上游。
- 邊界：**小修，不是新架構**。不改 `core_pipeline` 的任何既有步驟，不動
  canonical 權威本身，不碰 F-02。
- 驗收：見 Acceptance。

## 為什麼要做（而且為什麼理由跟原本想的不一樣）

稽核當時的說法是「怕上游改了、副本忘記改」。但 repo #5 repair-01 之後，
canonical gate 的語意比對**不管有沒有 pointer 都會跑**，所以：

| 上游變更 | repair-01 之後 |
|---|---|
| 插入新步驟 | 副本缺一步 → **已經會紅** |
| 移除步驟 | 副本留著孤兒名稱，該名稱不再是 canonical step → 從比對範圍消失 → **靜默通過** |
| 步驟改名 | 同上 → **靜默通過** |

真正沒被守住的是後兩種：**上游瘦身時，副本會安靜地留下孤兒步驟**。
本卡補的是這個，不是「副本過期」那個（那個已經有人盯）。

## 修法

### 1. 契約明確宣告重述範圍

`personal-harness-integration.yaml` 新增 `core_pipeline_promotion_binding`：
`promotion_path_ref` 指回上游，`covers` 列出它重述的四個步驟，並以 `rule`
說明 `core_pipeline` 自己的其他階段（SOURCE／OBJECT_LINKING／…）不受此綁定
管轄。

### 2. 斷言加在「相鄰的 key 已經有、它卻沒有」的那個地方

加進 `validate_ai_work_record_boundary_contract.rb`——它本來就在讀
`personal-harness-integration.yaml` 並斷言 `core_invariants`。`core_pipeline`
就在隔壁幾行卻沒被讀，本卡正好補平這個不對稱。三條檢查：

- `covers` 每一步都必須是上游**現存**步驟（孤兒 → 紅）
- `covers` 必須是上游的**連續同序切片**（自己描述的範圍內不得跳步）
- `core_pipeline` 實際出現的 canonical 步驟必須**剛好等於** `covers`
  （宣告與內容不得脫節）

### 3. 移除 `KNOWN_UNBOUND` 例外

canonical gate 的例外清單清空（`known unbound=0`）。註解寫明「空的才是正常
狀態」。

### 4. 順手修掉我自己在探測時發現的洞（主動揭露）

驗證「拿掉 pointer 應該轉紅」時發現 **沒有紅**：canonical gate 原本用
「整份檔案文字裡有沒有出現 pointer 字串」判定綁定，所以把
`promotion_path_ref` 改成 `none`、只靠下方 `rule` 散文裡提到那串字，
仍被當成已綁定。

那又是「驗存在、不驗實質」——跟 repo #5 大 review 打我的同一類問題，只是
換個位置。改成只認**結構化欄位的值**（整值比對 pointer 或其點號延伸），
散文提及不再算數。

## Constraints

- 不改 `core_pipeline` 既有步驟、不改 canonical 權威。
- 不碰 F-02（Owner 裁決維持 P3）。
- 不新增任何儲存、registry、writer。

## Acceptance

1. 上游改名／移除 canonical 步驟 → 孤兒檢查轉紅。
2. `core_pipeline` 內容與 `covers` 宣告脫節 → 轉紅。
3. 拿掉結構化 pointer（即使散文仍提及）→ canonical gate 轉紅。
4. `KNOWN_UNBOUND` 清空，`known unbound=0`。
5. 27 支 validator 全 PASS；`git diff --check` clean。

## Evidence

`.work/evidence/CORE-PIPELINE-PROMOTION-BINDING-20260917.md`
