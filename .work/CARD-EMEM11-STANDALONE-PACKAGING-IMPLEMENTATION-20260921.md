---
id: EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921
status: ALL_SLICES_ACCEPTED_GO
review_round_1: NO_GO（P1×1：A/B identity 邊界矛盾）→ 已修
review_round_2: GO（2026-09-21，P2×1 非阻擋，已納入 Slice A 驗收第 8 項）
slice_a: ACCEPTED_GO @ ce62092（repair-01 f9ba9e3、repair-02 943aec0、closeout ce62092）
slice_b: ACCEPTED_GO @ e3e35ff（交付 d99cdcd、repair-01 e3e35ff）
slice_c: ACCEPTED_GO @ d652bee（交付 46370a5、repair-01 d652bee）
slice_c_review_round_1: NO_GO（2026-09-21，P1×2：同內容重裝 GC 掉可回退版本／rollback receipt 寫失敗留下 pointer-receipt 分裂）→ repair-01 已修
slice_c_review_round_2: GO（2026-09-21，P0/P1/P2/P3 皆 0；.work/handoff/EMEM11-SLICE-C-REPAIR-01-REREVIEW-20260921.md）
type: implementation
tier: T2
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
research: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920（ACCEPTED_GO）
architecture: CARD-EMEM11-Q7-ACTIVATION-RUNTIME-PROFILE-20260921（DECIDED_FROZEN）
absorbs:
  - CARD-EMEM11-STALE-HOOK-RELOCATION-20260920 → Slice A
  - CARD-EMEM11-RUBY-GUARD-CRITERION-20260921 → Slice B（僅 guard；identity 在 A）
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
- **A 必須先於 B，且 identity 的 ownership 在 A**：guard 要綁的 **artifact
  build identity 與 native dependency manifest 是 packaging 本身才會建立的
  東西**。第一版把 identity 放在 B，但 A 已經要產生 `versions/<artifact-id>`
  ——那等於逼 A 先發明臨時 ID、B 再改一次，正是切片要避免的 provisional
  identity（reviewer P1，已修）。

```
Slice A  activation substrate ＋ stale-hook ＋ **artifact identity**
   ↓     （產生真實的 versions/<artifact-id> 與 identity/manifest）
Slice B  runtime profile guard（消費 A 的 identity，不再定義）
   ↓
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

- **定義最小 artifact／build identity**（見下方「identity ownership」）
- **宣告 production native dependency manifest**
- **materialize 2 份 spec ＋ 7 支 evaluator 進 artifact**（ownership 由 C 前移，
  見下方「為什麼 9 檔 materialize 在 A」）
- **`contract.rb` 改讀 artifact-local 路徑**，artifact 搬離 repo 後仍能啟動
- 建立固定 launcher：
  `~/.omos/personal-memory/bin/omos-personal-memory-mcp`、
  `…/bin/omos-personal-memory-session-start`
- 建立 `versions/<artifact-id>/` 與 `current -> versions/<artifact-id>`
- Host command 一律只寫 stable launcher path
- 修 relocation／upgrade／uninstall 的 zombie hook
- atomic `current` switch

### identity ownership（reviewer P1 修正，2026-09-21）

**identity 由 Slice A 定義並產生；Slice B 只消費，不得再定義第二份。**

原本把 identity 放在 B 是矛盾的：A 已經要產生 `versions/<artifact-id>`，
卻不准定義 identity——那 A 只能先發明一個臨時 ID，B 再改一次，正是這次切片
本來要避免的 provisional identity。

**設計約束（避免同類問題在 C 重演）**：Slice C 才會把 2 份 spec ＋ 7 支
evaluator 機械納入 artifact，因此 **A 當下的 artifact 並不包含那 9 個檔**。
identity 的算法必須是對「**artifact 實際承載的內容**」取 digest，使得 C 把
9 個檔 materialize 進來時 **identity 自然涵蓋它們、無須更動算法**。
**不得**定義成「固定列舉這幾類檔案」——那會逼 C 再改一次定義，重蹈本次
P1 的覆轍。

### 為什麼 9 檔 materialize 在 A（reviewer 裁決，2026-09-21）

實測：把 artifact 複製到 repo 外後，立刻在 `contract.rb:25` 掛掉——
`cannot load such file -- <relocated>/scripts/lib/omos_contract_helpers`，
因為 `REPO_ROOT` 由 `__dir__` 上溯四層推導。

**A 既然要建立真正的 `versions/<artifact-id>`，那 artifact 當下就必須是可執行
的完整單位**，不能等 C 才補那 9 個檔。否則只剩兩條路，且都會產生之後要拆掉
的暫時結構：在 artifact 裡記「repo 在哪」的橋接檔（接近研究卡已否決的
「契約來源可被指定」），或讓 `versions/<id>` 只放假門面（identity-over-content
就沒有東西可雜湊）。

**因此**：9 檔 materialize、`contract.rb` 改讀 artifact-local 路徑、複製必須
**byte-identical 且 deterministic** —— 全部屬 Slice A。
**Slice C 改為驗證與防漂移**（雙向 digest gate、workspace B 驗收、
packaged 缺檔／損壞 fail-closed、receipt 最終綁定、upgrade/rollback/relocation
E2E）。

### 驗收

0. **artifact 搬離 repo 後可正常啟動**，不再依賴 `REPO_ROOT`。
1. **原缺陷重現案例歸零**：`install(A)` → 從 B `upgrade` → Host 內**只有
   一組**本產品 SessionStart 註冊且指向 stable launcher；再 `uninstall` →
   **零殘留**。（原始重現：A→B upgrade 後 2 組並存、uninstall 後殘留 A。）
2. **Host 設定內不得出現版本字樣**：安裝後機械檢查寫入的 `.claude.json` 與
   `.claude/settings.json`，**不得含 `versions/` 或任何 artifact-id**。
3. **舊版安裝的遷移**：目前**已經存在**以舊形狀安裝的環境——Host 設定直接
   指向 repo 內的 `exe/…`（例如真人驗收用的隔離 HOME
   `/Users/matt/omos-acceptance-home`）。Slice A 必須能**把這種 pre-launcher
   安裝遷移成 launcher 形狀**，且不留下舊註冊。
   這不是假想情境：任何在本片之前裝過的人都是這個狀態。

   **遷移的辨識 authority（reviewer 補充，硬性）**：舊 hook 的辨識**必須由
   既有 receipt 或精確的 legacy command evidence 驅動**——
   **不得**用模糊前綴比對，**不得**「掃到像 OMOS 的就刪」。
   receipt 缺失或損壞時必須 **fail loud 或要求人工處理，不得用猜的**。
   （repair-02 的 collision-adjacent 測試已鎖住「不誤刪第三方」；這一條進一步
   鎖住「不靠猜測決定什麼是自己的」。）
4. **argv 注入未被破壞**：遷移後 hook 仍收到 `--host` 與
   `--runtime-scope-mode`，SessionStart 仍能落地可信 session 記錄。
5. **第三方 hook 不受影響**：沿用 repair-02 的 collision-adjacent 測試形狀
   （`…-session-start-foreign`）——install／uninstall／doctor 都不得誤認。
6. **atomic switch**：切版過程中不存在「`current` 不指向任何有效 artifact」
   的窗口；切換失敗時舊版本仍可用。
7. 3a／3b／3c 全數通過（3c 群組 A 預期需隨新結構調整，但**不得放寬斷言**）。
8. **identity 的 deterministic semantics 必須鎖在測試裡**（reviewer P2，
   非阻擋但本片收）：
   - 同一組「相對路徑 ＋ bytes」→ **同一個 ID**
   - 任一實際 payload 改變 → **ID 改變**
   - 安裝位置、`current` symlink、mtime、receipt 等 **activation metadata
     不得影響 ID**
   - 流程採 **stage → hash → rename to `versions/<artifact-id>`**，
     避免 identity 自我引用

### 不做

不做 guard 的判定邏輯（Slice B 消費本片產生的 identity）、不改
`pinned-ruby.sh` 的判準（Slice B）、不做 spec／evaluator 的 materialize 與
digest gate（Slice C）。

---

## Slice B｜Runtime profile guard（消費 A 的 identity）

承接 `CARD-EMEM11-RUBY-GUARD-CRITERION-20260921`，判準見 Q7 §0.3。

### 範圍

- **消費 Slice A 產生的 artifact identity 與 native dependency manifest**
  （**不得重新定義第二份**；identity 的 ownership 在 A）
- guard 改驗四項：選中的 Ruby executable／loader resolution／真實 load
  probe／qualified profile 比對
- 取代現行的 `RUBY_VERSION == "3.4.10"` 判準
- fail closed ＋ 精確錯誤原因

### 驗收

0. **manifest 的 `require` 欄位必須被真正使用**（reviewer P2，Slice A 收片時
   發現並轉入本片）：每個 manifest entry 的 `require` 必須在**隔離的
   production process** 中真實 require 成功，並解析到該 entry 宣告的 native
   extension。
   **拼錯的 require 不得被其他「實際已載入」的證據掩蓋**——reviewer 做過
   mutation proof：把 `bigdecimal` 的 `require` 改成不存在的名稱，Slice A 既有
   的 extension-name 斷言仍會通過。本片必須讓該 mutation 轉紅。
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

- **驗證** Slice A 產出的 materialize 結果（9 檔 byte-identical）
- **source ↔ packaged digest drift gate（雙向）**：repo 改了原件而未重新
  產生 package，**CI 必須紅**；只驗「package 內副本有沒有被竄改」不足夠
- receipt 綁 artifact identity（**Slice A** 定義的那一份）
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
Part 2 qualification（`CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921`，
`BLOCKED_ENVIRONMENT`）。

### repair-01（2026-09-21）

review round 1 判 **NO_GO**，2×P1，兩筆都已各自重播確認成立：

| # | 缺陷 | 根因 | 修法 |
|---|---|---|---|
| P1-1 | 同內容重裝把真正能回退的那一版 GC 掉，隨後 rollback 撞 `ROLLBACK_ARTIFACT_MISSING` | GC 保留集另外推導一份狀態（上一次安裝時的 current），同內容重裝時塌成一個元素 | 新增 `rollback_reachable_ids`，保留集只讀剛寫好的 receipt 的 current ＋ previous |
| P1-2 | rollback 在 receipt 寫失敗時留下 `current=A` 但 receipt 說 `current=B` 的分裂 | 先 activate 再寫 receipt，中間失敗沒有復原 | `#rollback` 成為交易：先存 pointer 與 receipt 位元組，失敗一起復原，不碰 Host 設定；receipt 一律 temp + rename |

驗證：3a 26/26、3b 34/34、3c 134/134（新增 10 項）、validator 40/40；
兩筆各做單點反轉的鑑別力反證（分別轉紅 3 項與 2 項，還原後全綠）；
workspace B 重跑（3c 132/132 ＋ 3 N/A，四個交付面全可用）。
證據包：`.work/handoff/EMEM11-SLICE-C-REPAIR-01-EVIDENCE-20260921.md`。

**裁定結果**：`Installer#rollback(fail_before_receipt:)` **接受保留**
（review round 2）。它與既有 `install(fail_after:)` 是同級 deterministic
failure seam；為了這一個 failure path 再抽一層 writer injection 反而增加
不必要結構。用途明確、預設不啟用。

### review round 2（2026-09-21）：GO

P0/P1/P2/P3 皆 0，兩筆 P1 **CLOSED**。reviewer 獨立重播 `A → B → B`
與注入失敗路徑，並**未沿用交付方的反轉點**另做一次鑑別力反證
（`rollback_reachable_ids` 只回 current），確認保護不是假綠；
`receipt chmod 0444` 的舊 exploit 在 temp + rename 之後也不再造成 split。
確認狀態來源未重新分裂：rollback 與 GC 都只認 receipt、upgrade 走
install、uninstall 移除 activation ＋ receipt。
verdict：`.work/handoff/EMEM11-SLICE-C-REPAIR-01-REREVIEW-20260921.md`。

**Slice A／B／C 至此全部 ACCEPTED_GO，本卡三片交付完成。**
卡上「不做」的範圍不變：配送格式、release pipeline、跨平台、
clean-macOS Part 2 qualification 仍在本卡之外。

收片時一併處理的卡面（2026-09-21）：

- `CARD-EMEM11-STALE-HOOK-RELOCATION-20260920` → `ABSORBED_ACCEPTED_GO`
  （Slice A @ ce62092）
- `CARD-EMEM11-RUBY-GUARD-CRITERION-20260921` → `ABSORBED_ACCEPTED_GO`
  （Slice B @ e3e35ff）
- Slice B 驗收第 2 項的不可驗半段（ABI 相容但版本字串不同 → 不得誤拒）
  另開 `CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921`，狀態
  `BLOCKED_ENVIRONMENT`。**條文未改寫**——可驗的半段留在 Slice B 且已收，
  不可驗的半段整條搬走並標阻塞。

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
