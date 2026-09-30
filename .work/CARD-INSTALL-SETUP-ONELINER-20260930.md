---
id: INSTALL-SETUP-ONELINER-20260930
jira: 尚無對應 ticket，需補開一張並回填此欄
status: DONE（2026-10-01，repair-01 後驗收 13／14 全項 PASS）
tier: T0
parent: INSTALL-FLOW-SIMPLIFY-20260930
---

# `setup`：把安裝收成一條指令

👉 [假設與目標確認]
- **目標**：使用者貼一段、只改自己的名字，就能跑完。指令從 6 行降到 2 行。
- **邊界**：只做**依序呼叫**，不合併交易、不新增身分形狀、不新增預設 tenant。
- **驗收**：見 §3。

## 1. Measured gap

`CARD-INSTALL-FLOW-SIMPLIFY-20260930` 把使用者動作降到 6 步，但交付時
Owner 指出真正的門檻不是步數，是**要貼幾個東西**：

> 「假設使用者什麼都不會。我要做到他貼整段、只要改自己的名字，就可以全部跑完。」

目前最後三行是三個獨立指令（`install`／`schedule remove`＋`schedule install`／
`doctor --report`），每一行都是使用者可能貼漏、貼錯順序的地方。

## 2. 改動

新增 `setup`，依序執行既有的三件事，**不改變任何一件的行為**：

```
omos-personal-memory setup --owner <urn> --tenant <id> [--no-schedule]
```

1. `install`（失敗即停，回非零）
2. `schedule remove` → `schedule install`（`--no-schedule` 可略過）
3. `doctor --report`

### 2.1 明確不做

- **不合併交易。** 排程失敗時 install 已經成功，必須照實分別回報並**繼續**跑
  doctor，不得把已完成的安裝一起回滾。launchd 生命週期已 freeze
  （CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922），
  `setup` 只是排序器，不是新的交易邊界。
- **不新增 `--tenant` 預設值。** 把某個租戶代號寫進產品碼等於把單一客戶
  烘進通用產品。
- **不接受簡寫的 owner。** `--owner wen` 自動展開成 URN 會變成第二種身分
  表達方式，與 `personal_memory_resource_contracts` 的 id_template 形成
  兩份來源。

## 3. Acceptance

1. `setup` 成功時，三段結果依序印出，且與分別執行三個指令的結果相同。
2. 未裝過排程時 `schedule remove` 回 `SCHEDULE_NOT_REMOVED（NOT_INSTALLED）`
   **不得**讓 `setup` 失敗。
3. `install` 失敗時 `setup` 立即停止並回非零，**不得**繼續跑排程或 doctor。
4. 排程失敗時 **install 的結果保留**、照實回報、仍繼續跑 doctor；
   反證：把它改成一起失敗會轉紅。
5. `--no-schedule` 時完全不碰 launchd。
6. `setup` 不得新增任何 `--tenant` 預設值或 owner 簡寫；反證：加上去會轉紅。
7. 既有保證不變：3a／3b／3c 全綠、40 支 validator 全綠。

## 4. Minimum Sufficient

- **why_not_less**：少一行就少一個貼漏的機會；Owner 明確要求「貼整段就跑完」。
- **why_not_more**：不動 install／schedule／doctor 任何一個的行為，
  `setup` 只是排序器。
- **do_not_absorb**：不吸收 Homebrew／Ruby 前置（需要密碼，非互動環境做不到）、
  不吸收 Codex hook trust（只能由使用者本人確認）。

---

## 5. 實作結果（2026-09-30）

### 5.1 交付形狀

```
rm -rf ~/OMOS-Personal-Memory
unzip -q ~/OMOS-Personal-Memory.zip -d ~
xattr -dr com.apple.quarantine ~/OMOS-Personal-Memory
~/OMOS-Personal-Memory/exe/omos-personal-memory setup --owner urn:omos:employee:你的英文名 --tenant t-clickforce
```

使用者要做的三件事：把 zip 放到家目錄、改名字那一格、整段貼。
**新裝與升級同一段**（`rm -rf` 對沒裝過的人是空操作；填同一個名字資料不動）。

### 5.2 逐條對驗收

| # | 驗收 | 結果 |
|---|---|---|
| 1 | 三段依序、結果與分別執行相同 | **PASS** |
| 2 | 未裝過排程的 `NOT_INSTALLED` 不得讓 setup 失敗 | **PASS** |
| 3 | install 失敗立即停止 | **PASS**。反證 S1b（吞掉失敗繼續跑）RED |
| 4 | 排程失敗時 install 結果保留、仍跑 doctor | **PASS**。反證 S2b（一起失敗）／S6（一起回滾）皆 RED |
| 5 | `--no-schedule` 不碰 launchd | **PASS**。反證 S3 RED |
| 6 | 不得新增 tenant 預設或 owner 簡寫 | **PASS**。反證 S5 RED |
| 7 | 既有保證不變 | **PASS**。3a 26/26、3b 46/46、3c 455/455、40/40 validators |

### 5.3 過程中補掉的一個真缺口

寫驗收 3 時發現 **`install` 根本沒驗 `--owner` 的形狀**：
`--owner wen`（忘了 URN 前綴）會被安靜收下，直到使用者第一次 `import`
才出現看似無關的錯誤——那時他已經不記得安裝時打了什麼。

對「整段貼、只改名字那一格」的交付方式來說，**打錯名字正是最可能發生的錯**，
所以這不是額外功能，是這張卡的前提。修法沿用既有的 `Inbox::OWNER_REF`／
`TENANT_ID`，不另寫一份規則。反證 S4（拿掉驗證）RED。

### 5.4 兩個假綠（已修）

S1／S2 第一輪是綠的：

- **S1**：`return code unless code.zero?` 其實是死碼——安裝失敗的主路徑是
  `Installer::Failed`，例外直接穿過 `cmd_setup`，由 `run` 的 rescue 接住。
  改用「吞掉例外繼續跑」當變異（S1b）才證明得出這條有被測到。原碼保留該行
  並加註解說明它守的是**不丟例外**的非零回傳。
- **S2**：**沒有任何測試覆蓋「排程失敗但安裝成功」**，也就是驗收 4 只寫在
  卡上、沒有落地。補了 (3b)：把 `Library/LaunchAgents` 做成一個**檔案**
  讓 plist 寫不進去，斷言 install 的 receipt 與身分仍在、doctor 仍然跑完。

### 5.5 最終驗證

```text
最終 ZIP  SHA-256  8593b8683bd7a5ad86aace2417bd332339051030730fa272172aebc5a3e8b4b9

3a 26/26  ·  3b 46/46  ·  3c 455/455  ·  40/40 validators  ·  diff --check clean
```

**驗收 13（升級路徑，改用 `setup` 走一次）七項全 PASS**：store 逐位元組不變、
身分保留、origin 保留、evidence 不變、匯入的還在、`artifact_id` 與乾淨安裝
一致（`01359c1511eb6e6d…`）、`~/.omos` 無 quarantine 殘留。

**驗收 14 三項全 PASS，彈窗 0 次**：`exit=78`、0 秒、`~/.omos` 未建立；
解除後 3 秒跑完；安裝出來 10 個 `.bundle` 帶隔離 0 個。

---

## 6. repair-01（2026-10-01）

外部 review 在 `a33e5fc` 上找到 P1×2、P2×2，**全部成立**，四點皆已收。

| # | 問題 | 修法 | 反證 |
|---|---|---|---|
| P1-1 | `cmd_schedule` 自己的 rescue 把 `Schedule::Failed` 轉成 `return 2`，`setup` 完全沒看回傳值 → 「提醒沒裝上」顯示成 exit 0 | `setup` 檢查回傳值，失敗時印 `SETUP_INCOMPLETE` 並回 **exit 3**；**不回滾安裝、仍跑完 doctor** | R1／R2b RED |
| P1-2 | 新增的 setup 測試用 fake HOME 跑完整流程，但 `domain` 永遠是 `gui/<uid>`，實際會動到真人 launchd | 見 §6.1 | R3b RED |
| P2-1 | `setup` 的 doctor 跑在重開與批准 Codex hook **之前**，而 INSTALL.md 又說「已經自動跑過了」→ 批准後沒有最終複驗 | `setup` 結尾明講這份是重開之前的，並印出要再跑的那一行；INSTALL.md 同步改 | R4b RED |
| P2-2 | 「只裝一個工具時 hosts 只列一個」**是假的**——`Contract.supported_hosts` 是固定契約，空白 home 實測仍列兩個、還會建 `~/.codex/config.toml` | 刪掉那句，改成說實話：不偵測、照契約兩邊都寫、沒用到的放著不動 | 事實已查證 |

### 6.0 P1-1 還有第二條路沒覆蓋

review 指的是「`cmd_schedule` 回 2」，但卡上原本的 (3b) 走的是另一條
（plist 寫不進去 → 丟例外）。**兩條都要有測試**，否則改掉其中一個判斷不會
轉紅。新增 (3c)：在 conformance 下不帶 `--no-schedule`，`remove` 先回
`NOT_INSTALLED`（不碰 launchctl），`install` 寫完 plist 去呼叫 launchctl 被
機器強制擋下 → `Schedule::Failed` → `cmd_schedule` 回 2。

### 6.1 P1-2：把規則變成機器強制

`schedule.rb` 的註解一直寫著「conformance 必須注入替身」，但那是靠人遵守。
現在：

- `test/support.rb` 頂端設 `ENV["OMOS_CONFORMANCE"] = "1"`（子行程繼承）。
- `Schedule.launchctl` 第一件事就是檢查它，有設就 raise
  `SCHEDULE_REAL_LAUNCHCTL_IN_CONFORMANCE`。
- setup 的子行程測試一律帶 `--no-schedule`。

兩層都不依賴人記得。

### 6.2 同一個根因第三次，改結構

三次都是「測試／變異透過 process 級狀態逃出沙箱」：

1. 變異把 `xattr -dr` 範圍改成 `File.expand_path("~")` 並實際執行 → 在 Owner
   家目錄遞迴清除，無法還原。
2. setup 測試用 fake HOME 但 `gui/<uid>` 是真的 → 留下 job，症狀是不同機器
   跑出不同分數（454 vs 455），外部 review 才抓到。
3. **為了反證 §6.1 那道 guard，把 guard 關掉再跑整套** → 又留下一個 job
   （`state = not running`，已 `bootout`，`~/Library/LaunchAgents` 無 plist）。

依「同一 blocker 第 3 次失敗即停」改結構，新增硬規則：

> **安全 guard 的反證一律用原始碼斷言，不得用執行。**
> 「把 guard 關掉再跑整套」本身就是一次真實副作用。

落地成一條測試：斷言 `Schedule.launchctl` 的 `OMOS_CONFORMANCE` 檢查必須在
`Open3.capture3` **之前**。把 guard 挪到後面就轉紅，而執行時仍受保護（R3b）。

### 6.3 最終驗證

```text
最終 ZIP  SHA-256  6df5fa8953945b387c81eeafccb67f2cf43c8821ec264b40ca07b01ae15ebc33

3a 26/26  ·  3b 46/46  ·  3c 461/461  ·  40/40 validators  ·  diff --check clean
真人 launchd 殘留 0
```

**驗收 13 七項全 PASS**：store 逐位元組不變、身分保留、origin 保留、
evidence 不變、匯入的還在、`artifact_id` 與乾淨安裝一致（`5d4f0607aa624d16…`）、
`~/.omos` 無 quarantine 殘留。

**驗收 14 三項全 PASS**：`exit=78`、0 秒、`~/.omos` 未建立；解除後 3 秒跑完；
安裝出來 10 個 `.bundle` 帶隔離 0 個。彈窗 0 次。

> 驗收 13／14 一律帶 `--no-schedule`：沙箱 home 的 plist 路徑雖然被 `--home`
> 導走，但 `bootstrap` 的 domain 是執行者真實的 session。排程路徑由
> conformance 以注入替身覆蓋，真 launchd 的驗收在 Slice B 驗收 8 已完成。
