# SSP-291 EMEM-02 Personal Evidence Profile — 實作 evidence

日期：2026-09-11　branch：`cc/ssp291-personal-evidence-profile`　base：`5e5d9a8`

## Measured gap（實測，非推測）

實作前在 `main` 執行：

```
grep -rn "source_profiles\|employee_memory_profile_minimum\|connector_grants\|capture_scope" scripts/*.rb
→ 0 hits
```

`規格/v0.1/personal-harness-integration.yaml` 的 `employee_memory_profile_minimum`、
`source_profiles`、`role_profiles`、`phase_1_pilot` 全是散文，沒有任何 validator 讀它們。
兩份剛驗收的 adapter mapping（`ebeaab2` Document、`0ac8c09` Jira）與個人層之間沒有任何機器連線，
「所有來源映射到同一 RawEvidence contract」在 repo 裡無法被證偽。

## 交付

| 檔 | 行數 | 說明 |
| --- | --- | --- |
| `規格/v0.1/personal-evidence-profile.yaml` | 142 | 擷取准入契約 |
| `scripts/validate_personal_evidence_profile_contract.rb` | 288 | 薄 validator（< 400 行硬上限） |
| `規格/v0.1/fixtures/personal-memory-{positive,negative}-fixtures.json` | +2 / +19 cases | 共用 fixture 檔追加兩個 key |
| `scripts/validate_personal_memory_contract.rb` | +1 slice | 掛進 aggregator，納入既有 gate |

## 設計要點

1. **零列舉重述**。role / source catalog / phase gate / capability level / scope mode /
   ownership mode / visibility scope 全部在執行期由 `upstream_bindings` 的 path 從上游規格讀取。
   validator 本身不存任何一份清單。上游一改，判斷即改（P3/P4 probe 已證）。
2. **adapter mapping 執行期綁定**。每個 phase-1 來源指名一份已驗收 mapping，
   `source_system` 由那份 mapping YAML 當場讀出，並與擷取宣稱投影出的 `source_system` 比對。
   契約內另有斷言禁止把 `source_system` 值複寫進本契約（避免抄一份就永遠相等）。
3. **phase gate fail-closed**。`next_sources_if_policy_ready`（Teams / Outlook）在
   permission/retention/deletion 契約（repo #4，Owner blocked）凍結前不得擷取。
4. **error_contract 由原始碼綁定**。吸取 SSP-302 TIGHTEN-F-01：`reachable_failure_codes`
   掃描 `evidence_profile_failure` 的 `return "<CODE>"` 字面量，與 YAML `error_contract` keys 取等。
   兩份手寫清單互比證明不了 evaluator，故不採用。
5. **未綁定分支已移除**。`EPROFILE_ADAPTER_MAPPING_NOT_BOUND` 在 phase gate + 結構斷言下
   不可達，故從 evaluator 與 error_contract 刪除，改由結構斷言（P2 probe）承擔。

## 驗證

### 負例單一 mutation（逐葉比對，非宣稱）

吸取 SSP-302 TIGHTEN-F-02（在自撰 evidence 中寫下未驗證的事實宣稱）：本輪以程式逐葉展開
每個負例與正例 base，計算對稱差。**19 個負例全部剛好差 1 個 leaf path**，逐案清單見下：

```
1 EPROFILE_NEG_MEMORY_POLICY_FIELD_MISSING        /profile/memory_policy/retention_policy_ref
1 EPROFILE_NEG_CLAIMS_CANONICAL_DIRECT_WRITE      /profile/granted_authorities/2
1 EPROFILE_NEG_UNKNOWN_ROLE_PROFILE               /profile/identity/role_profile
1 EPROFILE_NEG_CAPABILITY_LEVEL_OFF_MATRIX        /profile/memory_policy/capability_level
1 EPROFILE_NEG_SCOPE_MODE_OFF_CONTRACT            /profile/memory_policy/personal_scope_mode
1 EPROFILE_NEG_OWNERSHIP_MODE_OFF_CONTRACT        /profile/memory_policy/ownership_mode
1 EPROFILE_NEG_VISIBILITY_SCOPE_OFF_CONTRACT      /profile/memory_policy/visibility_scope
1 EPROFILE_NEG_CAPTURE_OF_ANOTHER_EMPLOYEE        /capture/employee_id
1 EPROFILE_NEG_SOURCE_NOT_IN_CATALOG              /capture/source_type
1 EPROFILE_NEG_SOURCE_OUTSIDE_ROLE_PROFILE        /capture/source_type
1 EPROFILE_NEG_PHASE_2_SOURCE_CAPTURED_EARLY      /capture/source_type
1 EPROFILE_NEG_NO_ACTIVE_CONNECTOR_GRANT          /profile/source_policy/connector_grants/0/status
1 EPROFILE_NEG_NO_CONSENT_OR_NOTICE_REF           /profile/source_policy/consent_or_notice_ref
1 EPROFILE_NEG_CONTAINER_OUTSIDE_CAPTURE_SCOPE    /capture/container
1 EPROFILE_NEG_PROJECTED_SOURCE_SYSTEM_WRONG_ADAPTER  /capture/projected_source_identity/source_system
1 EPROFILE_NEG_PROJECTED_INSTANCE_NOT_DECLARED    /capture/projected_source_identity/source_instance_id
1 EPROFILE_NEG_SOURCE_POLICY_NOT_AN_OBJECT        /profile/source_policy（整個群組換成 null）
1 EPROFILE_NEG_CONSENT_REF_KEY_ABSENT             /profile/source_policy/consent_or_notice_ref（key 消失）
1 EPROFILE_NEG_POLICY_REF_PRESENT_BUT_BLANK       /profile/memory_policy/sensitivity_policy_ref
```

`EPROFILE_NEG_NO_ACTIVE_CONNECTOR_GRANT` 最初是「刪掉陣列第 0 個元素」，逐葉比對顯示 5 處差異
（index shift 造成），已改為把該筆 grant 的 `status` 改成 `REVOKED`，回到真正的單點 mutation，
語意上也更強（撤銷的授權不得准入）。

### Enforcement parity（evaluator 分支）

對 `evidence_profile_failure` 的 18 條 guard，逐條把條件中和成永不觸發（`unless true` / `if false`），
保留 code 字面量使原始碼掃描仍綠，因此 RED 只可能來自 fixture 對該條 enforcement 的覆蓋。
備份還原一律用 `cp`，**不用 `git checkout --`**（會從 index 還原並抹掉未提交修改）。

**18 RED / 0 GREEN，18/18。**

首輪跑出 3 個 GREEN(bad)，全落在 profile 結構的三條 guard：
`is_a?(Hash)` 無任何負例；`key?` 與 `present?` 互相遮蔽。已補三個負例
（群組非物件 / consent key 整個消失 / policy ref 存在但空字串）後轉全紅。
這 3 個 GREEN 是真實缺口，不是 probe 誤判。

### 結構與跨契約 probe

| Probe | 動作 | 結果 |
| --- | --- | --- |
| P1 | evaluator 改名一個 code，YAML 未同步 | RED |
| P2 | 移除 DOCUMENT adapter binding | RED |
| P3 | 改 `jira-adapter-mapping.yaml` 的 `source_system` 值 | RED |
| P4 | 上游 `phase_1_pilot.first_sources` 多一個來源 | RED |
| P5 | `upstream_bindings` 指向不存在的上游路徑 | RED |
| P6 | authority floor 少一項禁止授權 | RED |

**6 RED / 0 GREEN。** P3/P4 是關鍵：證明 adapter 綁定與 phase gate 是執行期讀取，不是複寫。
所有 probe 後上游檔案 `git diff --name-only` 為空，未留下改動。

### Gate

- Ruby validators：**21 PASS / 0 FAIL**（含新 slice；先前 20 支結果不變）。
- `scripts/validate_personal_memory_contract.rb` aggregator：PASS（新 slice 已納入）。
- `validate_cc_cross_layer_contract.py`：PASS，negative 8。
- `validate_document_adapter_mapping_instances.py`：PASS，positive 10 / negative 3。
- `validate_jira_adapter_mapping_instances.py`：PASS，positive 6 / negative 3。
- `validate_std_schema_engine.py`：STD01 12/12、STD02 16/16、STD03 9/9。
- `git diff --check`：clean。
- 檔案大小：validator 288 行（`< 400` 硬上限）。

## 已知取捨（請 reviewer 特別看）

1. 本契約**只單向**綁上游，沒有回頭把 `PersonalEvidenceProfile` 加進
   `contract_registry.define_for_employee_memory`。理由是不動已鎖上游；代價是上游的 registry
   仍未列出這份契約。若 reviewer 認為 registry 必須完整，這是 P2 而非 P1（gate 已由 aggregator 涵蓋）。
2. 上游 `role_profiles` 列了 `CLIENT_FEEDBACK` / `CRM_ENTITY` / `CLIENT_DOCUMENT`，
   但 `source_profiles` 目錄裡沒有這三個。本契約的判斷順序讓它們一律落在
   `EPROFILE_SOURCE_NOT_DECLARED`（fail-closed，正確），但這暴露了上游本身的不一致。
   我沒有改上游。是否要開一張 Owner 卡修 `source_profiles`，請 reviewer 給意見。
3. `capture_scope` 目前是 `source_instance_ids` + `containers` 兩個扁平清單的成員判斷。
   不做前綴 / 階層 / glob，因為那需要各來源的容器階層語意，屬 connector 範疇（明確排除）。
