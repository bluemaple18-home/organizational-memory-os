---
id: SSP291-PERSONAL-EVIDENCE-PROFILE-20260911
status: AWAITING_BIG_REVIEW
type: implementation
jira: SSP-291（EMEM-02 Personal Evidence Profile / Source Mapping）
lane: A
tier: T1
---

# EMEM-02 Personal Evidence Profile（SSP-291）

👉 [假設與目標確認]
- 目標：把「不同角色來源不同，但必須輸出同一 RawEvidence contract」從散文變成**可驗契約**。
  定義 `EmployeeMemoryProfile` 作為個人層的**擷取准入閘門**：哪些來源對這位員工合法、
  需要什麼授權與告知、以及每個准入來源必須綁到哪一份已 merged 的 adapter mapping。
- 邊界：只封個人層 profile 與 source admission。不重定義 STD-01/02/03、不重定義兩份
  adapter mapping、不改 SSP-288/289/290 已鎖的 scope mode / ownership / capability 契約
  （一律 pointer 綁定，執行期讀取）。不做 connector、不做 ingestion runtime、不碰 EMEM-03+。
- 驗收：見 Acceptance。

## Objective

`規格/v0.1/personal-harness-integration.yaml` 已有 `employee_memory_profile_minimum`、
`source_profiles`、`role_profiles`、`phase_1_pilot`，但 **validator 完全沒有驗到它們**
（`grep source_profiles scripts/*.rb` 零命中）。因此目前：

- 任何來源都可以宣稱自己是個人記憶的來源，沒有 phase-1 / role 准入檢查。
- 沒有 connector grant / consent 或告知的 fail-closed 檢查。
- 「所有來源映射到同一 RawEvidence contract」沒有任何機器綁定 —— 兩份剛 merged 的
  adapter mapping 與個人層 profile 之間沒有連線。

本卡建立 `personal-evidence-profile` 契約 + 薄 validator，把上述變成 fail-closed。

## Root question

如何讓「這位員工的這筆擷取是否合法，以及它是否真的走了已鎖的 adapter mapping 落成同一份
RawEvidence」成為可驗契約，而不重定義任何上游？

## Traces to

- `規格/v0.1/personal-harness-integration.yaml`：`employee_memory_profile_minimum`、
  `phase_1_pilot.first_sources`、`role_profiles`、`capability_levels`、
  `employee_memory_scope_modes.modes`、`ownership_visibility_contract.ownership_modes`。
- `規格/v0.1/document-adapter-mapping.yaml`（repo #2，`ACCEPTED_GO` @ `ebeaab2`）：
  `raw_evidence_projection.source_system`。
- `規格/v0.1/jira-adapter-mapping.yaml`（repo #3，`ACCEPTED_GO` @ `0ac8c09`）：同上。
- `文件/待辦補充-個人知識庫Harness-20260830.md` §5；`文件/個人知識庫Harness提案查核與整合裁決-20260830.md` §EMEM-02。
- Requirement ID：`EMEM02-S01`。

## Dependencies / Blockers / Current frontier

- Dependencies：repo #2 / #3 adapter mapping 皆 `ACCEPTED_GO` + merged；SSP-288/289/290 已鎖。
- Blockers：無。
- Current frontier：`EMEM02-S01`。

## Scope

- 新 `規格/v0.1/personal-evidence-profile.yaml`：profile 必填結構、phase-1 來源准入、
  role 准入、connector grant / consent、capture scope、**source → adapter mapping 綁定**、
  policy ref 必填、authority floor、`error_contract`、`required_negative_fixtures`。
- 新 `scripts/validate_personal_evidence_profile_contract.rb`：結構斷言（值必須來自上游
  已鎖清單，執行期讀 3 份 YAML）+ 純函式 `evidence_profile_failure(capture, target)` evaluator。
- 新正負 fixtures。
- `文件/待辦重整.md` 狀態更新。

## Constraints

- 不重定義任何上游；所有清單執行期讀取，上游改動即失配（fail-closed）。
- validator 薄判斷、`< 400` 行；沿用 `scripts/lib/omos_contract_helpers.rb`；不新增 package。
- 不新增 registry / FSM / runtime。推 branch，不 merge。
- `error_contract` 必須逐字等於 evaluator 可回傳集合（吸取 SSP-302 TIGHTEN-F-01 的教訓，
  由原始碼掃描綁定，不用手寫清單互比）。

## Product fit

- Measured gap：上述三個區塊零 enforcement，且兩份 adapter mapping 與個人層之間無連線。
- Why not less：沒有准入閘門，Phase-1 pilot 無法證明「只擷取被授權的來源」。
- Why not more：不做 connector / ingestion runtime / EMEM-03 recall；不新增 role。
- Do not absorb：任何 connector SDK、Job Engine、Knowledge DB。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. profile 結構逐欄等於上游 `employee_memory_profile_minimum`（三組欄位）。
2. 來源准入：非 `phase_1_pilot.first_sources` → `EPROFILE_SOURCE_NOT_IN_PHASE_1`；
   不在該 `role_profile.likely_sources` → `EPROFILE_SOURCE_NOT_IN_ROLE_PROFILE`。
3. 授權與告知：缺該來源的 connector grant → `EPROFILE_NO_CONNECTOR_GRANT`；
   缺 `consent_or_notice_ref` → `EPROFILE_NO_CONSENT_OR_NOTICE`。
4. capture 必須落在宣告的 `capture_scope` 內 → `EPROFILE_OUTSIDE_CAPTURE_SCOPE`。
5. **adapter mapping 綁定**：每個准入來源必須指名 adapter mapping，且該擷取投影出的
   `source_identity.source_system` 必須等於那份 mapping YAML 執行期讀到的
   `raw_evidence_projection.source_system` → `EPROFILE_ADAPTER_MAPPING_MISMATCH`。
6. policy：`capability_level` ∈ 上游 `capability_levels`；`personal_scope_mode` ∈ 上游
   modes；`ownership_mode` ∈ 上游 ownership_modes；五個 `*_policy_ref` 皆非空。
7. authority floor：profile 不得帶公司 canonical 寫入或全公司搜尋權 → `EPROFILE_EXCEEDS_AUTHORITY`。
8. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
9. `error_contract` 由 evaluator 原始碼掃描綁定（改名任一 return 未同步宣告 → RED）。
10. 全 21 validator + schema engine + cross-layer + `git diff --check` 全 PASS。

## Stop conditions

- 若准入語意需要新增 role 或改動已鎖的 scope/ownership 契約 → 停，回 Owner。
- 若需要定義 connector 或 ingestion runtime 才能表達 → 停，回 Owner。

## Likely files

- `規格/v0.1/personal-evidence-profile.yaml`（新）
- `scripts/validate_personal_evidence_profile_contract.rb`（新）
- `規格/v0.1/fixtures/personal-evidence-profile-{positive,negative}-fixtures.json`（新）
- `文件/待辦重整.md`
- `.work/evidence/SSP291-PERSONAL-EVIDENCE-PROFILE-20260911.md`

## Evidence

`.work/evidence/SSP291-PERSONAL-EVIDENCE-PROFILE-20260911.md`
