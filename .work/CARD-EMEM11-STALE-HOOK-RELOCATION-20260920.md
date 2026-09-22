---
id: EMEM11-STALE-HOOK-RELOCATION-20260920
status: ABSORBED_ACCEPTED_GO
closed_by: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921 Slice A（ACCEPTED_GO @ ce62092）
closed_at: 2026-09-21
unblocked_by: CARD-EMEM11-Q7-ACTIVATION-RUNTIME-PROFILE-20260921（2026-09-21 凍結）
target_shape: Q7 §0.1（固定 launcher path → current → versions/<artifact-id>）
severity: P1
type: product-defect
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
discovered_via: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920
prerequisite_for: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921
absorbed_as: Slice A
found_in: fa0959a
authority: organizational-memory-os
---

# P1｜product_root 改變後，upgrade／uninstall 留下 stale SessionStart 註冊

> **今天就存在的 correctness bug**，不是 packaging 的假想問題。任何人把產品
> 目錄改名或搬家後重裝，就會在 Host 設定裡留下一個指向舊路徑、永遠不會被
> 清掉的 SessionStart hook。
>
> **這張卡是 standalone packaging 實作的前置**——一旦改用 versioned artifact
> path，每次升版都會製造一個 zombie hook。

## 重現（雙方獨立各做一次，結果一致）

以兩個不同的 `product_root`（A、B）對同一個 HOME 操作：

```
install（product_root = A）   → SessionStart hook 1 組
從 B 執行 upgrade             → hook 2 組（A 與 B 並存）
從 B 執行 uninstall           → 殘留 1 組 —— A 的 zombie hook
```

## 根因（精確）

**MCP 沒壞，只有 hook 壞**，因為兩者的識別方式不同：

| 註冊 | 識別依據 | 換路徑後 |
|---|---|---|
| MCP entry | 穩定 id `omos.personal-memory` | 正確被取代 |
| SessionStart hook | **含絕對路徑的 command 字串**（`own_group?` 比對 `hook_invocation`，其中內嵌 `product_root`） | 認不出舊的 → 併存；uninstall 也只刪自己那條 |

`upgrade` 目前就是 `install`（`installer.rb`），該定義只在 **product_root
完全不變**時成立。

**不是 repair-03 的迴歸**：舊版用前綴比對（`start_with?(@hook_command)`），
從 B 執行時前綴是 B 的路徑，同樣認不出 A 的 hook。缺陷本來就在，只是先前
沒有人換過 product_root。

## 修法方向（**已裁決**，Q7 於 2026-09-21 凍結）

採 **A｜固定 launcher**。Host 永遠只認一條固定路徑，artifact 換版只切
launcher 背後的 pointer，Host 設定不隨版本變動：

```
Host config → ~/.omos/personal-memory/bin/omos-personal-memory-session-start
            → current -> versions/<artifact-id> → 真正的 artifact
```

（B｜versioned path ＋ receipt 遷移已被否決：它把 Host 設定的正確性綁在
「每次遷移都成功且 receipt never lost」這個前提上。）

**實作時的硬性約束**（來自 Q7 §0.4，不遵守的話缺陷會原封不動回來）：

1. **installer 不得用 `__dir__` 推導出的路徑去組 Host command。**
   實測：同一次呼叫裡 shell 保留 `current`，但 Ruby 的 `__dir__` 會解析
   symlink 得到 `versions/<id>`；而 `Installer#product_root` 的預設值正是
   由 `__dir__` 推導。沿用它就等於 Host 又被寫進版本路徑。
2. **argv authority 注入契約保留**：hook handler 在兩個 Host 的官方 schema
   都沒有 env 欄位，`--host` / `--runtime-scope-mode` 只能走 argv
   （repair-01 既有裁決）。固定 launcher 必須原樣轉傳。
3. **uninstall 不得刪掉 launcher 的父目錄**：`~/.omos/personal-memory/bin/`
   與 Personal Store（`…/personal.db`）同一個父目錄，預設必須保留 store。
4. 仍須決定 uninstall 清理的深度——只清本版，還是連歷史版本留下的本產品
   註冊一併清掉（Q7 裁決點 7 指定「歷史版本清理策略另外明確定義」）。

## 驗收（啟動後才適用）

1. `install(A)` → `upgrade(B)` 後，Host 內**只有一組**本產品的 SessionStart
   註冊，且指向 B。
2. 承上再 `uninstall` → **零殘留**，且非本產品的第三方 hook 完全不受影響
   （沿用 repair-02 的 collision-adjacent 測試形狀）。
3. `install(A)` → 直接從 B `uninstall`（未經 upgrade）→ 亦不得留下 A 的註冊。
4. 既有的 conformance 3c 群組 A 全數維持通過。

## 不在本卡範圍

- 不決定 packaging 格式，也不實作 build pipeline（見研究卡）。
- 不處理 `~/.omos/personal-memory/sessions/` 的殘留清理（那是另一個已登記的
  缺口，見 `.work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md` §G-2）。
