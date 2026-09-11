# SSP-291 Repair 01 — 定點 re-review 交付包

同一條 review line。只收 `SSP291-F-01`，不重開已裁決項。

## 1. 鎖定

```
base                5e5d9a8f7ef0d8d60f1e5a00d375800fab4cd84e
original_review     17893f0b35dd5f4771979167c15e4007b1eabf2d   （immutable，未改寫）
repair_commit       cd30d22f87ad40d2bf8c7d07bf82ae3942d9c29d
branch              cc/ssp291-personal-evidence-profile        （已 push origin）
```

定點 diff：`git diff 17893f0..cd30d22`

## 2. 只審這個

`SSP291-F-01`（P1）：准入值驗證不完整 —— 錯型別 reference 與空 scope 匹配仍可放行。

上一輪你已裁決、**本輪不必重開**：七個指定檢查點（上游執行期讀取、判斷順序、
刪除 `NOT_BOUND`、error-code 掃描、扁平 `capture_scope`、上游 catalog 缺三個 role source、
未新增 registry entry）、adapter mapping、phase 邊界、role／ownership／capability 契約。

## 3. 修法

| # | 修正 | 位置 |
| --- | --- | --- |
| 1 | 新增 `admission_value?` = 非空白 String。不造 URI scheme、不連外解析 | validator 本檔 |
| 2 | 新增 `ADMISSION_CONTAINER_TYPES`：`connector_grants` 非空 Array、`capture_scope` 非空 Hash | validator 本檔 |
| 3 | `within_capture_scope?` 先驗清單型別與 capture 識別值，再比成員 | validator 本檔 |
| 4 | 契約新增 `admission_value_constraints` 四條 rule + 斷言 | 契約 YAML |
| 5 | 負例 19 → 39（含 DOCUMENT 來源錯值負例 3 個） | 共用 fixture |

**錯誤碼集合維持 16 個、順序不變。**
**共用 `scripts/lib/omos_contract_helpers.rb` 的 `present?` 逐字未改** —— 請直接確認：

```
git diff 17893f0..cd30d22 -- scripts/lib/omos_contract_helpers.rb   →  應為空
```

## 4. 主動回報：我刪掉了兩條自己剛加的 guard

修的過程中我先在 projected identity 比較前加了兩條型別 guard，
parity probe 卻顯示它們 **GREEN(bad)** —— 中和後 gate 仍綠。原因是相等比較本身已足夠：
`source_system` 由結構斷言保證 mapping 必須提供非空值，
`capture["source_instance_id"]` 已由 `within_capture_scope?` 保證為非空白字串。

依你上一輪對 `EPROFILE_ADAPTER_MAPPING_NOT_BOUND` 的裁決邏輯（不留踩不到的死分支），
我刪除這兩條，並在原處留註解寫明**所依賴的兩個前提**，日後鬆動任一前提必須補回。
若你認為執行期仍應保留防禦，這是本輪可提的 finding。

## 5. 請重播

**A. 你列出的 8 個放行情境**
用 frozen 正例當 base，逐項套用你描述的單欄修改。
我的結果：**仍被放行 0 / 8**，逐項回傳語意正確的碼：

```
A1 consent_or_notice_ref = false          → EPROFILE_NO_CONSENT_OR_NOTICE
A2 Jira grant_ref = false                 → EPROFILE_NO_CONNECTOR_GRANT
A3 retention_policy_ref = false           → EPROFILE_PROFILE_FIELD_MISSING
A4 consent_or_notice_ref = "   "          → EPROFILE_NO_CONSENT_OR_NOTICE
A5 DOCUMENT 正例 consent = false          → EPROFILE_NO_CONSENT_OR_NOTICE
A6 DOCUMENT 正例 grant_ref = false        → EPROFILE_NO_CONNECTOR_GRANT
B1 containers 含 null + capture 無 container
                                          → EPROFILE_OUTSIDE_CAPTURE_SCOPE
B2 instance 清單含 null + capture/projected 皆無 source_instance_id
                                          → EPROFILE_OUTSIDE_CAPTURE_SCOPE
```

**B. 值約束 probe（本輪新增 9 條）** —— 用來證明新約束承重，不是裝飾。
我的結果：**9 RED / 0 GREEN（assertion 7 / exception 2）**。
最關鍵的是 H1：把 `admission_value?` 退回共用 `present?` 語意，gate 轉紅。
H2 / H6 是 exception-RED（移除型別檢查後產生 Ruby 例外），**不是乾淨的契約拒絕**。

**C. Evaluator guard parity（19 條）**
我的結果：**19 RED / 0 GREEN，assertion 17 / exception 2**。
exception-RED 兩條都是移除物件型別 guard 後的 Ruby 例外：
`group_value.is_a?(Hash)` 與 `container.is_a?(container_type)`。

**D. 結構／跨契約 probe（6 條，回歸）**
我的結果：**6 RED / 0 GREEN，assertion 5 / exception 1**（P5 為例外轉紅，與你上一輪觀察一致）。

**E. 既有 fixture 不變**
frozen 版本的 2 正例 / 19 負例，結果應與 `17893f0` 逐一相同。

還原請用 `cp` 備份，不要用 `git checkout --`。

## 6. 三處措辭已照你的指正改寫

1. **負例 mutation 形狀**。上一輪寫「19 個全部恰好差一個 leaf」不精確。
   本輪 39 個負例的正確分類是：
   **單一 leaf 29 / 單一 subtree replacement 7 / 多點 scenario 3**。
   （scenario 三個就是你的「兩邊都缺值」原樣重播，本質需要改 2~3 處。）
   我沒有為了湊 leaf 數拆掉必要的物件型別測試。

2. **parity 結果**。已全面分列 assertion-RED 與 exception-RED，
   不再寫成「每條都得到乾淨的契約拒絕」。

3. **adapter 綁定的保證範圍**。本卡證明的是
   **「准入來源與 adapter 的來源標籤（`source_system`）一致」**，
   **不是**「這一筆完整 RawEvidence 已通過 adapter／STD instance 驗證」。
   正例只帶 projected identity 的兩個欄位，沒有完整 RawEvidence instance。
   完整 adapter 驗證本輪不擴進來。

## 7. Gate

```
ruby scripts/validate_*.rb                     → 21 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
validator 行數                                  → 351（< 400 硬上限）
```

## 8. 邊界（未變）

本輪沒有改共用 `present?`、沒有新增 connector／resolver／registry／runtime、
沒有動任何上游契約或 schema、沒有為了綠燈新增 role source 或放寬 phase 邊界。
`CLIENT_FEEDBACK` / `CRM_ENTITY` / `CLIENT_DOCUMENT` 維持 fail-closed 拒絕，留上游 Owner 裁決。

請就 `SSP291-F-01` 給 `GO` 或 `NO_GO`。
