# EMEM-11 切片 1 repair-01 — 再 review Handoff Packet

- 原交付：`6c257c0`（NO_GO，P1×3 / P2×3）
- repair-01 交付 SHA：`e61718454b81b88fdc78ca4ee43176fff411adf8`
- 分支：`cc/emem11-local-store-runtime`
- 收治範圍：**只收三筆 P1**。三筆 P2 依裁決留在 backlog，未動。

## 0. 三筆 P1 的共同修法

三筆都不是補一個判斷式就好，共同根因是**我在 runtime 裡留了「部分的」自有實作**：
部分凍結的 row、部分抄寫的 closeout 詞彙、完全沒有本體的 row。修法一律是
**接既有 evaluator／契約，刪掉自有那一份**，所以這次 repair 淨增的判斷邏輯很少，
反而刪掉了原本手寫的 closeout 詞彙檢查。

新增共用檔一支：`scripts/lib/weekly_closeout_history.rb`（由 SSP-323 切片 4 抽出）。
`dig_dotted` / `dotted_key_present?` 由切片 3 移入 `lib/omos_contract_helpers.rb`。
兩處都**刪除了原本的本地副本**，不是複製。

## 1. P1-1：revision 的 idempotent replay / immutable row 互相打架

**reviewer 的兩個重播**
- 原封不動 replay 一筆 revision → 誤判 `PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED`
- 同 `row_id` + 同 `idempotency_key`，把 `supersedes_ref` 改成 nil → **PASS**

**根因**：我凍結的是 `row_id → {kind, key}`，不是 row 本身。所以「沒被記住的欄位」
可以自由改寫，而「被記住的欄位」相同時又不知道該視為重放。

**修法**：凍結整筆 row 的 `canonical_json`。
- 寫入已存在的 `row_id`，**只有逐欄相同**才合法，且該次是 no-op（`next`，
  不再動 supersession 帳）→ 重播 1 現在 PASS，且不會二次記帳。
- 其餘任何差異（含 `supersedes_ref` 被改、被刪、被加）→ `PMR_IN_PLACE_ROW_OVERWRITE`
  → 重播 2 現在被拒。

契約 `revision_rule` 同步改寫，明文寫出「immutability 檢查的是整筆 row，不是 id 與
idempotency key」以及「同 id 同 key 但改動 supersedes_ref 也是 in_place_record_overwrite」。

**fixtures**：正例 `pmr-pos-01` 第 10 步就是 revision 的逐欄重放；
負例 `a same-id same-key write that alters supersedes_ref`（刪 `supersedes_ref`）。

## 2. P1-2：Freeze D 的 promotion idempotency 沒落地

**根因**：我的 closeout 只有 `review_period_id / final_status / attempt_kind`，
而且那三套詞彙是我自己在 runtime 裡列的第二份。retry 換掉
`promotion_idempotency_key` 根本沒有東西在看。

**修法：委派，不是補檢查。**
把切片 4 的歷程 evaluator 抽成 `scripts/lib/weekly_closeout_history.rb`，
runtime 依 `review_period_id` 把 `CLOSEOUT_COMMIT` 分組——**每一組依定義就是
weekly_review_cycle 眼中的一段 closeout 歷程**——整組丟給同一支 evaluator。

於是這些全部一次到位，且都不是我重寫的：terminal 唯一性、status／attempt 詞彙、
SKIPPED 的 catch-up 規則、item disposition 分類、`promotion_ref` 不得缺
idempotency key、**以及同一 item 的 promotion 身分不得在 retry 之間漂移**。

runtime 端移除三個自有錯誤碼（`PMR_CLOSEOUT_STATUS_NOT_IN_VOCABULARY`、
`PMR_CLOSEOUT_ATTEMPT_KIND_NOT_IN_VOCABULARY`、`PMR_DUPLICATE_TERMINAL_CLOSEOUT`），
改為單一 `PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT`。runtime 只保留分組所必需的
兩個前置檢查（closeout 是 map、review_period_id 是非空字串）。

**closeout payload 形狀**隨之改為切片 4 的 closeout entry 形狀（九個欄位 +
`item_dispositions`），`review_period_id` 改為 URN。

## 3. P1-3：Local Store 接受「只有合法 ID、沒有本體」的 row

**修法**：`row` 新增 `resource` 本體，在評估當下讀
`personal_memory_resource_contracts.resources.<kind>` 的 `required_fields` 與
`forbidden`（用移入共用 helper 的 `dotted_key_present?`，與切片 3 同一份實作），
另外要求 **row_id 必須等於本體的 identity 欄位值**——否則合法 id 可以配上別人的本體。

`row_contract.identity_fields` 在 YAML 宣告哪個欄位是 identity，validator 斷言
每一個都**本來就在該 kind 的 required_fields 裡**，且該 kind 的 required_fields
不只一欄（否則「有本體」等於沒要求），並斷言 `row_contract` 不得內嵌第二份欄位清單。

新增四碼：`PMR_ROW_RESOURCE_NOT_MAP`、`PMR_ROW_RESOURCE_REQUIRED_FIELD_MISSING`、
`PMR_ROW_RESOURCE_FORBIDDEN_FIELD_PRESENT`、`PMR_ROW_ID_NOT_BOUND_TO_RESOURCE_IDENTITY`。

fixture 的資源本體是**依上游 required_fields 生成**的，不是手抄一份欄位清單。

## 4. 證據

- 錯誤碼 47 → **49**（−3 委派出去，+5 新增，+1 委派碼）
- `ruby scripts/validate_personal_memory_runtime_contract.rb` → PASS（codes=49）
- 全庫 **38 個 validator 全綠**；`git diff --check` clean
- **return-site parity sweep 49/49**：逐一刪除守衛 → 切片與 aggregator 同時轉紅 →
  還原 `diff` byte-identical（未用 `git stash`）
- **上游漂移探針 13/13 全紅**（新增 5 條涵蓋本次接點）：`optional_executors` 移除
  Codex、`executor_provenance_fields` 改名、`closeout_statuses` 移除 NO_PROMOTION、
  `terminal_statuses` 移除 COMPLETE、`attempt_kinds` 移除 CATCH_UP、
  `closeout_receipt.required_fields` 移除 item_dispositions、Record `required_fields`
  移除 support_link_refs、Candidate `forbidden` 移除 record_id、
  `historical_comparison.categories` 改名 MATERIALLY_CHANGED、Record `id_template`
  前綴變更、`correction_flow` 移除 in_place_record_overwrite、floor 移除
  permission_before_retrieval。每次還原後 spec byte-identical。
- fixtures：2 正例 / 58 負例，1,725 行（仍為 base + 明寫 mutation）

### 4.1 抽取的行為等價證明（切片 4 是 ACCEPTED_GO，不得被這次抽取改變）

1. **切片 4 自己的 fixture 套組全綠**——它逐例比對「精確錯誤碼」，行為若變必紅。
2. **多重違規順序敏感度 differential**：把抽取前的 evaluator（自 `git show HEAD`
   機械切出）與抽取後的共用版並排，餵 **203 組**兩兩／三三疊加的違規輸入，
   逐筆比對回傳碼 → **mismatch = 0**。檢查順序若在搬移中變動，這裡會抓到。

### 4.2 共用 evaluator 的組合證明

拿掉共用 evaluator 中的一個守衛，切片 4 與 runtime 應**同時**轉紅：

| 被拿掉的守衛 | 切片 4 | runtime |
|---|---|---|
| `WRC_PROMOTION_IDENTITY_DRIFT` | RED | RED |
| `WRC_PERIOD_START_INCONSISTENT` | RED | RED |
| `WRC_INVALID_FINAL_STATUS` | RED | RED |
| `WRC_INVALID_ATTEMPT_KIND` | RED | RED |
| `WRC_PROMOTION_REF_WITHOUT_IDEMPOTENCY_KEY` | RED | RED |
| `WRC_DUPLICATE_TERMINAL_CLOSEOUT` | RED | **GREEN（見下）** |

**這個組合證明在過程中抓到我自己的一個缺口，已修**：原本「第二次 terminal
closeout」的負例同時讓 `WRC_PERIOD_START_INCONSISTENT` 成立，而兩者映射到同一個
PMR 碼，所以那筆負例**證明不了** duplicate-terminal 真的被擋。已把該負例的
`scheduled_review_period_start` 對齊，使它只違反 terminal 唯一性，並另外補上
period-start 漂移與 promotion_ref 缺 key 兩筆負例。

**`WRC_DUPLICATE_TERMINAL_CLOSEOUT` 仍為 GREEN，原因是結構性不可隔離，不是缺口：**
`terminal_indices.size > 1` 必然蘊含 `terminal_indices.first != closeouts.size - 1`，
所以緊接在後的 `WRC_CLOSEOUT_AFTER_TERMINAL` 一定接手——拿掉前者，該負例仍被拒
（validator 仍 PASS 即為證據）。這是切片 4 內部兩個守衛互相覆蓋的既有性質，
**我沒有去改上游**；若 Owner 認為值得整理，應是切片 4 的 P3，不是本片。

## 5. 未收治（依裁決保留）

三筆 P2 原封未動，留在 backlog：`transaction.mode` 任意值仍 PASS（connection
policy 只落了 WAL）、`owner_authorization` 只用 substring 守（加一句反向授權仍
PASS）、`supported_hosts_v1` 只驗子集（加 `DeepSeek Harness` 仍 PASS，但卡片明寫
v1 只有 Codex + Claude Code）。

§5 邊界依裁決：#1 defer、#2 defer 到 Host Binding（full pilot 前必須 fail-closed）、
#3 = P2、#4 已於本次收治、#5 `genesis_version` 接受。
§1.5 依裁決：六個 `PMR_*_NOT_MAP` **保留不併**。
