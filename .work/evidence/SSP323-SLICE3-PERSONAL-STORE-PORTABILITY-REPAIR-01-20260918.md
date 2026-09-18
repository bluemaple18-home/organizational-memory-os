# SSP-323 切片 3 — repair-01 evidence

日期：2026-09-18　branch：`cc/ssp323-personal-store-portability`

```
base            b1885e7
original_review bfd97b7
repair_commit   （本次 commit，待 push 後補上）
```

## Reviewer NO_GO（2026-09-18，對 `bfd97b7`）

```
P0=0 / P1=1 / P2=1 / P3=0
```

1. **P1**：portability contract 沒有綁回既有 Personal Memory 權威
   schema——初版自己維護 `portable_fields`（`record_id`／`content_digest`／
   `evidence_refs`／`created_at`）四欄，跟 `PersonalMemoryRecord.required_
   fields` 真正的 `memory_kind`、實際 content、applicability、ownership／
   visibility、ACL、retention、status、supersession 等 load-bearing 語意
   完全脫鉤。實測兩 executor 這些真實欄位不同，`portability_failure`
   仍回 `nil`。第一個 positive fixture 用 `record_id: urn:...:candidate:1`
   這個既有 `PersonalMemoryCandidate.forbidden` 明文禁止的欄位名。
   `content_digest` 也沒有綁定既有 content，「內容 A／內容 B ＋ 同一自報
   digest」原本仍會通過。
2. **P2**（residual，reviewer 明示先列 backlog、不擋修復後 GO）：
   `local_first_export_surface` 本身是封閉列舉沒錯，但「因此公司只能拿到
   這兩種資料」的宣稱比 enforcement 大——validator 只確認這個 array 恰好
   兩項，沒有機器綁定 parent hard stop 的 continuous sync／reverse
   browse/search/pull。

其他判定（維持不變，本輪未動）：封閉列舉「新增第三型先紅」接受，不需
extensibility framework；`evidence_refs` 忽略順序的 set comparison 接受。

Reviewer 結論：「repair-01 只要收 P1：把 portability comparison 綁回既有
Candidate/Record authority，原本那些 ownership / visibility / content /
status drift exploit 轉 RED。P2 可留 backlog。」

## 修法

不再維護第二份核心語意清單。`portability_failure` 改成：

1. 呼叫端在投影裡宣告 `resource_kind`（`PersonalMemoryCandidate` 或
   `PersonalMemoryRecord`）與該 resource 的完整內容 `resource`。
2. evaluator 從 `personal_memory_resource_contracts.resources.<kind>` 這個
   既有權威 schema，在**評估當下**讀出真正的 `required_fields`／
   `forbidden`——不是抄一份、是每次都問上游。
3. 兩個投影必須宣告**同一個** `resource_kind`（`PORTABILITY_RESOURCE_
   KIND_MISMATCH`），且該 kind 必須是 `personal_memory_resource_
   contracts.resources` 裡真實存在的 kind（`PORTABILITY_UNKNOWN_
   RESOURCE_KIND`）。
4. 該 kind 的每一個 `required_fields`（用點號路徑逐段導航，例如
   `governance.ownership_mode`）必須在兩邊的 `resource` 都存在（key 本身
   存在，不是值非 null——`governance.supersedes` 這類欄位對全新 record
   合法為 null），且值相等（陣列用集合比對）。任一欄位缺席
   → `PORTABILITY_FIELD_MISSING`；任一欄位不相等 → `PORTABILITY_FIELD_
   MISMATCH`。
5. 該 kind `forbidden` 清單裡**真的是欄位名**的條目（用「是否出現在任一
   resource kind 的 required_fields 聯集裡」篩選，過濾掉
   `resource_kind=PERSONAL_MEMORY_RECORD`／`memory_kind in ...` 這種複合
   語意宣告，那不是本片職責）——出現在任一邊的 `resource` 就是
   `PORTABILITY_FORBIDDEN_FIELD_PRESENT`。這條直接關閉原始 P1 的具體
   repro（`record_id` 出現在 Candidate 投影）。
6. 契約結構斷言也同步改成綁定真實 `required_fields` 聯集：
   `executor_provenance_fields`（`executor_ref`／`executor_session_ref`）
   不得與任一 resource kind 的 `required_fields` 相交——這是「executor
   provenance 只能是補充 metadata」在契約層的機器邊界，取代原本比對兩份
   自報清單的做法。

## 重播 reviewer 指出的具體 exploit（對修好的程式碼）

```
Exploit 1（ownership/visibility 跨 executor drift）：
  governance.ownership_mode 從 EMPLOYEE_PRIVATE 改成 COMPANY_MANAGED_
  PERSONAL、visibility_scope 從 PERSONAL 改成 SHARED：
  → PORTABILITY_FIELD_MISMATCH（不再是 nil）

Exploit 2（同一個 digest 概念、真實內容不同）：
  content.statement_or_structured_content 兩邊完全不同文字：
  → PORTABILITY_FIELD_MISMATCH（不再是 nil；且新設計根本沒有
    content_digest 這個自報欄位可以繞過，直接比對真實 content）

Exploit 3（原始 P1 repro：record_id 混進 Candidate 投影）：
  Candidate 的 resource 裡多帶一個 record_id：
  → PORTABILITY_FORBIDDEN_FIELD_PRESENT
```

三個變體全數確認關閉。

## 逐 return site parity（非逐 code）

`portability_failure` 目前 9 個 return site（repair 前 5 個：拿掉舊的
`content_digest`／`portable_fields` 比對邏輯、新增
`PORTABILITY_UNKNOWN_RESOURCE_KIND`／`PORTABILITY_RESOURCE_KIND_
MISMATCH`／`PORTABILITY_RESOURCE_NOT_MAP`／`PORTABILITY_FORBIDDEN_
FIELD_PRESENT` 四個）。逐一中和、確認 RED、還原、確認逐位元相同：9/9
全紅，未被測到：無。

## 接回總入口的實測

```
中和 PORTABILITY_FORBIDDEN_FIELD_PRESENT 的 guard（本輪關鍵新增，直接
對應原始 P1 的具體 repro）：

直接呼叫新片   → FAIL PORTABILITY_NEG_FORBIDDEN_FIELD_PRESENT 預期
                 PORTABILITY_FORBIDDEN_FIELD_PRESENT，實際
                 PORTABILITY_FIELD_MISSING
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣兩個 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_personal_store_portability_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## Fixture 變更

- 正例全面重寫為新投影形狀（`resource_kind` + 完整 `resource`），兩筆：
  一筆 `PersonalMemoryCandidate`（19 個 required_fields 全部填滿）、一筆
  `PersonalMemoryRecord`（30 個 required_fields 全部填滿），證明機制對
  兩種 resource kind 都成立，不只是原本那四個自報欄位。`applies_to_refs`
  刻意在兩邊順序相反，延續證明集合比對不受順序影響。
- 負例新增 5 筆：`PORTABILITY_NEG_UNKNOWN_RESOURCE_KIND`／
  `PORTABILITY_NEG_RESOURCE_KIND_MISMATCH`／`PORTABILITY_NEG_RESOURCE_
  NOT_MAP`／`PORTABILITY_NEG_FORBIDDEN_FIELD_PRESENT`（原始 P1 repro）／
  `PORTABILITY_NEG_CONTENT_MISMATCH`（reviewer 點名的內容 drift）；
  `PORTABILITY_NEG_OWNERSHIP_MISMATCH`（reviewer 點名的 ownership
  drift）。既有 `PORTABILITY_NEG_FIELD_MISSING` 改用真實 Candidate
  required_fields（缺 `governance.acl_ref`）。

## P2（residual，未修）

`local_first_export_surface` 封閉列舉的宣稱比 enforcement 大（沒有機器
綁定 parent hard stop 的 continuous sync／reverse browse/search/pull）——
已登 `文件/待辦重整.md` 的規範債 backlog，依 reviewer 指示本輪不動。

## Gate

```
ruby scripts/validate_*.rb（33 支，含本片）→ 全部 PASS
4 支 Python schema engine                    → 環境缺 jsonschema 模組
                                                （pre-existing，未安裝
                                                venv，本輪未改動其涵蓋
                                                範圍）
git diff --check                              → clean
```

## 明確不在本輪範圍

- P2（`local_first_export_surface` 宣稱比 enforcement 大）——已登
  backlog，reviewer 指示留 residual。
- 切片 4（weekly grill／batch UX／收尾）：與原卡相同，未變。
