# EMEM-11 切片 1｜Local Personal Store Runtime — Handoff Packet（送獨立大 review）

- 卡片：`.work/CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918.md`
- 分支：`cc/emem11-local-store-runtime`
- 交付 SHA：`39534c999f2dde46c6d7eae7f2e25bbaba5b584c`
- 基底：`ee11da5`（main，已含 Owner 裁決的 Design Freeze A～F）
- worktree：`../知識庫-emem11a`

## 1. 這片交付什麼

`personal_memory_runtime` 契約區塊 + `scripts/validate_personal_memory_runtime_contract.rb`
+ 正負 fixtures。驗證單位是**一段對同一個本機 personal store 的 runtime 操作序列**：
store 表頭（engine / journal_mode / schema_version）＋依序發生的 operations。

選序列而不是單筆，是因為這片要守的保證全都跨操作才成立：schema_version 必須是
migration 鏈的尾巴、idempotent replay 必須落回同一列、revision 必須指向這個 store
裡真的寫過的前身、同一個 `review_period_id` 只能有一次 terminal closeout。
單看一筆操作，以上沒有一條驗得出來。

卡片切片 1 的十個 scope 項目與守衛對應：

| scope 項目 | 守衛 |
|---|---|
| SQLite schema | `PMR_STORE_ENGINE_NOT_SQLITE`、`PMR_ROW_KIND_UNKNOWN`、`PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE` |
| WAL / 連線政策 | `PMR_STORE_JOURNAL_MODE_NOT_WAL` |
| schema version / migration receipt | `PMR_MIGRATION_RECEIPT_INCOMPLETE`、`PMR_MIGRATION_CHAIN_BROKEN`、`PMR_MIGRATION_RECEIPT_MUTATED`、`PMR_STORE_SCHEMA_VERSION_NOT_MIGRATION_CHAIN_TAIL` |
| transaction 邊界 | `PMR_WRITE_OUTSIDE_TRANSACTION`、`PMR_UNCOMMITTED_WRITE_DURABLE` |
| 唯一 ID / idempotency | `PMR_IDEMPOTENCY_KEY_INVALID`、`PMR_IDEMPOTENT_REPLAY_CREATED_SECOND_ROW` |
| 不可變 revision / supersession | `PMR_IN_PLACE_ROW_OVERWRITE`、`PMR_HISTORY_ERASURE`、`PMR_SUPERSEDES_TARGET_*`（3 碼） |
| review-period / closeout 唯一性 | `PMR_DUPLICATE_TERMINAL_CLOSEOUT`、`PMR_CLOSEOUT_*_NOT_IN_VOCABULARY` |
| HostSessionBinding 儲存 | `PMR_HOST_BINDING_*`（6 碼）、`PMR_MCP_OPERATION_MISSING_HOST_BINDING`、`PMR_CLI_OPERATION_CLAIMS_HOST_BINDING` |
| 確定性權限檢查 seam | `PMR_PERMISSION_CHECK_NOT_FIRST` |
| MCP server base interface | `PMR_SURFACE_FORBIDDEN`、`PMR_SURFACE_NOT_IN_CLOSED_ENUM`、`PMR_PATH_NOT_DECLARED_PATH` |

## 2. 對照表（每個檢查：對照物是誰、它長什麼樣、我讀的是不是同一個東西）

這是 SSP-324 收尾時自己記下的紀律，這片先做完再送 review。

| 檢查 | 權威對照物 | 對照物的資料形狀 | 我讀的是不是同一個東西 |
|---|---|---|---|
| supported_hosts_v1 合法性（凍結 B） | `runtime_policy.optional_executors` | 6 元素字串陣列 | 是。契約層做子集斷言；evaluator 內**沒有**任何 host 名單字面值 |
| HostSessionBinding 身分欄位（凍結 C） | `runtime_policy.portable_record_contract.executor_provenance_fields` | `["executor_ref","executor_session_ref"]`，字串陣列 | 是。YAML 只放 `executor_identity_fields_ref`，並斷言不得內嵌 `executor_identity_fields`；另加斷言「上游若改形狀就紅」 |
| closeout 狀態 / terminal / attempt 詞彙（凍結 D） | `weekly_review_cycle.closeout_statuses` / `.terminal_statuses` / `.attempt_kinds` | 三個字串陣列（4 / 3 / 3 元素） | 是。三者都以 `*_vocabulary_ref` 指過去，並斷言 `closeout_uniqueness` 不得內嵌同名副本 |
| row id 形狀 | `personal_memory_resource_contracts.shared_constraints.id_templates` | `{kind => "urn:…:{uuidv7}"}` 映射 | 是。用切片 A 既有的 `MEPShape.build_id_template_pattern` 展開，UUID 版本位元由 `identifiers.omos_generated.algorithm` 推導，不寫死 7 |
| revision / receipt 不可變 | `correction_flow.contract.forbidden` + `.immutable_receipt` | 5 元素字串陣列 + boolean | 是。斷言三個禁項仍在；`PMR_IN_PLACE_ROW_OVERWRITE` / `PMR_HISTORY_ERASURE` / `PMR_MIGRATION_RECEIPT_MUTATED` 是它們在 runtime 層的 enforcement |
| 讀路徑權限 seam | `capability_safety_floor.invariants` | 5 元素字串陣列 | 是。斷言 `permission_before_retrieval` 仍在，並要求 `path.first == RUNTIME_POLICY_CHECK` |
| FAILED 可重試但非 terminal | `weekly_review_cycle`（`closeout_statuses` ⊃ `terminal_statuses`） | 同上 | 是。額外斷言 `FAILED ∈ closeout_statuses ∧ FAILED ∉ terminal_statuses`——否則「retry 保留同一 review_period_id」會被誤判成第二次 closeout |

## 3. Design Freeze 落地位置

- **A／invariant `NO_REMOTE_PERSONAL_STORE_ACCESS_SURFACE`**：`access_surfaces` 是封閉
  列舉且斷言兩者都以 `LOCAL_` 開頭；`forbidden_access_surfaces` 四項
  （HTTP_TUNNEL / REMOTE_QUERY / REMOTE_MOUNT / COMPANY_SIDE_FORWARDING）**每一項都有
  負例實際打過**，validator 會檢查這件事，不接受只宣告在 YAML 裡。
- **B**：見對照表。
- **C**：`host_session_binding` 是封閉外殼＝上游身分欄位 + `{cwd, project_ref,
  effective_scope}`。`host` / `host_session_id` / `session_id` / `client_id` /
  `agent_id` / `remote_endpoint` 以 `PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD`
  先於泛用 unknown-field 失敗。附加欄位另有值形狀鎖
  （`PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING`）——欄位名合法不等於值合法。
- **D**：SQLite constraint 是 enforcement 不是權威，見對照表。
- **E**：`owner_authorization` 逐字保留 Owner 的限定範圍，validator 斷言
  `Personal scope only` 字樣仍在。
- **F／invariant `LOCAL_CLI_AND_HOST_MCP_SHARE_THE_SAME_RUNTIME_AUTHORITY`**：
  兩個 surface 共用同一條 `write_path`；`direct_sql` 這類欄位會被
  `PMR_OPERATION_UNKNOWN_FIELD` 擋（負例即以 `direct_sql: true` 打），跳過
  transaction 步驟則被 `PMR_PATH_NOT_DECLARED_PATH` 擋。
- **invariant `HOST_BINDING_IS_AN_ADAPTER_NOT_THE_RUNTIME`**：MCP 操作必須帶 binding、
  CLI 操作必須不帶（`PMR_CLI_OPERATION_CLAIMS_HOST_BINDING`）；但兩者的 path、
  transaction、id、唯一性規則完全相同——adapter 不因為存在與否而改變 runtime 權威。

## 4. 證據

- `ruby scripts/validate_personal_memory_runtime_contract.rb`
  → `PASS ... (surfaces=2 hosts=2 codes=47)`
- `ruby scripts/validate_personal_memory_contract.rb` → `PASS`（aggregator 已接上）
- 全庫 38 個 validator 全綠（原 37，本片 +1）
- **return-site parity sweep：47/47**。逐一刪除守衛敘述 → 切片 validator 與
  aggregator 入口**同時**轉紅 → 由 job-tmp 備份還原 → `diff` 驗證 byte-identical。
  （未使用 `git stash`。）
- **上游漂移探針：8/8 全紅**——移除 `optional_executors` 的 Codex、改名
  `executor_provenance_fields`、移除 `terminal_statuses` 的 COMPLETE、移除
  `closeout_statuses` 的 NO_PROMOTION、移除 `attempt_kinds` 的 CATCH_UP、
  更動 Record 的 `id_template` 前綴、移除 `correction_flow` 的
  `in_place_record_overwrite`、移除 floor 的 `permission_before_retrieval`。
  每次都還原並 `diff` 驗證 spec byte-identical。
- fixtures：2 正例（完整九步序列 / 最小兩步序列）、50 負例涵蓋 47 個錯誤碼
  （`PMR_SURFACE_FORBIDDEN` 有 4 筆，四種遠端面各一）。

## 5. 已知邊界（請 review 針對這些下手）

1. **`STORE_READ` 目前不帶 payload，也不檢查讀到什麼**。權限 seam 只證明
   「policy check 在 store 存取之前」，沒有證明 check 的**結果**被遵守。
   這是刻意留給切片 2／3 還是這片就該補，請裁決。
2. **`effective_scope` 目前只鎖成非空字串，沒有綁 `employee_memory_scope_modes` 的詞彙。**
   我認為這是真缺口（正是「欄位名合法、值未綁上游」那一族），但補它會動到
   scope 區塊的接點，先不自行擴張。
3. **`transaction` 只檢 `committed`，沒有檢 SQLite 的 `IMMEDIATE`/`DEFERRED` 模式，
   也沒有連線併發政策（WAL 之外）**。卡片寫的是「WAL/connection policy」，
   我只落了 WAL。
4. **row 的內容完全沒驗**——只驗 id / kind / key / supersedes。內容欄位屬於
   `personal_memory_resource_contracts` 的 `required_fields`，這片沒有接上去。
   是否該接，請裁決（接了會與切片 3 的 portability 檢查重疊）。
5. **`genesis_version: "0.0.0"` 是本片新造的值**，沒有上游對照物。它是 migration
   鏈起點的錨，我找不到既有宣告可綁。

## 6. 請 review 回覆格式

`GO` / `NO_GO` + P0～P3 分級。若 `NO_GO`，請指明 repair 只收哪幾項。
