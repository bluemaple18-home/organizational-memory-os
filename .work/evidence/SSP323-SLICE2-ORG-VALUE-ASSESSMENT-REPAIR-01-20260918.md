# SSP-323 切片 2 — repair-01 evidence

日期：2026-09-18　branch：`cc/ssp323-org-value-assessment`

```
base            f38e82c
original_review 80bce4c
repair_commit   71124da
delivery        0604b85   （branch HEAD，含本檔／handoff 文件；review 應以此為準）
```

## Reviewer NO_GO（2026-09-18，對 `80bce4c`）

```
P0=0 / P1=3 / P2=1 / P3=0
```

基線正常：32/32 Ruby validator PASS、aggregator parity 重播確認會同步
RED、`git diff --check` clean。

1. **P1**：`needs_org_followup=false` 可以把應輸出的 follow-up 靜默壓
   掉——`needs_org_followup` 仍是 caller 自報的 boolean，evaluator 只驗
   「宣告為 true 時」合不合法，caller 可以在條件全部成立時仍宣告
   `false`，直接通過。
2. **P1**：Owner 的「或」被實作成「且」——原文是「本人不知道答案 *或*
   缺外部 evidence，且組織價值仍高」，前一版把兩個條件錯寫成 AND，只要
   `missing_external_evidence=false` 就會拒絕合法 follow-up，即使本人確實
   無法回答、有 unresolved question、有合法 HIGH。
3. **P1**：Organizational Value Assessment 可以完全沒有 readable
   reasons——上游卡明寫「必須輸出可讀 reasons」，前一版只有 HIGH 才要求
   reasons，9 個構面全 LOW、完全不寫 `dimension_reasons` 仍會 PASS，退化成
   9 個裸 label。HIGH-only evidence requirement 保留，問題只在 reasons。
4. **P2**（residual，reviewer 明示不拿它擋這輪）：「結構性禁止」的宣稱比
   enforcement 大——只擋固定 top-level key，nested 或別名欄位不受影響。

Reviewer 對交付包四個設計問題的判定（全部維持不變，本輪未動）：九構面
全部評分可接受；LOW/MEDIUM 不強制 evidence 可接受；`suggested_expert`
維持 optional/null 可接受；unresolved question 存在性檢查已足夠，不需要
判內容品質。

Reviewer 結論：「repair-01 建議只收上面 3 個 P1；P2 可登 backlog。」

## 修法

### F-01：`needs_org_followup` 改為完全由 evaluator 推導

這正是切片 1 對 `category`／`disposition` 定下、卻在本卡漏套用的同一條
規則——分類結果不能是呼叫端自報的欄位。修法：

1. 新增 `FORBIDDEN_SELF_DECLARED_FIELDS = %w[needs_org_followup]`，run 裡
   出現這個欄位一律 `OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP` fail-closed
   拒絕（不留一個「夾帶了但被忽略」的殘留欄位——切片 1 的 P2 已經指出過
   這種殘留欄位的誤導風險，這裡直接用「禁止宣告」避免重蹈覆轍，而不是
   重演同一種殘留）。
2. 新增 `needs_org_followup?(run, high_dimensions)` 函式，只在
   `assessment_failure` 回傳 `nil` 之後才有意義呼叫，完全從
   `answer_provided`／`missing_external_evidence`／已通過佐證檢查的
   `high_dimensions` 三個原始訊號算出布林值，呼叫端無從干預。

### F-02：OR 不是 AND

`needs_org_followup?` 的推導條件改為：

```ruby
(answer_provided == false || missing_external_evidence == true) && high_dimensions.any?
```

`||` 取代原本的隱含 AND（原本兩個 `unless` guard 各自要求
`answer_provided == false` 與 `missing_external_evidence == true` 同時
成立才不擋，等同 AND）。

### F-03：reasons 從「只有 HIGH」改成「九個構面全部都要」

`assessment_failure` 新增一個對 `dimensions` 全量的迴圈，任何一個構面的
`dimension_reasons` 缺席或全為空白字串就 `OVA_DIMENSION_REASONS_
INCOMPLETE`。`dimension_evidence_refs` 的 HIGH-only 非空要求維持不變
（reviewer 明確保留這條）。

### 契約 YAML 同步修正

`規格/v0.1/personal-harness-integration.yaml` 的 `needs_org_followup`
區塊重寫：`purpose` 改為說明它是 evaluator 推導、不是 caller 宣告；新增
`derivation` 明確寫出「或」的 load-bearing 語意；`rating_derivation_and_
substantiation` 改為說明 reasons 對九個構面一視同仁，只有 evidence_ref
才是 HIGH-only。

## 重播 reviewer 的三個 exploit（對修好的程式碼）

```
Exploit 1（needs_org_followup=false 壓掉合法 follow-up）：
  assessment_failure: nil（run 本身合法）
  derived needs_org_followup?: true （條件成立時 evaluator 自己算出 true，
    caller 不再能提供這個欄位去壓掉它）
  舊攻擊方式（run 裡夾帶 needs_org_followup: false）：
    OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP（直接被結構性拒絕）

Exploit 2（OR 被實作成 AND）：
  answer_provided=false、missing_external_evidence=false（只有「不知道」
  成立，evidence 不缺）：
  assessment_failure: nil；derived needs_org_followup?: true
  （只要滿足其中一個條件即可，不再要求兩者都成立）

Exploit 3（九構面全 LOW、完全沒有 reasons）：
  assessment_failure: "OVA_DIMENSION_REASONS_INCOMPLETE"（不再是 nil）
```

三筆 P1 全數確認關閉。

## 逐 return site parity（非逐 code）

`assessment_failure` 目前 15 個 return site（repair 前 17 個：拿掉
`OVA_NEEDS_FOLLOWUP_NOT_BOOLEAN`／`OVA_FOLLOWUP_WHILE_ANSWERED`／
`OVA_FOLLOWUP_WITHOUT_MISSING_EVIDENCE`／`OVA_FOLLOWUP_WITHOUT_ORG_VALUE`
四個、新增 `OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP`／`OVA_DIMENSION_REASONS_
INCOMPLETE` 兩個）。逐一中和、確認 RED、還原、確認逐位元相同：15/15 全
紅，未被測到：無。

## 接回總入口的實測

```
中和 OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP 的 guard（本輪新增）：

直接呼叫新片   → FAIL OVA_NEG_SELF_DECLARED_FOLLOWUP 預期
                 OVA_FORBIDDEN_SELF_DECLARED_FOLLOWUP，實際
                 OVA_DIMENSION_RATINGS_INCOMPLETE
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_organizational_value_assessment_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## Fixture 變更

- 正例：全部改用完整九構面 `dimension_reasons`；移除 `needs_org_followup`
  輸入欄位，改為 `expected_needs_org_followup` 期望值。新增
  `OVA_POS_NEEDS_FOLLOWUP_MISSING_EVIDENCE_ONLY`（只靠
  `missing_external_evidence` 觸發，`answer_provided=true`），連同既有的
  `OVA_POS_NEEDS_FOLLOWUP_UNANSWERED_ONLY`（只靠 `answer_provided=false`
  觸發）一起證明 OR 的兩側都能單獨成立。
- 負例：新增 `OVA_NEG_SELF_DECLARED_FOLLOWUP`（F-01）、
  `OVA_NEG_DIMENSION_REASONS_MISSING`（F-03，reviewer 的原始 exploit）；
  移除三個已不可能觸發的舊負例（`OVA_NEG_FOLLOWUP_WHILE_ANSWERED`／
  `OVA_NEG_FOLLOWUP_WITHOUT_MISSING_EVIDENCE`／`OVA_NEG_FOLLOWUP_WITHOUT_
  ORG_VALUE`，其對應的 caller-自報檢查已整個移除）；其餘既有負例補齊
  九構面完整 `dimension_reasons` 以維持原本要測的失敗路徑可達。

## P2（residual，未修）

「結構性禁止」的宣稱比 enforcement 大（只擋 top-level 固定清單）——已登
`文件/待辦重整.md` 的規範債 backlog，依 reviewer 指示本輪不動。

## Gate

```
ruby scripts/validate_*.rb（32 支，含本片）→ 全部 PASS
4 支 Python schema engine                    → 環境缺 jsonschema 模組
                                                （pre-existing，未安裝
                                                venv，本輪未改動其涵蓋
                                                範圍）
git diff --check                              → clean
```

## 明確不在本輪範圍

- P2（結構性禁止宣稱過寬）——已登 backlog，reviewer 指示留 residual。
- 切片 3（platform-neutral local-first）、切片 4（weekly grill／batch
  UX／收尾）：與原卡相同，未變。
