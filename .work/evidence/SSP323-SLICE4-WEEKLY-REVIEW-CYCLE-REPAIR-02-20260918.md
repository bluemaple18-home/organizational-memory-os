# SSP-323 切片 4 — repair-02 evidence

日期：2026-09-18　branch：`cc/ssp323-weekly-review-cycle`

```
base            b1d40d7
repair-01       f945486
original_review 965c111（審的是 ca3b42e..f945486；965c111 只是 handoff SHA 補正）
repair_commit   （本次 commit，待 push 後補上）
```

## Reviewer NO_GO（2026-09-18，對 `f945486`）

```
P0=0 / P1=1 / P2=1 / P3=0
```

repair-01 的 3×P1 + 1×P2 原始 repro 全數確認關閉（reviewer 逐項重播
確認）。新發現：

**P1**：repair-01 的 allowlist 只鎖了 disposition 的**欄位名稱**，沒有鎖
`record_ref`／`promotion_ref` 這些欄位的**值形狀**——三個新 repro：

1. `record_ref = {"candidate_status":"ACCEPTED_FOR_RECORD",
   "weekly_work_summary":"secret"}` → `nil` / PASS
2. `record_ref = "not-a-record-ref"` → `nil` / PASS
3. `promotion_ref = {"weekly_work_summary":"secret"}`，兩次 retry 用
   相同 Hash → `nil` / PASS

這是 repair-01 那筆 P1（「item_dispositions 沒鎖 shape，直接打穿
Candidate/receipt 邊界」）的直接殘留，不是新開 scope——allowlist 擋住了
「多帶一個欄位」，但沒擋住「透過允許的欄位夾帶任意 payload」。

**P2**：`promotion_idempotency_key` 有、`promotion_ref` 缺席時目前放行
（語意不對稱，但 reviewer 明示沒有證明會造成 duplicate Promotion，本輪
不修，登 backlog）。

## 修法

`record_ref`／`promotion_ref`／`promotion_idempotency_key` 三個欄位的值
形狀全部鎖死，不接受 Hash／Array 等任意 payload：

- **`record_ref`**：跟 F-01 綁 `PersonalMemoryCandidate` id_template
  同樣的做法，改綁既有 `personal_memory_resource_contracts...id_
  templates.PersonalMemoryRecord`（`urn:omos:personal-memory:record:
  {uuidv7}`），取前綴，要求值必須是這個前綴開頭的字串。新錯誤碼
  `WRC_RECORD_REF_NOT_RECORD`。
- **`promotion_ref`**：沒有對應的上游 id_template 可綁（`personal_
  memory_resource_contracts` 沒有 Promotion 這個 resource kind），退而
  求其次要求它至少是合法的 omos URN（重用既有 `urn?` helper）。新錯誤碼
  `WRC_PROMOTION_REF_NOT_URN`。
- **`promotion_idempotency_key`**：沒有格式約定，至少要求非空字串
  （重用既有 `blank?` helper）。新錯誤碼 `WRC_PROMOTION_IDEMPOTENCY_
  KEY_NOT_STRING`。

三個檢查都寫成安全的短路判斷（先確認型別是 String 才呼叫
`start_with?`／傳進 `urn?`），不會對 Hash／Array 輸入拋例外。

## 重播 reviewer 的三個具體 exploit（對修好的程式碼）

```
Exploit A（record_ref 塞 Hash，夾帶 candidate_status/weekly_work_summary）：
  → WRC_RECORD_REF_NOT_RECORD（不再是 nil）

Exploit B（record_ref = "not-a-record-ref"）：
  → WRC_RECORD_REF_NOT_RECORD（不再是 nil）

Exploit C（promotion_ref 兩次 retry 都是相同的非 URN Hash）：
  → WRC_PROMOTION_REF_NOT_URN（不再是 nil）
```

三個變體全數確認關閉。

## 逐 return site parity（非逐 code）

`weekly_review_cycle_failure` 目前 25 個 return site（repair-01 後 22
個，本輪新增 `WRC_RECORD_REF_NOT_RECORD`／`WRC_PROMOTION_REF_NOT_URN`／
`WRC_PROMOTION_IDEMPOTENCY_KEY_NOT_STRING` 三個）。逐一中和、確認 RED、
還原、確認逐位元相同：25/25 全紅，未被測到：無。

## 接回總入口的實測

```
中和 WRC_RECORD_REF_NOT_RECORD 的 guard（本輪關鍵新增，直接對應 reviewer
的 Exploit A/B repro）：

直接呼叫新片   → 兩筆負例同時 FAIL（HASH_PAYLOAD／NOT_URN_STRING 都預期
                 deny 實際通過）
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣的 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_weekly_review_cycle_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## Fixture 變更

新增 4 筆負例：`WRC_NEG_RECORD_REF_HASH_PAYLOAD`／`WRC_NEG_RECORD_REF_
NOT_URN_STRING`（兩者都對應 `WRC_RECORD_REF_NOT_RECORD`，分別示範
Hash payload 與純非法字串兩種攻擊面）、`WRC_NEG_PROMOTION_REF_HASH_
PAYLOAD`（`WRC_PROMOTION_REF_NOT_URN`，複製 reviewer 的兩次 retry 相同
Hash 情境）、`WRC_NEG_PROMOTION_IDEMPOTENCY_KEY_HASH_PAYLOAD`
（`WRC_PROMOTION_IDEMPOTENCY_KEY_NOT_STRING`，同一種 shape-locking
防禦對第三個欄位的對稱覆蓋，雖然 reviewer 沒有直接示範這個變體，但屬於
同一類漏洞，一併鎖上避免下一輪又被找到）。

## P2（residual，未修）

`promotion_idempotency_key` 有、`promotion_ref` 缺席時目前放行（語意
不對稱）——已登 `文件/待辦重整.md` 的規範債 backlog，reviewer 明示沒有
證明會造成 duplicate Promotion，本輪不動。

## Gate

```
ruby scripts/validate_*.rb（34 支，含本片）→ 全部 PASS
4 支 Python schema engine                    → 環境缺 jsonschema 模組
                                                （pre-existing，未安裝
                                                venv，本輪未改動其涵蓋
                                                範圍）
git diff --check                              → clean
```

## 明確不在本輪範圍

- P2（promotion_idempotency_key 有、promotion_ref 缺席時放行）——已登
  backlog，reviewer 指示留 residual。
- 切片 1／2／3 的既有契約——完全未動。
