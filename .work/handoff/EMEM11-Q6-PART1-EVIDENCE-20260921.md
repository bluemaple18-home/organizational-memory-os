# EMEM-11 Q6 Part 1｜zero-local-compiled-extension 可行性 — 實驗證據

- 研究卡：`CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920`（`ACCEPTED_GO`）
- 範圍限制（reviewer 指定）：**只產 evidence／research conclusion**。全程在
  `/tmp` 進行，**未改動產品的 Gemfile、.bundle/config、installer 或任何檔案**。
- 執行環境：macOS arm64，Homebrew Ruby 3.4.10，Bundler 4.0.21
- 日期：2026-09-21

## 結論（先講）

**Part 1 的答案是「不可行」——production artifact 無法做到 zero-local-compiled
extension。** 但量測過程推翻了一個原本以為成立的風險，也讓真正的邊界變清楚了。

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

## 2. 被推翻的假設：Homebrew patch 升級**不會**弄壞 artifact

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

> 誠實標註：這是**由 install_name 與 ABI 目錄推得的推論**，不是實測。
> 要確證需等到實際有一次 patch 升級，或 Part 2 的第二個 distribution 矩陣。

## 3. 真正的邊界是「安裝路徑」，不是「版本」

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

## 6. 後續可考慮的方向（不在本輪，僅列出以免遺失）

1. **接受單一 build profile**：artifact 綁定編譯時的 Ruby 安裝路徑，
   guard 改為檢查 linkage 路徑而非版本字串。
2. **安裝時重編原生擴充**：target 需有編譯工具鏈（Xcode CLT），安裝不再 hermetic。
3. **提供多組預編譯 artifact**（per Ruby 安裝路徑／distribution）——複雜度高。
4. **向上游要 precompiled bigdecimal**——不在本專案控制範圍。

## 附：本輪未改動任何產品檔案

實驗全在 `/tmp/q6`。產品的 `Gemfile`、`Gemfile.lock`、`.bundle/config`、
`bin/pinned-ruby.sh`、`installer.rb` 皆未變動，`git status` 於實驗前後皆 clean。
