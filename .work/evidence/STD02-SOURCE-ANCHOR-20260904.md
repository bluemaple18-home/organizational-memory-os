---
id: STD02-SOURCE-ANCHOR-20260904-EVIDENCE
status: LOCKED_OWNER_ACCEPTED_20260904
type: implementation-evidence
---

# STD-02 SourceAnchor Profiles v0.1 證據｜2026-09-04

> Current truth：Owner 已接受 `STD-02` DoD，`STD-02 = LOCKED_OWNER_ACCEPTED_20260904`。以下 `READY_FOR_REVIEW`、`NO-GO` 與本機無 standard engine 的段落是鎖版前 historical evidence；standard engine 與跨層補充證據見 `.work/evidence/CC-SCHEMA-FOUNDATION-PREP-20260904.md`。

## 範圍與前置

- 前置已同步為 `STD-00 = LOCKED`、`STD-01 = LOCKED_OWNER_ACCEPTED_20260904`。
- 只建立 Common SourceAnchor、`PDF_REGION_V1`、`MARKDOWN_TEXT_V1`、`JIRA_CLOUD_ENTITY_SEGMENT_V1` schema、fixtures與 deterministic validator。
- 未做 parser、resolver、Connector、Jira webhook／reconciliation、DB、runtime、Skill、Hook、Loop、Harness、Hermes或 canonical write；未 commit／push。
- Historical state：`STD-02 = READY_FOR_REVIEW`，當時未把任務卡標為 COMPLETE。

## JSON Schema engine 邊界

本機沒有可用且不需下載的 JSON Schema 2020-12 engine。本卡交付標準 JSON Schema 2020-12，並以 JSON parse、schema AST sanity與無依賴 deterministic behavior validator驗證；不宣稱 fixtures 已由標準 engine runtime validation。

## TDD 證據

RED：先建立 validator 並執行，因六個 STD-02 artifacts 尚不存在而 fail：

```text
ruby scripts/validate_std02_source_anchor_contract.rb
STD-02 SourceAnchor validator FAIL
- MISSING_FILE: 規格/v0.1/source-anchor.schema.json
- MISSING_FILE: 規格/v0.1/source-anchor-pdf-region-v1.schema.json
- MISSING_FILE: 規格/v0.1/source-anchor-markdown-text-v1.schema.json
- MISSING_FILE: 規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json
- MISSING_FILE: 規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json
- MISSING_FILE: 規格/v0.1/fixtures/std-02-source-anchor-negative-fixtures.json
```

GREEN：完成 schema、fixtures與 validator 後，STD-02 validator通過。

## 契約與 fixtures 覆蓋

- Common envelope 封住 anchor／evidence reference、source identity／version、source payload與selector representation digest、selectors、quote、normalization、availability與 resolution。
- 每個正向 profile都交叉比對 STD-01 RawEvidence 的 evidence reference、source identity、source version、source payload、ACL snapshot、permission reference與 LOCKED digest basis。
- PDF：source payload digest 與 normalized page-text representation digest 分離；1-based page、top-left normalized bbox、Unicode codepoint half-open char range、`char_representation_ref`／digest綁定、exact quote。
- Markdown：representation digest、Unicode codepoint range、1-based line range、heading path與 quote relocation context。
- Jira Cloud：cloudId、numeric issue ID、issue key alias、ADF JSON Pointer、field_id-pointer binding、renderer profile/version與獨立 rendered ADF text digest；拒絕 Data Center混入。
- 21 個負例由完整正向 base fixture deep-copy後，以宣告的最小 mutation形成；每個 invalid anchor 都在 validator內由完整 base加上 declared mutation得出，並驗證 mutation isolation與單一預期 failure code。
- availability/resolution truth table：`AVAILABLE` 可為 `EXACT_MATCH／RELOCATED／CONTENT_CHANGED／MISSING／AMBIGUOUS`；`ACCESS_REVOKED` 只能為 `ACCESS_REVOKED`；`REPRESENTATION_UNAVAILABLE` 只能為 `REPRESENTATION_UNAVAILABLE`。SourceAnchor同時交叉比對 RawEvidence 的 source availability、ACL snapshot與permission decision ref，反向也不得把 AVAILABLE偽稱 revoked。
- 負例覆蓋 PDF bbox越界／反轉、page 0、缺 digest、char range；Markdown line-only、UTF-16、quote mismatch、relocation context；Jira key identity、cloudId、numeric ID、Data Center、RFC6901 pointer、field_id-pointer binding；以及 ACL／permission reference mismatch、AVAILABLE偽稱 revoked、摘要當 quote與 source/evidence reference mismatch。

## P1 Repair｜Source anchor binding／schema-equivalent gate

RED：審查指出三個 profile仍以相對 `$ref` 指向 common schema，且舊 deterministic gate未封住 schema-required／closed objects、RFC3339、media type、selector composition、RFC6901、field-pointer binding、RawEvidence availability/access交叉檢查及 rendered representation digest 分離。

GREEN：

- 三個 profile改以 `urn:omos:schema:source-anchor:0.1.0` 引用 common schema；validator AST逐一斷言 canonical URN。
- validator新增最小 schema-equivalent AST／行為 gate：common/profile required、closed object、types、RFC3339、IANA media type、selector enum與profile composition、RFC6901、Jira field_id-pointer binding。
- SourceAnchor新增 source payload ref/digest與access reference交叉檢查；PDF char selector必須綁 normalized page-text ref/digest；Jira text selector必須綁獨立 rendered ADF text ref/digest，並聲明 renderer profile/version。PDF/Jira rendered representation digest不得冒充RawEvidence source payload digest。
- 新增完整單一 mutation negative與 ACL／permission／field-pointer／反向 revoked 負例；每個負例仍必須沒有 unrelated failure。
- STD-01既有 status seam已同步為 `LOCKED_OWNER_ACCEPTED_20260904`：正負 fixture header與evidence status一致；schema沒有artifact status欄，未新增欄位或改變其契約語意。

## Repair-02｜Reviewer P1 instance structural validation

RED：以 reviewer probe 對完整 PDF positive anchor 的 `profile_details` 加入 `untrusted_extra: true`。修補前 direct deterministic validation 輸出 `REVIEWER_PROBE_RED_EXPECTED_FAIL_ACTUAL_PASS`，證明 AST-only gate沒有在實例層拒絕未知欄位。

GREEN：validator現在實際驗 common root、source identity／version、representation、access、quote、resolution、selector items，以及 PDF／Markdown／Jira 的 profile_details與各 nested object。每層均檢查 object type、required fields、closed object與欄位型別；未知欄位一律拒絕。

- 新增 `pdf-profile-details-untrusted-extra`：完整 PDF base加上一個 `profile_details.untrusted_extra` mutation，唯一失敗碼為 `PDF_REGION_V1_PROFILE_DETAILS_CLOSED`，沒有 unrelated failure。
- 移除先前的 static `invalid_anchor`；負例不再依賴預先寫死的 invalid payload。
- 修補後同一 reviewer probe精準輸出：`PDF_REGION_V1_PROFILE_DETAILS_CLOSED: PDF_REGION_V1_PROFILE_DETAILS 不得含未知欄位 untrusted_extra`。

## 驗證命令

```text
ruby -c scripts/validate_std02_source_anchor_contract.rb
ruby scripts/validate_std02_source_anchor_contract.rb
ruby scripts/validate_std01_raw_evidence_contract.rb
ruby scripts/validate_std00_contract.rb
ruby scripts/validate_personal_memory_contract.rb
ruby -e 'require "json"; Dir["規格/v0.1/source-anchor*.schema.json", "規格/v0.1/fixtures/std-02-*.json"].sort.each { |path| JSON.parse(File.read(path)) }'
ruby -e 'require "yaml"; YAML.safe_load(File.read("規格/v0.1/common-vocabulary.yaml"), permitted_classes: [], aliases: false)'
git diff --check
```

## 最終驗證結果

```text
Syntax OK
STD-02 SourceAnchor validator PASS
STD-01 RawEvidenceEnvelope validator PASS
STD-00 validator PASS
PASS personal memory contract validation
JSON PASS：2 fixtures、4 SourceAnchor schema
YAML PASS common-vocabulary
git diff --check PASS
```

P1 repair後重跑：`ruby -c scripts/validate_std02_source_anchor_contract.rb`、STD-02／01／00／personal validators、全部 JSON／YAML parse（15 files）、`git diff --check` 均通過；untracked text whitespace 檢查通過（28 text paths；10 binary/non-UTF-8 paths略過，含 `.DS_Store`）。

已知剩餘風險僅為標準 JSON Schema engine 在本機不可用，並已明示上述邊界；`STD-02` 仍等待獨立 review，不以本卡自行宣告 review acceptance。

## Repair-03｜selectors 型別防護

RED：以完整 `pdf-region-source-anchor` 正向 base deep-copy，只將 `selectors` 替換為字串 `TEXT_QUOTE`。修補前在 `validate_instance_structure` 的 `each_with_index` 拋出 `NoMethodError`，沒有結構化 failure。

排序假說：根因是 Common root 型別檢查雖先記錄 `COMMON_ROOT_TYPE`，後續仍假設 `selectors` 可迭代；先停止 instance selector iteration，並在結構檢查後停止後續 selector-dependent validation，才能保留單一、精準的 type failure。

GREEN：只在 validator 加入陣列 guard，並新增 `selectors-not-array` 正式負例。相同完整 base 的單一 mutation probe 現在輸出：

```text
PROBE_PASS selectors-not-array => COMMON_ROOT_TYPE
```

negative fixture isolation assertion 同時驗證該案例只產生 `COMMON_ROOT_TYPE`，無 unrelated failure。已確認沒有除錯標記。

Historical Repair-03 驗證：Ruby syntax、STD-02／01／00／personal validators、全部 JSON／YAML parse，以及 `git diff --check` 均通過。當時 STD-02 為 `READY_FOR_REVIEW`；任務卡未標 COMPLETE，未 commit／push。

## Repair-03 最終獨立複驗

- Reviewer 重跑完整 PDF base `selectors` 字串 probe：唯一回傳 `COMMON_ROOT_TYPE`，未發生 `NoMethodError`。
- 正式負例為完整 base的單一 mutation；isolation assertion通過。
- 合法 selectors無 failure；非法 selector item回傳結構化 failure，未拋例外。
- Final verdict：`GO_READY_FOR_OWNER_REVIEW`；未解 P0／P1：無。
