---
id: CC-SCHEMA-FOUNDATION-PREP-20260904-EVIDENCE
status: ACTIVE_VERIFIED_NOT_REVIEW_COMPLETE
---

# CC Schema Foundation 前置證據｜2026-09-04

## TDD

RED：Review-01 指出的三個可重現缺口仍存在：STD-01／02 negatives 未明示
authority／expected result，standard engine 只累計任一 rejection，且 cross
fixture 內嵌 canonical SourceAnchor。status probe 也找到 EMEM-02 與 STD-04
仍引用過期前置。

Repair：每一 STD-01／02 negative 現有 `validation_authority` 與
`expected_result: REJECT`；scenario 另逐 instance 明示 index／expected。標準
engine 逐 case fail-closed 並分開輸出 JSON_SCHEMA coverage 與不計入該
coverage 的 RUBY_SEMANTIC cases。跨層 fixture 僅保留 fixture refs；validator
從 STD-01／02 positives registry resolve canonical raw／anchor objects，才在
resolved deep-copy 上做帶 target 的 single mutation。

主線在核准環境重跑 PEP 723 standard engine 的 RED：
`single-jira-404-marked-source-deleted` 與
`permission-revoked-classified-as-deleted` 不被 JSON Schema 拒絕。兩例分別
需要 deletion confirmation 與 permission decision 的跨狀態／來源證據判定，
不是欄位 schema constraint；本 Repair-01 將兩例改列 `RUBY_SEMANTIC`，保留
既有 Ruby expected failure／isolation，未為通過 engine gate 增加不合理 schema
conditional。

## 標準 engine receipt

```text
UV_CACHE_DIR=/tmp/cc-schema-foundation-uv \
  uv run --script scripts/validate_std_schema_engine.py
```

- script PEP 723 pin：`jsonschema==4.25.1`；以 five schema `$id` 建立 URN
  registry。
- 本 sandbox 於 2026-09-04 兩次執行（standard engine 與 cross-layer）皆在
  `system-configuration` 建立 NULL object 時 panic，未產生 validator result；
  此為 sandbox execution 歷史，不以 Ruby PASS 替代 standard engine gate。
- 主線在核准 external host 以同一 PEP 723 command 重跑後 PASS：
  `STD01 JSON_SCHEMA coverage: 10/10`、
  `STD01 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 11`、
  `STD02 JSON_SCHEMA coverage: 12/12`、
  `STD02 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 10`。

## 跨層 receipt

cross-layer PEP 723 script 無依賴但仍使用 `uv run --script`。base fixture
以 `raw_evidence_fixture_ref` 與 `anchor_fixture_ref` 指向 STD-01／02
positives，不再內嵌 canonical anchor；八個 original negative categories 均
指定 `candidate`／`support`／`anchor` target與 path。

主線在核准 external host 以同一 PEP 723 command 重跑 PASS：
`CC cross-layer validator PASS`、`resolved registry: STD01 RawEvidence + STD02
SourceAnchor`，以及 `negative cases rejected: 8`。

## 本機 verification receipt

```text
PASS ruby scripts/validate_std00_contract.rb
PASS ruby scripts/validate_std01_raw_evidence_contract.rb
PASS ruby scripts/validate_std02_source_anchor_contract.rb
PASS ruby scripts/validate_personal_memory_contract.rb
PASS JSON fixtures parse (jq empty)
PASS personal-harness YAML parse
PASS Ruby syntax (three Ruby validators)
PASS scoped git diff --check
PASS scoped untracked whitespace scan
PASS external-host standard-engine uv run --script
PASS external-host cross-layer uv run --script
```

Repair-01 follow-up local rerun：`ruby scripts/validate_std01_raw_evidence_contract.rb`、
`ruby scripts/validate_std02_source_anchor_contract.rb`、STD-01 negative JSON parse、
STD-01 Ruby syntax 與 scoped `git diff --check` 均 PASS。sandbox 先前已對兩個
`uv run --script` gates 觸發同一 panic；依 failure limit 未重試第三次，交由
主線用核准 external host 重跑後已 PASS。

## Repair-02：RUBY_SEMANTIC schema 前置閘門

Review-02 RED：fixture 雖已區分 `JSON_SCHEMA` 與 `RUBY_SEMANTIC`，但 reviewer
要求不能只靠 authority metadata 排除 schema coverage；每個 semantic negative
都必須先由 Draft 2020-12 engine 證明 schema 接受，才能交給 Ruby semantic
validator 拒絕。

Repair-02 保留原 RED 歷史並補強可執行契約：STD-01 的 11 個
`RUBY_SEMANTIC` cases（包含 5 個雙-envelope scenarios 與 6 個
`invalid_envelope` cases）及 STD-02 的 10 個 `RUBY_SEMANTIC` mutation cases
皆明示 `schema_expected_result: ALLOW`。`validate_std_schema_engine.py` 會逐一建立
實際 instance、用 Draft 2020-12 validator 執行；任一 instance 被 schema 拒絕即
以 `STD01_RUBY_SEMANTIC_SCHEMA_REJECTED` 或
`STD02_RUBY_SEMANTIC_SCHEMA_REJECTED` fail-closed，只有全部 schema-allowed 的
case 才列入「schema-allowed then excluded from schema rejection coverage」。

2026-09-04 核准 external host receipt：

```text
$ UV_CACHE_DIR=/tmp/cc-schema-foundation-uv \
    uv run --script scripts/validate_std_schema_engine.py
STD schema engine validator PASS
STD01 JSON_SCHEMA coverage: 10/10
STD01 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 11
STD02 JSON_SCHEMA coverage: 12/12
STD02 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 10

$ UV_CACHE_DIR=/tmp/cc-schema-foundation-uv \
    uv run --script scripts/validate_std_schema_engine.py --probe-structural-relabel
STD schema engine validator FAIL
FAIL STD01_RUBY_SEMANTIC_SCHEMA_REJECTED:missing-raw-digest:0
exit 1 (expected)
```

mutation probe 將結構性 `missing-raw-digest` 從 `JSON_SCHEMA` 重標為
`RUBY_SEMANTIC` 並補 `schema_expected_result: ALLOW`；因 Draft 2020-12 schema
仍拒絕該 instance，validator 如預期非零退出，證明 metadata 無法繞過 schema
前置閘門。sandbox 內 `uv` 仍因既有 `system-configuration` NULL object panic；
本 receipt 來自同一 command 的核准 external-host 執行。

Repair-02 final rerun：STD-01／STD-02 Ruby validators、兩份 negative fixture
JSON parse、Python／Ruby syntax、CC cross-layer validator、fixture metadata
全量 assertion、`git diff --check` 與 scope 檔案 trailing-whitespace scan 均
PASS。mutation probe 的 exit 1 是預期 acceptance signal，不是未解決失敗。

## Repair-03：控制文件一致性

Review-03 RED：canonical backlog 仍把已接受的 STD-01 Raw Evidence 標為
`PARTIAL`／`FIRST FRONTIER` 並列為第一施工項；decision 同時保留「至少一個
schema-level negative」的弱條款，與逐 case fail-closed 的 executable gate
不一致。

Repair-03 僅同步控制文件：backlog 將 STD-01 改為
`LOCKED_OWNER_ACCEPTED_20260904`，並明示 STD-01／02 均已鎖定；下一施工項改為
尚未施工的 `STD-03 NormalizedDocument block subset`。decision 移除「至少一個」
條款，唯一要求每個 `JSON_SCHEMA` case 都由 Draft 2020-12 engine 拒絕，任一
未拒絕或缺 instance 即 fail-closed；每個 `RUBY_SEMANTIC` case 也必須先經同一
engine 實際 ALLOW，才可排除 schema rejection coverage 並交 Ruby semantic
validator。未宣稱 STD-03 已施工。

Repair-03 verification：限定三個控制文件的 `rg` consistency probe PASS；
decision 已無現行「至少一個 schema-level negative」條款，backlog 已無 Raw
Evidence 的現行 `PARTIAL`／`FIRST FRONTIER`／第一施工項殘留，且 STD-03 僅標為
下一施工項與尚未施工。`git diff --check` 與三檔 trailing-whitespace scan PASS。

## Lock 與範圍

- `STD-00 = LOCKED`
- `STD-01 = LOCKED_OWNER_ACCEPTED_20260904`
- `STD-02 = LOCKED_OWNER_ACCEPTED_20260904`
- `STD-03 = UNBLOCKED_NOT_STARTED_BY_STD_01_LOCK`；未施工。
- `STD-04 = UNBLOCKED_NOT_STARTED_BY_STD_01_LOCK`；未施工。
- `EMEM-02 = BLOCKED_BY_STD_03_NORMALIZED_DOCUMENT`；STD-00／01／02 前置已滿足。
- Canonical Direct-Write Audit 仍 pending，未納入本 review substrate。
- 未做 STD-03、runtime、Connector、DB、Hook、Loop、Harness、Hermes；未
  commit／push。

## 外部 CC handoff boundary

外部 CLI reviewer 僅可讀 fixed commit／allowlisted snapshot，回傳結構化
stdout／receipt；不得取得 working-tree 寫入權。commit SHA、allowlist與
blob digest 必須由 Mainline commit 後填入
`文件/CC-Schema-Foundation-Contract-Decision-v0.1.md` 的模板，未預填。
