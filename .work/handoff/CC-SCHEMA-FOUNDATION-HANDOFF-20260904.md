---
id: CC-SCHEMA-FOUNDATION-HANDOFF-20260904
status: READY_FOR_EXTERNAL_CC_FIXED_COMMIT_REVIEW
review_mode: READ_ONLY_IMMUTABLE_DIFF
---

# CC Schema Foundation fixed-commit 外部審查交件包

## 1. 審查身份與不可變邊界

- Repository：`bluemaple18-home/organizational-memory-os`
- Remote：`origin`
- 審查 commit：`d0824e5a4dc02e8f77211ba1e790698a829e2a44`
- 審查 tree：`4d6c9635b13b22a6c3670dc59223de0c0be6f30f`
- Base commit：`8ac5c24c92ed70640612641734c33f90efa6374f`
- 唯一審查 diff：`8ac5c24c92ed70640612641734c33f90efa6374f..d0824e5a4dc02e8f77211ba1e790698a829e2a44`
- 內部 receipt commit：`adc867522cd8293bbd05e615f0a3bad4566912f3`
- Receipt tree：`7641ff3058bacb52102877bcdd47949aabb42a3e`
- Branch label：`codex/schema-foundation-cc-review`；label 只供取得物件，審查輸入仍以上述完整 commit／tree／blob 為準。

Review 開始後，`d0824e5a4dc02e8f77211ba1e790698a829e2a44` 即凍結。不得把 branch tip、後續 commit、working tree 或未追蹤檔案偷偷納入同一輪 review。Reviewer 只能讀 git object、在 repo 外的暫存位置產生 stdout／receipt，不得寫 `.work/current/*`、`status.md` 或任何 repository path。

取得與綁定檢查：

```sh
git fetch origin codex/schema-foundation-cc-review
git cat-file -e d0824e5a4dc02e8f77211ba1e790698a829e2a44^{commit}
git cat-file -e 8ac5c24c92ed70640612641734c33f90efa6374f^{commit}
git show -s --format='%H %P %T' d0824e5a4dc02e8f77211ba1e790698a829e2a44
git diff --name-status 8ac5c24c92ed70640612641734c33f90efa6374f d0824e5a4dc02e8f77211ba1e790698a829e2a44
```

預期最後一個 `git show` 輸出三欄依序為審查 SHA、base SHA、tree SHA。若任一不符，停止 review 並回報 `INPUT_BINDING_FAILURE`。

## 2. In-scope allowlist 與 commit blob OID

下表 35 個路徑是 `git diff-tree -r 8ac5c24c9..d0824e5` 的完整結果；OID 是 `d0824e5` tree 中的 Git blob OID。`A`／`M` 是相對 base 的狀態。

| 狀態 | 路徑 | commit blob OID |
|---|---|---|
| A | `.work/CARD-CC-SCHEMA-FOUNDATION-PREP-20260904.md` | `83a8652fe5e54fe0ce5691a7e3804252d78b8a11` |
| A | `.work/CARD-STD00-ACCEPTANCE-PREFLIGHT-20260903.md` | `101b93701b12d7b4352ae18f5e00bb67e6ab4d08` |
| A | `.work/CARD-STD00-LOCK-20260904.md` | `a0ae699bb329818d389c7d821daa8884b3352fc8` |
| A | `.work/CARD-STD01-RAW-EVIDENCE-20260904.md` | `f6517ec68257df9b042f530f8ecb51377f9a7304` |
| A | `.work/CARD-STD02-SOURCE-ANCHOR-20260904.md` | `27afcb862fc5d3033b6bdb86fdbf464cfea34be2` |
| A | `.work/evidence/CC-SCHEMA-FOUNDATION-PREP-20260904.md` | `dd2c5f28babb9f2e612ad5fa42a484953f679a80` |
| A | `.work/evidence/STD00-ACCEPTANCE-PREFLIGHT-20260903.md` | `cfd50fc74bd720f162d2360fe2bc92bf8a605fb4` |
| A | `.work/evidence/STD00-LOCK-20260904.md` | `afc8749b186100c3155b74870d600cbc06eb04c0` |
| A | `.work/evidence/STD01-RAW-EVIDENCE-20260904.md` | `9ba55ada281c33a4c6a1a4cd87df86ff65237e93` |
| A | `.work/evidence/STD02-SOURCE-ANCHOR-20260904.md` | `73c1e1ec68f8364bd17fac7010af8d0d6f88d51c` |
| A | `scripts/validate_cc_cross_layer_contract.py` | `6597fbefd617bc5dd6442851dfae10987d976cba` |
| A | `scripts/validate_std00_contract.rb` | `84ba84ffb4e661b6cef0c4422cd37b056cdf5119` |
| A | `scripts/validate_std01_raw_evidence_contract.rb` | `9b7bfecef697dfa9992f6dfe82bb3c7204c90e28` |
| A | `scripts/validate_std02_source_anchor_contract.rb` | `19416cd6145f5a65612164c33aef7de51f053927` |
| A | `scripts/validate_std_schema_engine.py` | `56f6358ae18012b86a149dd06be66ca3d4a05664` |
| A | `文件/CC-Schema-Foundation-Contract-Decision-v0.1.md` | `61a5a45d081baa6f0a0d11cdde3de987f7fd81b6` |
| M | `文件/Codex審查交接-STD-00-20260828.md` | `d7f78d2cbbfe498fc56c23b07a9dfd1f99674df3` |
| M | `文件/STD-00-Schema-Vocabulary-Freeze-v0.1-提案.md` | `ffeb9fbd3429fd3e1c07f0fa061f990a8c58f823` |
| M | `文件/待辦補充-個人知識庫Harness-20260830.md` | `1df1f41c0b06d5894aac3bc7902e2d2877ce21f7` |
| M | `文件/待辦補充-標準文件規格-20260828.md` | `bfecd9a3d9fa9b5b63d1792221e3d4cbbd0e23a3` |
| M | `文件/待辦重整.md` | `109487acfd5bfb8088fc27f46a369455c6521c2e` |
| M | `規格/v0.1/common-vocabulary.yaml` | `a3d03465e1aaaed0bf75b6b9704fb88ceb5b193e` |
| A | `規格/v0.1/fixtures/cc-schema-foundation-cross-layer-fixtures.json` | `e56f2a8070628043ecaae035365d4f2f16716265` |
| M | `規格/v0.1/fixtures/std-00-negative-fixtures.json` | `13706b3e3612a6eb034e50f46ee5241efab1e218` |
| M | `規格/v0.1/fixtures/std-00-positive-fixtures.json` | `640d648ea929e7fa5de5931a4c3e47bd8452278c` |
| A | `規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json` | `955846488ed06c3a00bacf395222b98bf00ce6ce` |
| A | `規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json` | `089b40f3dfbedebadce0b51c6d61cf4ee022658e` |
| A | `規格/v0.1/fixtures/std-02-source-anchor-negative-fixtures.json` | `b214f11ff0b6b8a136c615a2ebadfac22a2f1e3c` |
| A | `規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json` | `8dbad9e46b5292134bb8368a46da42675f4e26f0` |
| M | `規格/v0.1/personal-harness-integration.yaml` | `304b46b66b92281be9649ddbc58a7a1f8ac3e76a` |
| A | `規格/v0.1/raw-evidence-envelope.schema.json` | `bfd07d37fd8d309f6de77a099cbfa196e7b3b751` |
| A | `規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json` | `277d37af4249e900a9414f5331f38dbf8982c785` |
| A | `規格/v0.1/source-anchor-markdown-text-v1.schema.json` | `cb9b0d9aa1e8de1fc21f25cbd586deb85dddbc7d` |
| A | `規格/v0.1/source-anchor-pdf-region-v1.schema.json` | `c55a09a465cf7461eb754fb279b9a423fd015d42` |
| A | `規格/v0.1/source-anchor.schema.json` | `3caab8cef0eda636fc68c76b832af625acec7053` |

Reviewer 應以 `git diff-tree --no-commit-id --raw -r --abbrev=40 <base> <review>` 重算，並逐列比對。不得以 working-tree `hash-object` 取代 commit blob。

## 3. 明確排除範圍

下列 working-tree 項目不在 `8ac5c24c9..d0824e5`，不得讀入結論、修改或提交：

- 所有 `KM` 工作卡／evidence。
- 所有 `SSP` 工作卡／evidence。
- `km-mvp-engineering-tunnel.html` 與其他 HTML。
- `.DS_Store`。
- `CLAUDE.md`。
- `Canonical Direct-Write Audit`、STD-03、runtime、Connector、DB、Hook、Loop、Harness、Hermes 實作。
- Receipt commit `adc8675` 的兩個文件變更只作內部 review 證據，不可混入審查 diff。

## 4. Normative authority 與執行入口

- STD-01／02 field-level authority：JSON Schema Draft 2020-12。
- `scripts/validate_std_schema_engine.py` 使用 `jsonschema==4.25.1`，以五個 `$id` 建立 `referencing.Registry`，執行 `Draft202012Validator.check_schema`、正例接受、每個 `JSON_SCHEMA` 負例拒絕，以及每個 `RUBY_SEMANTIC` 負例必須先被 schema 接受的前置閘門。
- Ruby validators 只補跨事件／跨資源語意、完整 base 與 mutation isolation；其 field checks 是 defensive mirror，不可取代標準 engine。
- Cross-layer validator 必須由 fixture 名稱 registry 取出 STD-01 RawEvidenceEnvelope 與 STD-02 SourceAnchor 實體，再比對 reference／identity／digest／ACL／visibility／resolution；URN 前綴相符不算 resolve。

可重跑命令：

```sh
UV_CACHE_DIR=/tmp/cc-schema-foundation-uv uv run --script scripts/validate_std_schema_engine.py
ruby scripts/validate_std00_contract.rb
ruby scripts/validate_std01_raw_evidence_contract.rb
ruby scripts/validate_std02_source_anchor_contract.rb
ruby scripts/validate_personal_memory_contract.rb
UV_CACHE_DIR=/tmp/cc-schema-foundation-uv uv run --script scripts/validate_cc_cross_layer_contract.py
git diff --check 8ac5c24c92ed70640612641734c33f90efa6374f d0824e5a4dc02e8f77211ba1e790698a829e2a44
```

`scripts/validate_personal_memory_contract.rb` 存在於 base，並非 35-path diff；它只作 `personal-harness-integration.yaml` 的既有 consumer verification，不可被誤列為本次新增 blob。

## 5. Spec claim → exact enforcement → fixture parity

### 5.1 STD-01 RawEvidenceEnvelope

三個正例 `pdf-manual-upload-raw-evidence`、`git-markdown-sop-raw-evidence`、`jira-cloud-issue-description-raw-evidence` 必須同時被 standard engine 與 Ruby validator 接受。

下表的 `expected code` 是 fixture 宣告的 parity label。對 `RUBY_SEMANTIC` case，Ruby validator會核對實際 code 與 unrelated failure isolation；對 `JSON_SCHEMA` case，現行 standard engine只核對該完整 instance 至少被 Draft 2020-12 拒絕，並不核對拒絕來自哪個 keyword／path，也不消費 `expected_failure_codes`。外部 reviewer 必須特別檢查「因無關錯誤被拒但目標 invariant 其實沒擋」的 false coverage。

| 規格宣稱／invariant | Exact enforcement | 證明 fixture（authority → expected code） |
|---|---|---|
| Evidence identity 不得沿用 delivery／source event identity | `validate_envelope` 的 `EVIDENCE_ID_DELIVERY_ID` | `evidence-id-equals-delivery-id`（Ruby → `EVIDENCE_ID_DELIVERY_ID`） |
| 同一 CloudEvent＋raw digest 不得建立第二 Evidence | `validate_cross_event_semantics` 的 redelivery identity/key 比對 | `same-cloudevent-redelivery-creates-second-evidence`（Ruby → `REDELIVERY_DUPLICATE_EVIDENCE`） |
| 同 delivery 不同 payload 不得靜默通過 | `validate_cross_event_semantics` 要求 `REDELIVERY_PAYLOAD_MISMATCH` gap | `redelivery-payload-mismatch-without-finding`（Ruby → `REDELIVERY_PAYLOAD_MISMATCH_UNFLAGGED`） |
| 同 stable source 的新 revision 不得重用 Evidence identity | `validate_cross_event_semantics` 比對 source identity／version／evidence id | `same-source-new-revision-reuses-evidence-id`（Ruby → `REVISION_REUSED_EVIDENCE_ID`） |
| 同 stable source 的新 revision 不得重用 idempotency key | `validate_cross_event_semantics` 比對 source identity／version／key | `same-source-new-revision-reuses-idempotency-key`（Ruby → `REVISION_REUSED_IDEMPOTENCY_KEY`） |
| 相同 bytes 不得跨不同 source identity 合併 | `validate_cross_event_semantics` 比對 raw digest、source identity、evidence id／key | `same-payload-different-sources-merged`（Ruby → `CROSS_SOURCE_DIGEST_MERGE`） |
| 無 native event id 時 must 使用 deterministic fallback，含必要 basis 並留下 gap | schema `allOf if/then` fallback branch；standard engine；Ruby mirror | `source-event-without-native-event-id-missing-fallback`（Schema → `SOURCE_EVENT_FALLBACK`, `SOURCE_EVENT_FALLBACK_BASIS`, `SOURCE_EVENT_FALLBACK_GAP`） |
| Four clocks 不得全部塌縮，且 observed ≤ received ≤ persisted | `validate_envelope` chronology parsing／ordering | `four-clocks-collapsed-or-reordered`（Ruby → `FOUR_CLOCKS_COLLAPSED`） |
| 單次 404 不得直接確認 source deleted | `validate_envelope` 要求 deletion confirmation | `single-jira-404-marked-source-deleted`（Ruby → `SOURCE_DELETED_CONFIRMATION`） |
| Access revoked must 有 permission decision，不得誤作 deleted | `validate_envelope` availability branch | `permission-revoked-classified-as-deleted`（Ruby → `ACCESS_REVOKED_PERMISSION`） |
| Webhook-only confirmation forbidden | `validate_envelope` 排除 `webhook-only` confirmation | `project-deletion-webhook-only-confirmation`（Ruby → `SOURCE_DELETED_WEBHOOK_ONLY`） |
| NON-I-JSON forbidden 宣稱 canonical digest，且 must 留 canonicalization gap | schema conditional＋Ruby mirror | `non-i-json-canonical-digest-claimed`（Schema → `NON_I_JSON_CANONICAL_DIGEST`, `NON_I_JSON_GAP`, `JCS_REQUIRES_I_JSON`） |
| `digests.raw_digest` must 存在且為 sha256 | schema `required`／`$defs/sha256`；standard engine | `missing-raw-digest`（Schema → `RAW_DIGEST`） |
| ACL snapshot ref must 存在 | schema nested `required`＋pattern；standard engine | `missing-acl-snapshot`（Schema → `ACL_SNAPSHOT`） |
| Provenance required fields must 存在 | schema nested `required`；standard engine | `missing-provenance`（Schema → `PROVENANCE_FIELD`） |
| Activity COMPLETE 不等於 verification PASS | `validate_envelope` provenance semantic check | `openlineage-complete-treated-as-verified`（Ruby → `COMPLETE_NE_VERIFIED`） |
| Entity snapshot idempotency must 包含 source_version | `$defs/idempotency_basis allOf if/then`；standard engine | `entity-snapshot-idempotency-missing-source-version`（Schema → `IDEMPOTENCY_PROFILE_INCLUDES`） |
| Native source event idempotency must 包含 native_event_id | root `allOf if/then`；standard engine | `source-event-idempotency-missing-native-event-id`（Schema → `SOURCE_EVENT_NATIVE_BASIS`） |
| canonicalization `NONE` 時 canonical digest must 為 null | root `allOf if/then`；standard engine | `canonicalization-none-with-canonical-digest`（Schema → `CANONICALIZATION_NONE_DIGEST`） |
| RFC8785 JCS must 搭配 I-JSON | root `allOf if/then`；standard engine | `jcs-with-non-i-json-profile`（Schema → `JCS_REQUIRES_I_JSON`） |
| Quality gap code must 來自 LOCKED vocabulary | schema enum＋Ruby vocabulary mirror | `unknown-quality-gap-code`（Schema → `QUALITY_GAP_CODE`） |

### 5.2 STD-02 SourceAnchor

三個正例 `pdf-region-source-anchor`、`markdown-text-source-anchor`、`jira-cloud-entity-segment-source-anchor` 必須由 profile validator 經 canonical common `$ref` 接受，且 evidence refs 分別 resolve 至三個 STD-01 正例。

同樣地，STD-02 的 `JSON_SCHEMA` case 現行 gate 是 per-case boolean rejection，不做 error keyword／instance path isolation；表內 code 是 fixture 的預期語意標籤，不代表 standard engine實際比對過該 code。

| 規格宣稱／invariant | Exact enforcement | 證明 fixture（authority → expected code） |
|---|---|---|
| PDF bbox must 在 `[0,1]` | PDF profile schema bounds；standard engine | `pdf-bbox-out-of-range`（Schema → `PDF_BBOX_RANGE`） |
| PDF bbox min must 小於 max | `validate_pdf` ordering | `pdf-bbox-reversed`（Ruby → `PDF_BBOX_ORDER`） |
| PDF page must 為 one-based 且 ≥ 1 | PDF profile schema；Ruby mirror | `pdf-page-zero`（Schema → `PDF_PAGE`） |
| representation digest must 存在 | common schema nested `required`／`$ref` | `pdf-missing-representation-digest`（Schema → `REPRESENTATION_REQUIRED`） |
| profile details forbidden 未知欄位 | profile schema `additionalProperties:false` | `pdf-profile-details-untrusted-extra`（Schema → `PDF_REGION_V1_PROFILE_DETAILS_CLOSED`） |
| selectors must 為 array | common schema type；standard engine | `selectors-not-array`（Schema → `COMMON_ROOT_TYPE`） |
| PDF char range must 是 half-open Unicode code point 且 start < end | `validate_pdf` | `pdf-char-range-reversed`（Ruby → `PDF_CHAR_RANGE`） |
| Markdown 不得只靠 line range；must 有 codepoint range | Markdown profile schema `required` | `markdown-line-only`（Schema → `MARKDOWN_TEXT_V1_PROFILE_DETAILS_REQUIRED`） |
| Markdown unit must 是 Unicode code point，UTF-16 forbidden | Markdown profile schema const；Ruby mirror | `markdown-utf16-unit`（Schema → `MARKDOWN_CODEPOINT_UNIT`） |
| quote.exact must 等於實際 selected text，不得用摘要 | `validate_markdown`／`validate_pdf`／`validate_jira` | `markdown-quote-mismatch`、`summary-used-as-quote`（Ruby → `QUOTE_SELECTED_TEXT`） |
| RELOCATED must 保留 prefix 或 suffix robust context | `validate_common` relocation branch | `markdown-relocation-without-robust-context`（Ruby → `RELOCATED_CONTEXT`） |
| Jira issue identity must 是 numeric native id；key 只能是 alias | Jira profile schema pattern；`validate_jira` identity binding | `jira-key-used-as-identity`、`jira-non-numeric-issue-id`（Schema → `JIRA_ISSUE_IDENTITY`） |
| Jira cloud_id must 非空並對齊 source_instance_id | schema `minLength`＋`validate_jira` cross-field | `jira-missing-cloud-id`（Schema → `JIRA_CLOUD_ID`） |
| Cloud profile forbidden 混入 Data Center | Jira profile schema const；`validate_jira` | `jira-data-center-mixed-into-cloud`（Schema → `JIRA_CLOUD_ONLY`） |
| JSON Pointer must 符合 RFC6901 | Jira profile schema pattern＋Ruby parser | `jira-invalid-json-pointer`（Schema → `JIRA_JSON_POINTER`） |
| field_id must 與 pointer `/fields/<field_id>` 綁定 | `validate_jira` token binding | `jira-field-id-pointer-mismatch`（Ruby → `JIRA_FIELD_POINTER_BINDING`） |
| Anchor ACL snapshot must 對齊 RawEvidence | `validate_common` resolved evidence cross-ref | `acl-snapshot-reference-mismatch`（Ruby → `ACL_SNAPSHOT_CROSS_REF`） |
| Permission decision must 對齊 RawEvidence | `validate_common` resolved evidence cross-ref | `permission-reference-mismatch`（Ruby → `PERMISSION_REF_CROSS_REF`） |
| availability／resolution must 符合 truth table | `availability_resolution_valid?`＋truth-table self-check | `resolution-falsely-claims-revoked`（Ruby → `RESOLUTION_AVAILABILITY_MISMATCH`） |
| evidence_ref must resolve 至既有 RawEvidence，不得只過 URN pattern | `evidence_by_ref` lookup＋`validate_common` | `source-evidence-reference-mismatch`（Ruby → `EVIDENCE_REF`） |
| Profile schema must 經 canonical common `$ref`，且 root／nested objects closed | `validate_schema_documents` 驗 exact URN；standard engine registry 實際解 `$ref` | 三個 profile 正例＋`pdf-profile-details-untrusted-extra`；其餘 closure 層級見下節待加壓項 |

### 5.3 Candidate → SupportLink → STD-01／02 跨層真實解析

正例不是內嵌 RawEvidence／SourceAnchor。`base_case.raw_evidence_fixture_ref=git-markdown-sop-raw-evidence` 與 `anchor_fixture_ref=markdown-text-source-anchor`；validator 由兩份 canonical positive fixture 建 `raw_by_name`／`anchor_by_name` registry，找不到名稱會得到 `None`，再做完整 binding。正例 must 通過 evidence／anchor refs、candidate support backlink、tenant／owner、source identity＋version、payload／representation digest、ACL、visibility、EXACT_MATCH／AVAILABLE 與 exact quote。

| 負例 | 單一 mutation target／path | Exact failure |
|---|---|---|
| `missing-source-anchor-ref` | support／`source_anchor_ref` delete | `SUPPORT_ANCHOR_REF` |
| `wrong-raw-evidence-ref` | support／`evidence_ref` | `SUPPORT_EVIDENCE_REF` |
| `representation-digest-mismatch` | resolved anchor／`representation.representation_digest` | `REPRESENTATION_DIGEST` |
| `revoked-source-claims-exact` | resolved anchor／`source_availability` | `RESOLUTION_AVAILABILITY` |
| `owner-widening` | support／`employee_owner_ref` | `OWNER_ALIGNMENT` |
| `acl-widening` | candidate／`governance.acl_ref` | `ACL_BINDING` |
| `visibility-scope-widening` | candidate／`governance.visibility_scope` | `VISIBILITY_SCOPE` |
| `summary-only-support` | support／`support_material.kind` | `SUPPORT_MATERIAL` |

## 6. 必須異質加壓、不可被內部 GO 掩蓋的缺口

下列項目是外部 review 的指定攻擊面。表中「未有 dedicated fixture」不先判成 finding，但 reviewer 必須用讀碼、repo 外臨時 probe 或結構化 finding 判定 parity；不得因主 gate PASS 就略過。

| 攻擊面 | 目前可見 enforcement／證據 | 外部 reviewer 必做 |
|---|---|---|
| Presence-only：required field=`""` | STD-01 Ruby `present?` 明確把 empty string／empty collection 視為 absent；schemas 對部分字串有 `minLength:1`。STD-02 有 `jira-missing-cloud-id` 空字串負例。 | 逐一列出所有 spec 宣稱非空但 schema 只寫 `type:string` 的欄位；確認 Ruby mirror 不會掩蓋 field authority 缺口。 |
| Presence-only：required array=`[]` | `selectors` 有 `minItems:1`；部分 required arrays（例如 STD-01 `source_aliases`、visibility refs、quality gaps）允許空值可能是設計語意。沒有通用 empty-array negative。 | 依 spec must 語意判斷哪些 array 必須非空；每一個宣稱非空者須有 schema constraint＋negative fixture。 |
| Duplicate fixture/resource id | fixture name 順序須精確等於 constant，會擋多數 duplicate name；但 Python dict comprehension、Ruby `to_h` 與 cross-layer registry 都可能 last-write-wins。沒有 duplicate resource-id dedicated fixture。 | 檢查 evidence_ref／anchor_ref／fixture name 重複時是否 fail-closed；若 last-write-wins 可改變被 resolve 實體，列 P1。 |
| Duplicate YAML key | Ruby 使用 `YAML.safe_load(..., aliases:false)`，但此設定不等於明示拒絕 duplicate key；沒有 duplicate-key fixture。 | 實測 `common-vocabulary.yaml`／`personal-harness-integration.yaml` duplicate key 是否被拒；last-write-wins 則依影響分級。 |
| Duplicate JSON key | Python `json.load`、Ruby `JSON.parse` 預設通常不提供 object-pairs duplicate rejection；現有 harness 無 dedicated probe。 | 檢查 schema／fixture duplicate key 能否改寫 authority、expected result、id 或 mutation；提出具體修補與 fixture。 |
| `$ref` resolution | 五 schema `$id` registry＋profile `allOf[0].$ref` exact URN，由 Draft 2020-12 engine執行。 | 破壞／指錯 `$id`、`$ref`、registry target 應 fail-closed；確認不是只做字串 shape check。 |
| `if/then` semantics | STD-01 fallback/native event、canonicalization NONE/JCS、idempotency profile 均有逐 case negative。 | 檢查 `if` 缺 `required` 時是否 vacuous match；逐 branch 驗 then 真正約束實例。 |
| `additionalProperties:false` closure | STD-01 root與主要 nested schema closed；STD-02 common/profile/nested closures由 schema-doc validator檢查。只有 PDF profile_details 有明示 extra-field negative。 | 對 root、common nested、每個 profile nested 各挑一個 unknown field；任何未拒絕皆是 parity finding。 |
| Cross-layer real resolution | base 只存 fixture refs；validator從 canonical positives建立 registry並比對值；8 個負例全擋。 | 對不存在 fixture name、重複 fixture name、正確 URN但錯實體、anchor evidence_ref錯指另一合法 RawEvidence 加壓，確認不是前綴或最後寫入者過關。 |

## 7. 內部獨立 review：已覆蓋面、方法與限制

主線使用獨立 subagent reviewer 做 blocking review；git receipt 只固化「內部獨立 reviewer」，不宣稱特定模型，也不把模型名稱當 correctness 證據。該輪綁定 `d0824e5` commit、tree 與 blob，檢查 allowlisted diff、standard engine、cross-layer resolution、四個 Ruby gates、JSON／YAML parse、`git diff --check`，並以 findings severity 判定。最終 verdict `GO`，P0／P1／P2=`0/0/0`。

在 fixed commit 前的三輪修補已處理：negative authority／逐 case fail-closed、cross fixture 不得內嵌 canonical SourceAnchor 自證、JSON Schema 與 Ruby 責任邊界、backlog blocker／STD-03 狀態一致，以及 `uv` 可重現入口。內部 review 也驗證 semantic cases 必須先被 schema ALLOW 才能排除 schema rejection coverage。

這些覆蓋不降低外部門檻。外部 CC 必須異質：優先重建 spec parity、攻擊未有 dedicated fixture 的 parser／index 邊界，以及嘗試讓錯誤實體在合法 URN／合法 shape 下通過；不可只重跑同一批 PASS commands 後輸出 GO。

## 8. Mutation probe harness

Harness 就是 fixed blob `scripts/validate_std_schema_engine.py` 的 `structural_relabel_probe`，不是報告中的人工敘述。命令：

```sh
UV_CACHE_DIR=/tmp/cc-schema-foundation-uv \
  uv run --script scripts/validate_std_schema_engine.py --probe-structural-relabel
```

預期：

```text
STD schema engine validator FAIL
FAIL STD01_RUBY_SEMANTIC_SCHEMA_REJECTED:missing-raw-digest:0
```

預期 process exit code 是 `1`。Probe deep-copy 結構性 negative `missing-raw-digest`，把 metadata 從 `JSON_SCHEMA` 重標為 `RUBY_SEMANTIC` 並宣稱 `schema_expected_result: ALLOW`；Draft 2020-12 仍拒絕 instance，因此 gate 必須 fail-closed。這就是「防止 `RUBY_SEMANTIC` 繞過」：改 authority label 不能把應由 schema 拒絕的結構錯誤排除於 schema coverage。Exit `0` 或 `2` 都是失敗。

## 9. Receipt commit `adc8675` 的可稽核內容

Receipt commit 的 parent 是 review commit；只修改兩個既有控制／證據檔：

| 路徑 | `d0824e5` blob | `adc8675` blob | Receipt 新增重點 |
|---|---|---|---|
| `.work/CARD-CC-SCHEMA-FOUNDATION-PREP-20260904.md` | `83a8652fe5e54fe0ce5691a7e3804252d78b8a11` | `41456112b53ed6b036b612f3e6c5b4cf88f25ccd` | status 改為 ready for external CC；寫入 fixed commit／tree、內部 GO 與 STD-03 gate。 |
| `.work/evidence/CC-SCHEMA-FOUNDATION-PREP-20260904.md` | `dd2c5f28babb9f2e612ad5fa42a484953f679a80` | `ba2a9693feaa770a805bdfe71bbe8ccc35e60bdc` | 寫入 mainline rerun、mutation exit 1、commit/tree/blob binding、P0/P1/P2=`0/0/0`。 |

Receipt 的 verdict／findings／evidence 是：`GO`、沒有 P0／P1／P2、standard engine 為 STD-01 `10/10 + 11 semantic`、STD-02 `12/12 + 10 semantic`，cross-layer 8 negatives 全拒絕，四個 Ruby gates與 parse／diff checks PASS。它只證明內部 checkpoint，不是外部 CC verdict。

## 10. 外部 CC 結構化輸出契約

回傳一份 stdout／repo 外 receipt，至少符合下列結構；每個 finding 必須有 fixed-commit `path:line`、觸發輸入、實際行為、spec claim、嚴重度與最小修補／測試建議。

```yaml
review_input:
  repository: bluemaple18-home/organizational-memory-os
  base_sha: 8ac5c24c92ed70640612641734c33f90efa6374f
  review_sha: d0824e5a4dc02e8f77211ba1e790698a829e2a44
  tree_sha: 4d6c9635b13b22a6c3670dc59223de0c0be6f30f
  allowlist_count: 35
  binding: PASS|FAIL
  zero_mutation: PASS|FAIL
verdict: GO|NO_GO
counts: {P0: 0, P1: 0, P2: 0, P3: 0}
findings:
  - id: CC-SF-001
    severity: P0|P1|P2|P3
    axis: spec|correctness|regression|security|testing|maintainability
    path: <repo-relative-path>
    line: 1
    spec_claim: <must/forbidden claim>
    trigger: <minimal reproducible input or mutation>
    observed: <actual validator behavior>
    risk: <concrete consequence>
    recommendation: <minimal repair and fixture>
verification:
  commands:
    - <exact command>
  results:
    standard_engine: PASS|FAIL|NOT_RUN
    mutation_probe_expected_exit_1: PASS|FAIL|NOT_RUN
    cross_layer: PASS|FAIL|NOT_RUN
  parity_summary:
    must_claims_checked: 0
    forbidden_claims_checked: 0
    unproven_claims: []
open_questions: []
```

Severity：P0 是資料破壞／重大安全或完全不可用；P1 是主要契約可被繞過、錯誤資源 resolve、重要資料／權限錯綁；P2 是可控邊界或測試缺口；P3 是非阻塞維護性。只列「沒有跑測試」不是 finding，必須指出未驗證的具體風險。

## 11. Gate 與 targeted re-review

- 外部 P0／P1：`NO_GO`，阻塞 STD-03。
- 外部 P2：記入 backlog，不單獨阻塞 STD-03；若其實能繞過主要契約或權限／resource binding，必須升為 P1。
- 無 P0／P1 且 binding、schema、mutation probe、cross-layer、zero-mutation 均 PASS：外部 gate 可 `GO`。
- 若出 P1，修復後沿同一條 review line 做 targeted re-review：只驗原 finding、修補 fixture／gate與相關 regression；不得假裝為另一輪全新大 review。修補 commit 必須另給完整 SHA、parent、tree、changed blobs；原 `d0824e5` 仍保持 immutable。
- 外部 CC 不寫 repo。Mainline 收到輸出後自行驗 binding、schema、redaction、zero mutation，再把 findings／receipt 寫回 repository。

Zero-mutation 收尾：

```sh
git diff --exit-code
git diff --cached --exit-code
git status --porcelain=v1
```

Reviewer 應在乾淨 detached checkout 執行；最後 `git status --porcelain=v1` 必須為空。若工具在 repo 內留下 cache／lock／receipt，先判 `zero_mutation: FAIL`，不要自行清除後掩蓋。
