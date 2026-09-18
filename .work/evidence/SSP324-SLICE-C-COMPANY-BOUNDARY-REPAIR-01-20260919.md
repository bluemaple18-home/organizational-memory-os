# SSP-324 切片 C — repair-01 evidence

日期：2026-09-19　branch：`cc/ssp324-company-boundary`

```
base            9ac5de7
original_review 48af52a（審的是 9ac5de7..4b4298c）
repair_commit   （本次 commit，待 push 後補上）
```

## Reviewer NO_GO（對 `48af52a`）

```
P0=0 / P1=3 / P2=1 / P3=0
```

三筆 P1 全部是同一族：**欄位名對上 ≠ 資料形狀與來源也對上**。

## F-01｜retrieval 用了錯的資料形狀

既有 recall evaluator 讀的是
`selected.map { |m| m["memory_ref"] }`——`selected_memories` 是**物件
陣列**，`source_refs` 才是裸 ref。切片 C 卻把兩者拼起來直接比字串，於是
真正被選中的封包完全看不見。我自己原本的 retrieval 正例也用了裸字串形狀，
所以從來沒踩到真實形狀。

**修法**：先鎖容器與元素形狀（`selected_memories` 必須是物件陣列且每個
`memory_ref` 為字串；`source_refs` 必須是字串陣列），再比對引用。
`memory_ref` 這個欄位名讀自
`recall_context_pack.contract.permission_intersection_entry_fields`
——recall 自己用的同一份詞彙，不自創。

依裁決，**不**把檢查擴大到所有 `*_ref` 欄位：
`permission_decision_covered_memory_refs` 是授權涵蓋範圍，不是實際選中
結果，兩者是不同義務，契約以 `scope_note` 明寫不合併。

**交叉驗證**（這是重點）：

```
真實形狀、用 memory_ref 選中本次封包
  既有 recall evaluator → nil      ← 在 recall 那邊完全合法
  切片 C（repair 後）    → CSB_RETRIEVAL_NAMES_HANDLED_PACKAGE
另一份封包（相同 identity 規格）
  切片 C                → CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE
```

## F-02｜follow-up 仍是開放形狀

**修法**：封閉 allowlist（`unresolved_question`／`suggested_expert`）
＋值形狀鎖。canonical 與 lifecycle 的明確檢查保留在 allowlist **之前**，
讓那些名字仍以自己的錯誤碼失敗。

```
夾帶 record_ref + promotion_ref → CSB_FOLLOWUP_UNKNOWN_FIELD
unresolved_question 塞物件      → CSB_FOLLOWUP_QUESTION_NOT_STRING
```

第一條正是 `weekly_review_cycle` 已對 NEEDS_ORG_FOLLOWUP 明文禁止的欄位
——切片 C 原本等於在跟一張已驗收的契約互相矛盾。契約層另有斷言：followup
allowlist 不得包含 `record_ref`／`promotion_ref`／canonical／lifecycle。

## F-03｜封包身分：A 的准入與 C 的排除改用同一判定

**這是本輪對已驗收切片的有限變更，明列如下，不包裝成「完全沒動其他切片」。**

新增 `minimal_evidence_package.package_identity.id_template`
（`urn:omos:personal-memory:evidence-package:{uuidv7}`），共用封包
evaluator 依它驗 `package_id`（新錯誤碼
`MEP_PACKAGE_ID_NOT_EVIDENCE_PACKAGE`），切片 C 用**同一個 pattern** 做
排除。C 自己宣告的前綴已移除，契約另有斷言禁止它再出現。

**這確實收窄了切片 A 對 `package_id` 的接受範圍。** 相容性驗證：

```
切片 A golden：既有 42 筆逐字不變，只多出新增的那筆負例
              （MEP_NEG_PACKAGE_ID_NOT_EVIDENCE_PACKAGE）
切片 B（共用同一支 helper）：PASS
切片 1 golden：27/27 不變
```

也就是**沒有任何原本被接受的輸入改變結果**；改變的是原本「不該被接受卻被
接受」的那一類：

```
generic-but-non-template 的 package_id
  切片 A → MEP_PACKAGE_ID_NOT_EVIDENCE_PACKAGE（repair 前：接受）
  切片 C → 該封包身分已不可能存在，兩邊範圍因此一致
```

範圍對齊是靠**收窄 A**，不是靠放寬 C 的比對——後者只會讓 C 去猜。

## 合法控制案例（不得誤殺）

```
真實形狀 retrieval pack、不含封包、followup 用 null expert → nil
```

## 逐 return site parity（非逐 code）

```
共用封包 helper（MEP_）        23 sites → 23/23 全紅
共用推導 helper（COMPARISON_）  14 sites → 14/14 全紅
切片 A（access_request）         4 sites → 4/4 全紅
切片 B（PKGREV_）               27 sites → 27/27 全紅
切片 C（CSB_）                  19 sites → 19/19 全紅
```

## 對照表第一列的校正（依裁決）

`promotion_flow.required_steps` 是「應該做哪些步驟」的權威，**不是**
「這次確實做完」的證據。逐項相等只證明提交的清單完整、有序，不能證明
Verification／Review／Writer 真的跑過。已寫入契約
`canonical_requires_full_promotion`，並明寫不為此新增第二套 ledger
——執行事實屬於那些步驟自己的契約，最終屬於 `SSP-295` 真人 pilot。

同理，C 的 PASS 只代表這筆處理紀錄符合 C 的用途／輸出契約，不代表呼叫者
已認證、已授權（actor／authz 維持既有分工，不在 C 重做）。

## P2（residual，未修）

`promotion_proposal_ref: false` 會跳過整組 promotion 檢查，連帶讓
`promotion_steps_completed` 不受型別約束——已登 `文件/待辦重整.md`，
依裁決本輪不動。

## Gate

```
ruby scripts/validate_*.rb（37 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
切片 C fixtures：6 positive + 28 negative
```
