---
id: JIRA-ADAPTER-MAPPING-REPAIR-04-20260910
parent: JIRA-ADAPTER-MAPPING-20260909
prior_repairs: [REPAIR-01, REPAIR-02, REPAIR-03 — 20260910]
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #3 / EMEM-02 前置）
tier: T1
review_line: JIRA-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: 170da7f
repair_01_sha: 733a9e3
repair_02_sha: fb939c1
repair_03_sha: 3e18080
repair_delta: 3e18080..HEAD（cc/jira-adapter-mapping）
scope: 只收 F-02-R03（reconciliation version 完整驗證缺口）；F-01-F03-R02 identity binding 已 CLOSED，fractional / json pointer prefix / required identity 也保留 CLOSED，不重開
---

# Repair 04｜Jira Adapter Mapping（repo #3）

Repair 03 的再 review 結論為 **NO_GO（P0=0, P1=1, P2=0）** —— identity finding CLOSED，
剩 F-02-R03（reconciliation version 仍有 fail-open 路徑）。原 review SHA `170da7f`、
Repair 01/02/03（`733a9e3` / `fb939c1` / `3e18080`）皆不動；本修復是 `cc/jira-adapter-mapping`
上的新 commit。

## 收到的裁決（F-02-R03，P1）

定點 replay 找到的實際旁路：

- **A**：`current_version` 有提供但不是物件（字串／陣列），仍走 `else` 分支靜默 fallback 到
  projection 自身 `version_instant`。`if current_version.is_a?(Hash)` 把「沒提供」與「提供錯
  型別」當同一件事。
- **B**：`current_version` 未綁到實際投影 —— 把 `previous_version` 複製成 `current_version`
  並設 `decision: NOOP`，實際投影 / 完整 STD instance 不改，仍 PASS。驗證器比對的是自報的
  current version，不是這輪真正投影出的 current version。
- 相關缺口：刪掉 `decision` 可跳過已提供的 malformed `previous_version`；`decision: SKIP`
  不會被 enum 擋；reconciliation 的 `secondary_digest` 缺失或非合法 SHA256 也可能被接受。

## 修復內容（只收 F-02-R03）

### 1. supplied reconciliation version 一律 fail-closed 驗（與 decision 無關）

- 新 helper `reconciliation_version_problem(node)`（共用 lib）：
  - 非物件 → `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`
  - `value` 不可 parse 成 RFC3339 instant → `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`
  - `secondary_digest` 非 `^sha256:[0-9a-f]{64}$` → `JIRA_MAP_RECONCILIATION_VERSION_DIGEST_MALFORMED`（新 code）
- evaluator：`reconciliation.key?("previous_version")` / `.key?("current_version")` 時**無條件**
  跑 `reconciliation_version_problem`，不再包在 `if present?(decision)` 內。

### 2. current compound version 的唯一來源是實際 projection

- evaluator 移除 `parse_instant(current_version["value"]) || version_instant` 分支；current
  一律取當輪 `version_instant` / `version["secondary_digest"]`。
- 若 `reconciliation.current_version` 有提供，必須逐字等於實際 projected `source_version`
  （`value` 與 `secondary_digest`），否則 `JIRA_MAP_RECONCILIATION_CURRENT_VERSION_NOT_PROJECTED`
  （新 code）。

### 3. decision enum

- `present?(decision)` 時，`decision` 必須 ∈ `RECONCILIATION_DECISIONS = [NEW_EVIDENCE, NOOP]`，
  否則 `JIRA_MAP_RECONCILIATION_DECISION_UNKNOWN`（新 code）；`decision` 有值時
  `previous_version` 必填。

### 4. YAML / fixtures

- `reconciliation.rule` 改寫，明列 fail-closed 驗證、current = projected、decision enum。
- `error_contract` +3 code；`required_negative_fixtures` +5 label。
- 既有 3 個 reconciliation-version 負例（`VERSION_DECISION_MISMATCH` / `VERSION_DECISION_FRACTIONAL`
  / `COMPOUND_DIGEST_NOOP`）改寫為「current = projected、previous 帶合法 digest」形式，
  `expected_failure_code` 不變。
- 新 5 個負例：`CURRENT_VERSION_WRONG_TYPE`（字串）、`CURRENT_NOT_PROJECTED`（自報 current ≠
  projected）、`DECISION_UNKNOWN`（`SKIP`）、`VERSION_DIGEST_MALFORMED`（`sha256:zz`）、
  `MALFORMED_PREV_NO_DECISION`（無 decision + `value: "garbage"`）。
- positive `JIRA_MAP_POS_DESCRIPTION` 補 `decision: NEW_EVIDENCE` + `previous_version`（無
  `current_version`）作為「current 省略時以 projected 為準」的控制案例。

### 檔案大小

`scripts/validate_jira_adapter_mapping_contract.rb` 367 行（< 400）。
`reconciliation_version_problem` 在 `scripts/lib/omos_contract_helpers.rb`。

## 驗證（session evidence）

- `ruby scripts/validate_jira_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_jira_adapter_mapping_instances.py` →
  `PASS (positive_instances=6, instance_negatives=3)`
- 全 19 個 Ruby validator（含共用 lib 回歸）→ 全 PASS
- `validate_std_schema_engine.py` → `PASS`（STD01 12/12、STD02 16/16、STD03 9/9）
- `validate_cc_cross_layer_contract.py` → `PASS`
- 定點驗證 `reconciliation_version_problem`：string / array / nil →
  `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`（不 crash）；bad digest →
  `JIRA_MAP_RECONCILIATION_VERSION_DIGEST_MALFORMED`；valid → nil。
- enforcement parity（cp-based restore）：neutralize `CURRENT_VERSION_NOT_PROJECTED` /
  `DECISION_UNKNOWN` / `VERSION_DIGEST_MALFORMED`、以及把 `previous_version` 驗證重新包回
  `decision` 內 → 皆 RED。
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 只動 mapping yaml / validator / 兩份 mapping fixture + 共用 lib；未動任何
  `LOCKED_OWNER_ACCEPTED` schema。
- 沒新增 registry / FSM / package / runtime；新增 3 個 reconciliation-version error code；
  F-01（完整 STD instance gate）、F-01-F03-R02 identity binding、F-04、fractional / json
  pointer prefix / required identity 成果原封保留。

## 交付

- branch `cc/jira-adapter-mapping`，repair-04 commit 在 `3e18080` 之後。
- 針對性再 review 範圍：`3e18080..<repair-04 SHA>`（`170da7f` / `733a9e3` / `fb939c1` /
  `3e18080` 皆不動）。
