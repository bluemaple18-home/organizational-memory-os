---
id: SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915
status: AWAITING_BIG_REVIEW
type: implementation
tier: T1
jira: SSP-309 (AIWR-11) — 既有票，非新開
depends_on: SSP-307 (ACCEPTED_GO, 32b3f82) / SSP-308 (ACCEPTED_GO, 97d68fe) / NATIVE-ADAPTERS-CORRELATION-CLOSEOUT (ACCEPTED_GO, 6bfacff)
---

# SSP-309／AIWR-11 — Codex／Claude Code Native Adapter Conformance

👉 [假設與目標確認]
- 目標：兩份 Native Adapter 契約現在都有真實的 `lifecycle_event_map` 與
  `native_correlation_ref`，寫一支薄 conformance validator，把兩邊已宣告
  但沒人驗證的「一致性承諾」變成可重播的真實斷言。
- 邊界：只驗證兩份契約與 `ai-task-card-record.yaml` 之間、以及兩份契約
  互相之間**已經宣告要遵守**的東西；不新增任何契約沒說過的一致性要求，
  不強行拉平兩邊合理的平台差異。
- 驗收：見 Acceptance。

## 範圍（研究後縮減為 2 條——C-01 已存在，不重做）

### ~~C-01~~（研究後刪除：已經有真實 enforcement，不需要新 validator）
原計畫「`lifecycle_event_map` 綁定上游權威」。實際檢查
`scripts/validate_codex_native_adapter_contract.rb:148-170` 與
`scripts/validate_claude_code_native_adapter_contract.rb:144-163` 後發現：
兩支既有 validator **各自**已經在跑的時候讀取同一份
`ai-task-card-record.yaml`，把 `lifecycle_event_map` 的每個 target fail-closed
綁定到 `lifecycle_event_to_status` 的 key（讀檔案本身，不是自我宣稱）。
兩邊讀的是同一份實體檔案，所以「兩個 Adapter 對同一上游一致」在數學上
已經是真的，不需要第三支 validator 再比一次——那會是「兩份手寫清單互相
比對」的重複模式。本卡不新增此項，只在 Evidence 裡記錄這個研究結論。

### C-01（原 C-02）：`mapping_run` 核心欄位集合相等
兩邊 `mapping_run.fields` 減去各自已有書面理由（`*_rule` 區塊）的平台專屬
欄位後（Claude Code 的 `stop_hook_active`），核心集合必須相等：
`native_event_type / mapped_to / adapter_output_ref / native_correlation_ref /
outcome`。`outcomes` 列舉（`MAPPED / NOT_LIFECYCLE / DISABLED`）必須逐字相等。

### C-02（原 C-03）：`error_contract` 語意碼對應
兩邊 `error_contract` 的 key，去掉平台前綴（`CODEX_` / `CLAUDE_CODE_`）後，
應該互相對應存在；有差集的碼必須能在該契約自己的 `design_note` 或
`*_rule` 區塊裡找到對應的平台差異理由（例如 Codex 的
`RUNTIME_SAMPLE_UNCLASSIFIED` 因為 SSP-308 明確延後 runtime probe；
Claude Code 的 `STOP_HOOK_ACTIVE_NOT_TERMINAL` 因為 FP-2-A 只在 Claude
Code 這邊有已知問題）。**不要求差集為零**——只要求差集有記錄在案的理由，
沒理由的差集才是 finding。

## 明確排除

- 不驗證兩邊 `non_lifecycle_event_types` 的事件清單要一樣（Codex 8 個、
  Claude Code 31 個，平台原生事件集合本來就不同，這不是缺陷）。
- 不做 runtime probe／跨平台真實 session 比對（SSP-308 已明確延後，
  本卡不擴大範圍去做）。
- 不改動 `codex-native-adapter.yaml` / `claude-code-native-adapter.yaml` /
  `ai-task-card-record.yaml` 的既有內容——本卡只新增一支唯讀比對用的
  validator + fixture，不修改被比對的契約本身。

## Constraints

- 新 validator `< 400` 行。
- 唯讀：只讀三份既有 YAML，不寫入、不改動它們。
- `runtime_independence` 不變。

## Acceptance

1. C-01/C-02 兩條斷言各自有正例（目前狀態應 PASS）與至少一個負例
   （用臨時 fixture／mutation 證明斷言真的會抓到違反）。
2. Guard parity：每個 guard 都能被單獨命中（enforcement-parity probe，
   逐一中和每個 `return "<CODE>"`，確認 validator 真的紅）。
3. `git diff --check` clean；不動既有 23 支 Ruby validator 的行為
   （全部重跑仍 PASS）。

## Stop conditions

同一 blocker 第 3 次失敗即停，轉 Owner spec-freeze——不預期會發生，
因為三條斷言都是讀既有契約已宣告的東西，不是新設計決策。

## Evidence

`.work/evidence/SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915.md`
