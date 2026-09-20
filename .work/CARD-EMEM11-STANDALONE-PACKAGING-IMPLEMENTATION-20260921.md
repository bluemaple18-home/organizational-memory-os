---
id: EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921
status: READY_SLICE_A_NOT_STARTED
type: implementation
tier: T2
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
research: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920（ACCEPTED_GO）
architecture: CARD-EMEM11-Q7-ACTIVATION-RUNTIME-PROFILE-20260921（DECIDED_FROZEN）
absorbs:
  - CARD-EMEM11-STALE-HOOK-RELOCATION-20260920 → Slice A
  - CARD-EMEM11-RUBY-GUARD-CRITERION-20260921 → Slice B
pinned_baseline: fa0959a
authority: organizational-memory-os
---

# EMEM-11｜Standalone Packaging Implementation

👉 [假設與目標確認]
- **目標**：把 Q7 已凍結的架構做成實物，讓 `product/personal-memory` 成為
  離開 repo 也能安裝與執行的 artifact。
- **邊界**：架構不重開（Q7 已凍結）、研究不重做（研究卡已 GO）。
  **不決定配送格式**（gem／tarball／brew 仍未定，且本卡不需要它）。
  不碰 doctor P2、不碰 EMEM-11b、不碰 clean-macOS Part 2 qualification。
- **驗收**：三片各自獨立通過定點 review。

---

## 0. 為什麼切三片，而且順序固定

reviewer 裁決（2026-09-21）：**不要把 stale-hook 與 Ruby guard 合成同一個
review diff。**

- 兩者**共享架構但失敗型態不同**：A 壞了是「Host 設定裡留下垃圾」，
  B 壞了是「在不該跑的 runtime 上放行或誤拒」。混在一起會分不出哪一層壞掉。
- **A 必須先於 B**：guard 要綁的 **artifact build identity 與 native
  dependency manifest 是 packaging 本身才會建立的東西**。先做 B 等於先發明
  一份臨時 identity，之後再改一次。

```
Slice A  activation substrate ＋ stale-hook
   ↓     （產生真實的 versions/<artifact-id> 結構）
Slice B  artifact identity ＋ runtime profile guard
   ↓     （guard 有真正的 identity 可綁）
Slice C  standalone packaging closure
```

## 1. 跨片共同約束（來自 Q7 §0.4，任何一片都不得違反）

1. **Host 設定裡永遠不得出現 versioned path。** 只能是固定 launcher path。
2. **installer 不得用 `__dir__` 推導出的路徑去組 Host command。**
   實測：同一次呼叫裡 shell 保留 `current`，Ruby 的 `__dir__` 卻解析成
   `versions/<id>`；而 `Installer#product_root` 預設正是由 `__dir__` 推導。
   沿用它 ＝ A 案靜默退化成 B 案。
3. **hook 的 argv authority 注入契約保留**：`--host` /
   `--runtime-scope-mode` 只能走 argv（兩個 Host 的 hook handler 都無 env
   欄位，repair-01 既有裁決）。固定 launcher 必須原樣轉傳。
4. **uninstall 不得刪除 launcher 的父目錄**：`~/.omos/personal-memory/bin/`
   與 Personal Store（`…/personal.db`）同一層，預設必須保留 store。
5. **`current` 切換必須原子**：`ln -s new tmp && mv -f tmp current`
   （`rename(2)`），不得用 `ln -sfn` 先刪後建。
6. 既有的 3a／3b／3c conformance **全數維持通過**，不得為了讓新結構過關而
   放寬既有斷言。

---

## Slice A｜Activation substrate ＋ stale-hook P1

承接 `CARD-EMEM11-STALE-HOOK-RELOCATION-20260920`。

### 範圍

- 建立固定 launcher：
  `~/.omos/personal-memory/bin/omos-personal-memory-mcp`、
  `…/bin/omos-personal-memory-session-start`
- 建立 `versions/<artifact-id>/` 與 `current -> versions/<artifact-id>`
- Host command 一律只寫 stable launcher path
- 修 relocation／upgrade／uninstall 的 zombie hook
- atomic `current` switch

### 驗收

1. **原缺陷重現案例歸零**：`install(A)` → 從 B `upgrade` → Host 內**只有
   一組**本產品 SessionStart 註冊且指向 stable launcher；再 `uninstall` →
   **零殘留**。（原始重現：A→B upgrade 後 2 組並存、uninstall 後殘留 A。）
2. **Host 設定內不得出現版本字樣**：安裝後機械檢查寫入的 `.claude.json` 與
   `.claude/settings.json`，**不得含 `versions/` 或任何 artifact-id**。
3. **舊版安裝的遷移（本卡新增，先前無人提出）**：目前**已經存在**以舊形狀
   安裝的環境——Host 設定直接指向 repo 內的 `exe/…`（例如真人驗收用的隔離
   HOME `/Users/matt/omos-acceptance-home`）。Slice A 必須能**把這種
   pre-launcher 安裝遷移成 launcher 形狀**，且不留下舊註冊。
   這不是假想情境：任何在本片之前裝過的人都是這個狀態。
4. **argv 注入未被破壞**：遷移後 hook 仍收到 `--host` 與
   `--runtime-scope-mode`，SessionStart 仍能落地可信 session 記錄。
5. **第三方 hook 不受影響**：沿用 repair-02 的 collision-adjacent 測試形狀
   （`…-session-start-foreign`）——install／uninstall／doctor 都不得誤認。
6. **atomic switch**：切版過程中不存在「`current` 不指向任何有效 artifact」
   的窗口；切換失敗時舊版本仍可用。
7. 3a／3b／3c 全數通過（3c 群組 A 預期需隨新結構調整，但**不得放寬斷言**）。

### 不做

不定義 build identity（Slice B）、不做 digest gate（Slice C）、
不改 `pinned-ruby.sh` 的判準（Slice B）。

---

## Slice B｜Artifact identity ＋ Runtime profile guard

承接 `CARD-EMEM11-RUBY-GUARD-CRITERION-20260921`，判準見 Q7 §0.3。

### 範圍

- 定義**最小 build identity**（能綁住 code ＋ 2 spec ＋ 7 evaluator ＋
  dependency layout；**不得**拿 store `schema_version` 冒充）
- 宣告 **production native dependencies** 清單（manifest）
- guard 改驗四項：選中的 Ruby executable／loader resolution／真實 load
  probe／qualified profile 比對
- 取代現行的 `RUBY_VERSION == "3.4.10"` 判準
- fail closed ＋ 精確錯誤原因

### 驗收

1. **版本相同但 linkage 不符 → guard 當場擋下**，不得放行到載入原生擴充才
   `LoadError`。（可用 `install_name_tool` 改寫一份複本的 libruby load
   command 來構造，已實證該手法會產生明確 LoadError。）
2. **ABI 相容但版本字串不同 → 不得誤拒**（對應現行 guard 過嚴的那一格）。
   ※ 本機無法完整驗證，需與 Part 2 clean-macOS qualification 合併收尾；
   本片至少要讓判準**不再以版本字串為唯一依據**。
3. **load probe 真的發生**：至少涵蓋 `bigdecimal` ＋ `sqlite3`，且 probe
   失敗時 guard 失敗。
4. **「能跑」與「已 qualified」分開**：未 qualified 但 probe 成功的組合必須是
   **明確可辨識的狀態**，不得靜默放行。
5. 錯誤訊息指出**實際缺的是什麼**（哪個 native dependency、哪一項 profile
   不符），不是只說版本不符。
6. 完全不相容的 Ruby（例如系統 2.6）維持現行行為：當場失敗、不靜默改用別的。

### 不做

不做 spec／evaluator 的打包與 digest gate（Slice C）、不做 clean-macOS
qualification 矩陣（Part 2）。

---

## Slice C｜Standalone packaging closure

### 範圍

- 把 2 份 spec ＋ 7 支 evaluator **機械納入** artifact（方案 A：build 時複製，
  byte 相同；**非** installer 執行時複製）
- **source ↔ packaged digest drift gate（雙向）**：repo 改了原件而未重新
  產生 package，**CI 必須紅**；只驗「package 內副本有沒有被竄改」不足夠
- receipt 綁 artifact identity（Slice B 定義的那一份）
- **workspace B**、無 source checkout 的完整 standalone acceptance
- upgrade／rollback／relocation E2E

### 驗收

1. **workspace B**：build 在 workspace A；artifact 送到**沒有 source
   checkout** 的 workspace B ＋ isolated HOME，B 內完全沒有 `scripts/lib`
   與 `規格/v0.1`；CLI／MCP／SessionStart／doctor ＋ 3a/3b/3c 全部可跑。
   **不得改名或移走已驗收的主工作區來製造隔離。**
2. **drift gate 雙向有效**：故意只改 repo 原件而不重新打包 → gate 必須紅；
   故意竄改 package 內副本 → 同樣必須紅。
3. **packaged spec／evaluator 缺檔或損壞 → fail closed 並回明確錯誤碼**，
   不得退化成「跑得起來但沒有治理」（研究卡 Q5）。
4. **upgrade／rollback／relocation E2E**：rollback 只切 pointer、**不重寫
   Host 設定**，且不得靠重新下載或猜 SHA。
5. 3a／3b／3c 在 workspace B 全數通過。

### 不做

不決定配送格式、不建 release pipeline、不做跨平台、不做 clean-macOS
Part 2 qualification（那在本卡之後）。

---

## 2. 與既有驗收證據的關係

真人驗收（`.work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md`，ACCEPTED_GO）
驗的是**舊形狀**的安裝。Slice A 改變安裝結構後：

- 該份證據**仍然有效**——它證明的是「hook 真的被真 Host 觸發、identity 可信」
  這條鏈，與 activation 形狀無關；
- 但 **Slice C 的 standalone acceptance 必須在新形狀下重跑一次等價驗證**，
  不能只引用舊證據。

## 3. Minimum Sufficient

- **why_not_less**：少一片都不行——A 不做則 Host 永遠綁版本路徑；B 不做則
  guard 繼續用錯誤判準放行／誤拒；C 不做則產品仍離不開 repo。
- **why_not_more**：不決定配送格式、不建 pipeline、不做跨平台、不做自動更新
  服務、不新造版本治理系統。
- **do_not_absorb**：不把 artifact 版本與 store `schema_version` 混談；
  不因為要做 packaging 就順手改 doctor（P2 另案）或 evaluator 本身。
