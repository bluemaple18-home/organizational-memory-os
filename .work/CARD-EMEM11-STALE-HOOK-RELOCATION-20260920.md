---
id: EMEM11-STALE-HOOK-RELOCATION-20260920
status: CONFIRMED_DEFECT_NOT_SCHEDULED
severity: P1
type: product-defect
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
discovered_via: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920
# 本卡是 packaging **實作**的前置，不是那張 research card 的前置——research
# 完成後才發現並建立本卡。implementation card 尚未建立；建立後在此指向它。
prerequisite_for: PENDING_PACKAGING_IMPLEMENTATION_CARD
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

## 修法方向（待裁，不要直接動手）

兩條路，對應 packaging 研究卡的 Q7：

- **A｜stable launcher**：Host 永遠指向固定路徑的 launcher，artifact 換版
  只換 launcher 背後的目標。Host 設定不隨版本變動。
- **B｜versioned path ＋ receipt 驅動遷移**：保留 versioned 路徑，但 upgrade
  必須讀前一份 receipt 取得舊 command，先遷移／清除舊註冊再寫新的。

兩者都需要決定「uninstall 要清到什麼程度」——只清自己這版，還是清掉所有
歷史版本留下的本產品註冊。

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
