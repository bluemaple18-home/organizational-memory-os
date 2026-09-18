# SSP-324 切片 C — 大 review 交付包

## 鎖定

```
base    9ac5de7
review  （本次 commit，待 push 後補上）
branch  cc/ssp324-company-boundary
```

```
規格/v0.1/personal-harness-integration.yaml         +company_side_evidence_boundary
scripts/validate_company_side_evidence_boundary_contract.rb  234 行
規格/v0.1/fixtures/company-side-evidence-boundary-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
```

**未修改切片 A／B、切片 1、SSP-294 任何既有契約或程式。**

## 這張卡

`SSP-324` 最後一片：公司端使用邊界 ＋ `NEEDS_ORG_FOLLOWUP` 不得取得
canonical identity。驗證單位是一筆公司端處理紀錄——用途與產出必須一起
看，分開驗會各自留一半。

## 我先答完「權威對照物是誰」才動工

這是切片 A／B 三輪 repair 換來的紀律。三輪 NO_GO 的共同根因都是
「驗了形式，沒驗它從哪來」，所以這片每條檢查都先答這個問題：

| 要驗的事 | 權威對照物 | 位置 |
|---|---|---|
| canonical 是否走完整路徑 | `promotion_flow.required_steps` | 上游，逐項比對 |
| retrieval 的欄位詞彙 | `recall_context_pack...pack_required_fields` | 上游，讀欄位名 |
| 封包有沒有混進 retrieval | 本筆自己的 `package_ref` | 同筆事實 |
| follow-up 不得 canonical | `historical_comparison` lifecycle 禁列 | 共用 helper |
| 上位宣告仍在 | `core_invariants`／`capability_safety_floor` | 上游，只確認未被繞過 |

**唯一自創的是 purpose 詞彙**（上游沒有），所以從一開始就是封閉
allowlist，而不是禁用清單——「不在 ban list 上」正是切片 A 初版漏掉
`private_blob` 的原因。另有斷言要求每個 forbidden purpose 都被負例實際
打過。

## 請重播

```bash
ruby scripts/validate_company_side_evidence_boundary_contract.rb  # 應 PASS
ruby scripts/validate_personal_memory_contract.rb                  # 應 PASS（聚合器）

# Acceptance #4：正式 retrieval 命不到封包
grep -A6 "CSB_NEG_RETRIEVAL_NAMES_HANDLED_PACKAGE" 規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
grep -A6 "CSB_NEG_RETRIEVAL_NAMES_OTHER_PACKAGE"   規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
# canonical 不是捷徑
grep -A6 "CSB_NEG_PROMOTION_STEPS_SKIP_WRITER"     規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
# Acceptance #5：suggested_expert=null 合法但不得 canonical
grep -A6 "CSB_POS_FOLLOWUP_NULL_SUGGESTED_EXPERT"  規格/v0.1/fixtures/company-side-evidence-boundary-positive-fixtures.json
grep -A6 "CSB_NEG_FOLLOWUP_CANONICAL"              規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
```

15/15 return site 全紅；中和 Acceptance #4 的 guard 驗證聚合器同步轉紅；
37/37 Ruby validator PASS；`git diff --check` clean。

## 對應卡片 Acceptance

```
#3 reverse browse/search/pull 一律拒絕   → 切片 A 已收（access_boundary）
#4 Evidence Package 無法被正式 company   → CSB_RETRIEVAL_NAMES_HANDLED_PACKAGE /
   retrieval fixture 命中                  CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE
#5 NEEDS_ORG_FOLLOWUP + null expert 合法  → 兩個正例 + CSB_FOLLOWUP_CARRIES_CANONICAL /
   但不得產生 canonical identity            CSB_FOLLOWUP_CARRIES_LIFECYCLE_FIELD
「只可 review/verification/audit」        → 封閉 allowlist，四個 forbidden purpose
                                            各有負例
「不得成為 Canonical」                    → CSB_PROMOTION_STEPS_INCOMPLETE（比對上游
                                            required_steps）＋ 契約斷言
                                            direct_copy_to_shared_canonical 仍 forbidden
#1/#2/#6/#7/#8                            → 切片 A／B 已收
```

## 請特別判斷（含我主動揭露的邊界）

1. **`evidence_package_ref_prefix` 是本片宣告的**，因為上游沒有
   evidence-package 的 id_template（切片 A 對 `package_id` 也只驗 generic
   URN）。為了不讓宣告漂移，validator 對每個正例額外斷言「該筆
   `package_ref` 必須符合宣告的前綴」。請判斷這個處理是否足夠，或該回頭
   在 `personal_memory_resource_contracts` 補一個 template（那會動到別片）。
2. **retrieval 只檢查 `selected_memories`／`source_refs` 兩個欄位**：這是
   `pack_required_fields` 裡會攜帶 ref 的兩個。其餘欄位（如
   `permission_decision_covered_memory_refs`）是否也該納入檢查範圍？我傾向
   要，但那會擴大本片對 recall 契約的耦合面，想先聽你判斷。
3. **本片不驗「誰在呼叫」**：actor／authz 仍是既有
   `actor_action_policy` 與 permission-before-retrieval 的職責（切片 A
   review 時你已確認過這個切分）。請確認在公司端這一側同樣成立。

## Gate

```
ruby scripts/validate_*.rb（37 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
fixtures：6 positive + 23 negative = 29
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
若 `GO`，`SSP-324`（EMEM-10）三片全數收完。
