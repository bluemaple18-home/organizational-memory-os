---
id: SSP295-FULL-PRODUCT-PILOT-20260921
status: ENTRY_CONDITIONS_MET_READY_TO_PLAN
jira: SSP-295
parent_jira: SSP-286
type: pilot
priority: MVP
depends_on:
  - SSP-323_EMEM09_ACCEPTED_GO
  - SSP-324_EMEM10_ACCEPTED_GO
  - EMEM11_DOD_MET_20260920
blocks:
  - SSP-286_MVP_CLOSURE
authority: organizational-memory-os
---

# SSP-295｜EMEM-06 真人產品部 Pilot

👉 [假設與目標確認]
- **目標**：用**真人 ＋ 既有 AI 平台**在實際工作情境下驗證已交付的三條線，
  而不是再跑一次 synthetic fixture。
- **邊界**：不改產品程式碼、不擴充支援矩陣、不重開任何已 `ACCEPTED_GO`
  的上游卡。pilot 發現的缺陷各自立卡，不在本卡內就地修。
- **現況**：進入條件全部成立，但 pilot 本身需要 Owner 指定真人與期間，
  故停在 `READY_TO_PLAN`。

## 1. 進入條件（逐項對照，全部成立）

| 條件 | 狀態 | 證據 |
|---|---|---|
| SSP-323 / EMEM-09 Personal Core | `ACCEPTED_GO` | EMEM-11 主卡依賴圖 |
| SSP-324 / EMEM-10 Evidence Package 三片 | `ACCEPTED_GO` | 切片 A `e3f6f7b`、切片 B `302ffb0`、切片 C `daed603`（皆已 merge） |
| EMEM-11 Runtime & Host Binding v1 | `DOD_MET_20260920_READY_FOR_SSP295` | `.work/CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918.md` §DoD |
| EMEM-11 standalone packaging（A／B／C） | `ALL_SLICES_ACCEPTED_GO` | `.work/CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921.md`，Slice C repair-01 @ `d652bee` |

「EMEM-10 與 EMEM-11 可平行施工；SSP-295 full product pilot 必須等兩者都到
可驗收狀態」——兩者都到了。

## 2. 繼承自上游卡的 pilot binding（不得改寫）

- **SSP-324 §Pilot binding**：真人 pilot 必須證明**公司只收到明確
  submission package，且不存在 reverse-access path**。
- **SSP-323 §Pilot binding**：必須用**真人 ＋ 既有 AI 平台**驗證該卡，
  而非只靠 synthetic schema fixture。
- **EMEM-11 範圍裁決（Owner 2026-09-20）**：v1 為 **Claude Code 單一 Host**。
  Codex 是 known-but-not-delivered，pilot **不涵蓋** cross-host。

## 3. 已知的缺口（進 pilot 時要知道，不是阻塞）

| 項目 | 狀態 | 卡 |
|---|---|---|
| runtime qualification 判準（原 clean-macOS 矩陣） | `READY_TO_IMPLEMENT`（2026-09-21 Owner 改判準） | `CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921` |
| doctor session-hook 證據 | `BACKLOG_NOT_SCHEDULED` | `CARD-DOCTOR-SESSION-HOOK-EVIDENCE-20260920` |
| Codex cross-host | `BLOCKED_UPSTREAM_IDENTITY_CHANNEL` | `CARD-EMEM11B-CODEX-CROSS-HOST-20260920` |

三者皆**不在** Owner 收斂後的 normative DoD 內，故不阻擋本卡。doctor 目前在
乾淨環境回 `18 OK / 2 WARN / 0 FAIL`，兩個 WARN 是「本機無法觀測」而非失敗。

## 4. 待 Owner 決定才能開跑

pilot 不是可以自動推進的工程步驟，以下四項只有 Owner 能定：

1. **真人是誰**（產品部的哪幾位）。
2. **期間多長**，以及以哪個 weekly review cycle 為單位。
3. **安裝形狀**：pilot 用的是 Slice A 之後的 launcher 形狀，既有以舊形狀
   安裝的環境（例如 `/Users/matt/omos-acceptance-home`）要遷移還是重裝。
4. **失敗的處置**：pilot 中途發現 P1 是停 pilot 還是併行修。

## 5. 不做

不改產品程式碼、不擴充 Host 支援、不在 pilot 期間改契約或驗收條文、
不把 pilot 觀察直接升級成產品需求（`NO_DONOR_PROMOTION`）。

## 6. Minimum Sufficient

- **why_not_less**：不開卡則三條線的 pilot binding 散在各自的上游卡裡，
  pilot 開跑時沒有單一地方說得出「要證明什麼」。
- **why_not_more**：本卡只收斂進入條件、繼承的 binding、已知缺口與待
  Owner 決定的四項；不預先設計 pilot 流程、不建量測系統、不定 KPI。
- **do_not_absorb**：不吸收 §3 的三張卡；不重開 SSP-323／SSP-324；
  不把 clean-macOS qualification 偷偷變成 pilot 的一部分。
