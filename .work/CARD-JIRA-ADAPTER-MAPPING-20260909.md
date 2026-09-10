---
id: JIRA-ADAPTER-MAPPING-20260909
status: NO_GO_REPAIRED_04_AWAITING_TARGETED_REREVIEW
type: implementation
lane: A（repo 施工順序 #3 / EMEM-02 前置）
tier: T1
---

# Jira Adapter Mapping（repo #3）

👉 [假設與目標確認]
- 目標：定義一份 machine-readable 契約：Jira Cloud 實體（issue / comment / description /
  ADF 片段）如何**確定性地**映射成 `RawEvidenceEnvelope`（STD-01）+ `SourceAnchor`
  （STD-02，profile `JIRA_CLOUD_ENTITY_SEGMENT_V1`）。只封「Jira 來源 → 已鎖 schema 的
  欄位對映、compound version、webhook + reconciliation 語意」；不做 Jira connector、
  Rovo/API 實作、ingestion runtime。
- 邊界：不重定義 STD-01/02；不動 Document（repo #2 另卡）；不做 Permission/Retention/
  Deletion（repo #4）或 Canonical writer（repo #5）。可與 repo #2 並行。
- 驗收：見 Acceptance；正向 + fail-closed 負例通過，且能對一則真實 Jira issue + comment
  重建同一組 envelope + anchor。

## Objective

以 `規格/v0.1/raw-evidence-envelope.schema.json` 與
`規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json` 為對映目標，定義：

- `jira_entity_kinds`：`ISSUE` / `COMMENT` / `DESCRIPTION` / `ADF_SEGMENT`；每種的
  `source_identity`（cloud id + project + issue key + entity id）與 `source_version`
  （compound：`updated` timestamp + revision id + ADF hash）組成規則。
- `raw_evidence_projection`：Jira 欄位 → `RawEvidenceEnvelope` 必填欄位（`source_aliases`
  容許 issue key 變更、`chronology` 四時鐘可得子集、`transport_delivery` = webhook vs poll、
  `source_availability`、`payload` reference-only）。
- `source_anchor_projection`：`JIRA_CLOUD_ENTITY_SEGMENT_V1` 的 `profile_details` 確定性
  shape（stable entity id + ADF node path + codepoint segment）、`selectors` 組合、
  `quote` prefix/suffix、`resolution` 重解析（webhook miss → reconciliation poll）。
- `reconciliation`：webhook 漏事件時的補償規則（version 比對、gap detection），
  且 reconciliation 不改變 evidence identity。
- `hard_stops`：no connector / API client / runtime；pure mapping tables + thin validator；
  不重定義 STD 契約。

## Root question

如何讓「Jira Cloud 實體確定性地產出 STD-01/02 已鎖 schema 的實例、compound version 可比對、
webhook + reconciliation 不破壞 identity、可 fail-closed 驗」變成可驗契約，不重開已鎖 schema？

## Traces to

- `規格/v0.1/raw-evidence-envelope.schema.json`（STD-01，LOCKED）。
- `規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json`（STD-02 profile，LOCKED）。
- `文件/研究包B-PDF-Markdown-Jira-SourceAnchor-20260828.md`（`RESEARCH_COMPLETE`：Jira stable
  IDs、compound version、webhook + reconciliation）。
- `文件/待辦補充-標準文件規格-20260828.md` §1 施工順序 #3。
- 下游：`EMEM-02`（SSP-291）；repo #2 Document Adapter Mapping（共用組合慣例）。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `JIRA-ADAPTER-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：STD-01/02 = `LOCKED_OWNER_ACCEPTED`；pre-adapter hardening `COMPLETE_OWNER_ACCEPTED`。
- Blockers：無（可與 repo #2 並行）。
- Current frontier：`JIRA-ADAPTER-S01`。

## Scope

- 新 `規格/v0.1/jira-adapter-mapping.yaml`：上述 4 個 mapping 區塊。
- `scripts/validate_jira_adapter_mapping_contract.rb`（新薄 validator）：structural +
  純函式 `jira_mapping_failure(entity, projected)` evaluator，交叉讀 STD-01 + Jira anchor
  profile schema（pointer binding）。沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures（一則 issue + 一則 comment 的完整投影 + reconciliation 案例）。
- `文件/待辦重整.md` §八 / §十 狀態更新。

## Constraints

- 不重定義 STD-01/02；pointer 引用並交叉驗證。
- validator 只做薄判斷；不新增 registry / FSM / 狀態機引擎；不新增 package。推 branch，不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：STD-02 定義了 Jira anchor profile，但沒有把「Jira 實體如何確定性投影成
  envelope + anchor、webhook 漏事件如何補、compound version 如何比對」寫成可驗契約。
- Why not less：沒有 Mapping 契約，Jira ingestion 會各自解讀 profile schema，webhook
  reconciliation 語意分裂。
- Why not more：Jira connector、Rovo/REST client、webhook 收信 runtime 都不是本卡。
- Do not absorb：Jira platform、任何 HTTP client、WorkPool。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. `jira_entity_kinds` 剛好 `[ISSUE, COMMENT, DESCRIPTION, ADF_SEGMENT]`；每種
   `source_identity` / `source_version`（compound）組成規則明確且確定性。
2. `raw_evidence_projection`：投影欄位 ⊆ `raw-evidence-envelope.schema.json` properties；
   必填齊；`payload` reference；`source_aliases` 容許 issue key rename；`transport_delivery`
   標明 webhook / poll。
3. `source_anchor_projection`：`profile == JIRA_CLOUD_ENTITY_SEGMENT_V1`；`profile_details`
   shape 確定（stable id + ADF path + codepoint segment）；`resolution` 定義 reconciliation 重解析。
4. `reconciliation`：version gap detection 規則明確；reconciliation 不改 evidence identity。
5. 缺必填投影欄位 / 投影非目標 schema 欄位 / profile 不符 / reconciliation 改了 identity
   → 各自 exact failure code。
6. 正向：一則 issue + 一則 comment 各自產出 contract-valid envelope + anchor；一個
   reconciliation 案例（webhook miss → poll 補齊，identity 不變）→ allow。
7. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
8. `ruby scripts/validate_jira_adapter_mapping_contract.rb` + STD schema engine + STD-00~03 +
   cross-layer + personal-memory aggregator（regression）+ JSON/YAML parse +
   `git diff --check` 全 PASS。

## Stop conditions

- 若映射需要改 STD-01/02 任一已鎖 schema → 停，回 Owner。
- 若 compound version 比對或 reconciliation 無法用純函式 + 資料表表達 → 停，回 Owner。

## Likely files

- `規格/v0.1/jira-adapter-mapping.yaml`（新）
- `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json`（新）
- `scripts/validate_jira_adapter_mapping_contract.rb`（新）
- `文件/待辦重整.md`
- `.work/evidence/JIRA-ADAPTER-MAPPING-20260909.md`

## Evidence

`.work/evidence/JIRA-ADAPTER-MAPPING-20260909.md`
