# EMEM-11 repair-03 — 再 review Handoff Packet

- 原交付：`263c048`（scope correction，**NO_GO**：P1×2／P2×2）
- **repair-03 交付 SHA：`6f042d9`**
- 分支：`cc/emem11-slice3-repair-01`（未 push、未動 main）
- 定點 diff：`git diff 263c048..6f042d9`

四筆全收，逐筆對應如下。

## P1-1 blocked host 繞過 bootstrap 進 Runtime —— CLOSED

**成立，而且是我造成的。** 上一輪為了讓 Codex 的設定面覆蓋不被短路，把
`binding_shape_bindings` 改吃 `known_hosts`；但 `Contract.binding_problem`
用的是同一份 bindings，而 `Runtime#authorize!` 正是拿它當授權閘。於是一份
不經 `SessionStart.produce` 的合法 Codex binding 可以直接被 Runtime 放行。
reviewer 的重播（`binding_problem=nil` / `runtime_read=ALLOWED`）我在本機重現。

修法是把兩個 seam 徹底拆開，不再共用：

| 用途 | 來源 | 認哪些 host |
|---|---|---|
| 純形狀／composition（切片 2 evaluator 的 `HBV1_PRODUCED_BINDING_REJECTED_BY_RUNTIME`） | `Contract.binding_shape_bindings` | `known_hosts`（含 blocked） |
| **Runtime 授權閘**（`Runtime#authorize!` → `Contract.binding_problem`） | `Contract.runtime_authorization_bindings` | **只認 delivered** |

切片 1 的 runtime validator 同步回到 delivered——它判的是**授權**，不是形狀。
其負例的主詞是「某個已交付 Host 的 binding」（測 CLI-claims-binding、
binding-not-map 這類），不是 Codex 本身，因此 fixture 改以 Claude Code 為例，
沒有刪掉任何一個負例。

Codex 現在被擋在三個獨立的地方，缺一不可：

1. `SessionStart.produce` → `HBV1_HOST_BLOCKED_UPSTREAM`（契約層）
2. 切片 2 evaluator 的 bootstrap 最後一關 → 同碼（契約 evaluator 層）
3. **Runtime 授權閘 → `PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST`**（不經
   produce 的 binding 走這條）

**新增回歸測試（3b）**：刻意不經 produce，手工遞一份逐欄合法、只有 host 是
Codex 的 binding 給 Runtime，必須被擋；並有「同形狀但已交付 Host」的對照組
必須通過——否則上面那條可能是因為別的原因綠的。

## P1-2 Owner A/C/A 沒完整寫回主卡 —— CLOSED

成立。上一輪只在卡片開頭加了 override block，normative 段落沒有真的收斂。
本輪逐處改掉，每處都標注原文與移出去向（不是刪掉）：

| 位置 | 原本 | 現在 |
|---|---|---|
| 定位／v1 支援範圍 | `OpenAI Codex` + `Anthropic Claude Code` | `supported_hosts_v1` 只列 Claude Code；另列 `blocked_hosts_v1: Codex — BLOCKED_UPSTREAM_IDENTITY_CHANNEL` |
| **DoD** | 「Codex 與 Claude Code 兩個 Host 都有真人實測」「cross-host same-store 實證」 | 「已交付 Host（Claude Code）有真人實測」「同一 Store 在並行 session 下…實證」＋新增一條「blocked host 在三個層級都真的擋得住」 |
| Slice 3 目標／邊界 | 「可跨 Codex／Claude Code 實際使用」「只做兩個 Host」 | v1 交付 Claude Code 單一 Host；Codex 保留 profile 與設定面評估但不交付 |
| Same-store acceptance 第 6 項 | 「同一 review period 在兩 Host 間切換」 | 「在同一 Host 的並行 session 間切換」 |
| 切片命名 | 「3c｜Installer / Doctor / 跨 Host conformance」 | 「…／並行 session conformance」 |

## P2-3 YAML 殘留舊 error code —— CLOSED

`blocked_hosts_rule` 與 `native_session_id_source.Codex.scope_note` 都改寫成
現行的兩段式：bootstrap 回 `HBV1_HOST_BLOCKED_UPSTREAM`（與「根本不認識這個
Host」的 `HBV1_HOST_NOT_SUPPORTED` 分開），繞過 bootstrap 的 binding 由 Runtime
授權閘回 `PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST`。

## P2-4 installer 在本卡一起收 —— CLOSED

- `install` / `upgrade` 預設只走 `Contract.supported_hosts`。
- `uninstall` 預設依 **install receipt 的 `hosts`** 清理；沒有 receipt 就掃過
  所有 known host——先前版本曾把 Codex 裝進去，不掃會留殘件。
- `doctor` 不再對 blocked host 跑安裝狀態檢查（那會把「依裁決刻意不安裝」報成
  三條 FAIL，使用者會以為機器壞了），改為一條據實說明的
  `codex_not_delivered`：理由＋解除條件。
- **保留的東西**：Codex 的 host profile、設定探索、install／uninstall／shadow／
  health 的 conformance 覆蓋全部還在。「真的 codex CLI 解析我們寫出的 MCP 註冊」
  這條實證也保留，但改成**明確指名** `install(hosts: ["Codex"])` 才會發生，
  不會偷偷變回預設交付；跨 Host 原子性測試同樣明確指名兩個 Host。

實測：預設 `install` 後 Codex 設定檔**位元組完全不變**，receipt 的 `hosts`
只有 Claude Code，`upgrade` 也不會把它補裝回去——三條都有斷言。

## 驗收

| 套組 | 上一輪（263c048） | repair-03（6f042d9） |
|---|---|---|
| conformance_3a | 26/26 | **26/26** |
| conformance_3b | 29/29 | **31/31**（+2：Runtime bypass 回歸＋對照組） |
| conformance_3c | 45/45 | **49/49**（+4：install 不碰 blocked host、receipt 只記已交付、upgrade 不補裝、receipt 驅動的殘件回收） |
| 全庫 `scripts/validate_*.rb`（39 支） | 39/39 | **39/39** |
| `git diff --check` | clean | **clean** |

## 請 review 針對這些下手

1. P1-1 的三層防線是否真的沒有第四條路：還有沒有任何呼叫端把
   `binding_shape_bindings`（known）餵給實際會動 store 的路徑。
2. 切片 1 負例 fixture 從 Codex 改成 Claude Code，是否有哪一條原本的覆蓋意圖
   因此改變（我判斷主詞是「已交付 Host 的 binding」而非 Codex，但這點請覆核）。
3. P2-4 之後，doctor 對 blocked host 只回一條 WARN 是否足夠——或你認為應該有
   更強的「使用者裝了 Codex 但永遠不會動」的提示。
