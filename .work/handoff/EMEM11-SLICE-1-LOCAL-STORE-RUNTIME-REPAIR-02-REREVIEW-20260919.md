# EMEM-11 切片 1 repair-02 — 再 review Handoff Packet

- repair-01 交付：`e617184`（NO_GO，P1×1）
- **repair-02 交付 SHA：`dfb24598afa478d4e18eb85b7639780e43653061`**
- 分支：`cc/emem11-local-store-runtime`
- 收治範圍：**只收 P1-3 後半**。未重開 P1-1／P1-2，未動三筆已 defer 的 P2。

## 1. P1-3 後半：本體必須真的過既有 resource 契約

**你的重播**：正例本體帶 `support_link_refs = []`、`verification_status = "V"`、
`candidate_snapshot.* = "V"`，runtime PASS，但同一份 resource 交給既有
`PersonalMemoryRecord` 契約會失敗。

**根因**：我只做了「required_fields 路徑存在 / forbidden 當欄位名 / id 對得上」
三件事，沒有消費既有 evaluator——而那三件事恰好是既有契約裡最表面的一層。

**修法：抽取 + 真組合，不是補檢查。**
把既有 evaluator 抽成 `scripts/lib/personal_memory_resource_evaluator.rb`
（`validate_personal_memory_resource_contract.rb` 改為呼叫它，本地副本刪除），
runtime 在每次 `STORE_WRITE` 時：

```ruby
store_cases = rows.map { |rid, rec| {"resource_type" => rec[:kind], "resource" => rec[:resource], "case_id" => rid} }
store_cases << { "resource_type" => row_kind, "resource" => resource, "case_id" => row_id }
resource_problems = PMRE.resource_failures(spec, vocab, PMRE.build_indexes(store_cases), ...)
return "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT" unless resource_problems.empty?
```

關鍵在 `indexes` 是用**這個 store 目前已寫入的列**建出來的，不是用一組假資料。
所以 `support_link_refs` 必須解析到**同一個 store 裡真的存在**、而且
`target_ref` 指回本列的 `MemorySupportLink`——這是組合，不是形式呼叫。
support、memory kind、verification／acceptance、lifecycle、Record creation gate
全部由那一份實作判定，runtime 一條都沒有重寫。

移除兩個自有錯誤碼（`PMR_ROW_RESOURCE_REQUIRED_FIELD_MISSING`、
`PMR_ROW_RESOURCE_FORBIDDEN_FIELD_PRESENT`），改為單一
`PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT`。**錯誤碼 49 → 48。**

**fixtures**：base 現在是一個真實的 store——先寫入四筆 `MemorySupportLink`
（分別指向 R1/R2/R3/C1），再寫 Record；本體的每個值都必須真的合法
（`verification_status: PASS`、`acceptance_status: ACCEPTED`、
`candidate_snapshot.candidate_status: ACCEPTED_FOR_RECORD`、
`memory_kind: DECISION` ∈ phase-1 …）。新增 9 筆負例涵蓋這條線。

## 2. 順帶做完 Owner 指定的 B（無爭議部分）

刪除 `pmr-pos-01`——它與負例檔的 `base` **逐字相同**，而 validator 早已斷言
「負例 base 必須本身通過」，那條斷言就是 pos-01 要證明的事。少 440 行，
一條保護都沒少。

**fixture 1,725 → 1,537 行**，而且這是在同時新增四筆 support link 與完整合法
本體之後的數字。

## 3. 交付量測（每輪主動回報）

| 類別 | vs main |
|---|---|
| 手寫 runtime validator | +672（其中註解 96、空行 69、error_contract 表 48、負例標籤表 62 → **判斷邏輯約 397 行**）|
| YAML 契約 | +178 |
| 共用 lib | +453 |
| 既有三支 validator | +33 / −422（抽取造成的淨減） |
| fixture（機器產生） | +1,537 |
| 文件 | +303 |

共用 lib 的 +453 與既有 validator 的 −422 是同一批程式碼的搬移，**淨增約 +64**。
真正新寫的判斷邏輯約 **913 行**（397 + 178 + 64 + 表格）。

## 4. 證據

- `codes=48`；全庫 **38 個 validator 全綠**；`git diff --check` clean
- **return-site sweep 48/48**：切片與 aggregator 同時轉紅，還原 byte-identical
- **上游漂移探針 12/12 全紅**，含本輪新接點：`memory_kinds_phase_1` 移除
  DECISION、`support_relation` 移除 SUPPORTS、`allowed_anchor_resolution_for_support`
  移除 EXACT_MATCH、Record `required_fields` 移除 `chronology.created_at`
- **抽取行為等價**：既有 `validate_personal_memory_resource_contract` 全綠（golden
  test），外加 **2,750 組** differential（既有全部 fixture × 兩兩／三三疊加違規），
  比對的是**完整 failure 清單**不只第一個碼 → **mismatch = 0**

### 4.1 共用 resource evaluator 的組合證明

拿掉共用 evaluator 的一個守衛，runtime 應轉紅：

| 被拿掉的守衛 | runtime |
|---|---|
| Record 必須至少有一個 support_link_ref | RED |
| verification_status 必須 PASS | RED |
| acceptance_status 必須 ACCEPTED | RED |
| candidate_snapshot 必須 ACCEPTED_FOR_RECORD | RED |
| anchor_resolution 可作為 support | RED |
| support_link_ref 必須可解析 | RED |
| support link target_ref 必須指回本列 | RED |
| 不得使用 transient memory kind | **GREEN（結構性不可隔離）** |

最後一項：`memory_kinds_phase_1 ∩ not_long_lived_memory_by_default = []`
（已實際驗證交集為空），所以任何 transient kind 也必然不在 phase-1，
前一條 `allowed_kinds.include?` 一定接手。保護未消失。

**這個組合證明在過程中抓到我自己兩個缺口，已修**：原本沒有能隔離
`acceptance_status` 與 `support target_ref` 的負例（各補一筆）；
另外「缺 required field」的負例原本刪的是 `governance.acl_ref`，那個欄位另有
專屬 assert，所以**證明不了 required_fields 綁定是活的**——改成刪
`chronology.created_at`（無專屬守衛），漂移探針才真的由 GREEN 轉 RED。

## 5. 關於 B 的 1a/1b 切片：我建議不做，理由如下

Owner 指示「先做 B」。B 的無爭議部分（刪重複 fixture）已完成（見 §2）。
但把切片 1 切成 1a（store）／1b（surface）兩片，我在動手前評估後**建議不做**：

repair-01／repair-02 之後，這片的結構已經是：

- **operation envelope**（op_seq / surface / kind / path / host binding / transaction）≈ 20 碼
- **store 與 row 語意**（migration 鏈 / id / idempotency / revision / 本體）≈ 22 碼
- **closeout** → 3 碼，其餘全部委派
- store 表頭與鏈尾 ≈ 3 碼

按「store vs surface」切，envelope 會落在 1b，但 1a 的每一次 row write 都需要
envelope——只能**在兩片各放一份（正是三輪 review 一直在罰的事）**，或再抽第三支
共用 evaluator；而抽掉 envelope 之後，1b 只剩下 closeout 委派那 3 碼，不成一片。

更根本的是：這片的驗證單位是「一段跨操作的序列」，`schema_version` 是鏈尾、
replay 落回同一列、revision 指向 store 裡真的存在的前身、support link 必須在
同一個 store 裡——**切開之後沒有任何一邊看得到完整的 store**。

repair-02 其實已經做掉了 B 想達成的事：語意現在住在三支共用 evaluator
（`weekly_closeout_history`、`personal_memory_resource_evaluator`、
`minimal_evidence_package_shape`），runtime validator 的判斷邏輯只剩約 397 行，
其餘是表格與註解。

**請 Owner 裁決**：接受不切（我的建議），或指定另一種切法。

## 6. 未收治

三筆 P2 原封未動：`transaction.mode` 任意值仍 PASS、`owner_authorization` 只用
substring 守、`supported_hosts_v1` 只驗子集。§4.2 的
`WRC_DUPLICATE_TERMINAL_CLOSEOUT` 依裁決記為切片 4 的 P3。
