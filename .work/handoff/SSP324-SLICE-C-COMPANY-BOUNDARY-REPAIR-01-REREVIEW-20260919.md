# SSP-324 切片 C — repair-01 定點複審交付包

## 鎖定

```
base             9ac5de7
original_review  48af52a（審的是 9ac5de7..4b4298c）
repair_commit    c6abe1e
branch           cc/ssp324-company-boundary
```

## 三筆 P1 全收；P2 依裁決留 residual

### F-01 retrieval 改吃真實形狀

先鎖容器與元素形狀，再比對引用：`selected_memories` 必須是物件陣列且每個
`memory_ref` 為字串，`source_refs` 必須是字串陣列。`memory_ref` 這個欄位
名讀自 `recall_context_pack.contract.permission_intersection_entry_fields`
——recall 自己用的同一份詞彙。

依你的裁決**沒有**擴大成無差別掃 `*_ref`：
`permission_decision_covered_memory_refs` 是授權涵蓋範圍、不是實際選中
結果，契約以 `scope_note` 明寫兩者不合併。

**交叉驗證**（請重點看這個）：

```
真實形狀、用 memory_ref 選中本次封包
  既有 recall evaluator → nil      ← 在 recall 那邊是合法 pack
  切片 C（repair 後）    → CSB_RETRIEVAL_NAMES_HANDLED_PACKAGE
另一份封包                → CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE
```

### F-02 follow-up 封閉形狀

allowlist（`unresolved_question`／`suggested_expert`）＋值形狀鎖；
canonical／lifecycle 的明確檢查保留在 allowlist 之前以維持loud code。

```
夾帶 record_ref + promotion_ref → CSB_FOLLOWUP_UNKNOWN_FIELD
unresolved_question 塞物件      → CSB_FOLLOWUP_QUESTION_NOT_STRING
```

契約另有斷言：followup allowlist 不得包含 `record_ref`／`promotion_ref`
（`weekly_review_cycle` 已明文禁止）／canonical／lifecycle 欄位。

### F-03 封包身分統一 — ⚠️ 這是對已驗收切片 A 的有限變更，明列於此

新增 `minimal_evidence_package.package_identity.id_template`，共用封包
evaluator 依它驗 `package_id`（新碼 `MEP_PACKAGE_ID_NOT_EVIDENCE_PACKAGE`），
切片 C 用**同一個 pattern** 排除。C 自宣告的前綴已移除，並有斷言禁止它
再出現。

**這收窄了切片 A 的 `package_id` 接受範圍。** 相容性：

```
切片 A golden：既有 42 筆逐字不變，只多出新增的那筆負例
切片 B（共用 helper）：PASS
切片 1 golden：27/27 不變
```

精確說法：**既有 golden 樣本結果未變；`package_id` 的接受集合是有意收窄**
——不是整個輸入域等價。原先一般 OMOS URN 可以通過，現在不能：

```
generic-but-non-template package_id
  切片 A → MEP_PACKAGE_ID_NOT_EVIDENCE_PACKAGE（repair 前：接受）
  切片 C → 這種封包身分已不可能存在，兩邊範圍一致
```

範圍對齊是靠**收窄 A**，不是放寬 C 的比對。

## 請重播

```bash
ruby scripts/validate_company_side_evidence_boundary_contract.rb
ruby scripts/validate_minimal_evidence_package_contract.rb
ruby scripts/validate_evidence_package_revision_contract.rb
ruby scripts/validate_personal_memory_contract.rb

grep -A10 "CSB_NEG_RETRIEVAL_SELECTS_PACKAGE_BY_MEMORY_REF" 規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
grep -A10 "CSB_NEG_FOLLOWUP_RECORD_AND_PROMOTION_REF"       規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
grep -A10 "CSB_NEG_FOLLOWUP_QUESTION_IS_OBJECT"             規格/v0.1/fixtures/company-side-evidence-boundary-negative-fixtures.json
grep -A6  "MEP_NEG_PACKAGE_ID_NOT_EVIDENCE_PACKAGE"         規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
```

合法控制案例：真實形狀 retrieval pack、不含封包、followup 用 null
expert → `nil`（沒有誤殺）。

## 逐 return site parity

```
共用封包 helper（MEP_）        23/23 全紅
共用推導 helper（COMPARISON_）  14/14 全紅
切片 A（access_request）         4/4 全紅
切片 B（PKGREV_）               27/27 全紅
切片 C（CSB_）                  19/19 全紅
```

## 你對我對照表第一列的校正，我已寫進契約

`promotion_flow.required_steps` 是「應該做哪些步驟」的權威，不是「這次
確實做完」的證據。逐項相等只證明清單完整有序。已寫入
`canonical_requires_full_promotion`，並明寫不為此新增第二套 ledger——執行
事實屬於那些步驟自己的契約，最終屬於 `SSP-295`。同理 C 的 PASS 不代表
呼叫者已認證授權。

## P2（residual）

`promotion_proposal_ref: false` 會跳過整組檢查、`promotion_steps_completed`
不受型別約束——已登 `文件/待辦重整.md`，依裁決本輪不動。

## Gate

```
ruby scripts/validate_*.rb（37 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
