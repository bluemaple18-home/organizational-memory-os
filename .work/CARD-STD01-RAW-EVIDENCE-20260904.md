---
id: STD01-RAW-EVIDENCE-20260904
status: LOCKED_OWNER_ACCEPTED_20260904
type: implementation
---

# STD-01 RawEvidenceEnvelope v0.1

- Objective：依已鎖定 STD-00 建立 JSON Schema 2020-12、PDF／Markdown／Jira 正負 fixtures 與 deterministic contract validator。
- Traces to：`STD-01`；`文件/待辦補充-標準文件規格-20260828.md` 第 7 節；`文件/研究包A-RawEvidence身份時間序與溯源-20260828.md` 第 9～13 節。
- Dependencies：`STD-00 = LOCKED`；本卡為 current frontier。
- Scope：RawEvidenceEnvelope field-level schema、fixtures、validator、backlog/status、evidence。
- Constraints：不做 parser、Connector、DB、migration、Skill、Graph、Hook、Loop、Harness、Hermes、runtime 或 canonical write；不新增第二套 vocabulary；不 commit／push。
- Acceptance：封住 evidence identity、stable source tuple／aliases、event／delivery identity、source version union、four clocks、raw／optional canonical digest、payload ref／retention、ACL snapshot、optional transport、adapter／activity／lineage refs、availability／deletion；正向含 PDF／Markdown／Jira；負向含 redelivery mismatch、新 revision、同 bytes 不同來源、missing event id、單次 Jira 404、`COMPLETE != VERIFIED`；schema 與跨事件 semantics 均有 deterministic test；parse、validator、personal memory regression、`git diff --check` 全過；獨立 review 無 P0／P1。
- Evidence：`.work/evidence/STD01-RAW-EVIDENCE-20260904.md`。

## 最小設計邊界

1. `evidence_id` 使用 STD-00 UUIDv7／URN 語意；不得沿用 delivery ID。
2. Idempotency key 必須包含 tenant＋stable source identity＋source version／event semantics；payload digest 不得跨來源合併 identity。
3. Four clocks 不互相覆寫；UUID timestamp 不是 business event time。
4. `NOT_FOUND_UNCONFIRMED` 不得直接變 `SOURCE_DELETED`。
5. Raw digest 必填；canonical digest 只有可 canonicalize 時存在，非 I-JSON 必須 fail closed／留下 gap。
6. Transport／OpenLineage 只作 provenance；不得取得 Evidence identity、verification 或 canonical authority。

## 收尾 Snapshot｜2026-09-04

- Current state：Owner 已接受，`STD-01 = LOCKED_OWNER_ACCEPTED_20260904`。
- Review chain：首審 3 個 P1；Repair-01 後剩新 revision 重用舊 idempotency key；Repair-02 已修復，re-review GO，未解 P0／P1：無。
- Verification：Ruby syntax、STD-01／STD-00／personal-memory validators、STD-01 JSON parse、`git diff --check` 全通過。
- Remaining risk：本機沒有可用且免下載的 JSON Schema 2020-12 engine；目前只證明 schema 可解析、AST sanity 與 deterministic semantics，不宣稱標準 engine runtime validation。
- Next step：STD-02 Source Anchor profiles 已由本卡鎖版前置解鎖；STD-03 與 EMEM-02 仍由各自卡片與主線裁決。
- Limits：未做 parser、Connector、DB、migration、runtime、Skill、Hook、Loop、Harness、Hermes、canonical write；未 commit／push。

## Owner acceptance

- Owner 於 2026-09-04 指示依最新流程繼續；承接前一個明示 `STD-01` 鎖版點，`STD-01 v0.1` 接受並鎖版。
