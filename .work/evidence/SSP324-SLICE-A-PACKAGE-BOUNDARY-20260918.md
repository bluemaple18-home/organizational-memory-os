# SSP-324 切片 A — evidence

日期：2026-09-18　branch：`cc/ssp324-package-boundary`　base：`faf6822`

## 交付

```
規格/v0.1/personal-harness-integration.yaml   +minimal_evidence_package 區塊
scripts/validate_minimal_evidence_package_contract.rb   258 行（< 400）
規格/v0.1/fixtures/minimal-evidence-package-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
文件/待辦重整.md                                       切片 3 的 P2 標記 CLEARED
```

**未修改 SSP-294 A/B/C 或 SSP-323 四片的任何既有契約區塊**——只透過
pointer/binding 讀取。

## 設計回應

### 驗證單位是「一次傳輸事件」，不是單獨的封包

`transmission_failure(run, ...)` 的 run 同時包含 `access_request` 與
`package`。理由：卡片要的「公司只能拿到明確送出的封包」同時是**封包形狀
問題**（裡面能放什麼）與**取得路徑問題**（怎麼拿到的）——只驗其中一半，
另一半就只是宣稱。這也是切片 3 那筆 P2 的成因（只驗列舉、沒驗行為）。

### Reverse-access：不是「被 policy 拒絕」，是結構上無法表達

`access_boundary` 的 request 詞彙只有兩個欄位（`request_kind`／
`package_ref`），且 `request_kind` 的唯一合法值是 `PACKAGE_LOOKUP`：

- `BROWSE`／`SEARCH`／`PULL`／`REMOTE_QUERY`／`REMOTE_MOUNT`
  → `MEP_FORBIDDEN_ACCESS_KIND`（五種各有獨立負例實際打過，validator
  另有一條斷言強制每種 forbidden kind 都必須被負例覆蓋，不能只宣告在
  YAML 裡）
- 在合法 lookup 上夾帶 `query`／`filter`／`scope` 等欄位
  → `MEP_ACCESS_REQUEST_UNKNOWN_FIELD`
- `package_ref` 塞 Hash／萬用字元 → `MEP_PACKAGE_REF_NOT_URN`
  （值形狀鎖，預先套用 SSP-323 切片 4 兩輪 repair 學到的教訓：只鎖欄位
  名稱、不鎖值形狀會留同根 bypass）
- 用合法 lookup 換走另一個封包 → `MEP_PACKAGE_REF_MISMATCH`

### governance 不是自報，是跟上游對帳

package 宣告 `scope_mode`，其 `ownership_mode`／`visibility_scope`
必須**等於** `ownership_visibility_contract.mode_definitions` 對那個
mode 的定義（`MEP_OWNERSHIP_MODE_MISMATCH`／
`MEP_VISIBILITY_SCOPE_MISMATCH`）——封包不可能一邊宣稱
`EMPLOYEE_PRIVATE`、一邊帶著公司級的 visibility_scope。

### consent 綁上游，不把 mode 名稱寫死

「是否需要 consent」讀上游該 mode 的 `consent_or_notice_required`：任何
宣告為 `CONSENT_REQUIRED` 的 mode 都必須帶非空 `consent_ref`，否則
`MEP_CONSENT_REQUIRED_BUT_MISSING` fail closed。正例
`MEP_POS_SHARED_WORK_CONTEXT_WITHOUT_CONSENT`（`NOTICE_REQUIRED`，
`consent_ref` 為 null）通過，證明這條規則是從上游讀的，不是對
`EMPLOYEE_PRIVATE` 字串寫死。未來若有新 mode 改為需要 consent，本契約
不必改。

### 不擴張成 whole Personal Store dump

`package_forbidden_fields` 含 `full_personal_store_ref`／
`personal_store_snapshot`／`weekly_work_summary`（whole-store ban），
以及 `candidate_status`／`record_status`／`verification_status`／
`acceptance_status`／`conflict_resolution_status`（沿用
`historical_comparison`／`weekly_review_cycle` 同一條 lifecycle 邊界）
——verification／acceptance 仍是封包抵達之後 SSP-294 的事，不是封包自己
路上宣稱的屬性。

### 切片 3 的 P2 收斂

validator 結構性斷言 `minimal_evidence_package` 確實在
`runtime_policy.local_first_export_surface` 之中，本契約即該項的
enforcement。封閉列舉的另一項 `weekly_closeout_receipt` 已由 SSP-323
切片 4 鎖住。兩項都有實際 enforcement 後，該 P2 在
`文件/待辦重整.md` 標記 `CLEARED`。

## 接回總入口的實測

```
中和 MEP_FORBIDDEN_ACCESS_KIND 的 guard（本片最核心的 reverse-access
邊界）：

直接呼叫新片   → 五個 forbidden-kind 負例全部 FAIL（預期 deny 實際通過）
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣的 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_minimal_evidence_package_contract exited 1

還原後 diff 確認逐位元相同，兩個入口都回到 PASS。
```

## 逐 return site parity（非逐 code）

18 個 return site → 18/18 全紅（第一輪就全紅），未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（35 支，含新增這支）  → PASS
四支 Python schema engine                         → 環境缺 jsonschema 模組
                                                     （pre-existing，未安裝
                                                     venv，本卡未改動其涵蓋
                                                     範圍）
git diff --check                                   → clean
```

## 明確不在本卡範圍

- 切片 B（immutable package／revision trace／dedup）。
- 切片 C（公司端使用邊界、`NEEDS_ORG_FOLLOWUP` 無 canonical identity、
  aggregator 收尾）。
- 「公司端確實無 reverse-access path」的真實驗證 → `SSP-295` 真人 pilot；
  本片鎖的是契約層的可表達性。
