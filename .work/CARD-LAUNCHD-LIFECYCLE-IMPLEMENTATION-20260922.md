---
id: LAUNCHD-LIFECYCLE-IMPLEMENTATION-20260922
status: READY_TO_IMPLEMENT
type: implementation
severity: P1
contract: CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922（OWNER_SIGNED 2026-09-22）
parent_card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
replaces: B2 repair-01～04（CARD-PERSONAL-INBOX-SLICE-B-RESEARCH-20260921 §3.6–§3.9）
baseline: 8041188
authority: organizational-memory-os
---

# Launchd lifecycle — 依凍結契約重做

👉 [假設與目標確認]
- **目標**：把 `lib/omos/schedule.rb` 的生命週期改成符合已簽署契約的實作。
- **邊界**：只動 `schedule.rb` 與其測試；**不碰** `ReviewQueue`（B1 已 GO）、
  Slice A、installer、delivery-path。不擴充排程能力。
- **這不是 repair-05**：契約已凍結，本卡依契約重做，repair-01～04 的既有
  修法**逐條對照**、不自動沿用。

## 1. 必須實作的（全部來自已簽契約）

| 契約條款 | 實作要點 |
|---|---|
| §1.1 `bootstrap` 四象限 | 含 **exit 非 0 + 實際已 loaded = partial activation**（目前完全沒處理） |
| §1.2 `bootout` 四象限 | 含 **exit 非 0 + 實際已停 = 成功**（目前會誤判成失敗） |
| §1.3.1 階段序列 | `SNAPSHOT_OLD → OLD_STOP_VERIFIED → PUBLISH_NEW_PLIST → NEW_ACTIVATION_ATTEMPTED → NEW_POSTCONDITION_CLASSIFIED → CLEANUP_NEW_IF_NEEDED → RESTORE_OLD_IF_NEEDED → FINAL_VERIFIED`。**流程階段，不是資料結構**——不得建 FSM engine／ledger／DB |
| §1.3.2 rollback 順序 | 新 job 仍 live 時**先清掉它**；清掉前不得換回舊 plist、不得 restore old；清不掉停在 dirty failure，磁碟保留與 live 對應的定義 |
| §1.3.3 正向發布順序 | **`OLD_STOP_VERIFIED` 之前磁碟維持舊版**；確認舊 job 停止後才 `PUBLISH_NEW_PLIST`。`8041188` 現行的「先寫 plist 再停舊 job」**必須改掉** |
| §1.4 序列化 | 同一 `Label` 的 lifecycle mutation 序列化；拿不到序列權明確失敗（`SCHEDULE_LIFECYCLE_BUSY`），不排隊半套、不靜默跳過。用 OS 既有最薄手段，不得新建 daemon／broker |
| §1.5 boundary | crash／斷電／外部改動列為 recovery boundary，不在保證範圍 |

## 2. repair-01～04 既有修法的逐條對照（契約驗收第 10 項）

| 既有修法 | 對照結果 |
|---|---|
| `install`／`remove` 真的呼叫 launchctl（repair-01） | **沿用** |
| `installed` = plist 是我們的 **且** job 真的載入（repair-01） | **沿用** |
| anchor 完整傳遞 ＋ 從 plist 讀回（repair-01） | **沿用** |
| ownership 看 plist 內部 `Label`（repair-01） | **沿用** |
| `install`／`remove` 是交易（repair-02） | **重做**——階段序列與發布順序都變了 |
| `bootstrap_and_verify`（repair-03） | **重做**——需涵蓋第四象限 |
| `bootout_and_verify`（repair-04） | **重做**——需涵蓋第四象限 |
| `restore_previous` 用 `loaded?` 判斷舊 job 是否還活著（repair-04） | **移除**——契約 §1.3 明文禁止 |
| 先寫 plist 再停舊 job（repair-01 起沿用至今） | **移除**——違反 §1.3.3 |

## 3. Acceptance

直接引用契約 §2 的 11 項，不重寫。額外要求：

12. 測試不得把 job 載進執行者的真實 session；收尾檢查
    `launchctl print gui/$(id -u)/com.omos.personal-memory.weekly-review`
    為 ABSENT。
13. 各情境測試互相隔離（獨立 `mktmpdir`），反證不得連鎖。
14. 行數 delta 逐檔回報，並說明淨增是否符合 `MINIMUM_SUFFICIENT`。

## 4. 不做

不改 `ReviewQueue`／Slice A／installer、不擴充排程能力（多重 anchor／多 job／
非 macOS）、不引入第三方排程相依、不建 FSM engine／ledger／DB、不新建
daemon／broker、不做 Acceptance #8 真機實證（需 Owner 明示）。

## 5. Minimum Sufficient

- **why_not_less**：契約已凍結四象限與階段順序；少實作任一項，下一個未處理
  的組合仍會以「新 P1」回來——這正是 repair 線失敗的原因。
- **why_not_more**：只重做 lifecycle；ownership／anchor／notify 等已 GO 的
  部分沿用不動。
- **do_not_absorb**：不吸收 Acceptance #8 真機實證、delivery-path 驗收、
  §1.5 的 recovery boundary 三項。
