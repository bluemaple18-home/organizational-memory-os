---
id: EMEM11-QUALIFICATION-KEY-FIX-20260921
status: ACCEPTED_GO
accepted_at: d771058（交付 06f6c6f、repair-01 d771058）
review_round_1: NO_GO（2026-09-21，P1×2：artifact integrity 欄位缺失時 fail-open／驗收第 5 項與程式互相矛盾）→ repair-01 已修
review_round_2: GO（2026-09-21，P0/P1/P2/P3 皆 0；.work/handoff/EMEM11-QUALIFICATION-KEY-FIX-REPAIR-01-REREVIEW-20260921.md）
residual: 驗收第 6 項（同事機重跑後 UNQUALIFIED 消失）需新版 artifact 送達後才算實證
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
5. **實際 runtime incompatibility 必須 fail closed。** 包含 candidate Ruby
   ABI 與 artifact vendor ABI 不符、native extension 無法載入、或宣告的
   native linkage 無法解析。
   單純 qualification key／觀測 metadata 不匹配，但實際 live native probes
   全部成功時，應回 `UNQUALIFIED_RUNTIME_PROFILE`，**不得誤當成執行不相容**。
6. 用同事那台重跑後，`UNQUALIFIED_RUNTIME_PROFILE` 應消失。

### Regression

7. 3a／3b／3c 全綠；40 支 validator 全綠；`git diff --check` clean。
8. 每一項附鑑別力反證。

## 3.1 repair-01（2026-09-21）

review round 1 判 **NO_GO**，2×P1：

| # | 缺陷 | 修法 |
|---|---|---|
| P1-1 | `assert_artifact_integrity!` 在宣告缺失時 `return`，等於**刪掉宣告就能關掉這道 guard**（實測 `PASSED_WITHOUT_DECLARATION`） | 缺欄位／格式錯／digest 不符三者一律 fail closed，各有專屬錯誤碼；缺宣告比不符更可疑，因為連「當初被 qualification 的是哪一份」都答不出來 |
| P1-2 | 驗收第 5 項與程式互相矛盾：卡說 CPU／ABI 不符要 fail closed，程式回 UNQUALIFIED | **Owner 裁決：維持 UNQUALIFIED**，改清楚驗收第 5 項 |

### P1-2 的裁決理由（Owner 2026-09-21）

這裡其實是兩層，不能混在一起：

```text
Compatibility / Safety gate          → fail closed
├─ candidate Ruby ABI 與 artifact vendor ABI 不符（pinned-ruby.sh，進 Ruby 前）
├─ native extension 真的載不動（live probe）
└─ 宣告的 native linkage 真的解析不到（live probe）

Qualification policy                 → UNQUALIFIED，不阻擋
├─ os_family 不在支援組合
├─ CPU metadata 不在已 qualification 組合
└─ ABI metadata 不在已 qualification 組合
```

reviewer 把 `RbConfig["host_cpu"] = "x86_64"` 與 `ruby_version = "9.9.9"`
當成「真的不相容」，測法不夠準：那只改了**回報 metadata**，底下仍是原本
那支 Ruby、原本那些 arm64 extension，所以 live probe 當然照樣成功。

**不採 hard allowlist**（CPU／ABI key 不符即 fail closed）——那會重新違反
Q7 §0.3 凍結的「runnable ≠ qualified」。
**不加第三道 self-check**（比對回報值與 artifact vendor 佈局）——除非找到
實際 exploit 證明「metadata 與 artifact layout 不一致、live probe 卻成功」
會造成錯誤行為，否則只是重複的 guard。

測試因此分成兩組：metadata-only mismatch → `UNQUALIFIED`；
physical／runtime incompatibility → `exit 78`。

## 3.2 review round 2（2026-09-21）：GO

P0/P1/P2/P3 皆 0，兩筆 P1 **CLOSED**。reviewer 未沿用交付方的破壞方式
（改用「64 字元但含非 hex 的 `g`」），並獨立確認兩層分家的四個情境都符合
裁決；另檢查 `verify!` 的順序為 live native probe → artifact integrity →
qualification key，**未找到**「實際 runtime 已不相容卻只落到 UNQUALIFIED」
的路徑。reviewer 自己的鑑別力反證（只改錯誤碼）只讓對應的不變式轉紅。
verdict：`.work/handoff/EMEM11-QUALIFICATION-KEY-FIX-REPAIR-01-REREVIEW-20260921.md`。

**驗收第 6 項尚未實證**：同事機目前裝的是舊版 artifact，`UNQUALIFIED` 是否
真的消失，要等新版送到他手上才算數。本機以 `host_os=darwin24` 模擬的結果
是 `QUALIFIED`，但模擬不等於實證，故列為 residual 而非通過。

## 4. 不做

不改 probe 實作、不改 `pinned-ruby.sh` 的候選搜尋、不新增平台、
不導入簽章／notarization、不重打已出貨的 zip（驗收第 6 項待下一版）、
**不新增第三道 self-check**（repair-01 裁決）。

## 5. Minimum Sufficient

- **why_not_less**：不改則每來一個同事就要往矩陣加一列，且加的是一個
  與相容性無因果關係的版本字串。
- **why_not_more**：只換比對 key，不動 probe、不動 guard 的候選搜尋、
  不擴充支援宣稱的範圍。
- **do_not_absorb**：不吸收「沒裝 Homebrew 是否開箱即用」那個宣稱——
  那仍需乾淨機器，留在 qualification 卡。
