# EMEM-11 Q6 Part 1｜zero-local-compiled-extension 可行性 — 實驗證據

- 研究卡：`CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920`（`ACCEPTED_GO`）
- 範圍限制（reviewer 指定）：**只產 evidence／research conclusion**。全程在
  `/tmp` 進行，**未改動產品的 Gemfile、.bundle/config、installer 或任何檔案**。
- 執行環境：macOS arm64，Homebrew Ruby 3.4.10，Bundler 4.0.21
- 日期：2026-09-21

## 結論（先講，範圍刻意寫精確）

> **在目前的 dependency set ＋ Bundler vendor 模式下，
> zero-local-compiled-extension 不可行。**
>
> 兩個必要條件同時成立才構成此結論：(1) `bigdecimal` 必須本機編譯
> （無任何 `*-darwin` 預編譯）；(2) 現行 Bundler 不允許同時使用 custom
> vendor path 與 system gems。**任一條件在未來改變（例如上游開始提供
> precompiled bigdecimal、或依賴樹不再經過 json_schemer），結論就要重驗**，
> 不是永久事實。

量測過程另外推翻了一個原本以為成立的風險，也讓真正的邊界變清楚了。

---

## 1. 為什麼不可行：兩道各自獨立的封鎖

### 1.1 `bigdecimal` 沒有預編譯版本

```
$ gem list -r bigdecimal --all
bigdecimal (4.1.3 ruby java, 4.1.2 ruby java, ... 3.1.8 ruby java, ...)
```

**只有 `ruby`（原始碼）與 `java` 兩個平台，沒有任何 `*-darwin` 預編譯。**
指定 `--platform arm64-darwin` 抓到的仍是同一份 116 KB 原始碼 gem。

對照：`sqlite3` 有完整的 platform gem 矩陣（`arm64-darwin`、
`x86_64-darwin`、多種 linux），所以它的 `.bundle` 是預編譯的，
`otool -L` 只連 `libz` 與 `libSystem`，**完全不依賴 libruby**。

因此只要 `bigdecimal` 被 vendored，就**必然**在本機編譯，必然連上編譯當下那個
Ruby 的 libruby。

### 1.2 Bundler 不允許「部分 vendor」

原本設想的迴避路線是：vendor 其他 gem，但讓 Ruby 3.4 自帶的 bundled gem
（Ruby 3.4 隨附 bigdecimal 3.1.8）去滿足這個無版本約束的依賴。實測：

```
BUNDLE_PATH: "vendor/bundle"
BUNDLE_DISABLE_SHARED_GEMS: "false"

$ bundle install --local
Using a custom path while using system gems is unsupported.
```

**Bundler 明文拒絕。** `path` 與 shared system gems 不能並用，是全有全無。

> reviewer 先前確認過「強制 `bigdecimal=3.1.8` 後 `mcp 1.5.1 + json_schemer
> 2.5.0` 仍可 resolve 並載入」——那個結論仍然成立，但它只證明**功能相依**
> 沒問題；本實驗證明的是**打包機制**這條路走不通。兩者不衝突。

### 1.3 `bigdecimal` 不是可有可無的

`mcp (1.5.1) → json_schemer (2.5.0) → bigdecimal`（runtime 依賴，無版本約束）。
production 實跑掃 `$LOADED_FEATURES` 確認 `bigdecimal.bundle` 真的被載入。
不能靠排除 `:development` group 擺脫它——那只能拿掉 `prism`／`racc`。

---

## 2. Homebrew patch 升級：**EXPECTED_COMPATIBLE / NOT_YET_VERIFIED**

原本（含我與 reviewer 雙方）都假設 Homebrew `ruby@3.4` 是 major.minor formula，
patch 前進後會讓 artifact 失效。**實測顯示不會**：

```
Ruby ABI 目錄            RbConfig ruby_version = 3.4.0   ← 整個 3.4 系列共用
libruby 的 install name  /opt/homebrew/opt/ruby@3.4/lib/libruby.3.4.dylib
                                       ↑ 穩定的 opt symlink，不是 Cellar 實體路徑
opt symlink 現況         /opt/homebrew/opt/ruby@3.4 -> ../Cellar/ruby@3.4/3.4.10
```

Homebrew 升 patch 時只是把 `opt/ruby@3.4` 重新指向新的 Cellar 目錄。
編譯進 `.bundle` 的絕對路徑**指的是那個 symlink**，而 Ruby 的 C extension ABI
目錄在整個 3.4 系列都是 `3.4.0`。

**因此 3.4.10 → 3.4.11 的 Homebrew 升級，dylib 路徑與 ABI 皆不變，
既有的 `bigdecimal.bundle` 應可繼續載入。**

> **狀態：`EXPECTED_COMPATIBLE / NOT_YET_VERIFIED`。**
> 這是由 install_name 與 ABI 目錄推得的**推論**，沒有真的載入 3.4.11 跑過，
> 因此**不得寫成 guaranteed support**。遇到下一個 Homebrew 3.4 patch 時補一次
> qualification 即可；此項**不阻塞 Q7**。

## 3. 真正的判準：runtime profile（linkage 可解析 ＋ ABI 相容）

口語可簡稱「安裝路徑 ＋ ABI」，但**契約不得只寫 path**。實際要驗的是兩件事：

1. `bigdecimal.bundle` 所需的 `libruby` **能否被 loader 正確解析**
   （路徑存在只是其中一種成立方式）；
2. **ABI 是否相容**（Ruby 的 C extension ABI 目錄，3.4 系列為 `3.4.0`）。

綜合 1 與 2：artifact 能不能在另一個 Ruby 上跑，取決於
**編譯時那個絕對 dylib 路徑在目標機器上存不存在、且 ABI 目錄相同**。

| 情境 | 預期 |
|---|---|
| 同一台、Homebrew patch 升級（3.4.10 → 3.4.11） | **可用**（路徑與 ABI 不變） |
| 另一台、同樣用 Homebrew `ruby@3.4` | 可用（路徑一致） |
| rbenv／asdf／ruby-build 的 3.4.10（裝在別的路徑） | **不可用**（絕對路徑不存在） |
| 系統 Ruby 2.6 | 不可用（已知，`pinned-ruby.sh` 擋下） |

## 4. 由此暴露的既有 guard 缺陷（新發現，非 reviewer 提出）

`bin/pinned-ruby.sh` 目前的判準是**版本字串相等**（`.ruby-version` 鎖 exact
`3.4.10`）。對照 §3，這個 guard 同時是：

- **過嚴**：Homebrew 升到 3.4.11 後 ABI 與路徑其實都沒變、artifact 仍可用，
  但 guard 會以 exit 78 拒絕，逼使用者無法使用一個其實相容的 Ruby。
- **過鬆**：它接受 rbenv／PATH 上**任何**剛好是 3.4.10 的 Ruby，而那些裝在
  不同路徑的 Ruby **無法**載入我們編譯出來的 extension。guard 放行之後才會
  在載入原生擴充時失敗。

也就是說：**guard 檢查的東西（版本字串）不是實際的約束（linkage 路徑 ＋
ABI）。** 這一條應該納入 Q6 的結論與後續 packaging 設計，但**本輪不修**。

## 5. 對 Q6 結論的影響

「zero-local-compiled-extension 後即可宣稱 universal Ruby 3.4.x」這條路
**已被證否**，因此：

- reviewer 原本「不先綁死 Homebrew、也不先宣稱 universal」的定案**仍然正確**，
  而且現在有了更精確的理由——不是「還沒驗」，是**機制上做不到**。
- 支援宣稱應改以**安裝路徑 ＋ ABI**為準，而非版本字串。
- Part 2（第二個 Ruby distribution 矩陣）的價值也隨之改變：它要驗的不再是
  「能不能放寬到任何 3.4.x」，而是 **§3 那張表的預期是否成立**，特別是
  「不同路徑的 Ruby 確實會失敗，且失敗方式是明確的、不是靜默壞掉」。

## 5b. 缺 linkage path 時會**大聲失敗**（已直接實證）

reviewer 設計的零成本負例，CC 獨立重現一次，結果一致：把
`bigdecimal.bundle` 複製到 `/private/tmp`，以 `install_name_tool` 把它的
libruby load command 改寫成不存在的絕對路徑，再嘗試載入：

```
otool -L → /nonexistent/libruby.3.4.dylib

$ ruby -e 'require "/tmp/q6neg/bigdecimal.bundle"'
LoadError: dlopen(...): Library not loaded: /nonexistent/libruby.3.4.dylib
  Reason: tried: '/nonexistent/libruby.3.4.dylib' (no such file), ...
exit 1
```

**結論**：目標機器缺少編譯時的 linkage path 時，失敗是
**明確的 LoadError、退出碼非零、訊息直接指出缺哪個路徑**——不會靜默繼續、
不會退化成「跑得起來但行為不明」。這符合本產品一貫的 fail-closed 紀律。

§3 那張表裡「rbenv／asdf 的 3.4.10（裝在別的路徑）→ 不可用」這一格，
至此有了直接證據支持其**失敗方式**（雖然尚未在真實 rbenv 環境重現，見 §5c）。

## 5c. 為什麼 Part 2 **不能**在這台機器上做（reviewer 指出，CC 同意）

原本規劃用 `ruby-build` 或可攜式 Ruby 在本機裝第二個 3.4.10 來跑矩陣。
**這個設計有缺陷**：

`bigdecimal.bundle` 寫死的是
`/opt/homebrew/opt/ruby@3.4/lib/libruby.3.4.dylib`，而**這條路徑在本機依然
存在**。alternate Ruby 載入該 extension 時，dyld 仍可解析到 **Homebrew 的
libruby**，於是同一個程序裡會出現兩套 Ruby runtime。

此時無論結果是成功、crash 或 LoadError，**都不等價於「一台只有 rbenv Ruby、
沒有 Homebrew Ruby 的乾淨機器」**，因此沒有判定力。

同理：

- `brew install ruby-build` 後在 `/tmp` 編 3.4.10 → 成本高且證據混淆。
- 第三方 portable Ruby → 同樣被既存 Homebrew dylib 路徑污染。
- Docker 官方 `ruby:3.4` → linux/arm64，答不了 macOS dyld/ABI 的問題。

**三者現在都不值得跑。**

### Part 2 重新定義

不再是「在這台裝第二個 Ruby」，改為：

> **Clean macOS runtime-profile matrix** —— 需要一個真的**沒有
> `/opt/homebrew/opt/ruby@3.4`** 的 macOS 環境（同事機、乾淨 Mac／VM、
> 或之後的第二台測試機）才有判定力。

**Part 2 因此不再阻塞 Q7**，改列為 **packaging acceptance／runtime-profile
qualification** 的一部分。

## 6. 後續可考慮的方向（不在本輪，僅列出以免遺失）

1. **接受單一 build profile**：artifact 綁定編譯時的 Ruby 安裝路徑，
   guard 改為檢查 linkage 路徑而非版本字串。
2. **安裝時重編原生擴充**：target 需有編譯工具鏈（Xcode CLT），安裝不再 hermetic。
3. **提供多組預編譯 artifact**（per Ruby 安裝路徑／distribution）——複雜度高。
4. **向上游要 precompiled bigdecimal**——不在本專案控制範圍。

## 附：本輪未改動任何產品檔案

實驗全在 `/tmp/q6`。產品的 `Gemfile`、`Gemfile.lock`、`.bundle/config`、
`bin/pinned-ruby.sh`、`installer.rb` 皆未變動，`git status` 於實驗前後皆 clean。
