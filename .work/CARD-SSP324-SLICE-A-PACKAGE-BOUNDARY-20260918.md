---
id: SSP324-SLICE-A-PACKAGE-BOUNDARY-20260918
status: READY
jira: SSP-324
parent_jira: SSP-286
related_jira: SSP-294, SSP-295, SSP-323
type: bounded-product-amendment
priority: MVP
authority: organizational-memory-os
primary_donor: ai-core
---

# SSP-324｜EMEM-10 切片 A：Package Boundary 與 Reverse-Access Boundary

## 目標

`.work/CARD-SSP324-MINIMAL-EVIDENCE-PACKAGE-20260917.md` 的第一片施工
切片（`SSP-324` 仍是一張卡，不增 Jira）：封包形狀、最小 evidence、
source anchor／provenance／hash／ACL、ownership／visibility／sensitivity／
redaction、`EMPLOYEE_PRIVATE` consent，以及「禁止 whole-store／reverse
access」。

同時收掉 `SSP-323` 切片 3 review 留下的 P2：`runtime_policy.
local_first_export_surface` 原本只是封閉列舉宣告，沒有任何機器
enforcement 說明 `minimal_evidence_package` 這個管道實際長什麼樣。

## Scope

1. `規格/v0.1/personal-harness-integration.yaml` 新增
   `minimal_evidence_package` 區塊：`access_boundary`（allowed/forbidden
   request kinds、allowed request fields）、`package_required_fields`
   （20 個）、`package_forbidden_fields`、governance binding rule、
   consent rule。
2. `scripts/validate_minimal_evidence_package_contract.rb`：驗證單位是
   一次「傳輸事件」（`access_request` + `package` 一起驗）——「公司只能
   拿到明確送出的封包」同時是封包形狀問題與取得路徑問題，只驗一半，
   另一半就是宣稱。
3. 接回 `scripts/validate_personal_memory_contract.rb` 聚合器。

## 不重述既有 authority（全部 pointer-bind）

- `ownership_visibility_contract.mode_definitions`：package 宣告
  `scope_mode`，其 `ownership_mode`／`visibility_scope` 必須等於上游對
  那個 mode 的定義；consent 是否必要也讀上游該 mode 的
  `consent_or_notice_required`，不把「EMPLOYEE_PRIVATE 才要 consent」
  寫死。
- `personal_memory_resource_contracts...id_templates.
  PersonalMemoryCandidate`：`candidate_ref` 必須是真正的 Candidate
  identity。
- `runtime_policy.local_first_export_surface`：結構性斷言
  `minimal_evidence_package` 確實在列舉內，本契約即其 enforcement。
- SSP-294 A/B/C（promotion gate／policy matrix／ACL ceiling）完全不動，
  本片只管封包本身，不決定能不能 promote。
- 不新增 DB／writer／workflow／registry／consent 系統。

## 不屬本卡（切片 B／C）

- 切片 B：immutable package／revision trace／dedup（綁 SSP-323 切片 1 的
  五態與既有 correction/supersession）。
- 切片 C：公司端使用邊界（只可 review/verification/audit，不得進正式
  Retrieval/Canonical）、`NEEDS_ORG_FOLLOWUP + suggested_expert=null`
  合法但無 canonical identity。
- 「公司端確實無 reverse-access path」的真實驗證留 `SSP-295` 真人 pilot；
  本片鎖的是契約層：request 詞彙裡結構性沒有 browse/search 的表達方式。
