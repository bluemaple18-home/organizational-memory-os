---
id: EMEM11-QUALIFICATION-KEY-FIX-20260921
status: READY_FOR_REVIEW
type: product-fix
severity: P2
scope: bounded
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
decided_by: CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921 §0（Owner 裁決 2026-09-21）
authority: organizational-memory-os
---

# EMEM-11｜qualification key 修正（host_os 移出比對）

👉 [假設與目標確認]
- **目標**：把 `host_os` 從 qualification 比對中移除、降為 observation，
  讓同一包 artifact 在任何 macOS 版本上只要 ABI／架構／live probe 成立
  就是 qualified。
- **邊界**：只動 `runtime_profile.rb` 與 `runtime-profile.json` 的比對 key
  與相應測試。**不**改 probe 行為、不改 `pinned-ruby.sh`、不擴充支援平台、
  不碰 installer／CLI／MCP。
- **判準來源**：Owner 2026-09-21 裁決，見
  `CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921` §0。本卡只實作，不重議。

## 1. Measured gap

同事機 `darwin24 / arm64 / 3.4.0`，本機 `darwin25 / arm64 / 3.4.0`，
兩台的 artifact 完全相同、live probe 都通過，但同事端每次執行都印
`UNQUALIFIED_RUNTIME_PROFILE`。

`qualified_profiles` 的五個欄位只有 `host_os` 會因人而異；
`native_linkage_digest` 是由 artifact 自己的 manifest 算出來的常數，
對同一包 artifact 在任何機器上恆為同值，**不具機器鑑別力**。

## 2. 修法

| 欄位 | 修法 |
|---|---|
| `host_os`（如 `darwin25`） | **移出比對**，降為 observation；仍記錄、仍在訊息中顯示 |
| os family（`darwin`） | 由 `host_os` 推導，**進入比對** |
| `host_cpu`、`ruby_engine`、`ruby_abi` | 維持在比對內 |
| `native_linkage_digest` | **改為 artifact integrity 欄位**，與 artifact 自己的 manifest 比對；不參與機器判定 |
| live native probes | 不變，仍是真正的守門人 |

`runtime-profile.json` 的 `qualified_profiles` 只留比對欄位；
linkage digest 改放為獨立的 artifact integrity 欄位。

## 3. Acceptance

1. `host_os` 從 qualification comparison 移除，保留為 observation。
2. qualification 依 `darwin family + arm64 + ruby engine + ruby ABI +
   live native probes`。
3. `native_linkage_digest` 只驗 artifact integrity，不拿來區分機器。
4. **`darwin99` mutation**：只改 OS version，結果仍須 `QUALIFIED`。
5. ABI／CPU／live linkage 任一真的不符，仍必須 **fail closed**。
6. 用同事那台重跑後，`UNQUALIFIED_RUNTIME_PROFILE` 應消失。

### Regression

7. 3a／3b／3c 全綠；40 支 validator 全綠；`git diff --check` clean。
8. 每一項附鑑別力反證。

## 4. 不做

不改 probe 實作、不改 `pinned-ruby.sh` 的候選搜尋、不新增平台、
不導入簽章／notarization、不重打已出貨的 zip（驗收第 6 項待下一版）。

## 5. Minimum Sufficient

- **why_not_less**：不改則每來一個同事就要往矩陣加一列，且加的是一個
  與相容性無因果關係的版本字串。
- **why_not_more**：只換比對 key，不動 probe、不動 guard 的候選搜尋、
  不擴充支援宣稱的範圍。
- **do_not_absorb**：不吸收「沒裝 Homebrew 是否開箱即用」那個宣稱——
  那仍需乾淨機器，留在 qualification 卡。
