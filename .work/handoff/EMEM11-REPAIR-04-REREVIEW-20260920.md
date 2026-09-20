# EMEM-11 repair-04 — 再 review Handoff Packet

- 前一輪：repair-03 交付 `6f042d9`／packet `6f1cea0`，四個原 blocker 經 fresh
  review 全部確認 **CLOSED**；同輪新抓到 **P2×1**（product post-write oracle
  仍用 `known_hosts`）。
- **repair-04 交付 SHA：`fa0959a`**
- 分支：`cc/emem11-slice3-repair-01`（未 push、未動 main）
- 定點 diff：`git diff 6f042d9..fa0959a`（4 檔，+41／-1）

本輪**只收那一筆 P2**。沒有重開 installer、DoD、session identity 或 repair-02。

## 這一筆的性質

`Contract.runtime_log_bindings[:binding_shape]` 仍指向
`binding_shape_bindings`（`known_hosts`）。事後 conformance oracle 因此會把一份
`executor_ref` 全是 Codex 的 operation journal 判為合法。

真正的 Runtime 早在 repair-03 就擋住了，所以**不是 store bypass**；但事後
oracle 判的其實是「這份 journal 記下來的操作當初該不該被允許」——那是授權問題，
本來就該與授權閘用同一組 host set。兩者不一致的後果是：**事後看 journal 會得到
錯的結論**，而 journal 正是這個產品用來當證據的東西。

## 修法

`runtime_log_bindings[:binding_shape]` 改用 `runtime_authorization_bindings`。

現在四組 host set 的實測值（reviewer 三行探針的同一組）：

```
delivered          = ["Claude Code"]
runtime_auth       = ["Claude Code"]
runtime_log_shape  = ["Claude Code"]        ← 本輪修正（原為含 Codex）
pure_shape(known)  = ["Claude Code", "Codex"]
```

`pure_shape` 維持 `known_hosts` 是刻意的：切片 2 evaluator 的 composition
檢查問的是「executor_ref 是不是契約認識的 Host」，Codex 的設定面覆蓋靠它活著。

## 負例（兩端都要）

**產品端（conformance_3b，新增 2 條）**

- 對照組：真實 MCP journal 仍通過事後 oracle（`nil`）。沒有這條，下面那條可能
  是因為別的原因紅的。
- 負例：把同一份 journal 的 MCP binding 的 `executor_ref` 改成 `Codex`
  （實際改寫 3 筆），oracle 必須回 `PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST`。

放在 3b 而不是 3a：3a 的 journal 全是 CLI surface，依契約不得帶 binding，
在那裡改寫會是 0 筆，驗不到任何東西（第一版寫在 3a，實跑「改寫 0 筆 → nil」
才發現，已移走）。

**validator 端（切片 1 negative fixture，新增 pmr-neg-25b）**

- `pmr-neg-25`（既有）：`Hermes` —— **never-known** host。
- `pmr-neg-25b`（新增）：`Codex` —— **known-but-not-delivered**。

兩者都必須回 `PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST`。分成兩條是因為
這是兩種不同的世界狀態，合併成一條會讓「Codex 被擋」這件事沒有專屬證據；
新標籤已加進 `EXPECTED_NEGATIVE_LABELS`，漏掉會紅。

## 驗收

| 套組 | repair-03（6f042d9） | repair-04（fa0959a） |
|---|---|---|
| conformance_3a | 26/26 | **26/26** |
| conformance_3b | 31/31 | **33/33**（+2：oracle 對照組＋blocked host journal 負例） |
| conformance_3c | 49/49 | **49/49** |
| 全庫 `scripts/validate_*.rb`（39 支） | 39/39 | **39/39**（含新增的 pmr-neg-25b） |
| `git diff --check` | clean | **clean** |

## 請 review 針對這一點

`pure_shape` 是目前唯一仍認 `known_hosts` 的出口。我的判斷是它只被切片 2
evaluator 的 composition 檢查使用（`HBV1_PRODUCED_BINDING_REJECTED_BY_RUNTIME`），
不會單獨決定任何「能不能動 store」或「這份證據算不算數」的結論。若你認為還有
第三種消費者應該改吃 delivered，請指出呼叫點。
