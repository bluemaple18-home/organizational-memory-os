---
id: AIWR-LAST-MILE-SPEC-FREEZE-20260916
status: AWAITING_OWNER_SIGNATURE
type: spec_freeze
tier: T2
jira: SSP-310 後續（最後一哩；是否需要新票待 Owner 決定）
origin: "SSP-310 真人 pilot ACCEPTED_GO 後，Owner 問「要找同事安裝了嗎」，CC 指出還缺最後一哩"
---

# AIWR 最後一哩 — Owner 凍結點

👉 [假設與目標確認]
- 目標：把 Native Adapter 產出的 `mapping_run` 接到既有 Hook 擷取契約，
  讓這條線第一次產出「真的通過 `hook_capture_failure` 的 capture batch」。
- 邊界：三個凍結點需要 Owner 簽，因為都涉及身分綁定或 `FORBIDDEN_BY_DEFAULT`
  的越權邊界，CC 不自行裁決。
- 驗收：簽核後另開 T1 closeout 卡實作。

## 研究結論（不需決策，僅記錄）

1. **多 turn 沒問題**：`ai-task-card-record.yaml` 的
   `allowed_status_transitions` 有 `IN_REVIEW → OPEN`，所以
   turn1 `start→submit_review`、turn2 `start→submit_review` … 是合法振盪。
2. **`complete` 永遠不會由 Adapter 發出**：Adapter 明確不取得完成權限，
   所以卡片不會因為這條路徑走到 `DONE`。這是設計，不是缺口。
3. **目前系統沒有任何 runtime 儲存層**：`hook_capture_failure` 是契約
   evaluator，不是寫入器。整個 repo 只有契約與 validator。

## FP-1：`task_ref` 從哪裡來？

`native_correlation_ref` 是 `prompt_id`（一個 turn）；`task_ref` 必須是
task-card URN（一個工作單位，通常跨多個 turn）。兩者沒有天然對應，必須有人
建立綁定。

- **(A)** 由使用者在啟動 pilot session 時**明示宣告**（例如環境變數
  `OMOS_TASK_REF=urn:omos:task-card:<uuid>`），該 session 的所有 turn 都
  歸屬這張卡。不建 registry、不做任何推論；沒宣告就不產出 batch。
  **← CC 建議**
- **(B)** 每個 turn 自動鑄一張新卡。語意錯誤（卡是工作單位不是 turn），
  且會產生大量無意義卡片。
- **(C)** 建一個 `prompt_id → task_ref` 的綁定儲存。這是
  `FORBIDDEN_BY_DEFAULT` 的 `new registry/DB`，需要 Owner 另外明示授權。

## FP-2：這一哩的終點是什麼？

- **(A)** 產出一個**通過既有 `hook_capture_failure` 驗證的 capture batch
  JSON 檔**，證明整條鏈（真實事件 → 分類 → 歸屬 → 組批 → 契約驗證）打通。
  不寫任何 canonical store。**← CC 建議**
- **(B)** 真的寫進某個 Work Record 儲存。但目前**沒有這種 store 存在**，
  要做就是新建 writer／DB，屬 `FORBIDDEN_BY_DEFAULT`，需 Owner 另案決策。

## FP-3：`event_key` 怎麼定？

`hook_capture_failure` 以 `event_key` 去重，且同 key 帶不同 event 會
`HOOK_DUPLICATE_CONFLICT`。

- **(A)** 決定性字串：`session_id` + `native_correlation_ref` + `event`。
  同一 turn 的同一事件重放會正確去重，跨 turn 不會誤併。**← CC 建議**
- **(B)** 直接用 `adapter_output_ref`。但它含微秒時間戳，每次都不同，
  去重永遠不會生效——等於冪等性形同虛設。

## 簽核方式

回三個字母即可，例如：`A A A`。

## Stop conditions

若 Owner 選 (C) 或 FP-2 的 (B)，CC 停下另開範圍決策，不在本卡實作。
