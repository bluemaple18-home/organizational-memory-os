---
id: AIWR-LAST-MILE-CLOSEOUT-20260916
status: NO_GO_REPAIRED_02_AWAITING_TARGETED_REREVIEW
type: implementation
tier: T1
jira: SSP-310 後續（最後一哩）
implements_spec_freeze: AIWR-LAST-MILE-SPEC-FREEZE-20260916
owner_signature: "FP-1: A / FP-2: A / FP-3: A（2026-09-16）"
---

# AIWR 最後一哩 — 實作 Owner 簽定的凍結點

👉 [假設與目標確認]
- 目標：把 Native Adapter 的 `mapping_run` 接到既有 Hook 擷取契約，產出
  第一個通過 `hook_capture_failure` 的 capture batch。
- 邊界：依 Owner 簽核的 FP-1-A／FP-2-A／FP-3-A 實作，不擴大。不寫任何
  canonical store，不新增 registry／DB。
- 驗收：見 Acceptance。

## 逐點收法

### FP-1-A：`task_ref` 由呼叫端明示宣告

hook 讀 `OMOS_TASK_REF`，把值**原樣**記進 `declared_task_ref`。刻意不叫
`task_ref`——讓「這是呼叫端的宣告、不是本層解析出來的結果」在資料本身就
看得出來，與 Native Adapter 契約「不核發、不解析 task-card 身分」的邊界
一致。沒宣告就不寫這個欄位，該筆記錄無法被組成 envelope。

### FP-2-A：終點是通過驗證的 batch 檔

新增 `scripts/build_aiwr_capture_batch.rb`（104 行）：讀 mapping_run log，
依 `declared_task_ref` 分組，每個 task_ref 輸出一個 batch JSON。不寫入
任何 canonical store（系統裡也不存在那種 store）。

### FP-3-A：決定性 `event_key`

`event_key = session_id + native_correlation_ref + event`。不含時間戳，
所以同一 turn 的同一事件被重複擷取時會正確去重；不同 turn 因
`native_correlation_ref` 不同而不會誤併。

## Constraints

- 不改任何既有契約檔案與既有 validator。
- 不新增 registry／DB／writer。
- 新腳本 `< 400` 行。

## Acceptance

1. 有宣告的記錄組出 batch；未宣告的被略過（FP-1-A）。
2. 產出的 batch 通過既有 `hook_capture_failure`（回傳 `nil`）。
3. 一個 batch 只含一個 `task_ref`；多張卡分成多個檔（`batch_scoping_rule`）。
4. 同一事件重放會被 `event_key` 去重，`emitted.lifecycle_events` 等於
   去重後序列（FP-3-A）。
5. 多 turn 形成 `start→submit_review→start→submit_review`，通過轉移重放。
6. 既有 24 支 validator 全 PASS；`git diff --check` clean。

## 已知限制（誠實記錄，非缺口）

- 目前用合成事件驗證整條鏈。**真人帶 `OMOS_TASK_REF` 的實跑尚未做**——
  那需要 Owner 再開一次 session，是下一步，不在本卡。
- `complete` 永遠不會由這條路徑發出（Adapter 無完成權限），所以卡片不會
  走到 `DONE`。設計如此。
- ~~batch 的驗證不在常設 gate 內~~ **（repair-01 已解決，此限制不再成立）**：
  新增 `scripts/validate_aiwr_capture_batch_builder.rb` 進入常設 gate。
  它以機械抽取的方式綁定既有 `hook_capture_failure` 的原始碼，**沒有**
  動到 SSP-301 本體，也沒有重寫第二份 capture 規則。

## 大 review 記錄

- `3d3b53c`：NO_GO，P1×2 + P2×1——(F-01) `task_ref` 只驗泛型 OMOS URN，
  別種 entity 會被當成 task card；(F-02) `event_key` 用 `join(":")` 串接，
  `("a:b","c")` 與 `("a","b:c")` 碰撞，不同 turn 被誤併；(F-03) builder
  沒有常設 regression gate，前兩個錯誤被 24 支既有 validator 全數放行。
- repair-01：身分收窄為 `urn:omos:task-card:` 並 fail-closed 整批拒絕；
  `event_key` 改用 `JSON.generate([...])` 消除歧義；新增
  `scripts/validate_aiwr_capture_batch_builder.rb` 進常設 gate（25 支），
  並以 enforcement parity 證明兩個 bug 放回去就會紅。

- `7e5eed0`：定點 re-review NO_GO，P1×1——F-01 只擋 entity 種類（前綴），
  沒擋 identity 形狀，`urn:omos:task-card:not-a-uuid` 仍被放行。
- repair-02：改為**綁定** `validate_ai_task_card_record_contract.rb` 的
  `CARD_ID_URN` 原始碼（抽不到就 fail loud），而非手抄 UUID regex；
  reviewer 的案例固定成常設負例，另加 canonical UUID 對照組。

## Evidence

`.work/evidence/AIWR-LAST-MILE-CLOSEOUT-20260916.md`
`.work/evidence/AIWR-LAST-MILE-CLOSEOUT-REPAIR-01-20260916.md`
`.work/evidence/AIWR-LAST-MILE-CLOSEOUT-REPAIR-02-20260916.md`
