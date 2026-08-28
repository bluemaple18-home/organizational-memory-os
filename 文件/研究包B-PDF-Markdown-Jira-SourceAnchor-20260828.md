# 研究包 B｜PDF／Markdown／Jira Source Anchor 與 Adapter Mapping

日期：2026-08-28

狀態：`RESEARCH_COMPLETE / DRAFT_INPUT / NOT_CANONICAL / NO_IMPLEMENTATION_AUTHORIZATION`

對應主線：

```text
STD-02 Source Anchor Profiles
STD-03 NormalizedDocument Block Subset
Document Adapter Mapping
Jira Adapter Mapping
Permission / Retention / Deletion Contract
```

本研究包回答：

> 一個 Knowledge Assertion／Procedure Step 要如何精確指回 PDF、Markdown或 Jira的來源區段？來源版本、刪除、權限與 webhook不完整性要如何進 contract？

---

## 1. 結論

Source Anchor不能只有：

```text
source: handbook.pdf
page: 7
```

正式 anchor應是：

```text
Source identity
+ Source version / representation digest
+ Source-specific selector
+ Robust fallback selector
+ Resolution status
```

三個 Phase-1 profiles：

```text
PDF_REGION_V1
MARKDOWN_TEXT_V1
JIRA_CLOUD_ENTITY_SEGMENT_V1
```

Cloud與Data Center必須分開：

```text
JIRA_CLOUD_V3
!=
JIRA_DATA_CENTER_V2
```

Webhook只作低延遲 observation：

```text
Webhook
!= Complete Source History
!= Deletion Truth
!= Permission Truth
```

---

## 2. Exact sources / pins

### 2.1 Web Annotation Data Model

```text
Standard: W3C Web Annotation Data Model
Status: W3C Recommendation
Published: 2017-02-23
```

Primary source：

- https://www.w3.org/TR/annotation-model/

Relevant selectors：

```text
TextQuoteSelector
TextPositionSelector
DataPositionSelector
SvgSelector
State
```

### 2.2 Docling Core

```text
Repository: docling-project/docling-core
Pinned commit: dedc35da4c99e3ae597423358e5648eb29ee3cad
License: MIT
Primary classes:
- DoclingDocument
- ProvenanceItem
- BoundingBox
- CharSpan
- PageItem
```

Primary sources：

- https://github.com/docling-project/docling-core/blob/dedc35da4c99e3ae597423358e5648eb29ee3cad/docling_core/types/doc/common/reference.py
- https://github.com/docling-project/docling-core/blob/dedc35da4c99e3ae597423358e5648eb29ee3cad/docling_core/types/doc/base.py

### 2.3 Jira Cloud

Primary official sources：

- Issues REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/
- Issue comments REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-comments/
- Issue attachments REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-attachments/
- Issue worklogs REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-worklogs/
- Issue changelogs REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-changelog-get
- Jira Cloud webhooks: https://developer.atlassian.com/cloud/jira/platform/webhooks/

Known official Atlassian defects / limitations：

- Project deletion does not emit per-issue `jira:issue_deleted`: https://jira.atlassian.com/browse/JRACLOUD-80809
- JQL-filtered webhooks may not fire for `issue_deleted`: https://jira.atlassian.com/browse/JRACLOUD-68414
- JQL behavior for comment/worklog webhooks has known limitations: https://jira.atlassian.com/browse/JRACLOUD-59980

### 2.4 Jira Data Center

Primary official source：

- https://developer.atlassian.com/server/jira/platform/webhooks/

Data Center adapter施工時必須另 pin：

```text
exact Jira major/minor version
REST API version
webhook behavior
user identity model
ADF vs rendered/plain body behavior
```

---

## 3. Common `SourceAnchor` envelope

```json
{
  "anchor_id": "urn:uuid:...",
  "evidence_ref": "urn:uuid:...",
  "source_identity_ref": "source-identity://...",
  "source_version_ref": "source-version://...",
  "profile": "PDF_REGION_V1",
  "representation": {
    "representation_ref": "representation://...",
    "media_type": "application/pdf",
    "content_digest": "sha256:..."
  },
  "selectors": [],
  "quote": null,
  "resolution": {
    "status": "EXACT_MATCH",
    "resolved_at": "...",
    "resolver_version": "..."
  }
}
```

### 3.1 Resolution status

```text
EXACT_MATCH
RELOCATED
CONTENT_CHANGED
MISSING
ACCESS_REVOKED
REPRESENTATION_UNAVAILABLE
AMBIGUOUS
NOT_CHECKED
```

`RELOCATED` 表示來源內容仍可由 quote／hash找回，但 position改變。

### 3.2 Selector composition

一個 anchor可以同時帶：

```text
position selector
+ quote selector
+ region selector
+ block selector
+ representation digest
```

越重要的 assertion越不應只依賴單一脆弱 selector。

---

## 4. Text selector semantics

### 4.1 TextQuoteSelector

建議保存：

```json
{
  "selector_type": "TEXT_QUOTE",
  "exact": "查詢員工薪資前必須先完成權限檢查。",
  "prefix": "安全要求：",
  "suffix": "不得先搜尋全公司資料。",
  "normalization_profile": "OMOS_TEXT_NORM_V1"
}
```

規則：

- `exact` 必須是實際被選取的文字。
- `prefix`／`suffix` 用於來源變更後重新定位。
- 不要以 summary或模型改寫文字當 quote。
- quote可以保存 digest以減少敏感內容長期暴露；但 reviewer view需要可授權取得原文。

### 4.2 TextPositionSelector

```json
{
  "selector_type": "TEXT_POSITION",
  "start": 412,
  "end": 795,
  "unit": "UNICODE_CODE_POINT",
  "range_semantics": "START_INCLUSIVE_END_EXCLUSIVE"
}
```

規則：

- position從 0開始。
- `start` included，`end` excluded。
- 計算位置時必須使用與 quote相同的 normalization profile。
- JavaScript UTF-16 code units不得假裝是 Unicode code points。
- Position很脆弱，必須搭配 representation digest和quote或State。

### 4.3 DataPositionSelector

適用：

```text
binary attachment member
byte range
forensic evidence
raw source payload segment
```

語意：0-based byte range，start included／end excluded。

不能拿 byte offset指向經 parser重排過的 normalized text。

---

## 5. Text normalization profile

Phase-1 建議固定：

```text
OMOS_TEXT_NORM_V1
```

最小規則：

1. Decode為 Unicode string；encoding與decode warning記入 ExtractionReceipt。
2. Line ending統一為 `\n`。
3. 不自動做 Unicode NFC／NFKC；來源字元保持不變。
4. 不自動 trim所有空白；parser-specific cleanup必須有 version。
5. 移除 invisible／bidi control時必須留下 sanitization receipt與位置映射。
6. Text position以 Unicode code point計算。
7. 任一 normalization規則改版都產生新 representation digest與profile version。

原因：RFC 8785 JCS本身不執行 Unicode normalization；Source Anchor若採不同 normalization，position與quote會失效。

---

## 6. `PDF_REGION_V1`

### 6.1 Canonical selector

```json
{
  "selector_type": "PDF_REGION",
  "page": 7,
  "page_number_basis": "ONE_BASED",
  "bbox": {
    "left": 0.10,
    "top": 0.20,
    "right": 0.75,
    "bottom": 0.31,
    "coordinate_space": "NORMALIZED_PAGE",
    "origin": "TOP_LEFT"
  },
  "block_id": "b-000123",
  "char_start": 120,
  "char_end": 240,
  "char_representation_ref": "representation://normalized-page-7"
}
```

### 6.2 Normative choices

- Page number：1-based，符合人類引用習慣。
- Canonical coordinate origin：TOP_LEFT。
- Canonical coordinates：page-normalized `[0,1]`。
- Range：left/top included，right/bottom geometric boundary。
- char span：相對指定 normalized representation，不相對 raw PDF bytes。
- parser-native bbox仍保留在 ExtractionReceipt，包含原 page width／height與coordinate origin。

### 6.3 Why normalized coordinates

Docling支援 TOPLEFT／BOTTOMLEFT與不同頁面尺寸；若只保存 parser-native座標，跨 parser或render scale難以比較。

因此保存兩層：

```text
Canonical normalized bbox
+ Parser-native provenance bbox
```

### 6.4 Optional shape selector

非矩形區域可增加：

```text
SVG_PATH
POLYGON
MULTI_REGION
```

Phase-1可以只接受 rectangle；遇到跨欄、跨頁或多區域引用，使用多個 anchor。

### 6.5 PDF anchor robustness

建議組合：

```text
page + normalized bbox
+ block id
+ char span into normalized page text
+ exact quote / prefix / suffix
+ source PDF digest
+ normalized representation digest
```

### 6.6 PDF quality interaction

若 anchor落在以下 gap：

```text
PAGE_REQUIRES_OCR
TABLE_STRUCTURE_UNCERTAIN
MULTI_COLUMN_READING_ORDER_RISK
IMAGE_CONTENT_NOT_READ
FORMULA_NOT_PARSED
ENCODING_REPLACEMENT_DETECTED
```

則 assertion不得只靠 parser text自動通過 Semantic Support；Verification Requirement必須升級。

---

## 7. `MARKDOWN_TEXT_V1`

### 7.1 Canonical selector

```json
{
  "selector_type": "MARKDOWN_TEXT",
  "representation_digest": "sha256:...",
  "codepoint_start": 540,
  "codepoint_end": 660,
  "range_semantics": "START_INCLUSIVE_END_EXCLUSIVE",
  "line_start": 23,
  "line_end": 27,
  "line_number_basis": "ONE_BASED_END_INCLUSIVE",
  "heading_path": ["訂單排查", "走期檢查"],
  "exact": "...",
  "prefix": "...",
  "suffix": "..."
}
```

### 7.2 Authority rules

Canonical定位依序：

1. representation digest exact match。
2. codepoint range + quote exact match。
3. quote + prefix/suffix relocate。
4. heading path + quote辅助 relocate。
5. line range只作 human display和fallback。

禁止只保存 line numbers，因為前方插入一行就會整體位移。

### 7.3 Markdown revision

來源是 Git-managed Markdown時，source version優先：

```text
repository identity
+ commit SHA
+ path
+ blob SHA
```

來源是 Outline／web editor export時，使用來源 native revision／updated_at＋digest。

### 7.4 Generated Markdown

Agent／parser生成的 Markdown不是 source truth；它的 anchor必須回到：

```text
RawEvidence
或
NormalizedDocument block
```

不能讓 generated `content.md` 成為唯一 Citation source。

---

## 8. Jira Cloud identity profile

### 8.1 Common source identity

```yaml
source_system: jira-cloud
source_instance_id: <Atlassian cloudId>
```

### 8.2 Stable identity choices

| Entity | Primary native identity | Alias / secondary |
|---|---|---|
| Issue | numeric `issue.id` | issue key、self URL |
| Comment | `comment.id` + parent issue id | self URL |
| Attachment | `attachment.id` + parent issue id | filename、content URL |
| Changelog | `changelog.id` + parent issue id | item index |
| Worklog | `worklog.id` + parent issue id | self URL |
| Issue link | link ID | inward/outward issue IDs |
| Project | numeric project id | project key |

Issue key可因 project move／key change而改變，不得作唯一永久 identity。

---

## 9. Jira source version profiles

### 9.1 Issue

Jira Cloud一般 issue representation沒有適用所有欄位的單一 monotonic revision token。

Phase-1採：

```yaml
source_version:
  basis: COMPOUND_OBSERVED
  kind: UPDATED_AT_DIGEST
  value: <fields.updated>
  secondary_digest: <canonical selected-field payload digest>
  cursor_refs:
    - max_changelog_id: <if available>
```

Rules：

- selected fields set要有 adapter config digest。
- `updated`相同但 payload digest不同，仍視為不同 observation。
- changelog id可協助 chronology，但不能假設所有變更都一定有可見 changelog。

### 9.2 Comment

```text
comment.id
+ comment.updated
+ canonical ADF body digest
+ visibility digest
```

Comment body在 Cloud v3通常使用 Atlassian Document Format（ADF）；source anchor可使用：

```text
ADF JSON Pointer
+ normalized rendered text selector
```

### 9.3 Attachment

```text
attachment.id
+ attachment metadata snapshot digest
+ downloaded content raw digest（若有權限取得）
```

Attachment content digest與metadata digest分開。

### 9.4 Changelog

```text
issue id
+ changelog id
+ created time
+ item index
```

Changelog observation應視為 event Evidence；不要用後續 issue snapshot覆寫它。

### 9.5 Worklog

```text
issue id
+ worklog id
+ updated / version fields if available
+ canonical payload digest
```

### 9.6 Issue link

```text
link id
+ inward issue id
+ outward issue id
+ type id
```

Link deleted時建立 tombstone Evidence。

---

## 10. `JIRA_CLOUD_ENTITY_SEGMENT_V1`

### 10.1 Issue field selector

```json
{
  "profile": "JIRA_CLOUD_ENTITY_SEGMENT_V1",
  "entity_type": "issue",
  "cloud_id": "...",
  "issue_id": "10042",
  "issue_key_alias": "PROJ-123",
  "field_id": "description",
  "json_pointer": "/fields/description/content/0/content/0/text",
  "text_selector": {
    "start": 0,
    "end": 42,
    "exact": "..."
  }
}
```

### 10.2 Comment selector

```json
{
  "entity_type": "comment",
  "issue_id": "10042",
  "comment_id": "20051",
  "json_pointer": "/body/content/1/content/0/text",
  "text_selector": {
    "start": 10,
    "end": 90,
    "exact": "...",
    "prefix": "...",
    "suffix": "..."
  }
}
```

### 10.3 Attachment selector

```json
{
  "entity_type": "attachment",
  "issue_id": "10042",
  "attachment_id": "30001",
  "content_digest": "sha256:...",
  "member_path": null,
  "byte_start": null,
  "byte_end": null
}
```

若 attachment再由 Document Adapter解析，Knowledge assertion應優先指向 attachment RawEvidence下的 PDF／Markdown anchor，而不是只指 attachment ID。

### 10.4 Changelog selector

```json
{
  "entity_type": "changelog",
  "issue_id": "10042",
  "changelog_id": "40001",
  "item_index": 0,
  "field": "status",
  "field_id": "status",
  "from": "3",
  "to": "10000",
  "created_at": "..."
}
```

---

## 11. Jira permission snapshot

### 11.1 Issue visibility

至少保存：

```text
Browse Projects access context
issue-level security level identity
project identity
source principal / app identity
capture result
```

### 11.2 Comment visibility

Comment可以限制給 role／group；child content和attachment可能繼承 comment visibility。

RawEvidence ACL snapshot應包含：

```yaml
comment_visibility:
  type: role-or-group
  identifier: ...
```

### 11.3 Attachment visibility

Attachment是否可讀不只取決於 attachment本身，還受：

```text
parent issue browse permission
issue security
private/restricted comment context
app access rules
```

因此 attachment adapter不可只保存 `content URL`，必須保存當時 permission snapshot與fetch principal。

### 11.4 Permission change

Jira source permission變更後：

```text
Source ACL delta / reconciliation
→ RawEvidence access state
→ ObjectLink / Candidate impact analysis
→ Projection invalidation
→ cache eviction
→ AnswerTrace audit
```

萃取內容不得因已下載而永久繞過來源撤權。

---

## 12. Webhook vs reconciliation

### 12.1 Webhook優點

```text
low latency
native event hints
delta-oriented processing
```

### 12.2 Webhook限制

官方 Atlassian defect顯示：

- 刪除 project可能不會逐一送出 issue-deleted webhook。
- JQL-filtered webhook可能漏 issue-deleted。
- Comment／worklog JQL behavior存在已知限制。

因此正式架構：

```text
Webhook ingest
        +
Periodic reconciliation / poll
        +
Administrative deletion / permission audit when available
```

Webhook不取得 completeness authority。

### 12.3 Reconciliation receipt

```yaml
reconciliation:
  adapter_id: jira-cloud-adapter
  scope: project:10000
  started_at: ...
  completed_at: ...
  previous_cursor: ...
  next_cursor: ...
  seen_entities: 123
  missing_entities: 4
  permission_denied_entities: 2
  confirmed_deleted_entities: 1
  unresolved_entities: 3
  partial: true
```

---

## 13. 404 / inaccessible state machine

單次 404不得直接等於 source deleted。

建議：

```text
AVAILABLE
        ↓ single 404 / hidden
NOT_FOUND_UNCONFIRMED
        ├─ later fetch succeeds → AVAILABLE
        ├─ permission evidence → ACCESS_REVOKED
        ├─ delete webhook/audit → SOURCE_DELETED
        └─ repeated reconciliation unresolved → UNAVAILABLE_UNKNOWN
```

Reasons：

- Jira endpoints受 Browse Projects和issue-level security影響。
- deleted與無權限可能在 consumer視角都無法讀取。
- project bulk deletion可能漏掉個別 issue-deleted webhook。

`SOURCE_DELETED` 必須有 evidence reference或authority decision。

---

## 14. Cloud vs Data Center semantic diff

| Area | Jira Cloud | Jira Data Center |
|---|---|---|
| REST | v3為主要 modern contract | 常見 `/rest/api/2`；依產品版本 |
| Instance identity | Atlassian `cloudId` | deployment/base URL + instance UUID if available |
| User identity | `accountId` | username/key／版本依賴 |
| Rich text | ADF常見 | rendered/plain/legacy body依版本 |
| Webhooks | Cloud registration／dynamic webhook限制 | admin webhook；Jira 10開始 async only |
| Event payload | Cloud-specific shapes | issue shape接近REST v2、版本差異 |
| App access rules | Cloud特有政策層 | self-managed permission/config |
| Upgrade behavior | Atlassian managed | customer-controlled version upgrade |

正式規則：

```text
jira-cloud-adapter
!=
jira-data-center-adapter
```

共用的只能是：

```text
RawEvidenceEnvelope
SourceAnchor abstract envelope
Entity-type vocabulary
```

不能共用未驗證的 field mapping。

---

## 15. Proposed Jira Adapter descriptor

```yaml
adapter_id: jira-cloud-adapter
adapter_version: 0.1.0
source_system: jira-cloud
api_profile: JIRA_CLOUD_REST_V3
supported_entities:
  - issue
  - comment
  - attachment
  - changelog
  - worklog
  - issue_link
supported_ingestion_modes:
  - WEBHOOK
  - POLL
  - BULK_BACKFILL
identity_profile: JIRA_CLOUD_NATIVE_ID_V1
version_profile: JIRA_CLOUD_COMPOUND_VERSION_V1
anchor_profile: JIRA_CLOUD_ENTITY_SEGMENT_V1
permission_profile: JIRA_CLOUD_VISIBILITY_V1
deletion_profile: WEBHOOK_PLUS_RECONCILIATION_V1
```

### Required adapter outputs

```text
RawEvidenceEnvelope
SourceDeltaReceipt
IngestionCheckpoint
ReconciliationReceipt
PermissionSnapshot
Deletion / Tombstone Evidence
```

---

## 16. Phase-1 fixtures

### 16.1 PDF fixture

必須包含：

- 一個普通 paragraph anchor。
- 一個 table cell／table region anchor。
- 一個 multi-column quality warning。
- 同一 quote在前方新增文字後可被 relocate。

### 16.2 Markdown fixture

必須包含：

- UTF-8繁中。
- codepoint position。
- 1-based line range。
- exact/prefix/suffix。
- Git commit＋blob SHA profile。
- 前方插入行後 line range失效但 quote可 relocate。

### 16.3 Jira fixture

必須包含：

- issue numeric ID與mutable issue key。
- ADF description anchor。
- restricted comment。
- comment update。
- attachment＋content digest。
- changelog status transition。
- issue delete webhook tombstone。
- single 404不確認 deletion。
- project deletion漏個別 webhook的reconciliation case。

---

## 17. Hard stops

禁止：

- PDF只存 page number，不存 source digest與selector。
- Markdown只存 line range。
- TextPosition使用 UTF-16 code unit卻標 Unicode code point。
- Parser改寫／清洗文字但不保存 normalization profile。
- Jira issue key當唯一 stable identity。
- `fields.updated`單獨作 universal monotonic revision。
- Comment visibility不進 ACL snapshot。
- Attachment下載後忽略來源撤權。
- webhook success當 completeness proof。
- single 404直接轉 `SOURCE_DELETED`。
- Cloud與Data Center共用一份未分版本的 mapping。
- Changelog event被最新 issue snapshot覆蓋。

---

## 18. Open decisions

1. PDF canonical bbox採 normalized float的小數精度。
2. Page number在 internal store是否同時保留 parser-native zero-based index。
3. Quote保存 plaintext或只保存 digest＋授權取得機制。
4. Sanitization前後 char offset mapping格式。
5. Markdown heading path canonical serialization。
6. ADF normalized text renderer的 exact version與extension node處理。
7. Jira selected-field payload digest的 default field set。
8. Jira Cloud instance identity使用 cloudId的取得與rotation policy。
9. Data Center instance identity的 authoritative來源。
10. Reconciliation頻率、missing threshold與SOURCE_DELETED authority。

---

## 19. Acceptance criteria

1. 一個 PDF assertion可以回到 source PDF digest、page、bbox、normalized char span與exact quote。
2. 同一 Markdown內容前方插入三行後，anchor可標 `RELOCATED`而不是錯指內容。
3. Jira issue key改變後，numeric issue identity不改。
4. restricted comment的projection不會被無權限 identity檢索。
5. attachment被刪／撤權後，可觸發projection invalidation。
6. delete webhook可產生 tombstone但不抹除 chronology。
7. single 404不會直接刪除 canonical support。
8. project deletion漏 webhook時，reconciliation能發現 missing entities並保持 unresolved／confirmed distinction。
9. Cloud與Data Center fixtures由不同 adapter profile驗證。
10. 所有 anchor都能回報 `EXACT_MATCH / RELOCATED / CONTENT_CHANGED / MISSING / ACCESS_REVOKED / AMBIGUOUS`。

---

## 20. Backlog disposition

```text
MERGE INTO STD-02:
- Common SourceAnchor envelope
- PDF_REGION_V1
- MARKDOWN_TEXT_V1
- JIRA_CLOUD_ENTITY_SEGMENT_V1

MERGE INTO Document Adapter Mapping:
- coordinate normalization
- text normalization profile
- quality gap interaction

MERGE INTO Jira Adapter Mapping:
- stable entity IDs
- compound versions
- ADF anchors
- ACL visibility
- webhook + reconciliation
- deletion ambiguity

DO NOT CREATE:
- one universal selector with source-specific fields mixed together
- Jira webhook canonical log as Knowledge truth
- Cloud/Data Center universal adapter
```
