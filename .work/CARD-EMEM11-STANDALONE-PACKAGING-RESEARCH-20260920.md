---
id: EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920
status: RESEARCH_ONLY_AWAITING_REVIEW
type: research
tier: T3
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
origin: .work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md §G-1
pinned_product_delivery: fa0959a
authority: organizational-memory-os
---

# EMEM-11｜產品獨立安裝：dependency closure 研究

👉 [假設與目標確認]
- **目標**：回答「`product/personal-memory` 要成為可配送的 artifact，還差什麼」，
  並把 packaging 方向收斂成帶取捨的選項交 Owner 裁決。
- **邊界**：**本卡不寫實作**。不改 `contract.rb`、不建 build script、不選
  packaging 格式（gem／tarball／brew 等）。EMEM-11 已
  `ACCEPTED_GO`，本卡不重開驗收、不碰 doctor P2、不碰 EMEM-11b。
- **驗收**：Owner／reviewer 對 §5 的兩個方案擇一，並回答 §4 的五個問題。

---

## 1. 問題陳述

真人驗收（2026-09-20，ACCEPTED_GO）通過，但證據包 §G-1 留了一項：
**產品尚未可獨立安裝**。目前 `product/personal-memory` 一旦離開
`organizational-memory-os` 這個 repo 就無法執行。

這不是「一條路徑寫死」的小 bug——是 **dependency closure 尚未成立**：
產品把 spec 與**治理 evaluator** 都直接從 repo 載入。少的不只是設定檔，
是判定邏輯本身。

影響面（措辭刻意收斂，不誇大）：

- 給同事安裝：**現在一定失敗**，會停在 install 階段。
- SSP-295 pilot：影響的是**任何沒有這個 repo 的機器**上的 pilot。若 pilot 就
  在本機這個 checkout 上跑，本項不構成阻擋。**「pilot 是否必須能在乾淨機器
  上跑」是 Owner 的範圍裁決，本卡不替它假設。**
- 未來真正產品化：硬前提。

---

## 2. 已量到的 dependency closure（實證，非估計）

### 2.1 repo 內的檔案依賴 —— 共 9 個檔

`lib/omos/contract.rb:19-22` 三個常數是唯一的入口：

```ruby
REPO_ROOT  = File.expand_path("../../../..", __dir__)
SHARED_LIB = File.join(REPO_ROOT, "scripts/lib")
SPEC_PATH  = File.join(REPO_ROOT, "規格/v0.1/personal-harness-integration.yaml")
VOCAB_PATH = File.join(REPO_ROOT, "規格/v0.1/common-vocabulary.yaml")
```

**Spec（2）**

- `規格/v0.1/personal-harness-integration.yaml`
- `規格/v0.1/common-vocabulary.yaml`

**共用 evaluator（7，此為完整遞移閉包）**

- `scripts/lib/host_session_binding_shape.rb`
- `scripts/lib/minimal_evidence_package_shape.rb`
- `scripts/lib/omos_contract_helpers.rb`
- `scripts/lib/personal_memory_host_binding.rb`
- `scripts/lib/personal_memory_resource_evaluator.rb`
- `scripts/lib/runtime_log_oracle.rb`
- `scripts/lib/weekly_closeout_history.rb`

**閉包已驗算**：對這 7 支做 `require_relative` 遞移展開，**沒有多出任何一支**
（彼此無互相 require）。另外檢查了檔案 I/O：7 支裡只有
`omos_contract_helpers` 有 `File.read`／`YAML.safe_load`，且都是**收 path
參數的泛用 helper**，沒有寫死任何路徑——因此不存在「執行時再偷偷讀第 10 個
檔」的情況。

### 2.2 已經解決、**不要重做**的部分

**Gem 依賴已自足。** `vendor/bundle` 已 vendored 全部 gem（22 MB），
`.bundle/config` 設 `BUNDLE_PATH: vendor/bundle`，入口
`lib/omos/entry/cli.rb:3-4` 自行設定 `BUNDLE_GEMFILE` 並 `require "bundler/setup"`。
產品目錄總計 23 MB，其中 22 MB 是 vendor。

這一塊**已經是 closure 的一部分且已完成**。研究結論不得把它重新列為待辦。

### 2.3 尚未納入 closure 的第三塊：**Ruby runtime 本身**

`bin/pinned-ruby.sh` 不是打包 Ruby，而是**到機器上找** Ruby 3.4.10
（依序試 `OMOS_RUBY` → Homebrew `ruby@3.4` → rbenv → PATH），找不到就
`exit 78`。

這是刻意設計（實測 macOS 系統 Ruby 2.6 載入為 3.4 編譯的原生 gem 會 SIGILL
且毫無輸出），**不是缺陷**。但它的後果是：

> 即使 spec 與 evaluator 都打包完成，把產品複製到同事機器仍會因為
> **沒有 Ruby 3.4.10** 而跑不起來。

因此目前的「standalone」上限是「**不依賴 repo**」，而非「**不依賴機器前置**」。
這兩者的差別必須在本卡裁決，否則會出現「我們宣稱 standalone、同事裝到一半
卡住」的落差。

---

## 3. 為什麼這不能用「把路徑改成可設定」解決

把 `SPEC_PATH` 變成環境變數或設定項，只是把「去哪裡找 repo」變成使用者的
責任，closure 仍然不成立——而且會讓**契約來源變成可由使用者指定**，那比
現在更糟。本卡不考慮這個方向。

---

## 4. 需要回答的問題（Owner／reviewer）

1. **最小 closure 確認**：§2.1 的 9 個檔是否就是全部？（本卡已做遞移展開與
   檔案 I/O 掃描，請 reviewer 覆核方法，而非重做清單。）
2. **漂移如何機械保證**——這題的理由要寫明白：那 7 支 evaluator 是**與 repo
   的 39 支 validator 共用的同一份程式**。若產品凍結副本、repo 原件繼續演進，
   就會出現「產品與 validator 依不同規則判定同一件事」，那正是憲法禁止的
   **第二套治理**。因此 gate 必須**雙向**：repo 改了原件而沒重新產生 package，
   **CI 必須紅**；只驗「package 內副本有沒有被竄改」不足夠。
   要求 byte/digest 級比對，不接受人工同步。
3. **真正的 standalone acceptance 怎麼驗**：把產品複製到 repo 外（`/tmp` 或
   隔離 HOME），**讓原 repo 路徑不可用**（改名或移走），CLI／MCP／hook／
   doctor 四個入口仍須全部可用。不讓原路徑失效就測不出東西。
4. **upgrade / rollback 的版本一致**：程式、spec、evaluator 必須同屬一個
   artifact version，不得各自換代。**先確認能否沿用既有的版本 seam**
   （`omos/version_guard`、store `schema_version`、install receipt），
   不要為此新造第三套版本概念。
5. **（新增）失效時的行為**：packaged spec／evaluator 缺檔或損壞時，產品必須
   **fail closed 並回明確錯誤碼**，不得退化成「跑得起來但沒有治理」。這條
   目前沒有任何人指定過，是這條線一路紀律的延伸。

---

## 5. 兩個 packaging 方案

### 方案 A｜build 時納入 artifact（CC 建議）

```
repo 內原始 spec/evaluator   = source of truth
build/package 時機械複製進產品 artifact（byte 相同）
runtime 只讀自己 artifact 內的 versioned copy
```

- **優點**：runtime 沒有任何 repo 依賴；版本與程式綁在同一個 artifact；
  漂移可用 digest gate 機械擋住。
- **代價**：需要一個 build 步驟與對應的 CI gate（目前沒有）。

### 方案 B｜installer 執行時複製到使用者目錄

- **優點**：不需要 build 步驟。
- **致命問題**：那份副本會**躺在使用者家目錄、而且是可寫的**。整個產品的
  權威模型建立在「spec 是 source of truth」之上——一份**使用者可改的契約
  副本是授權漏洞**，不只是「不知道誰負責升級」的維運麻煩。
  另外它也沒有回答「升級時誰負責換掉那份副本、rollback 時換回哪一版」。

**CC 立場**：選 A。B 不是「比較不乾淨」，是**與產品的授權模型直接衝突**，
應予排除而非並列。

---

## 6. Minimum Sufficient

- **why_not_less**：少於「spec + 7 支 evaluator 隨 artifact 配送」就無法在
  repo 外建立 binding／執行治理判定——產品在 repo 外根本不存在。
- **why_not_more**：本卡**不**決定配送格式（gem／tarball／homebrew／pkg），
  **不**建 release pipeline，**不**處理跨平台（目前只需 macOS arm64），
  **不**重做已自足的 gem vendoring。Ruby runtime 是否配送屬 §2.3 的裁決，
  不自動擴張成「打包一個 Ruby」。
- **do_not_absorb**：不因為要打包就把 evaluator 複製成產品自有版本——那會
  變成第二套治理。產品端永遠是 repo 原件的機械副本。
