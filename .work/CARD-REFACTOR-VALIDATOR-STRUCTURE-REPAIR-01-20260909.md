---
id: REFACTOR-VALIDATOR-STRUCTURE-REPAIR-01-20260909
status: IMPLEMENTED_AWAITING_TARGETED_REREVIEW
type: refactor-repair
mode: REFACTOR_STRICT
parent_card: .work/CARD-REFACTOR-VALIDATOR-STRUCTURE-20260909.md
review_line: .work/handoff/REFACTOR-VALIDATOR-STRUCTURE-REVIEW-20260909.md
frozen_review_sha: f3bb423b03e18097ba21110b9a68144c57785414
---

# Repair 01｜validator 結構 Refactor 大 review NO_GO

## 帶回的 finding（1×P1）

| id | severity | 內容 |
|---|---|---|
| F-01 | P1 | S02 把 `validate_personal_memory_contract.rb` 拆成 5 個命令,但沒保留舊入口作 aggregator。base `9328828` 的 `ruby scripts/validate_personal_memory_contract.rb` 涵蓋 EMEM-00/01 + SSP-290/292/293 全部檢查;review SHA `f3bb423` 的同名檔只剩 EMEM-00,對 capability/resource/recall/correction 的 mutation 不再由這個既有命令檢出 → 仍只呼叫舊命令的 CI／開發者／下游流程會得到假綠。違反 `REFACTOR_STRICT`「所有既有 gate 保留 / 行為不變」。 |

reviewer 建議的最小修法:**不要重拆**;讓舊 `validate_personal_memory_contract.rb` 保留完整 gate
語意(aggregator / delegate),並對舊入口補每個 slice 的 mutation parity。

## 定點修法（同 branch `cc/refactor-validator-structure`,原 review SHA immutable）

1. `git mv scripts/validate_personal_memory_contract.rb scripts/validate_personal_memory_scope_contract.rb`
   —— EMEM-00 本體(scope modes / ownership_visibility_contract / actor_action_policy /
   backlog registry / policy fixtures)整份搬過去,只把成功字串改成
   `PASS personal memory scope contract validation`。邏輯、failure code、fixture 判定零改動。
2. 新的 `scripts/validate_personal_memory_contract.rb` = backward-compatible aggregator:
   `Open3.capture3` 依序、fail-closed 執行 5 個 slice validator
   (`scope` / `resource` / `capability` / `recall` / `correction`);全數 exit 0 才印出
   與 refactor 前**逐字相同**的 `PASS personal memory contract validation`;任一 slice
   非 0 → 轉發其 stdout/stderr + 一行 `FAIL personal memory contract validation :: slice ...`
   → `exit 1`。無新 gem,只 `require "open3"` / `require "rbconfig"`。
3. 文件:`文件/CC-Schema-Foundation-Contract-Decision-v0.1.md` claim→enforcement 表改成
   「aggregator + 5 個 slice(縮排列出)」;`文件/待辦重整.md` 規範債段補 repair 說明。

## 驗證（定點:只驗原 finding + 行為不變 regression）

### 原 finding 消除 —— 舊命令對 5 個 slice 的 mutation parity

對 `規格/v0.1/personal-harness-integration.yaml` 各做一個單點 mutation,跑
**舊命令** `ruby scripts/validate_personal_memory_contract.rb`,還原後再跑一次:

| slice | mutation | 舊命令結果 |
|---|---|---|
| scope（EMEM-00） | `legal_hold_overrides_delete_and_purge` true→false | `exit 1` · `FAIL legal hold 必須覆蓋 delete/purge` |
| resource（EMEM-01） | `MemoryConflictSet.forbidden_authority` 移除 `winner_selection` | `exit 1` · `FAIL MemoryConflictSet 必須禁止自行選 winner` |
| capability（SSP-290） | `capability_matrix.cumulative` true→false | `exit 1` · `FAIL capability_matrix.cumulative 必須為 true` |
| recall（SSP-292） | `recall_context_pack.permission_strategy` INTERSECTION→UNION | `exit 1` · `FAIL ...必須是 INTERSECTION` |
| correction（SSP-293） | `correction_flow.contract.immutable_receipt` true→false | `exit 1` · `FAIL ...immutable_receipt 必須為 true` |

還原後 `ruby scripts/validate_personal_memory_contract.rb` → `PASS personal memory contract validation` exit 0。
`規格/` yaml 以 backup-file 還原,`diff` 乾淨。

### 行為不變 regression

- aggregator stdout+exit 對 `/tmp/golden/validate_personal_memory_contract.out` **byte-identical**
  (`PASS personal memory contract validation` / exit 0 / stderr 空)。
- 其餘 7 個 base validator + cross-layer 仍 byte-identical;schema engine PASS、coverage 不變。
- 5 個 slice validator 各自 `ruby scripts/<slice>.rb` 直接跑皆 PASS。
- `git diff --check` 乾淨。

## 檔案

- `scripts/validate_personal_memory_contract.rb`（改寫為 aggregator,~48 行）
- `scripts/validate_personal_memory_scope_contract.rb`（rename 自舊檔 + 標題註解 + PASS 字串）
- `文件/CC-Schema-Foundation-Contract-Decision-v0.1.md`
- `文件/待辦重整.md`
- `.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-20260909.md`（append repair 段）
- `.work/CARD-REFACTOR-VALIDATOR-STRUCTURE-20260909.md`（status note）

## 給定點複審

- review line 不變:`.work/handoff/REFACTOR-VALIDATOR-STRUCTURE-REVIEW-20260909.md`。
- 原 frozen review SHA `f3bb423` 保持不動;repair 是同 branch 新 commit。
- 只需驗:(a) F-01 是否消除 —— 舊命令 `validate_personal_memory_contract.rb` 對搬出的
  4 個 slice(+scope)是否都因 mutation RED、還原後 GREEN;(b) aggregator 對 golden
  是否 byte-identical;(c) 有無新 regression(其餘 validator、cross-layer、schema engine)。
- 無 P0/P1 → 寫 `.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-REREVIEW-01-20260909.yaml` →
  Owner accept → merge `cc/refactor-validator-structure` → `main`。
