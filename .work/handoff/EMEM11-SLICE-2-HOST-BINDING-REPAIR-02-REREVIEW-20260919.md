# EMEM-11 切片 2 repair-02 — 再 review Handoff Packet

- original_review baseline：`ec3a47c`
- repair-01：`a55a4aa`（2×P1 + P2-2 已由 reviewer 確認關閉）
- **repair-02 交付 SHA：`51654bc822395340e8e29be59f746a8d1b4c701f`**
- 分支：`codex/emem11-host-binding`
- 收治範圍：**只收 P2-1 這一筆**。未重開 2×P1、P2-2，未動 §5.1 已裁決的結構性遮蔽。

## 1. 根因：我把「掃描器看得到什麼」當成了「evaluator 會吐什麼」

上一輪我加的雙向斷言以 `LoopReturnContract.reachable_codes` 為基準。那支掃描器
只認得 `return "字面量"` 這一種出口形式，於是下面兩類出口對它完全隱形：

| 位置 | 形式 | 隱形原因 |
|---|---|---|
| `health_problem` | `return HEALTH_FAILURES.fetch(field)` | 表格查詢，return 位置不是字面量 |
| `derived_effective_scope` | `[nil, "HBV1_..."]`，由呼叫端 `return scope_problem` 轉送 | 碼在 tuple 裡，且跨函式轉送 |

兩邊都以 43 計數，所以 gate 自己顯示一致——**假一致**。實際輸出集合是 52，
少宣告的正是你列出的 9 個：`HBV1_MCP_NOT_VISIBLE`、
`HBV1_PROJECT_SCOPE_WIDENS_BASELINE`、`HBV1_PROJECT_UNTRUSTED`、
`HBV1_PROJECT_VISIBILITY_SCOPE_UNKNOWN`、`HBV1_RUNTIME_INCOMPATIBLE`、
`HBV1_RUNTIME_SCOPE_MODE_UNBOUND`、`HBV1_RUNTIME_SCOPE_MODE_UNKNOWN`、
`HBV1_SESSION_START_HOOK_INACTIVE`、`HBV1_VISIBILITY_READERS_NOT_ARRAY`。

諷刺的是，同一支 validator 的「覆蓋檢查」本來就在用原始碼字面量掃描
（`File.read(HELPER_PATH).scan(/HBV1_[A-Z0-9_]+/)`），所以 52 個碼其實**每一個
都有負例實際打過**；出問題的只有我新加的那組斷言選錯了基準。

## 2. 修法

- **斷言基準改成「evaluator 原始碼（去註解）裡出現的每一個 `HBV1_` 字面量」**，
  做雙向斷言。這個基準對「出口用什麼形式回傳」不敏感——表格查詢、tuple、
  跨函式轉送都躲不掉，因此不會再出現同一類假一致。
- **AST 可達碼降級為子集斷言**：它仍能抓到 return 位置的漂移，但不再是權威。
- **`ERROR_CONTRACT` 補齊 9 碼 → 52**，與實際輸出集合雙向差集皆空。
- **附帶收掉一個相鄰風險**：`health_problem` 的 `HEALTH_FAILURES.fetch(field)`，
  若上游為某個 profile 新增一個沒有對應碼的 `required_health` 欄位，會丟
  `KeyError` 當掉，而不是回一個已宣告的錯誤碼——那正是「error contract 涵蓋
  不到的出口」。加了契約層斷言先擋住（不改 evaluator）。
- **移除覆蓋檢查裡手列的 `dynamic_codes`**：repair-01 把 install/uninstall 的
  插值出口拆成字面碼之後，它已被 `literal_codes` 完全涵蓋（實測差集為空），
  留著就是第二份會漂移的清單。

## 3. 證據

### 3.1 反向探針（證明新斷言真的抓得到）

| 探針 | 結果 |
|---|---|
| `ERROR_CONTRACT` 移除一個實際會吐的碼 | RED |
| `ERROR_CONTRACT` 加入 evaluator 沒有的碼 | RED |
| evaluator 新增一個未宣告的字面出口 | RED |
| **把 tuple 出口的碼改名**（上一輪掃描看不到的那一類） | **RED**（同時觸發兩條新斷言） |
| 上游新增沒有對應錯誤碼的 `required_health` 欄位 | RED |

每次還原後三個檔案皆 `diff` 驗證 byte-identical。

### 3.2 以你的方法獨立複核

```
evaluator 可產生: 52   ERROR_CONTRACT 宣告: 52
未宣告: []
多宣告: []
```

### 3.3 既有 gate 重跑

- 切片 2 lib **43/43 return site**，逐一刪除後本片與 aggregator 同時轉紅，還原 byte-identical
- **全庫 39 個 validator 全綠**；`git diff --check` clean

## 4. 交付量測

vs repair-01（`a55a4aa`）：**2 檔、+171 / −8**。
其中 `ERROR_CONTRACT` 表格 +9 行、斷言改寫約 +25 行、契約層 health 斷言 +7 行，
其餘為 evaluator 註解與移除舊清單的調整。手寫約 45 行，落在開工前宣告的 40–70。

## 5. 未收治

切片 1 的三筆既有 P2 維持 defer；切片 1 的 `supported_hosts_v1` residual 在本片
GO 後才可標 CLEARED。切片 3 installer/doctor、live Host evidence、cross-host
真人測試、SSP-295 皆未觸及。
