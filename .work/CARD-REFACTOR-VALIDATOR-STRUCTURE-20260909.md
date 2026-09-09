---
id: REFACTOR-VALIDATOR-STRUCTURE-20260909
status: IMPLEMENTED_AWAITING_BIG_REVIEW
type: refactor
mode: REFACTOR_STRICT
lane: A+B（共用,兩 lane 匯流點）
---

> 進度（2026-09-09）：S01 = `7b9c714`；S02 = `f3bb423`（frozen review SHA）；S03 DEFER 至 backlog。
> 大 review `NO_GO`（1×P1 F-01：舊入口 coverage 縮窄）→ repair 01：舊檔名改 aggregator、
> EMEM-00 搬 `validate_personal_memory_scope_contract.rb`，舊命令補 5 條 mutation parity。
> repair 卡：`.work/CARD-REFACTOR-VALIDATOR-STRUCTURE-REPAIR-01-20260909.md`。待定點複審。
> evidence：`.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-20260909.md`。
> 大 review 交接卡：`.work/handoff/REFACTOR-VALIDATOR-STRUCTURE-REVIEW-20260909.md`。

# Repo-wide validator 結構 Refactor

👉 [假設與目標確認]
- 目標:讓 `scripts/*.rb` 全部符合 `.agentskills/docs/coding-standards.md` 第 2 節 hard limit(`< 400 行`),消除跨檔重複的 helper 樣板,並把 `draft_card_contract_valid?` 這種第二份實作收斂成單一來源。**功能與行為不變**,所有既有 gate 與 fixture 逐字保留。
- 邊界:不改任何 `規格/v0.1/*.yaml` / `*.schema.json` / fixtures 的內容語意;不改 evaluator 的判定邏輯與 failure code;不動 STD-01/02/03 的契約結構(僅可抽 helper)。
- 驗收:見下方 Acceptance;refactor 前後所有 validator 輸出逐字相同,mutation 探針行為不變。

## Root question

`.agentskills/docs/coding-standards.md`(知識庫 CLAUDE.md 明確採用)第 2 節:一般 `< 150`、複雜 `< 400`。目前 10 個 code 檔有 6 個超標(`validate_personal_memory_contract.rb` 1119、`std01` 557、`std02` 540、`std03` 429、`std_schema_engine.py` 436、`std00` 152),且 8 個 Ruby validator 各自複製 ~50–70 行相同 helper。如何在「行為不變」前提下拆到合規、抽共用,而不重開任何 `LOCKED_OWNER_ACCEPTED` 契約?

## Traces to

- `.agentskills/docs/coding-standards.md` §0(Dual-Mode:「檔案過大」→ Refactor Mode)、§2(hard limits)、§0.A.4 / §3(禁重複代碼 / 零廢棄)。
- `ai-core/rules/07-code-simplifier-protocol.md`(精煉範圍、抽象只在已證明可維護性時保留、跨模組先補薄 refactor plan)。
- `ai-core/rules/02·05-karpathy`(手術刀、功能不變、驗證閉環)。
- `文件/待辦重整.md` 第十節「規範債」。
- 2026-09-09 全 repo 掃描結果(session evidence)。

## Dependencies / Blockers / Current frontier

- Dependencies:6 張已 `ACCEPTED_GO` 的 slice —— Lane A `SSP-290/292/293`(branch `cc/ssp293-correction-supersession` 線性含全部)、Lane B `SSP-298/299/300`(branch `cc/ssp300-work-record-skill` 線性含全部)、kickoff branch 的 workflow doc / 待辦重整 / 卡片。
- **Blocker:需先把這三條 branch 匯流到一個整合 base**(見「整合前置」)。Owner 需授權 merge。
- Current frontier:`REFACTOR-S01`(helper 抽取)→ `REFACTOR-S02`(personal-memory 拆分)。

## 整合前置（需 Owner 決策）

三條 accepted branch 未 merge。Refactor 需要一個含全部 6 slice 的 base。選項:
- (a) merge `cc/ssp293-correction-supersession` + `cc/ssp300-work-record-skill` + `cc/dispatch-kickoff-20260907` → `main`(或 kickoff),Refactor 從整合後 head 分支。
- (b) 不動 main,建 `cc/integration-20260909` 做三方 merge,Refactor 從它分支;之後整包再議 merge。
- 衝突面預估:低。Lane A 只碰 `personal-memory` 三件 + 自己的卡;Lane B 全新檔;kickoff 只碰 docs/卡片。`待辦重整.md` 第十節是 kickoff-only 的乾淨 append。

## Scope

- `REFACTOR-S01`:`scripts/lib/omos_contract_helpers.rb` —— 抽出 `StrictJsonObject`、`DuplicateKeyError`、`assert_unique_yaml_mapping_keys`、`read_json`、`read_yaml`、`assert`、`present?`、`blank_string?`、`sorted_set`、`OMOS_URN` / `CARD_ID_URN` pattern 與 `omos_urn?` / `urn?` / `dig_dotted`。所有 validator(含 STD-00~03、cross-layer、personal-memory、ai-work-record-*)改 `require_relative "lib/omos_contract_helpers"`。逐字搬移,不改行為。
- `REFACTOR-S02`:`validate_personal_memory_contract.rb`(1119)拆:
  - 原檔留 EMEM-00/01(scope modes / ownership / actor_action_policy / resource contracts / backlog / request+resource fixtures)。
  - `validate_personal_capability_contract.rb` —— SSP-290 `capability_matrix` / `level_transitions` / `capability_safety_floor` + `capability_profile_failure` / `level_transition_failure` + capability fixtures。
  - `validate_recall_context_pack_contract.rb` —— SSP-292 `recall_context_pack.contract` + `context_pack_failure` + context-pack fixtures。
  - `validate_correction_flow_contract.rb` —— SSP-293 `correction_flow.contract` + `correction_proposal_failure` / `supersession_receipt_failure` + correction fixtures。
  - 每個新檔讀同一份 `personal-harness-integration.yaml` + 各自 fixture section;抽 helper 後每檔目標 `< 400`。
- `REFACTOR-S03`(選,若時間允許):`draft_card_contract_valid?`(SSP-300)改為 `require` SSP-299 的共用 record-shape helper(需先把 `task_card_record_failure` 的 shape 部分抽成 `scripts/lib/ai_task_card_shape.rb`)。若風險過高則留 backlog,維持現有「已標註的第二份實作 + parity 測試」。
- STD-01/02/03 + `std_schema_engine.py`:**只做 `REFACTOR-S01` 的 helper 抽取**,不拆結構(契約 `LOCKED_OWNER_ACCEPTED`)。
- 更新受影響 CI / 文件 / `待辦重整.md`。

## Constraints

- **行為不變**:refactor 前後每個 validator 的 stdout、exit code、failure code、fixture 判定逐字相同。
- 不改 yaml / schema / fixture 內容;不改 evaluator 邏輯與 code 名稱。
- 不新增 gem / package;`require_relative` only。
- STD-01/02/03 契約結構不動。
- 不 merge / push,除非 Owner 明示(整合前置與 refactor branch 的 push 需 Owner 授權)。

## Product fit

- Measured gap:6/10 code 檔違反專案採用的 `< 400` hard limit;~450 行跨檔重複 helper;SSP-300 review 抓到 drift 的第二份實作。這些是 session evidence,不是推測。
- Why not less:只拆最大那一個檔不夠 —— 重複 helper 跨 8 檔,不抽共用則每次改 helper 要改 8 處(已發生 drift)。
- Why not more:不重寫 evaluator、不改契約、不碰 STD 結構、不引入 framework。`draft_card` 共用化(S03)是 nice-to-have,可 backlog。
- Do not absorb:validation framework、DSL、schema-registry、任何 runtime。helper 就是一個 plain Ruby module。
- Rollback:每個 slice 一個 commit,可逐一 revert;helper module 刪掉、各檔把樣板貼回即還原。

## Acceptance

1. `scripts/lib/omos_contract_helpers.rb` 存在;所有 `scripts/validate_*.rb` `require_relative` 它,檔內不再有重複的 `StrictJsonObject` / `read_json` / `read_yaml` / `present?` / URN pattern 定義。
2. `validate_personal_memory_contract.rb` 拆成 4 檔,每檔 `< 400` 行(抽 helper 後)。
3. STD-01/02/03 + `std_schema_engine.py` 只少了重複 helper,契約結構與行為零改動。
4. **逐字比對**:refactor 前(base head)與 refactor 後,對每個 validator 跑一次,`diff` stdout 為空、exit code 相同;跑一輪本 session 記錄過的所有 mutation 探針,RED/GREEN 結果相同。
5. `ruby` 全部 validator + `uv run` schema engine + cross-layer + STD-00~03 + JSON/YAML parse + `git diff --check` 全 PASS。
6. `文件/待辦重整.md` 第十節「規範債」更新為已清;`.agentskills` §2 hard limit 全數符合(STD locked 檔以「僅 helper 抽取、結構拆分 backlog」註記)。
7. 走 Refactor Mode:refactor plan(問題 / 公共接口 / 依賴邊界 / 測試接縫 / 回退條件)已在本卡;獨立 review 可重現。

## Stop conditions

- 若 helper 抽取後任一 validator 行為改變(stdout / code 不同)→ 停,回退該檔,回報。
- 若 personal-memory 拆分需要動到 `personal-harness-integration.yaml` 或 fixture 語意 → 停,回 Owner(那不是 refactor,是契約變更)。
- 若 STD locked 檔的 helper 抽取碰到 `structural_relabel_probe` 等內嵌邏輯無法乾淨分離 → 該檔跳過 helper 抽取,只留 backlog 註記。

## Likely files

- `scripts/lib/omos_contract_helpers.rb`（新）
- `scripts/validate_personal_memory_contract.rb`（縮小）
- `scripts/validate_personal_capability_contract.rb` / `validate_recall_context_pack_contract.rb` / `validate_correction_flow_contract.rb`（新）
- `scripts/validate_std00_contract.rb` / `validate_std01_raw_evidence_contract.rb` / `validate_std02_source_anchor_contract.rb` / `validate_std03_normalized_document_contract.rb` / `validate_cc_cross_layer_contract.py`（去重複）
- `scripts/validate_ai_work_record_boundary_contract.rb` / `validate_ai_task_card_record_contract.rb` / `validate_ai_work_record_skill_contract.rb`（去重複）
- `文件/待辦重整.md`
- `.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-20260909.md`

## Evidence

`.work/evidence/REFACTOR-VALIDATOR-STRUCTURE-20260909.md`
