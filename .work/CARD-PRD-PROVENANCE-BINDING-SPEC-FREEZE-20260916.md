---
id: PRD-PROVENANCE-BINDING-SPEC-FREEZE-20260916
status: AWAITING_OWNER_SIGNATURE
type: spec_freeze
tier: T2
blocks: PERMISSION-RETENTION-DELETION-CLOSEOUT-20260916
trigger: "同一 blocker 連續兩輪被打穿，且查證後確認所有 in-scope 修法都被卡片自身約束與 FORBIDDEN_BY_DEFAULT 堵死"
---

# repo #4 — provenance 綁定邊界，需 Owner 裁決

## 為什麼停下來

大 review 連續兩輪指出同一個根因：**caller 自己提供所謂的權威事實**。

| 輪次 | 我的修法 | 被打穿的方式 |
|---|---|---|
| `12b7c90` | `pre_hold_state` 欄位／`permission_decision_stale` 旗標 | caller 自己填 |
| `4ddbfe5` | 改成整份 `history` 陣列／兩個 snapshot ref | caller 自己編一份自洽的 |

第三次再用「多要一個 caller 提供的輸入」去修，只會被同樣方式打穿。

## 查證結果：in-scope 已無路可走

- `grep` 全 repo：**沒有任何既有契約記錄 retention 歷史**（唯一提到的是我
  這份新契約自己）。要綁就得建持久紀錄。
- 建持久紀錄 = retention DB／ledger，**卡片自己的 Constraints 明文禁止**
  （「不建 retention DB、deletion queue、legal-hold registry、新 writer」），
  `FORBIDDEN_BY_DEFAULT` 也禁止。
- 唯一找得到的既有權威是 `source-anchor.schema.json`：它的 `access`
  同時 required `acl_snapshot_ref` 與 `permission_decision_ref`，確實綁定
  「這個 decision 基於哪個 ACL 快照」。我已據此改寫 F-02（事實改從
  anchor／envelope 各自的欄位讀，並檢查兩份紀錄談的是同一份證據）——**但
  那兩份紀錄仍是 caller 隨 run 提交的**，沒有地方可以「查」它們是否真實。

換句話說：**這一層能做到「提交的紀錄彼此自洽」，做不到「紀錄本身為真」**，
除非有一個可查的權威來源。那個來源目前不存在，且被禁止建立。

## FP-1：這個邊界怎麼處理？

- **(A)** **誠實記錄邊界 ＋ 示範性 fixture**。契約明寫：本層驗證的是提交紀錄
  之間是否自洽，**不驗證紀錄本身的真實性**；確保紀錄為真是呼叫端責任。
  再加一個 fixture，用一份自洽但偽造的 history 證明這個缺口是真的存在、
  不是假裝沒有。不新增任何儲存。
  **← CC 建議**。這正是你本 session 已經簽過的 FP-3-A 先例
  （`ai-work-record-hook.yaml` 的 `batch_scoping_rule` ＋
  `HOOK_CAP_POS_MIXED_TASK_REF_KNOWN_GAP` fixture）。
- **(B)** **授權建立最小權威紀錄**（retention history／decision receipt 的
  持久化）。這是真正的修法，但跨越 `FORBIDDEN_BY_DEFAULT` 的
  new ledger／registry，需要你像上次核准 runtime hook 那樣明示授權，
  並且會是一張獨立的大卡。
- **(C)** **縮小契約宣稱**：把 FP-1-A 的「解除回到原階段」與 FP-4-A 的
  「ACL 變更即 stale」降級為純語意定義，契約不宣稱能強制。比 (A) 更退一步，
  連缺口都不記錄，CC 不建議。

## 簽核方式

回一個字母。

## 目前分支狀態

`cc/permission-retention-deletion` 上已有 F-02 的改良（綁 anchor／envelope
的欄位而非 run 直述），**但沒有宣稱任何一筆 finding 已關閉**——等你裁決
FP-1 之後才決定怎麼收。
