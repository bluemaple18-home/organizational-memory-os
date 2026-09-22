---
id: EMEM11-CLEAN-MACOS-QUALIFICATION-20260921
status: ACCEPTED_GO
implemented_by: CARD-EMEM11-QUALIFICATION-KEY-FIX-20260921（ACCEPTED_GO @ d771058）
closed_at: 2026-09-22——第二台機器的真實觀測到位（.work/handoff/EMEM11-QUALIFICATION-SECOND-MACHINE-EVIDENCE-20260922.md）
owner_decision: 2026-09-21 Owner 裁決改判準——qualification key 改為
  darwin family + arm64 + ruby engine + ruby ABI + runtime live native probes；
  exact host_os 降為 observation。本卡改為驗證該判準跨 OS version 是否成立，
  不再建逐版本矩陣。產品實作另送 review。
superseded_blocker: 原為 BLOCKED_ENVIRONMENT（需一台沒有 /opt/homebrew/opt/ruby@3.4
  的 macOS）；改判準後不再需要乾淨機器，見 §2
type: qualification
severity: P2
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
origin: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920 §Q6 Part 2
deferred_from: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921（Slice B 驗收第 2 項）
evidence_part_1: .work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md
blocks: 無（不阻擋 SSP-295，見 §4）
authority: organizational-memory-os
---

# EMEM-11｜Runtime qualification 判準（原 Q6 Part 2）

👉 [假設與目標確認]
- **目標**：驗證 **darwin family + arm64 + ruby engine + ruby ABI +
  runtime live native probes** 這組判準**跨 macOS 版本成立**，因此不需要
  逐版本矩陣。
- **邊界**：本卡只做判準的驗證與卡面裁決；**產品實作（改
  `runtime-profile.json` 的比對 key）另送 review**，不在本卡就地改。
- **現況**：`READY_TO_IMPLEMENT`。原本的 `BLOCKED_ENVIRONMENT` 因 Owner
  改判準而解除——判準不再以乾淨機器為前提。

## 0. Owner 裁決（2026-09-21）

實測觸發：同事機回報 `profile: darwin24 / arm64 / 3.4.0`，本機為
`darwin25 / arm64 / 3.4.0`，於是同事端每次執行都印 `UNQUALIFIED_RUNTIME_PROFILE`。

檢視 `qualified_profiles` 的五個欄位後發現，只有 `host_os` 會因人而異：
`ruby_engine`、`host_cpu`、`ruby_abi` 對同一包 artifact 都是定值，
`native_linkage_digest` 更是**由 artifact 自己的 `native-dependencies.json`
算出來的常數**——它驗的是 artifact 完整性，不具機器鑑別力。於是這份
「矩陣」實質上是「一個 macOS build 版本一列」，永遠列不完。

而 `darwin24` 這個字串本來就不是相容性的判準。Q6 Part 1 已經證明用版本
字串當判準同時過嚴又過鬆，guard 因此改看 ABI 與 linkage；但
`qualified_profiles` 沒跟著改，仍以版本字串為 key——**同一個錯，高了一層**。

**Owner 裁決**：

1. qualification key 改為 **darwin family ＋ arm64 ＋ ruby engine ＋
   ruby ABI ＋ runtime live native probes**。
2. **`native_linkage_digest` 不得作為 machine qualification key**——它是
   artifact-derived constant，可留作 artifact 完整性欄位，但不參與機器判定。
3. **exact `host_os` 降為 observation**，記錄但不參與判定。
4. 本卡改為驗證此判準**跨 OS version 是否成立**，不再建逐版本矩陣。
5. **先改研究／qualification 卡，產品實作另送 review。**

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

上表仍然成立，但**在改判準之後不再構成阻塞**：新判準不宣稱「某個 macOS
版本已驗證」，而是宣稱「ABI ＋ 架構 ＋ live probe 通過即支援」。要證否它
不需要乾淨機器，只需要兩個以上不同 `host_os` 的真實觀測——這個條件**已經
滿足**（`darwin24` 來自同事機，`darwin25` 來自本機）。

原本的乾淨機器需求留在此處備查：若日後要宣稱「未裝 Homebrew 的機器也能
開箱即用」，仍然需要一台真正乾淨的 macOS。那是另一個宣稱，不是本卡的。

## 3. 驗收

1. **判準跨 OS version 成立**：至少兩個不同 `host_os` 觀測值（目前已有
   `darwin24` 與 `darwin25`）在同一包 artifact 上，live native probe 全部
   通過且行為一致。兩者都必須判為 qualified。
2. **`host_os` 確實不參與判定**：把觀測值換成一個從未見過的字串
   （例如 `darwin99`），判定結果**不得改變**。這是本卡的主要鑑別力反證。
3. **`native_linkage_digest` 不再是機器判定的一部分**：證明它對同一包
   artifact 在不同機器上恆為同值，因此不具鑑別力；若仍保留在檔案中，
   必須明確標示為 artifact 完整性欄位。
4. **live native probe 才是真正的守門人**：`bigdecimal` 與 `sqlite3` 任一
   載不動時必須當場失敗並指出實際缺什麼，不得因為「key 對得上」就放行。
5. **ABI 相容但版本字串不同 → 不得誤拒**（Slice B 驗收第 2 項的分號前半，
   本卡承接的原條文）。
6. **版本相同但 linkage 不符 → 當場擋下**（本機已用 `install_name_tool`
   實證，此處為回歸確認）。
7. **完全不相容的 Ruby（例如系統 2.6）**：當場失敗、不靜默改用別的。
8. 每一項附鑑別力反證；跑不到的項目印 `N/A` 並指名由誰負責，**不得印
   PASS**。

### 實作後的對照（2026-09-21，`d771058` ACCEPTED_GO）

判準本身已由 `CARD-EMEM11-QUALIFICATION-KEY-FIX-20260921` 實作並通過 review。
逐項對照本卡驗收：

| # | 狀態 | 依據 |
|---|---|---|
| 1 判準跨 OS version 成立 | **通過**（2026-09-22） | 同事機升級到新版 artifact 後回報 `darwin24 / arm64 / 3.4.0` 且**不再印 `UNQUALIFIED_RUNTIME_PROFILE`**——真實觀測，非模擬。同一台機器修正前會印、修正後不印，變的只有 artifact |
| 2 `host_os` 不參與判定 | **通過** | `darwin99`／reviewer 另用 `darwin4242`，判定結果不變 |
| 3 linkage digest 不再機器判定 | **通過** | 已移出 `qualified_profiles`，改為 artifact integrity 欄位並 fail closed |
| 4 live probe 才是守門人 | **通過** | 兩層分家的四個情境皆實測 |
| 5 ABI 相容但版本字串不同不得誤拒 | **通過** | metadata-only mismatch → `UNQUALIFIED`，不阻擋 |
| 6 版本相同但 linkage 不符當場擋下 | **通過** | `OMOS_NATIVE_DEPENDENCY_UNRESOLVED`，exit 78 |
| 7 完全不相容的 Ruby 當場失敗 | **通過** | `OMOS_RUBY=/usr/bin/ruby` → exit 78 |
| 8 每項附鑑別力反證 | **通過** | 交付方三筆、reviewer 兩筆 |

**2026-09-22 結案**：第 1 項等到了第二台機器上的**實證**。當初沒有把它降格
成「本機模擬兩次」是對的——真正的證據只花了一次交付就拿到，而降格的條文會
永遠留在卡上假裝通過。

附帶澄清：同事端助理回報時寫「darwin24 已經在你們的驗證矩陣裡」，**說法相反**
——我們是把 `host_os` **移出** key，不是把 darwin24 加進矩陣。若真是加進矩陣，
下一個 `darwin26` 的人又會看到警告。

### 不在本卡

改 `runtime-profile.json` 的比對 key、改 `RuntimeProfile#current` 的欄位
組成——**產品實作另送 review**，本卡只裁決判準與驗證方式。

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
