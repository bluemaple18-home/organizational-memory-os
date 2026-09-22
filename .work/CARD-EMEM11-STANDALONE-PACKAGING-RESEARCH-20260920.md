---
id: EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920
status: ACCEPTED_GO
signed_at: 2026-09-21
type: research
tier: T3
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
origin: .work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md §G-1
pinned_product_delivery: fa0959a
review_round_1: NO_GO（P1×2 + P2×2）
cc_response: .work/handoff/EMEM11-PACKAGING-REVIEW-RESPONSE-20260920.md
review_round_2: GO after documentation correction（P0/P1/P2 = 0）
review_round_3: GO（P2×1 metadata 已修）
# 下一階段（packaging 實作）開卡前必須先處理的既存缺陷：
implementation_prerequisite:
  - CARD-EMEM11-STALE-HOOK-RELOCATION-20260920
  - CARD-EMEM11-RUBY-GUARD-CRITERION-20260921
authority: organizational-memory-os
---

# EMEM-11｜產品獨立安裝：dependency closure 研究

👉 [假設與目標確認]
- **目標**：回答「`product/personal-memory` 要成為可配送的 artifact，還差
  什麼」，並把 packaging 方向收斂成可裁決的選項。
- **邊界**：**本卡不寫實作**。不改 `contract.rb`、不建 build script、不選
  配送格式（gem／tarball／brew）。EMEM-11 已 `ACCEPTED_GO`，本卡不重開驗收、
  不碰 doctor P2、不碰 EMEM-11b。
- **驗收**：§7 的定案清單成立，且 §4 的七個問題有明確承接。

---

## 0. 定案（經兩輪 review）

| 項目 | 結論 |
|---|---|
| 9-file repo-external governance closure | **CONFIRMED**（雙方各自獨立驗證） |
| Packaging 方案 | **A（build 時納入 artifact）selected** |
| installer-copy | **B rejected** —— authority／version integrity ＋ lifecycle duplication |
| Ruby runtime | **不先配送 runtime；也不先綁死 Homebrew build；更不先宣稱 universal Ruby 3.4.x** |
| Q6 Part 1 | **已完成並收線（2026-09-21）**：**在目前 dependency set ＋ Bundler vendor 模式下**，zero-local-compiled-extension **不可行**。證據：`.work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md` |
| runtime 支援判準 | 由 `RUBY_VERSION` 字串改為 **runtime profile ＝ native linkage 可解析 ＋ ABI 相容**。口語可稱「安裝路徑 ＋ ABI」，但**契約不得只寫 path** |
| Homebrew patch 相容 | **`EXPECTED_COMPATIBLE / NOT_YET_VERIFIED`** —— 證據足以支持「3.4.10 → 3.4.11 很可能相容」，但未實際載入跑過，**不得寫成 guaranteed support**；遇下一個 patch 時補 qualification，**不阻塞 Q7** |
| Q6 Part 2 | 重新定義為 **clean-macOS runtime qualification**，需一台真的沒有 `/opt/homebrew/opt/ruby@3.4` 的 Mac／VM／同事機；**不再阻塞 Q7**，移入 packaging acceptance |
| `pinned-ruby.sh` guard | 另立卡（`CARD-EMEM11-RUBY-GUARD-CRITERION-20260921`）。判準已由 Q7 §0.3 定義、**blocker 解除**，與 stale-hook P1 同層列為 packaging 實作前置 |
| Q7 | **已裁決並凍結（2026-09-21）**：A 案，stable identity ＝ **固定 launcher path**（非 current symlink）；三層分離 Host identity ／ activation pointer ／ artifact identity。runtime guard 四項定義收緊。見 `CARD-EMEM11-Q7-ACTIVATION-RUNTIME-PROFILE-20260921` §0 |
| zombie hook | **另開 P1**（`CARD-EMEM11-STALE-HOOK-RELOCATION-20260920`），且為 **packaging 實作的前置** |
| standalone acceptance | workspace B／clean environment，不動已驗收工作區 |
| artifact receipt | 需能識別 code + spec + evaluator 同屬一個 build；**不得拿 store `schema_version` 代替** |

### 定案順序

```
Q6 Part 1 收線（已完成）
  → Q7 activation identity ／ runtime profile 裁決
  → stale-hook P1 ＋ pinned-ruby guard defect（兩者同層）
  → packaging implementation
  → clean-macOS Part 2 qualification
```

---

## 1. 問題陳述

真人驗收（2026-09-20，ACCEPTED_GO）通過，但證據包 §G-1 留了一項：
**產品尚未可獨立安裝**——`product/personal-memory` 離開
`organizational-memory-os` 就無法執行。

這不是「一條路徑寫死」，是 **dependency closure 尚未成立**：產品把 spec 與
**治理 evaluator** 都直接從 repo 載入，少的不只是設定檔，是判定邏輯本身。

影響面（措辭收斂，不誇大）：

- 給同事安裝：**現在一定失敗**，停在 install 階段。
- SSP-295 pilot：影響**任何沒有這個 repo 的機器**上的 pilot。若 pilot 就在
  本機這個 checkout 上跑，本項不構成阻擋。**「pilot 是否必須能在乾淨機器上
  跑」屬 Owner 範圍裁決，本卡不替它假設。**
- 未來產品化：硬前提。

---

## 2. Dependency closure（實證）

### 2.1 repo-external governance closure —— 9 個檔（CONFIRMED）

> 命名刻意精確：這是**「離開 repo 就缺的治理依賴」**，不是整個 distributable
> closure——Ruby／native ABI 是另一層（§2.3）。

`lib/omos/contract.rb:19-22` 是唯一入口：

```ruby
REPO_ROOT  = File.expand_path("../../../..", __dir__)
SHARED_LIB = File.join(REPO_ROOT, "scripts/lib")
SPEC_PATH  = File.join(REPO_ROOT, "規格/v0.1/personal-harness-integration.yaml")
VOCAB_PATH = File.join(REPO_ROOT, "規格/v0.1/common-vocabulary.yaml")
```

**Spec（2）**：`personal-harness-integration.yaml`、`common-vocabulary.yaml`

**共用 evaluator（7）**：`host_session_binding_shape`、
`minimal_evidence_package_shape`、`omos_contract_helpers`、
`personal_memory_host_binding`、`personal_memory_resource_evaluator`、
`runtime_log_oracle`、`weekly_closeout_history`

**兩條獨立證據**：

1. （CC）對 7 支做 `require_relative` 遞移展開——**沒有多出任何一支**；
   檔案 I/O 掃描顯示只有 `omos_contract_helpers` 有 `File.read`／
   `YAML.safe_load`，且都是收 path 參數的泛用 helper，無寫死路徑。
2. （reviewer）在 `/private/tmp` 建最小樹，只放產品檔 ＋ 這 9 個檔，不帶
   repo 其他任何東西，實跑 **3a 26/26、3b 33/33、3c 49/49 全 PASS**。
   另檢查 `load`／`autoload`／glob／subprocess／ENV path-like metadata。

YAML 內雖有 `native_adapter_spec`、`acl_snapshot_pattern_source`、
`evaluator_ref` 等其他檔名，但 product 與這 7 支 evaluator 在 runtime
**不會 dereference 它們**——屬 metadata／provenance reference，不是 runtime
dependency。

### 2.2 Gem 層：已 vendored，但 layout 仍待裁

`vendor/bundle` 已 vendored 全部 gem（22 MB，產品目錄共 23 MB），
`.bundle/config` 設 `BUNDLE_PATH: vendor/bundle`，入口
`lib/omos/entry/cli.rb:3-4` 自設 `BUNDLE_GEMFILE` 並 `require "bundler/setup"`。
**Bundler 本身不構成新前置**：實測 Homebrew Ruby 3.4.10 內附的 Bundler
4.0.15 可讀目前由 4.0.21 產出的 lockfile 並載入 vendored gem。

**但不可寫成「gem 已自足、不必再管」**（第一版曾如此宣稱，已更正）：

- 現行 `BUNDLE_PATH=vendor/bundle` 會把 **Ruby 隨附的 bundled gem 隔離掉**。
  若要走 §2.3 的「讓 Ruby 自帶 gem 滿足無約束依賴」路線，**packaging layout
  本身要改**，不是設定微調。

### 2.3 Ruby／native ABI —— 真正未成立的一層

`bin/pinned-ruby.sh` 不打包 Ruby，而是**到機器上找** Ruby 3.4.10
（`OMOS_RUBY` → Homebrew `ruby@3.4` → rbenv → PATH），找不到 `exit 78`。
這是刻意設計（macOS 系統 Ruby 2.6 載入 3.4 編譯的原生 gem 會 SIGILL 且無
輸出），不是缺陷；但後果是「standalone」目前上限只到**不依賴 repo**。

**實測（`otool -L` ＋ 實跑掃 `$LOADED_FEATURES`）**——production 實際載入的
vendor native extension 只有兩個：

| extension | 來源 | 連結 |
|---|---|---|
| `sqlite3_native.bundle` | 預編譯 platform gem `sqlite3-2.9.6-arm64-darwin` | 只有 `/usr/lib/libz.1.dylib`、`libSystem`，**無 libruby** |
| `bigdecimal.bundle` | 本機編譯 `extensions/arm64-darwin-25/bigdecimal-4.1.3/` | **硬連 `/opt/homebrew/opt/ruby@3.4/lib/libruby.3.4.dylib`** |

`prism`、`racc` **在 production 從未被載入**（`prism` 由 `:development`
group 的 `minitest` 拉入）。因此 ABI 問題收斂到 **`bigdecimal` 單一 gem**，
來源為 `mcp (1.5.1) → json_schemer (2.5.0) → bigdecimal`，且 json_schemer
**未下任何版本約束**；Ruby 3.4 自帶 bigdecimal 3.1.8（bundled gem）。

**reviewer 的前進一步**：在 `/tmp` 重解一份 macOS arm64 production lock、
強制 `bigdecimal=3.1.8`，結果 **`mcp 1.5.1 + json_schemer 2.5.0` 可正常
resolve 並載入**——功能相依上，Ruby 隨附版本可用。

**但仍不得宣稱「任何 Ruby 3.4.x 都 portable」**，兩個理由：

1. §2.2 的 `BUNDLE_PATH` 會隔離 Ruby 自帶 gem，layout 要先改。
2. `sqlite3_native.bundle` 雖無 libruby 絕對 linkage，**它仍是 Ruby C
   extension**。沒有第二個 Ruby 3.4 distribution 的實跑證據前，**不能從
   `otool` 推論 ABI 相容**——那是「觀察到一個就推廣」的同一類錯誤。

**Q6 Part 1 已於 2026-09-21 就上述兩點給出結論**（證據：
`.work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md`）：

- 第 1 點走不通——`bigdecimal` 沒有任何 `*-darwin` 預編譯，而 Bundler 明文
  拒絕 `path` 與 system gems 並用（`Using a custom path while using system
  gems is unsupported.`）。**在目前 dependency set ＋ Bundler vendor 模式下，
  zero-local-compiled-extension 不可行。**
- 第 2 點維持成立——仍未取得第二個 distribution 的實跑證據，因此
  Part 2 改為 **clean-macOS runtime qualification**（需一台沒有
  `/opt/homebrew/opt/ruby@3.4` 的 Mac），且**不阻塞 Q7**。
- 已實證：缺 linkage path 時是**明確 LoadError、exit 非零**，不是靜默失敗。

**因此定案**：不配送 runtime；支援判準改為 **runtime profile ＝ native
linkage 可解析 ＋ ABI 相容**（不以版本字串為準）；Homebrew patch 相容列為
`EXPECTED_COMPATIBLE / NOT_YET_VERIFIED`。

---

## 3. 為什麼不能用「把路徑改成可設定」解決

把 `SPEC_PATH` 變成環境變數或設定項，只是把「去哪找 repo」變成使用者的責任，
closure 仍不成立——而且會讓**契約來源變成可由使用者指定**，比現況更糟。
本卡不考慮此方向。

---

## 4. 待回答的問題

1. **最小 closure 確認**：§2.1 的 9 個檔。**已 CONFIRMED**（兩條獨立證據）。
2. **漂移如何機械保證**：那 7 支 evaluator 是**與 repo 的 39 支 validator
   共用的同一份程式**。若產品凍結副本而 repo 原件繼續演進，會出現「產品與
   validator 依不同規則判定同一件事」——憲法禁止的**第二套治理**。
   gate 必須**雙向**：repo 改了原件而未重新產生 package，**CI 必須紅**；
   只驗「package 內副本有沒有被竄改」不足夠。要求 byte/digest 級比對。
3. **真正的 standalone acceptance**：build 在 workspace A；artifact 送到
   **沒有 source checkout 的 workspace B**（或第二個 CI job）＋ isolated
   HOME，workspace B 內完全沒有 `scripts/lib` 與 `規格/v0.1`；再跑
   CLI／MCP／SessionStart／doctor ＋ 3a/3b/3c。**不得改名或移走已驗收的主
   工作區來製造隔離。** 另須包含 **relocation/upgrade case**（見 Q7 與前置
   P1 卡）。
4. **upgrade / rollback 版本一致**：程式、spec、evaluator 必須同屬一個
   artifact version。**現有 receipt 沒有 artifact identity**——欄位只有
   `installed_at / product_root / ruby_version / store_path / schema_version /
   commands / hosts`，其中 `schema_version` 是 **store 的 schema**，MCP
   server 的 `0.1.0` 也不能證明 code/spec/evaluator 同一份 build。
   先研究能否以 minimal build digest／source identity 補足，**不要新造一整套
   版本治理系統**。
5. **失效時的行為**：packaged spec／evaluator 缺檔或損壞時，必須 **fail
   closed 並回明確錯誤碼**，不得退化成「跑得起來但沒有治理」。
6. **（新）Runtime／native ABI closure**：**Part 1 已於 2026-09-21 完成並
   結案**——zero-local-compiled-extension 路線**證否**（`bigdecimal` 無任何
   `*-darwin` 預編譯；Bundler 拒絕 `path` 與 system gems 並用）。因此支援
   宣稱改以 **native linkage path ＋ ABI 目錄**為準，不以版本字串為準。
   另已實證：缺 linkage path 時是明確 LoadError、非靜默失敗。
   **Part 2 原定為 Clean macOS runtime-profile matrix**，需要一台沒有
   `/opt/homebrew/opt/ruby@3.4` 的 macOS 環境才有判定力——在本機裝第二個
   Ruby 會被既存的 Homebrew dylib 路徑污染（dyld 可能把 Homebrew libruby
   載進 alternate Ruby 的程序），結果不等價於乾淨機器。Part 2 因此移入
   packaging acceptance，**不阻塞 Q7**。

   **2026-09-21 Owner 改判準，Part 2 不再是矩陣。** 同事機回報 `darwin24`、
   本機為 `darwin25`，暴露出 `qualified_profiles` 只有 `host_os` 會因人而異，
   等於「一個 macOS build 一列」且永遠列不完；而 `darwin24` 這個版本字串
   本來就不是相容性判準——與 Q6 Part 1 否掉的那個錯相同，只是高了一層。
   新判準為 **darwin family ＋ arm64 ＋ ruby engine ＋ ruby ABI ＋ runtime
   live native probes**；`native_linkage_digest` 是 artifact-derived constant，
   **不得**充當 machine qualification key；exact `host_os` 降為 observation。
   Part 2 改為**驗證此判準跨 OS version 是否成立**，見
   `CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921`。產品實作另送 review。
   `pinned-ruby.sh` guard 判準錯誤另立卡待裁。
7. **（新）Installation root／activation identity**：Host command 要綁
   **stable launcher**，還是 versioned artifact path ＋ receipt 驅動的遷移？
   artifact relocation／upgrade／rollback 如何保證不留下舊 hook？
   **相關的現存缺陷已另立 P1 卡承接**（見 §6）。

---

## 5. Packaging 方案

### 方案 A｜build 時納入 artifact —— **selected**

```
repo 內原始 spec/evaluator = source of truth
build/package 時機械複製進 artifact（byte 相同）
runtime 只讀自己 artifact 內的 versioned copy
```

優點：runtime 無 repo 依賴；版本與程式同屬一個 artifact；漂移可用 digest
gate 機械擋住。代價：需要 build 步驟與對應 CI gate（目前沒有）。

### 方案 B｜installer 執行時複製到使用者目錄 —— **rejected**

理由（**已修正**）：

- 產生**第二份 mutable authority material**；
- code／spec／evaluator **無法 atomic 版本化**，upgrade／rollback 容易形成
  mixed version；
- 額外需要同步、digest、清理與 rollback 機制，**卻不增加任何產品能力**。

> **更正紀錄**：本卡第一版主張「使用者家目錄可寫 ⇒ 授權漏洞」。該論證**不
> 成立**——產品 artifact 本身也位於同一個 OS user 可寫的位置，在沒有簽章、
> root-owned 目錄或 immutable mount 之類 trust boundary 的前提下，`~/.omos`
> 並未多出任何 authorization boundary。結論不變，理由已替換。

---

## 6. 前置：既存的 stale hook 缺陷（另立 P1）

`CARD-EMEM11-STALE-HOOK-RELOCATION-20260920`。

product_root 改變時，`upgrade` 會留下舊路徑的 SessionStart 註冊，
`uninstall` 也清不掉。**這是今天就存在的產品 correctness bug**，與最終選
tarball 或 gem 無關，且會讓 versioned artifact 一啟用就產生 zombie hook。

**該卡是 packaging 實作的前置**，不是普通 backlog。本研究卡的 Q7 只負責
長期 activation identity 的設計裁決。

---

## 7. Minimum Sufficient

- **why_not_less**：少於「spec ＋ 7 支 evaluator 隨 artifact 配送」，產品在
  repo 外無法建立 binding／執行治理判定——等於不存在。
- **why_not_more**：本卡**不**決定配送格式、**不**建 release pipeline、
  **不**處理跨平台（目前只需 macOS arm64）、**不**重做 gem vendoring 本身。
  Ruby runtime 是否配送屬 §2.3 定案（不配送），不自動擴張成「打包一個 Ruby」。
- **do_not_absorb**：不因打包而把 evaluator 複製成產品自有版本——那會變成
  第二套治理。產品端永遠是 repo 原件的機械副本。
