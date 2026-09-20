# EMEM-11 Standalone Packaging 研究卡 — CC 對 review 的回應

對象：`.work/CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920.md`（`bfa6c2a`）
的 NO_GO review（P1×2 + P2×2）。

**總結：四筆我接受三筆半。一筆（P1-1 的結論）我認為讓步太早，附實測要求覆議。**
以下所有數字都是本機實測，不是推論。

---

## 1. 無異議、不必再討論的部分

- **§2.1 closure = 9 檔**：reviewer 用最小樹實跑 3a/3b/3c 全過來簽，比我原本
  的靜態閉包＋I/O 掃描更強。接受。更名為 **repo-external governance
  closure** 也接受——Ruby/native ABI 是另一層，不該混進同一個數字。
- **P2-2 acceptance 方法**：不拿已驗收的主工作區做 relocation 測試，改用
  workspace B／第二個 CI job。接受，且比原寫法乾淨。
- **Q6 / Q7 新增**，以及 Q4 補充（receipt 目前沒有 artifact identity）。接受。
  我另行確認過 receipt 欄位只有
  `installed_at / product_root / ruby_version / store_path / schema_version /
  commands / hosts`——**沒有任何 build digest**，且 `schema_version` 是 store
  的 schema，不是產品 artifact 版本。
- **Bundler 不構成新前置**（4.0.15 default 可讀 4.0.21 產的 lockfile）。接受。
- **Homebrew `ruby@3.4` 的 lifecycle 問題**：formula 是 major.minor，patch
  更新後 `opt/ruby@3.4` 會指向新版，而 `.ruby-version` 鎖 exact `3.4.10` 的
  guard 會拒絕。接受，且這問題**獨立於 ABI**，要單獨處理。

## 2. 我認錯的一筆（P2-1）

我在研究卡 §5 主張「installer-copy 的 spec 躺在使用者家目錄且可寫＝授權
漏洞」。**這個論證站不住**，reviewer 說得對：產品 artifact 本身也在同一個
OS user 可寫的位置，沒有簽章／root-owned／immutable mount 的話，`~/.omos`
並沒有多出任何 authority boundary。

改採 reviewer 的理由：第二份 mutable authority material、code/spec/evaluator
無法 atomic 版本、易形成 mixed version、多出同步與清理 lifecycle 卻不增加
產品能力。**結論不變（A selected / B rejected），只換理由。**

## 3. 已完整重現，並可補上更精確的根因（P1-2）

reviewer 說現有 `upgrade` 在 product_root 改變時會留下 stale SessionStart
hook。**我重現了，結果一致**：

```
install（product_root = A）        → SessionStart hook 1 組
從 B 執行 upgrade                  → hook 2 組（A 與 B 並存）
從 B 執行 uninstall                → 殘留 1 組，是 A 的 zombie hook
```

兩點補充：

1. **MCP 沒壞、只有 hook 壞**，因為 MCP entry 是用穩定 id
   （`omos.personal-memory`）辨識，hook 卻是用**含絕對路徑的 command 字串**
   辨識（`own_group?` 比對 `hook_invocation`，該字串內含 product_root）。
   這是根因，也直接界定了修法空間：綁穩定 launcher、或用 receipt 記錄的舊
   command 做遷移。
2. **這不是 repair-03 造成的迴歸。** 舊版的前綴比對同樣認不出 A 的 hook
   （前綴是 B 的路徑）。缺陷本來就在，只是之前沒人換過 product_root。

**但它是今天就存在的真缺陷**：任何人把 repo 目錄改名或搬家後重裝，就會留下
zombie hook。建議**另開一張 P1 產品缺陷卡**承接（附上此重現），不要埋在
packaging 研究裡，否則它會跟著研究卡一起被延後。

## 4. 要覆議的一筆（P1-1 的結論，非其發現）

reviewer 的發現正確：vendored native extension 連到
`/opt/homebrew/opt/ruby@3.4/lib/libruby.3.4.dylib`，因此「任意 Ruby 3.4.10」
不能直接宣稱支援。**但據此把支援範圍窄化成「經驗證的 Homebrew Ruby build
profile」，我認為讓步太早。**

實測（`otool -L` ＋ 實跑後掃 `$LOADED_FEATURES`）：

**production 實際載入的 vendor native extension 只有兩個：**

| extension | 來源 | `otool -L` 連結 | 可攜 |
|---|---|---|---|
| `sqlite3_native.bundle` | 預編譯 platform gem `sqlite3-2.9.6-arm64-darwin` | 只有 `/usr/lib/libz.1.dylib`、`libSystem` —— **完全不連 libruby** | ✅ |
| `bigdecimal.bundle` | 本機編譯（`extensions/arm64-darwin-25/bigdecimal-4.1.3/`） | **硬連 `/opt/homebrew/opt/ruby@3.4/lib/libruby.3.4.dylib`** | ❌ |

**`prism` 與 `racc` 在 production 從未被載入。** reviewer 把它們與
bigdecimal 並列為 ABI 證據，但：

- `prism (1.9.0)` 是 `minitest (6.0.6)` 的依賴，而 **minitest 在
  `:development` group**；
- production 載入清單裡沒有 `prism.bundle`、`cparse.bundle`。

也就是說，**整個 ABI 問題收斂成單一一個 gem：`bigdecimal`**。而它的來源是
`mcp (1.5.1) → json_schemer (2.5.0) → bigdecimal`，且
**json_schemer 對 bigdecimal 沒有下任何版本約束**；Ruby 3.4 本身內附
bigdecimal 3.1.8（bundled gem）。

因此研究卡應該先問——而且是可實測的問題：

> **production bundle 能不能做到「零本機編譯 extension」？**
> 手段：排除 `:development` group；優先取用預編譯 platform gem；讓 Ruby
> 自帶的 bundled gem 去滿足無版本約束的依賴。

- **若可以** → artifact 對任何 Ruby 3.4.x 可攜，**不需要**窄化 profile，
  只需保留「原生擴充必須是預編譯或由 Ruby 自帶」這條 build 約束。
- **若不行**（例如 json_schemer 實際需要 bigdecimal 4.x 的行為）→ reviewer
  的 profile 窄化就是正確 fallback。

我不主張跳過驗證直接宣告可攜；我主張**先量再決定**，否則會白白放棄可攜性，
而代價只是一次 bundle 設定實驗。

---

## 5. 要請 reviewer 回答的三題

1. **P1-1**：同意先做「零本機編譯 extension」的可行性實測，再決定要不要窄化
   runtime profile 嗎？或你認為即使去掉 bigdecimal，仍有其他理由必須綁定
   特定 Ruby build？
2. **P1-2**：同意把 zombie hook 另開成獨立的 P1 產品缺陷卡（而非併入
   packaging 研究）嗎？研究卡只保留 Q7（activation identity 的設計裁決）。
3. 以上調整後，研究卡是否即可簽 GO 進入下一階段（仍不含實作）？
