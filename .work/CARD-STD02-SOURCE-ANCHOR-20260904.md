---
id: STD02-SOURCE-ANCHOR-20260904
status: LOCKED_OWNER_ACCEPTED_20260904
type: implementation
---

# STD-02 SourceAnchor Profiles v0.1

- Objective：依已鎖定 STD-00／01 建立 Common SourceAnchor 與 `PDF_REGION_V1`、`MARKDOWN_TEXT_V1`、`JIRA_CLOUD_ENTITY_SEGMENT_V1` 可驗證契約。
- Traces to：`STD-02`；`文件/待辦補充-標準文件規格-20260828.md` 第 8 節；`文件/研究包B-PDF-Markdown-Jira-SourceAnchor-20260828.md` 第 3～10、19～20 節。
- Dependencies：`STD-00 = LOCKED`、`STD-01 = LOCKED_OWNER_ACCEPTED_20260904`。
- Scope：SourceAnchor JSON Schema 2020-12、三種 Phase-1 profiles、正負 fixtures、deterministic validator、backlog/status、evidence。
- Constraints：不做 parser、resolver runtime、Jira webhook／reconciliation實作、Connector、DB、migration、Skill、Hook、Loop、Harness、Hermes；Jira Data Center 不冒充 Cloud profile；不 commit／push。
- Acceptance：Common envelope 封住 anchor/evidence/source identity、source version／representation digest、selectors、quote／robust fallback、resolution、normalization；PDF 可定位 digest＋page＋normalized bbox＋char span＋quote；Markdown 可用 digest＋codepoint／line／heading＋quote relocation；Jira Cloud 用 cloud/entity numeric IDs＋field/JSON pointer＋text selector，key 只能 alias；ACL/access revoked、content changed、missing/ambiguous 狀態 fail closed；正負 fixtures 與 deterministic mutations 通過；STD-01／00／personal regression、parse、`git diff --check` 全綠；獨立 review 無 P0／P1。
- Evidence：`.work/evidence/STD02-SOURCE-ANCHOR-20260904.md`。

## 實作狀態｜2026-09-04

- 歷史狀態（鎖版前）：`STD-02 = READY_FOR_REVIEW`；當時 schema、正負 fixtures與 deterministic validator 已建立，等待獨立 review。
- 已同步前置：`STD-00 = LOCKED`、`STD-01 = LOCKED_OWNER_ACCEPTED_20260904`。

## 最小邊界

1. 以 LOCKED `common-vocabulary.yaml` 為準；不重開已鎖 vocabulary。
2. Anchor 只定位來源，不取得 Evidence／Knowledge／Verification authority。
3. Position selector 必須綁 representation digest；不得只靠 line number、issue key或模型摘要。
4. Resolution 至少支援 `EXACT_MATCH／RELOCATED／CONTENT_CHANGED／MISSING／ACCESS_REVOKED／AMBIGUOUS`；非 exact 不可假裝 exact support。
5. Quote 可採授權 plaintext 或 digest；不得用摘要取代 exact quote semantic。
6. Cloud／Data Center profile 分離；本卡只正式建立 Jira Cloud。

## Historical Blocked Snapshot｜2026-09-04

- Current state：`NO-GO`；strict chain 已使用 Repair-01／02 上限。
- Resolved：canonical schema URN `$ref`、RawEvidence ACL／availability 與 resolution truth table、PDF／Jira selector representation digest、實例 closed-object 檢查。
- Unresolved P1：`selectors` 為非陣列時，validator 記錄 type failure後仍呼叫 `each_with_index`，造成 `NoMethodError`；必須 fail closed並回傳結構化 failure code。
- Required repair：非陣列時停止 selector iteration；新增完整 base單一 type mutation負例與 isolation assertion。
- Historical limit：不得自動建立第三輪修復；當時 STD-02 不可標 GO／LOCKED，STD-03／EMEM-02 不解鎖。
- Owner override：Owner 已明確授權 Repair-03；此授權只涵蓋上述唯一 P1，不重置或擴大原驗收範圍。

## Final Acceptance｜2026-09-04

- Repair-03：`selectors` 非陣列由 `NoMethodError` 改為唯一結構化 `COMMON_ROOT_TYPE`；正式完整 base單一 mutation負例與 isolation assertion已加入。
- Independent re-review：GO；未解 P0／P1：無；合法 selector與非法 selector item路徑均無例外。
- Mainline gates：STD-02／01／00／personal validators、JSON／YAML parse、`git diff --check` 全通過。
- Historical current state：完成並等待 Owner review；當時 STD-02 尚未 `LOCKED`。
- Historical remaining risk：當時本機無標準 JSON Schema 2020-12 engine；目前已由 CC foundation engine gate 補齊。
- Limits：未做 parser、resolver runtime、Connector、DB、Skill、Hook、Loop、Harness、Hermes；未 commit／push。

## Owner lock｜2026-09-04

- Owner 接受 STD-02 DoD 後，`STD-02 = LOCKED_OWNER_ACCEPTED_20260904`。
- 標準 Draft 2020-12 engine、URN registry與跨層 Candidate→SupportLink→SourceAnchor→RawEvidence gate 的補充證據見 `.work/evidence/CC-SCHEMA-FOUNDATION-PREP-20260904.md`。
- `STD-03` 未啟動，狀態由真實 dependency 改為 `UNBLOCKED_NOT_STARTED_BY_STD_01_LOCK`；本卡不實作它。
