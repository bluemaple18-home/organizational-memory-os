# SSP-324 切片 A — 大 review 交付包

## 鎖定

```
base    faf6822
review  （本次 commit，待 push 後補上）
branch  cc/ssp324-package-boundary
```

```
規格/v0.1/personal-harness-integration.yaml         +minimal_evidence_package
scripts/validate_minimal_evidence_package_contract.rb   258 行
規格/v0.1/fixtures/minimal-evidence-package-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
文件/待辦重整.md                                     切片 3 的 P2 標記 CLEARED
```

**未修改 SSP-294 A/B/C 或 SSP-323 四片的任何既有契約區塊。**

## 這張卡

`SSP-324`（EMEM-10）切片 A：Package Boundary + Reverse-Access Boundary，
順帶收掉 SSP-323 切片 3 留下的 `local_first_export_surface` P2。

核心設計：驗證單位是**一次傳輸事件**（`access_request` + `package` 一起
驗）。「公司只能拿到明確送出的封包」同時是封包形狀問題與取得路徑問題，
只驗一半、另一半就是宣稱——切片 3 那筆 P2 正是這樣產生的。

## 請重播

```bash
ruby scripts/validate_minimal_evidence_package_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb             # 應 PASS（聚合器）

# reverse-access：五種 forbidden request kind 各有負例
grep -c "MEP_NEG_FORBIDDEN_ACCESS_KIND" 規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json

# consent 規則是從上游讀的，不是對 EMPLOYEE_PRIVATE 寫死
grep -A3 "MEP_POS_SHARED_WORK_CONTEXT_WITHOUT_CONSENT" 規格/v0.1/fixtures/minimal-evidence-package-positive-fixtures.json

# 接回總入口的證明：中和 MEP_FORBIDDEN_ACCESS_KIND 的 guard，
# 不只直接呼叫新片會紅，呼叫總入口也應該紅
# 逐 return site parity（非逐 code）→ 我的結果 18/18 全紅
```

## 對應卡片 Acceptance

```
#1 合法 Proposal 只帶 bounded package  → 20 個 required field 全是 refs/
                                          snapshot，無 whole-store 欄位
#2 缺 anchor/provenance/ACL/integrity/ → MEP_REQUIRED_FIELD_MISSING /
   redaction metadata fail closed         MEP_REF_LIST_NOT_URN_ARRAY /
                                          MEP_REF_FIELD_NOT_URN
#3 reverse browse/search/pull/          → MEP_FORBIDDEN_ACCESS_KIND（五種各一
   remote-query 一律拒絕                   負例，validator 另有斷言強制覆蓋）
#8 EMPLOYEE_PRIVATE 無 consent          → MEP_CONSENT_REQUIRED_BUT_MISSING
   fail closed                            （條件讀上游 mode 宣告）
#4/#5/#6/#7                             → 切片 B／C（明確不在本片）
```

## 請特別判斷

1. **`content_snapshot` 目前只要求非空字串，沒有長度或結構上限**：卡片
   要求「最小必要資料、不得擴張成 whole Personal Store dump」。目前的
   機器邊界是「禁止那三個 whole-store 欄位名」+「其餘欄位都是 ref」，
   但 `content_snapshot` 本身理論上可以塞進一份極大的文字。請判斷是否
   需要長度上限（那會是一個相當武斷的數字），或維持現狀、把「最小必要」
   交給 review/pilot 判斷。
2. **`content_hash` 沒有跟 `content_snapshot` 做實際計算比對**：目前只
   要求兩者都是非空字串。要真的綁定需要指定 hash 演算法與正規化規則
   （上游 `personal_memory_resource_contracts` 沒有現成的可綁）。請判斷
   這是否該在本片補、或屬於另一張卡。
3. **`access_request` 沒有 actor/permission 欄位**：本片只鎖「能不能用
   這種方式問」，不鎖「誰在問」——後者是既有
   `ownership_visibility_contract.actor_action_policy` 與
   Permission-before-Retrieval 的職責。請確認這個切分正確，或本片該
   一併要求 actor 欄位。
4. **切片 3 的 P2 我直接標記 `CLEARED`**（理由：封閉列舉的兩項現在都有
   實際 enforcement）。請確認這個收斂判斷成立，或該維持 OPEN 直到
   `SSP-295` 真人 pilot 實證。

## Gate

```
ruby scripts/validate_*.rb（35 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
