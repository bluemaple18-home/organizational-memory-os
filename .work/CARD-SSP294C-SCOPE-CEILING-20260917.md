---
id: SSP294C-SCOPE-CEILING-20260917
status: ACCEPTED_GO
merged_commit: 2f9284b
type: implementation
tier: T1
jira: SSP-294（EMEM-05 Promotion）切片 C
parent_card: CARD-SSP294-PROMOTION-20260909
implements_spec_freeze: SSP294C-SCOPE-FREEZE-20260917
owner_signature: "FP-1: A / FP-2: A / FP-3: A（2026-09-17）"
sibling: CARD-SSP294A / CARD-SSP294B（皆 ACCEPTED_GO）
---

# SSP-294 切片 C — source ACL ceiling 的強制

👉 [假設與目標確認]
- 目標：把上游「source ACL 是天花板，個人記憶可收窄不可放寬」的規則變成真的
  會攔的 evaluator，取代目前只驗規則敘述文字裡有沒有 "cannot widen" 的斷言。
- 邊界：只做 ceiling。retention 傳遞（FP-1-A 裁定上游無宣告）另開 Owner 決策
  卡；與 `ai-work-record-boundary.promotion_path` 明確隔離（FP-2-A）。
- 驗收：見 Acceptance。

## FP-2-A 的落實：兩個 promotion 不是同一條路徑

`promotion_name_collision` 區塊明文區分：本契約治理
`actor_action_policy.PROMOTE`（個人 → 公司／共享可見範圍放寬），與
`ai-work-record-boundary.promotion_path`（證據 → 個人記憶紀錄的 6 步鏈）
無關。`hard_stops` 也明寫不得綁定後者。

## 沒有上游宣告的順序，從既有資料推導（不是發明）

上游只給每個 visibility scope 的 `default_readers`，沒給順序。用子集關係推導
「可證明的收窄」，過程中發現一件事：**`EMPLOYEE_AND_POLICY_SYSTEM` 與
`WORK_CONTEXT_PARTICIPANTS` 互不包含，兩者之間的移動無法判定方向**。

裁決：無法證明是收窄的一律當放寬處理——天花板規則要防的是放寬溜過去，
「可疑的收窄要求 receipt」的代價遠小於「可疑的放寬被放行」。

## Constraints

- 不重述上游 receipt／scope 名稱；不發明範圍順序。
- 不做 retention 傳遞（另卡）；不綁 `promotion_path`（FP-2-A）。
- 不建 identity／receipt store／writer。
- validator `< 400` 行。

## Acceptance

1. 可證明的收窄不需任何 receipt 或 gate。
2. 放寬（含無法比較的移動）必須備齊上游全部 `required_receipts`，且來源範圍
   宣告 `widening_requires_promotion_gate: true` 時必須帶 gate run 的 URN。
3. `REFUSED` 永遠可接受。
4. 上游新增 receipt／改動 gate 旗標／新增 scope → 本檔一行不改即反映，且
   「每個宣告需要 gate 的範圍都有對應負例」的覆蓋斷言擋住新範圍被漏測。
5. 逐 return site parity 全紅；既有 29 支 validator 不受影響。

## 已知邊界

`provenance_boundary` 承認三件本層驗不了的事：receipt 真實性、引用的 gate
run 是否真的通過（那是切片 A 的責任）、宣告的 `from_scope` 是否真是材料的
現行範圍。

## 大 review 記錄

- `61ba39b`：NO_GO，P1×1（FP-2-A 只有文字宣告，validator 沒真的禁止結構化
  binding；reviewer 塞 `promotion_path_ref` 進契約，兩條散文斷言照樣 PASS）
  + P2×2 residual（覆蓋斷言不分旗標值宣稱過寬／`from_scope == to_scope`
  語意未定義，皆非阻擋）。
- repair-01（`8e185c1`）：新增結構化掃描，契約結構裡任何字串整值符合
  `ai-work-record-boundary.promotion_path` 形狀即違規。
- 定點 re-review（`588c6f0`）：**GO**，P0=P1=0。reviewer 確認 repo 現有
  真正的 `promotion_path` binding 都是同一種 dot-pointer scalar 形狀，本次
  修補覆蓋實際契約慣例，不只是擋單一 exploit。

## Evidence

`.work/evidence/SSP294C-SCOPE-CEILING-20260917.md`
`.work/evidence/SSP294C-SCOPE-CEILING-REPAIR-01-20260917.md`
