# Evidence｜SSP-305 AIWR-08 端到端驗收與主管進度視圖

- 卡：`.work/CARD-SSP305-E2E-MANAGER-VIEW-20260909.md`
- Tier：T1（Lane B AIWR 線最後一張 / 匯流點）
- branch：`cc/ssp305-e2e-manager-view`（off `main` @ `b07353a`）
- lane：B

## 交付物

| 檔 | 說明 | 行數 |
|---|---|---|
| `規格/v0.1/ai-work-record-e2e-acceptance.yaml` | 端到端契約：e2e_trace / manager_view / status_completeness / memory_promotion_gate / reconstruction / authority / error_contract / cross_reference / hard_stops | 136 |
| `scripts/validate_ai_work_record_e2e_acceptance_contract.rb` | 薄 validator：結構斷言 + 純函式 `e2e_acceptance_failure(run, lifecycle_events)`；交叉讀 task-card-record／boundary／harness；沿用 `scripts/lib/omos_contract_helpers.rb` | 223 |
| `規格/v0.1/fixtures/ai-work-record-e2e-acceptance-positive-fixtures.json` | `e2e_acceptance_cases` ×2（DONE / CANCELLED-with-promoted-record） | — |
| `規格/v0.1/fixtures/ai-work-record-e2e-acceptance-negative-fixtures.json` | `e2e_acceptance_negative_cases` ×12，各單一 mutation + `expected_failure_code` + `covers_e2e_negative_fixture` | — |

檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator 223 < 400）。

## 契約重點（對應 Acceptance）

- **端到端 trace 完整性**：`lifecycle_trace[]` 每筆 `{event, evidence_receipt_ref}`；非空、
  第一個 event `start`、最後一個 ∈ `{complete, cancel}`、每個 event ∈
  `ai-task-card-record.lifecycle_event_to_status`（validator 執行期讀）→ 否則 `E2E_TRACE_INCOMPLETE`；
  `evidence_receipt_ref` 非 `urn:omos:` URN → `E2E_RECEIPT_NOT_REF`。
- **manager_view 投影邊界**：欄位集合剛好 `[objective, status, blockers, acceptance_summary,
  evidence_links]`；多欄 → `MANAGER_VIEW_LEAKS_FIELD`；`sensitive_content_copied: true` 或帶
  `raw_work_body` → `MANAGER_VIEW_LEAKS_CONTENT`；`evidence_links` 含非 URN →
  `MANAGER_VIEW_INLINE_CONTENT`。
- **狀態完整性**：`final_status ∈ [DONE, FAILED, CANCELLED, BLOCKED, HUMAN_INTERVENTION]`
  （否則 `E2E_INVALID_STATUS`）；trace 終止 event `complete` → `final_status` 必須 `DONE`、
  `cancel` → 必須 `CANCELLED`（否則 `E2E_STATUS_UNMAPPED`）。
- **記憶升格閘門**：`work_records[]` 任一筆 `personal_memory: true` 但缺 `candidate_ref` 或
  `acceptance_ref`（URN）→ `E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE`（對應六條 Truth
  Boundary 的「WorkRecord 只有經 Candidate／Acceptance 才可成 Personal Memory」）。
- **可重現**：`reconstructable_from_jira != true`、或 `manager_view` 缺非空 `status` /
  非空 `evidence_links` → `MANAGER_VIEW_NOT_RECONSTRUCTABLE`。
- **projection-only 不越權**：`authority.is_projection: true` / `performs_acceptance: false` /
  `is_canonical: false`；run 帶 `personal_acceptance_ref` / `canonical_write_receipt_ref` 等 4 個
  forbidden 欄位或宣稱越權 → `E2E_EXCEEDS_AUTHORITY`。
- **fail-loud**：`authority.error_behavior: FAIL_LOUD`（與 boundary `error_behavior_enum` 交叉鎖）；
  run 有 `error` 但 `ok != false` → `FAIL_SILENT`。
- **cross_reference**：`must_match` 四 pointer 字串 exact，引用目標
  （`lifecycle_event_to_status`、boundary `non_acceptance_authority.signals`、harness `schema_id`、
  boundary `error_behavior_enum`）存在。
- **runtime_independence: true**：fixtures 無 runtime-specific 欄位。

## 驗證

### gate 全綠（branch head）

```
18 Ruby validator（含 e2e-acceptance 本卡 + hermes-adapter/harness/loop/hook/skill/boundary/
task-card-record regression + personal-memory aggregator + STD-00~03 + 4 個 personal-memory
slice）  exit=0 PASS
std_schema_engine.py   PASS  coverage 12/12、16/16、9/9（不變）
validate_cc_cross_layer_contract.py   PASS
git diff --check   clean
```

### 負例 enforcement parity（移除 enforcement → gate 轉紅）

逐一 neutralize 每個 `return "<CODE>"`：`E2E_EXCEEDS_AUTHORITY`（forbidden fields）／`FAIL_SILENT`／
`E2E_TRACE_INCOMPLETE`（first==start）／`E2E_TRACE_INCOMPLETE`（terminal）／`E2E_RECEIPT_NOT_REF`／
`MANAGER_VIEW_LEAKS_FIELD`／`MANAGER_VIEW_LEAKS_CONTENT`／`MANAGER_VIEW_INLINE_CONTENT`／
`E2E_INVALID_STATUS`／`E2E_STATUS_UNMAPPED`／`E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE`／
`MANAGER_VIEW_NOT_RECONSTRUCTABLE` —— 全部移除後 `ruby scripts/validate_ai_work_record_e2e_acceptance_contract.rb`
exit 1（RED），還原後 `PASS`。12 個 enforcement 全數 load-bearing。

### DoD：端到端正向 + fail-closed 驗收

- 端到端正向：`E2E_POS_DONE`（`start → submit_review → complete`，每步 receipt URN，
  `manager_view` 五欄齊，`final_status: DONE`，`reconstructable_from_jira: true`，
  `work_records` 皆非 personal_memory）→ allow。
- 取消 + 已升格記錄：`E2E_POS_CANCELLED_WITH_PROMOTED_RECORD`（`start → block → cancel`，
  `final_status: CANCELLED`，一筆 `personal_memory: true` 帶完整 `candidate_ref` + `acceptance_ref`）→ allow。
- fail-closed：12 個負例覆蓋 trace 不以 start 起／未收在終止 event／receipt 非 URN／
  manager_view 多欄／帶敏感內容／evidence_link 非 URN／status 未對映／status 非法／
  WorkRecord 未經 acceptance 卻宣稱 personal memory／不可重現／帶 canonical write 欄位／fail-silent。
- 主管可從 Jira 重現：正向案 `manager_view` 帶非空 `status` + `evidence_links`（URN），
  `E2E_NEG_NOT_RECONSTRUCTABLE` 證明 `reconstructable_from_jira: false` 會被擋。

## Repair 01｜大 review NO_GO（4×P1 + 1×P2）

| finding | 修法 | fixture |
|---|---|---|
| F-01（P1）manager_view.status 未綁 final_status | evaluator 加 `E2E_MANAGER_STATUS_MISMATCH`（`view["status"] != final_status`） | `E2E_NEG_MANAGER_STATUS_MISMATCH` → `E2E_MANAGER_STATUS_MISMATCH` |
| F-02（P1）promotion gate 放寬 SSP-298 promotion_path | 要求完整 chain refs `[raw_evidence_ref, candidate_ref, verification_receipt_ref, personal_acceptance_ref, record_ref]` 皆 URN；結構斷言直接讀 boundary `promotion_path.ordered_steps` / `receipts_required` 對齊；`cross_reference` +2 pointer | `E2E_NEG_PROMOTION_CHAIN_INCOMPLETE` → `E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE`；正例改帶完整 5 refs |
| F-03（P1）FAILED/BLOCKED/HUMAN_INTERVENTION 無合法路徑 | `terminal_events` +`block`；`terminal_event_to_status` +`block: BLOCKED`；新 `unsubstantiated_outcome_statuses: [FAILED, HUMAN_INTERVENTION]`（trace 末非 complete + `outcome_evidence_ref` URN，否則 `E2E_UNSUBSTANTIATED_OUTCOME`）；結構斷言鎖「五 status 都有終止路徑」 | 正例 `E2E_POS_BLOCKED` / `E2E_POS_FAILED` / `E2E_POS_HUMAN_INTERVENTION`；負例 `E2E_NEG_UNSUBSTANTIATED_OUTCOME` |
| F-04（P1）is_projection 未 enforce | evaluator authority 段首 `return "E2E_EXCEEDS_AUTHORITY" unless run["is_projection"] == true` | `E2E_NEG_NOT_PROJECTION` → `E2E_EXCEEDS_AUTHORITY` |
| F-05（P2）無 transition replay | evaluator trace 段 replay `ai-task-card-record.allowed_status_transitions` → `E2E_TRACE_ILLEGAL_TRANSITION`；`cross_reference` +`allowed_transitions_from` | `E2E_NEG_ILLEGAL_TRANSITION`（`start → cancel → complete`）→ `E2E_TRACE_ILLEGAL_TRANSITION` |

- `required_negative_fixtures` / `EXPECTED_E2E_NEGATIVE_LABELS` 各 12 → 16；正例 2 → 5。
- enforcement parity 重跑：`E2E_MANAGER_STATUS_MISMATCH` / promotion 完整 chain（弱化→ candidate+acceptance）/
  `E2E_UNSUBSTANTIATED_OUTCOME` / `is_projection` 強制 / `E2E_TRACE_ILLEGAL_TRANSITION` /
  `E2E_STATUS_UNMAPPED`(regression) —— 逐一移除 → `ruby` exit 1（RED）；還原後 `PASS`。
- 行為 regression：18 Ruby validator + `std_schema_engine`（coverage 不變）+ cross-layer +
  `git diff --check` 全綠；上游 8 份契約未改動。validator 281 行（< 400）。
- repair 卡：`.work/CARD-SSP305-REPAIR-01-20260909.md`。原 frozen review SHA `54891cc` 不動。

## 上游契約未被改動

`git diff --name-status b07353a..HEAD` 僅新增 4 檔 + 卡 + evidence + 待辦重整；未碰
`ai-task-card-record.yaml`／`ai-work-record-boundary.yaml`／`ai-work-record-harness.yaml`／
`ai-work-record-{hook,loop,skill,hermes-adapter}.yaml` 或其 validator（`git diff --stat` 對這些檔為空）。
`lifecycle_events` 由執行期讀 `ai-task-card-record`,上游改動會自動失配。dup-key fail-closed 對
3 個新檔已跑（`StrictJsonObject` / `assert_unique_yaml_mapping_keys`，來自共用 lib）。

## Lane B（AIWR 線）DoD 判定

`SSP-298`～`SSP-305` 全部 `ACCEPTED_GO` 後,AIWR 自動化執行層契約鏈完整:邊界（298）→ 卡片
格式（299）→ Skill（300）→ Hook（301）→ Loop（302）→ Harness（303）→ Hermes Adapter（304）
→ 端到端驗收 + 主管視圖（305）。本卡大 review `GO` + merge 即 Lane B DoD 達成。
