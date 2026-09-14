---
id: NATIVE-ADAPTERS-TASK-REF-SPEC-FREEZE-20260914
status: AWAITING_OWNER_SIGNATURE
type: spec_freeze
tier: T2
review_line: Native Adapters task_ref correlation
blocker: "task_ref 的抽象化程度不足以支撐恢復 lifecycle mapping（卡片自訂 stop condition）"
frozen_refs:
  base: 28438bb
  review_commit: 869a5ca8422b7707a003d8309de3ff960ada7a87
  reviewer_verdict: NO_GO (P0=0, P1=2, P2=1, P3=0)
---

# Owner Spec-Freeze — native turn correlation 要怎麼綁進 Hook 的 task_ref 身分模型

👉 [假設與目標確認]
- 目標：由 Owner 簽定 native adapter 的 correlation 欄位要怎麼跟
  `ai-work-record-hook.yaml` 既有的 `task_ref`（task-card URN）身分模型
  接軌，之後由一張新卡實作。
- 邊界：本卡**不實作**。不重開已關閉的 `SSP-307`／`SSP-308` review line；
  不動 `ai-work-record-hook.yaml`（除非 Owner 在 FP-3 明確選擇要動）。
- 驗收：Owner 在下方每個 freeze point 簽選項。

## 為什麼走到這裡

`cc/native-adapters-task-ref-correlation` 這輪送審，reviewer 判 NO_GO
（P1=2、P2=1），並指出我在卡片裡自己寫的 stop condition
（「若無法確認 task_ref 的抽象化程度是否足夠... 停，回 Owner」）已經
被觸發。三筆 finding 我逐一去讀程式碼／查文件驗證過，全部屬實：

## 缺口已實測（不是推論）

**F-01：identity 混淆**——`ai-work-record-hook.yaml` 的 `task_ref` 已經是
既有、正在使用中的欄位，validator 要求它是 `urn:omos:task-card:<uuid>`：

```ruby
return "HOOK_EVENT_INLINE_CONTENT" unless urn?(envelope["task_ref"], OMOS_URN)
```

既有 fixture：`"task_ref": "urn:omos:task-card:11111111-..."`。

我這輪的 Native Adapter 卻要求呼叫端把 native `turn_id`／`prompt_id`
（如 `"turn-01a08a6f-..."`）填進同名的 `task_ref` 欄位——**這是兩種不同的
身分**：一個是「這個原生事件屬於哪個 turn」，一個是「這個事件屬於哪張
任務卡」。一個 turn 不天然等於一張任務卡，也沒有任何機制保證兩者
一一對應。

**F-02：Claude `Stop` 的終態前提不成立**——查證官方文件：

```
Stop can fire multiple times per turn if a Stop hook blocks it with exit
code 2. Each time Claude finishes responding after being unblocked by a
Stop hook, the Stop event fires again for the same turn.
```

`stop_hook_active` 專門用來讓呼叫端分辨「這是不是已經被擋過的延續」。
我的映射把每一次 `Stop` 都當成終態的 `submit_review`，即使 `task_ref`
綁定問題解決了，同一個 turn 仍可能收到多次 `Stop`，重新產生
`IN_REVIEW → IN_REVIEW` 非法 transition。

**F-03：「Hook 依 task_ref 組批」沒有機器保證**——讀完
`hook_capture_failure` 全文：

```ruby
deduped = raw.uniq { |envelope| envelope["event_key"] }
return "HOOK_DUPLICATE_NOT_IDEMPOTENT" if emitted_events != deduped.map { |envelope| envelope["event"] }
...
transition_code = replay_transition_failure(emitted_events, card_record_spec)
```

去重跟 transition replay 都是對**整個 `raw` 陣列**做的，沒有任何地方
照 `task_ref` 分組、也沒有斷言同一批次只能有一個 `task_ref`。我在
handoff 裡寫的「Hook 本來就是在 task_ref 範圍組批」，描述的是我認為
**應該** 是誰的責任，不是契約**已經**保證的事。

---

## Freeze Point 1：native correlation id 要不要叫 `task_ref`

**FP-1-A（CC 建議）**　改名。Adapter 的欄位改叫 `native_correlation_ref`
（值仍是 `turn_id`／`prompt_id`），`task_ref`（task-card URN）明確排除
在這個薄 Adapter 的職責之外——Adapter 本來就不做卡片建立／URN 核發
（`hard_stops` 已經禁止 registry／FSM／database），native-id 到
task-card-URN 的綁定是呼叫端（Hook 組批那一層）的責任，不是這個
Adapter 該解的問題。
　　風險：把「怎麼綁」這個真正的問題往上游推，沒有解決，只是正確定位
　　責任歸屬。

**FP-1-B**　由本卡新建一份薄的 binding 契約：
`native-correlation-to-task-ref.yaml`，定義 native-id → task-card URN
的映射規則與驗證。
　　風險：這是一個新的小型 registry 概念（即使很薄），需要想清楚誰來
　　維護這份映射、什麼時候建立、要不要持久化——容易滑向「新增
　　registry／database」，正是 `hard_stops` 明文禁止的。

**FP-1-C**　放寬 `ai-work-record-hook.yaml` 的 `task_ref` 格式要求，
接受非 URN 的 native correlation id。
　　**CC 不建議**：`task_ref` 是已經 `LOCKED_OWNER_ACCEPTED` 的既有欄位，
　　被多個下游（Skill／Task Card／既有 fixture）依賴，動它的 blast
　　radius 遠超這張卡的範圍。

## Freeze Point 2：Claude `Stop` 的終態判斷

**FP-2-A（CC 建議）**　`mapping_run` 新增 `stop_hook_active`
（或更中性的 `is_continuation`）欄位：`Stop` 只在該欄位為
`false`／缺席時可以 `MAPPED → submit_review`；為 `true` 時一律
`NOT_LIFECYCLE`（這是延續，不是終態）。這是本檔已有 `task_ref` 模式的
延伸，不是新機制。

**FP-2-B**　`Stop` 整個退回非生命週期，不追加欄位處理這個情境；
`SSP-308` 的映射範圍縮小為只有 `UserPromptSubmit → start`，`complete`
留給更高層另想辦法。
　　代價：`Stop` 沒有終態訊號，`submit_review` 這個轉換永遠不會由這個
　　Adapter 觸發。

**CC 建議 FP-2-A**——已有文件可查的欄位，修法成本不高，且沿用本卡
已經建立的「多加一個必要輸入欄位」模式，跟 FP-1 的精神一致。

## Freeze Point 3：Hook 契約要不要補強「依 task_ref 組批」的保證

**FP-3-A（CC 建議）**　不動 `ai-work-record-hook.yaml`。在
`ai-work-record-hook.yaml` 明確寫一條 `batch_scoping_rule`：
「一次 `hook_capture_failure` 呼叫的 `raw` 陣列，呼叫端必須保證全部
屬於同一個 `task_ref`；這是呼叫端的責任，不是這個 evaluator 驗證的」，
並新增一個 cross-layer negative fixture，證明「混入不同 task_ref 的
`raw` 陣列」目前**不會**被攔下（誠實記錄這個已知邊界，而不是假裝
它被保證）。

**FP-3-B**　在 `hook_capture_failure` 加一條斷言：`raw` 陣列裡所有
`task_ref` 必須相同，否則新 code `HOOK_MIXED_TASK_REF`。
　　這是動 `ai-work-record-hook.yaml`（`SSP-301`，`ACCEPTED_GO` 已合併
　　多時、被多個下游依賴）的既有 evaluator，blast radius 較大，且會
　　讓這張已經很成熟的契約多一條新規則。

**CC 建議 FP-3-A**——先把責任邊界寫清楚、補測試證明現狀，不急著加
enforcement；如果之後真的出現「混批」的真實案例，再回頭考慮 FP-3-B。

---

## Owner 簽核

```
FP-1: ____    FP-2: ____    FP-3: ____
簽核日期: ____
```

簽完之後：

1. `cc/native-adapters-task-ref-correlation` 這個 branch **不合併**——
   目前的內容已被 NO_GO，不是可回收的半成品。簽核後開一張新卡
   （或在新 worktree 重新實作），依 FP-1/FP-2/FP-3 的選項重新設計。
2. `SSP-307`／`SSP-308` 維持目前已 `ACCEPTED_GO` + merged 的狀態
   （`lifecycle_event_map` 皆為空）不變，直到新卡完成。
3. 兩張延後 backlog 卡（`CARD-SSP307-LIFECYCLE-MAPPING-BACKLOG`、
   `CARD-SSP308-RUNTIME-PROBE-BACKLOG`）維持原狀，不標記 superseded。

## 本卡不做

不實作任何 FP 選項；不合併任何分支；不動
`ai-work-record-hook.yaml`（除非 Owner 簽 FP-3-B）。
