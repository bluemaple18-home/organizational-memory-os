---
id: INSTALL-SETUP-ONELINER-20260930
jira: 尚無對應 ticket，需補開一張並回填此欄
status: DONE（2026-09-30，驗收 13／14 全項 PASS）
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
