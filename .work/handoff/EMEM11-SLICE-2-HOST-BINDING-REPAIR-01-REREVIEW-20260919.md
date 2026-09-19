# EMEM-11 切片 2 repair-01 — 再 review Handoff Packet

- original_review baseline：**`ec3a47c`**（NO_GO，P1×2 / P2×2；working tree 原樣保存，已推上 origin）
- **repair-01 交付 SHA：`a55a4aa384dce1d0c9ad480dfd19f36340edab57`**
- 分支：`codex/emem11-host-binding`（base `251a0d8`）
- 收治範圍：**只收裁決指定的四筆**。未碰切片 3 installer/doctor、live Host evidence、
  cross-host 真人測試、SSP-295。

## 0. 兩筆 P1 的共同根因

兩筆都不是「少一個判斷式」，而是**同一個欄位在兩片各有一套解讀**：
binding 的值形狀有兩個 `blank?` 定義，`effective_scope` 有兩套詞彙。
修法一律是把那個判準變成**兩片共用的唯一實作**，而不是在切片 2 補檢查。

新增共用檔一支：`scripts/lib/host_session_binding_shape.rb`（53 行），
由切片 1 的 runtime 與切片 2 的 Host 適配器共同消費。

## 1. P1-1：切片 2 能產出切片 1 會拒絕的 binding

**你的實測**：`native_session_id=false`、`cwd=false`、`project_ref=1` 在切片 2 回 `nil`。

**根因**：切片 2 的 `blank?` 是
`value.nil? || (value.respond_to?(:empty?) && value.empty?) || (String 且 strip 為空)`，
對 `false` 與 `1` 全部回 false；切片 1 用的是 `MEPShape.blank?`，要求必須是 String。

**修法**：共用 evaluator 只保留一個定義 `nonblank_string?`，切片 2 的 bootstrap
三個欄位改用它；並在 `produced_binding` 組出來之後直接呼叫
`HostSessionBindingShape.binding_problem`——**切片 1 判定 binding 用的就是這一支**。

檢查順序刻意放在「值比對」之前：先問「這是不是一個 runtime 形狀的 binding」，
再問「它是否對得上 bootstrap 事實」。這也讓
`HBV1_PRODUCED_BINDING_REJECTED_BY_RUNTIME` 成為**可達**碼，而不是宣告了卻永遠
回不到的裝飾。

**重播結果（repair-01 實測）**

| 輸入 | 結果 |
|---|---|
| `bootstrap.native_session_id = false` | `HBV1_NATIVE_SESSION_ID_MISSING` |
| `bootstrap.cwd = false` | `HBV1_CWD_MISSING` |
| `bootstrap.project_ref = 1` | `HBV1_PROJECT_REF_MISSING` |
| `produced_binding.cwd = false` | `HBV1_PRODUCED_BINDING_REJECTED_BY_RUNTIME` |

## 2. P1-2：`effective_scope` 兩套語意

依裁決**維持切片 2 的設計**：`runtime_scope_mode` 與 `effective_scope` 分離，
後者固定是 `ownership_visibility_contract.visibility_scopes` 的詞彙。

- 共用 evaluator 新增 `PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE`，
  兩片同時生效。
- **切片 1 的 runtime fixture 由 `EMPLOYEE_PRIVATE` 收斂為 `SELF_ONLY`**，
  並新增負例「effective_scope 放 ownership mode」。
- 切片 1 另加斷言：visibility scope 與 ownership mode 的詞彙**不得相交**，
  否則這個欄位又會兩義。

跨片驗證：`produced_binding.effective_scope = "EMPLOYEE_PRIVATE"` 現在回
`HBV1_PRODUCED_BINDING_REJECTED_BY_RUNTIME`——切片 2 產出的東西若不是切片 1
收得下的，當場就被擋。

## 3. P2-1：error contract 與 evaluator 機器對綁

實測確認你的判斷：`LoopReturnContract.reachable_codes(lib, "merge_problem")`
**回傳 0**——三個 `HBV1_#{action}_*` 插值出口對掃描器完全隱形，而且連
`exit_shape_violations` 也不會報（是個盲點）。

修法：拆成 `merge_core_problem`（回傳 symbol，邏輯單一份）+
`install_merge_problem` / `uninstall_merge_problem`（字面碼轉發）。
出口因此可靜態列舉，共 **43 碼**。

validator 新增：

- `ERROR_CONTRACT`（43 碼）
- `reachable ↔ declared` **雙向**斷言（union over evaluator 的每一個 `def`）
- **防回歸斷言**：evaluator 出口不得再出現字串插值（否則掃描會再次靜默失效）

## 4. P2-2：same-payload shadow 隔離負例

新增兩筆：higher-precedence 的 MCP entry 與 SessionStart hook 使用**與 user
registration 逐欄相同的 payload**，仍必須回 `HBV1_MCP_SHADOWED` /
`HBV1_SESSION_START_HOOK_CONFLICT`。兩筆直接通過——證實實作本來就是看 id 與
precedence，缺的確實只是測試證據。

## 5. 證據

- **切片 2 lib：43/43 return site**，逐一刪除後本片與 aggregator 同時轉紅，還原 byte-identical
- **切片 1：49/49 return site** 同樣兩端轉紅（新增了一個 effective_scope 碼）
- **全庫 39 個 validator 全綠**；`git diff --check` clean

### 5.1 跨片組合證明（本輪的重點）

拿掉**共用 binding evaluator**中的一個守衛：

| 被拿掉的守衛 | 切片 1 | 切片 2 | aggregator |
|---|---|---|---|
| `PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING` | RED | **RED** | RED |
| `PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE` | RED | **RED** | RED |
| `PMR_HOST_BINDING_NOT_MAP` | RED | GREEN | RED |
| `PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD` | RED | GREEN | RED |
| `PMR_HOST_BINDING_UNKNOWN_FIELD` | RED | GREEN | RED |
| `PMR_HOST_BINDING_IDENTITY_FIELD_MISSING` | RED | GREEN | RED |
| `PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST` | RED | GREEN | RED |

前兩條正是 P1-1／P1-2 的守衛，**兩片同時轉紅**——這就是「切片 2 產出的 binding
可直接被切片 1 接受」的機器證明。其餘五條在切片 2 端維持 GREEN 是**結構性**的：
切片 2 在委派之前先做了自己的 map-ness／forbidden／unknown／completeness／
executor 身分檢查，會先擋下來，所以那些共用守衛在切片 2 這條路徑上被遮蔽。
若要讓它們也從切片 2 側可隔離，就得刪掉切片 2 那幾個先行檢查——那會改動本輪
未受指派的既有錯誤碼，因此**沒有動**。

## 6. 交付量測

| 檔案 | 增量 |
|---|---|
| `scripts/lib/host_session_binding_shape.rb`（新） | +53 |
| `scripts/lib/personal_memory_host_binding.rb` | +56 / −9 |
| `scripts/validate_personal_memory_host_binding_contract.rb` | +80 / −1 |
| `scripts/validate_personal_memory_runtime_contract.rb` | +55 / −13 |
| host-binding fixtures | +8 / −1 |
| runtime fixtures（機器產生） | +105 / −47 |
| **合計** | **+287 / −71** |

手寫約 244 行，落在開工前宣告的 200–260 區間。

**另註（過程中自己修掉的一個問題）**：我第一版用 `json.dump` 改寫
host-binding fixture，把整個檔案重排成每行一鍵，產生 +850/−94 的格式噪音。
已還原成 Codex 原本的緊湊排版、只做最小插入，現在是 +8/−1。

## 7. 未收治

切片 1 的三筆既有 P2（`transaction.mode` 任意值、`owner_authorization` substring、
`supported_hosts_v1` 子集）維持 defer。切片 1 的 `supported_hosts_v1` residual
在本片 GO 後才可標 CLEARED。
