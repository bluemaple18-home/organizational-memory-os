# EMEM-11 scope correction — re-review Handoff Packet

- 前一輪：repair-02 correctness 已由 reviewer 定點 **GO**（P0=0／P1=0／P2=0），
  交付 SHA `756f005`，packet `.work/handoff/EMEM11-SLICE-3-REPAIR-02-HANDOFF-20260920.md`
- **本輪交付 SHA：`37a8beb`**（scope correction，單一 commit）
- Owner 簽核：`.work/CARD-EMEM11-SCOPE-FREEZE-20260920.md` → **FP-1 A／FP-2 C／FP-3 A**
- 分支：`cc/emem11-slice3-repair-01`（未 push、未動 main）
- 定點 diff：`git diff 756f005..37a8beb`

**這一輪不是 repair。** repair 線已依 reviewer 指示停止，沒有新增任何 session
workaround。本輪只做 Owner 簽核後的契約與卡片收斂。

## 1. Owner 裁決與它改了什麼

| FP | 簽核 | 落地 |
|---|---|---|
| FP-1 | **A** | `supported_hosts_v1` → `[Claude Code]`；新增 `blocked_hosts_v1`，Codex 記 `BLOCKED_UPSTREAM_IDENTITY_CHANNEL`＋`evidence_ref`＋`unblock_condition` |
| FP-2 | **C** | EMEM-11 v1 收斂為 Claude Code；Codex／真 cross-host 整條搬到新卡 `CARD-EMEM11B-CODEX-CROSS-HOST-20260920`（BLOCKED、上游觸發、**現在不排不做**） |
| FP-3 | **A** | SSP-295 進入條件以收斂後的單 Host DoD 為準，不等 Codex |

FP-2 Owner **否決了 CC 原本建議的 A**（把 Cross-host acceptance 改寫成「同 Host
並行 session」），理由是那會把既有能力需求偷換成另一個能力。因此主卡的做法是：
需求整條搬到 EMEM-11b 保留，留在 EMEM-11 的那組測試**改掉會誤導的名字**
（驗收組 C 現在叫「並行 session、同一 Store 與跨專案」），不再自稱 cross-host。

## 2. 實作中發現的機械後果，以及 Owner 的追加裁決

直接收斂 `supported_hosts_v1` 會有一個原本沒看見的後果：
`scripts/lib/personal_memory_host_binding.rb` 的 `scenario_failure` 是**單一
gate chain**，`supported_hosts` 檢查排在最頂層，在所有設定面判定之前。因此
「Codex 不再是 supported host」會一併讓 Codex 的**設定探索與安裝合併評估全部
短路**——實測 validator 當場 **47 FAIL**，44 個以 Codex 為 base 的負例（包含純
設定面的 `HBV1_NEG_CODEX_MCP_SHADOWED_SAME_PAYLOAD`）全部退化成
`HBV1_HOST_NOT_SUPPORTED`。那正是 FP-2 要避免的型態。

Owner 追加裁決 **B（additive seam，不重排已驗收 evaluator 的 gate 順序）**：

- `known_hosts = host_profiles.keys` — 認識、能評估設定面的 Host。**Codex 仍在
  這裡**，頂層閘與 `HBV1_HOST_NOT_SUPPORTED` 的語意一字未改。
- `delivered_hosts = supported_hosts_v1` — 這一版真的能產出可信
  `HostSessionBinding` 的 Host，**只在 bootstrap 最後一關**檢查。
- known-but-not-delivered → 新碼 **`HBV1_HOST_BLOCKED_UPSTREAM`**，與「根本不
  認識這個 Host」明確分開。
- 放在最後一關是刻意的：形狀錯誤要回形狀的碼，不能被「反正這個 Host 沒交付」
  蓋掉；而只要走到那一關，binding 就一定不會產出。
- **既有 44 個 fixture 的期望結果一個都沒有改**，這是選 B 而非重排 gate 的主因。

新碼已納入雙向 error-contract（`ERROR_CONTRACT` ↔ evaluator 原始碼字面量）與
return-site coverage（由 CODEX base 實際回傳過）。

## 3. 產品側同步

- `Contract` 新增 `blocked_hosts` / `known_hosts`；切片 1 的 binding 形狀檢查
  （`PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST`）改讀 `known_hosts`——它問的
  是詞彙／形狀，不是交付與否。
- `SessionStart.produce` **不自己判「已交付」**：它最後本來就會把整個 bootstrap
  交給切片 2 evaluator 複核，`HBV1_HOST_BLOCKED_UPSTREAM` 由那一關統一吐出，
  產品與契約 evaluator 不會各判各的。
- `Doctor` 的 binding 探針改用**已交付** Host。先前它用
  `HostConfig.hosts.first`（= Codex），收斂後會讓 doctor 報一條 FAIL——但那是
  契約的正常狀態，不是這台機器壞了。

## 4. Codex 現在實際還剩什麼（給 reviewer 對照）

**保留**：host profile、MCP 註冊形狀（真 `codex mcp add` 實測）、三層 hook
結構、設定探索／install／uninstall／shadow／health 的全部 conformance 覆蓋、
「Codex 產不出 binding」的負例。

**不再有**：產出 `HostSessionBinding` 的能力（契約邊界即拒）、v1 的 supported
host 身分、cross-host same-store 驗收（移至 EMEM-11b）。

## 5. 驗收

| 套組 | repair-02 交付（756f005） | 本輪（37a8beb） |
|---|---|---|
| conformance_3a | 26/26 | **26/26** |
| conformance_3b | 27/27 | **29/29**（+2：blocked 與 unknown 必須分得開） |
| conformance_3c | 45/45 | **45/45** |
| 全庫 `scripts/validate_*.rb`（39 支） | 39/39 | **39/39** |
| `git diff --check` | clean | **clean** |

## 6. 已知且刻意未做的一項（請 reviewer 裁決是否需要補）

**installer 目前仍會把 MCP 註冊與 SessionStart hook 寫進 Codex 設定**，因為
`HostConfig.hosts` 讀的是 `host_profiles`（Codex 的 profile 依裁決保留）。
契約現在明說 Codex 未交付、產不出 binding，所以這等於在使用者的 Codex 設定裡
留下一份「寫得進去但用不了」的註冊。

沒有自行改掉，是因為這屬於**交付行為**變更而非本輪簽核的契約收斂，而且會動到
3c 群組 A 的多條驗收（含用真 codex CLI 解析我們寫出設定的那條實證）。
CC 建議：由 reviewer／Owner 裁決是否要讓 installer 預設跳過 blocked host。

## 7. 請 review 針對這些下手

1. §2 的 additive seam 是否真的沒有鬆動任何既有防線——特別是
   `known_hosts` 取代頂層 `supported_hosts` 之後，還有沒有哪條路徑可以讓一個
   blocked host 走到產出 binding。
2. §3 中「切片 1 形狀檢查改讀 known_hosts」是否為正確的層級切分。
3. §6 的 installer 行為是否需要在本卡內一併收掉。
