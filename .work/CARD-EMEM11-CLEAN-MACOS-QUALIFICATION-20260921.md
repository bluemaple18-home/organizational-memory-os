---
id: EMEM11-CLEAN-MACOS-QUALIFICATION-20260921
status: BLOCKED_ENVIRONMENT
blocker: 需要一台沒有 /opt/homebrew/opt/ruby@3.4 的 macOS 環境
type: qualification
severity: P2
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
origin: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920 §Q6 Part 2
deferred_from: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921（Slice B 驗收第 2 項）
evidence_part_1: .work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md
blocks: 無（不阻擋 SSP-295，見 §4）
authority: organizational-memory-os
---

# EMEM-11｜Clean macOS runtime-profile qualification（Q6 Part 2）

👉 [假設與目標確認]
- **目標**：在一台**真的沒有** `/opt/homebrew/opt/ruby@3.4` 的 macOS 上，
  驗證 runtime profile guard 的判準在乾淨環境下成立。
- **邊界**：只驗 guard 判準與 native ABI 這一格；不改產品程式碼、不擴充
  支援矩陣、不決定配送格式。
- **現況**：`BLOCKED_ENVIRONMENT`。開卡是為了不讓這條驗收在 packaging 卡
  收片時消失，**不是**排程。

## 1. 為什麼另開一張卡

Slice B 驗收第 2 項原文是：

> **ABI 相容但版本字串不同 → 不得誤拒**（對應現行 guard 過嚴的那一格）。
> ※ 本機無法完整驗證，需與 Part 2 clean-macOS qualification 合併收尾；
> 本片至少要讓判準**不再以版本字串為唯一依據**。

Slice B 已交付分號後那一半（判準不再以版本字串為唯一依據，`e3e35ff`
ACCEPTED_GO）。分號前那一半**在本機無從驗證**。

條文不改寫。可驗的部分留在 Slice B 且已收，不可驗的部分整條搬到這裡並標
`BLOCKED`——把驗收條文改成「現在測得到的那件事」等於製造假成功，那正是
本產品一路在防的東西。

## 2. 阻塞原因（已實證，非推測）

`.work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md` 已逐項否掉本機的替代
做法：

| 替代做法 | 為什麼不算數 |
|---|---|
| 本機裝第二個 Ruby | 被既存 Homebrew dylib 路徑污染——dyld 可能把 Homebrew libruby 載進 alternate Ruby 的程序，結果不等價於乾淨機器 |
| `brew install ruby-build` 後在 `/tmp` 編 3.4.10 | 成本高且證據混淆 |
| 第三方 portable Ruby | 同樣被既存 Homebrew dylib 路徑污染 |
| Docker 官方 `ruby:3.4` | linux/arm64，答不了 macOS dyld／ABI 的問題 |

因此本卡的判定力**只能**來自真實環境：同事機、乾淨 Mac／VM，或之後的第二
台測試機。

## 3. 驗收（解除阻塞後才執行）

1. 在**沒有** `/opt/homebrew/opt/ruby@3.4` 的 macOS 上取得 artifact。
2. **ABI 相容但版本字串不同 → guard 不得誤拒**（Slice B 驗收第 2 項的
   分號前半）。
3. **版本相同但 linkage 不符 → guard 當場擋下**，在乾淨機器上同樣成立
   （本機已用 `install_name_tool` 實證，此處是回歸確認）。
4. **完全不相容的 Ruby（例如系統 2.6）**：當場失敗、不靜默改用別的。
5. 3a／3b／3c ＋ install／CLI／SessionStart／MCP／doctor 在該機器上可跑。
6. 每一項附鑑別力反證；跑不到的項目印 `N/A` 並指名由誰負責，**不得印
   PASS**。

## 4. 這張卡不阻擋什麼

- **不阻擋 SSP-295 full product pilot**。Owner 範圍裁決 2026-09-20 後的
  normative DoD 不含本項；parent card 的
  `status: DOD_MET_20260920_READY_FOR_SSP295` 不因本卡而改變。
- **不阻擋 Q7**（研究卡已明載 Part 2 不再阻塞 Q7）。
- 交付形狀已由 packaging 卡 Slice C 在 workspace B 實證可離開 repo；本卡驗的
  是**另一台機器上的 runtime profile 判準**，不是 standalone 本身。

## 5. 不做

不擴充支援矩陣、不決定配送格式、不建 release pipeline、不做跨平台
（非 macOS）、不做安裝時重編原生擴充。研究卡 §6 列的四個方向都留在原處。

## 6. Minimum Sufficient

- **why_not_less**：不開卡則這條驗收隨 packaging 卡收片消失，日後只會以
  「反正本機測不到」的形式悄悄變成永遠不驗。
- **why_not_more**：本卡只承接 Slice B 驗收第 2 項的不可驗半段＋必要的回歸
  確認，不順手把整個 runtime 支援矩陣搬進來。
- **do_not_absorb**：不吸收 doctor P2（`CARD-DOCTOR-SESSION-HOOK-EVIDENCE-20260920`）
  與 EMEM-11b Codex cross-host；兩者各有卡。
