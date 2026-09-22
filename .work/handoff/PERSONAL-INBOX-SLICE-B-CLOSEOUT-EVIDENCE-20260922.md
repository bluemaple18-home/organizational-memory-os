---
id: PERSONAL-INBOX-SLICE-B-CLOSEOUT-EVIDENCE-20260922
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
type: closeout-evidence
status: READY_FOR_REVIEW
range: bf33090..602b679（29 commits：28 個交付 ＋ 1 個本收片證據包）
---

# Slice B 收片證據包｜Weekly Review Queue ＋ Friday Trigger

## 0. 被驗收的實物

驗收 13／14 驗的是**外部 ZIP 實物**，不是 repo 內容。因此釘住 digest，
避免日後重打 ZIP 之後沿用舊的 PASS：

```text
OMOS-Personal-Memory.zip
SHA-256  a1568da4aad5a81579c8cc86dd208dd44b67f244bee05da957699f10c2912e1b
```

**ZIP 一旦重打，驗收 13／14 必須重跑。**

### 已知的文件小瑕疵，**刻意留到下次重打包**

交付包 `INSTALL.md` 第 2 節寫「裡面有 11 個資料庫用的原生模組」，實際是
**10 個**。改這一行會讓 ZIP digest 變掉，依上面那條規則就得連 13／14 一起
重跑——而驗收 14 每跑一次都會在執行者畫面連續彈出系統對話框。

為了一個不影響功能的數字去換一輪彈窗不划算，因此**留到下次因產品變更重打包
時一併修**（那時 13／14 本來就要重跑）。repo 內的證據與卡片已全部更正為 10。

本包是 **closeout review** 用：B1／B2 的行為已於先前 targeted review 走過，
這裡收斂全段結果與**只有真實環境測得出來的三項證據**。

## 1. 驗收逐項

| # | 項目 | 結果 |
|---|---|---|
| 7 | `review due` 對同一 period 穩定；只由既有事實建 projection；無 queue DB | **PASS** |
| 8 | Friday trigger 可由 launchd **實際觸發** | **PASS**（真機重跑，見 §3） |
| 9 | install 重跑不產第二份；remove 只移除自己的 job | **PASS** |
| 10 | trigger 前後不增加任何 acceptance／Record／Promotion／terminal closeout | **PASS** |
| 11 | 0 due item 明確回 0，不造假 closeout | **PASS** |
| 12 | 既有安裝 upgrade 後 store／Host config 保留並取得新 surface | **PASS** |
| 13 | 實際交付路徑（zip 覆蓋解壓）的 upgrade | **PASS**（含指定正確步驟，見 §4） |
| 14 | 帶 quarantine 的交付路徑 | **PASS**（見 §5） |
| 15 | 3a／3b／3c 全綠；validators 全綠；`git diff --check` clean | **PASS** |
| 16 | 每項附鑑別力反證 | **PASS** |

## 2. 全段行數

| 檔案 | +/- |
|---|---|
| `lib/omos/review_queue.rb`（新） | +144 |
| `lib/omos/schedule.rb`（新） | +611 |
| `lib/omos/cli.rb` | +89 |
| `test/conformance_3c.rb` | +1219 |
| `test/support.rb` | +11 |
| 產品合計 | **+2074** |

產品碼 844 行中：**程式 474、註解 277、空白 93**。

註解比例偏高是刻意的：`schedule.rb` 裡每一個順序與象限旁邊都寫了「為什麼
不能改回去」。這份東西前後被 reviewer 退回 **7 次**，其中 4 次是同一個根因
換位置出現；把理由寫在程式旁是防止第 8 次的唯一手段。

## 3. 驗收 8：真 launchd（**只有真機測得出來**）

首次實跑 **FAIL**：`schedule remove` 回 `SCHEDULE_BOOTOUT_FAILED`——
`launchctl bootout` 回 `exit=0` 但瞬時複查仍 loaded。根因是 post-condition
是 **eventual 不是瞬時**。

這一格 **353 項 conformance 全綠時仍然會壞**，因為注入的替身是同步的。
它直接推翻了已簽署的 freeze 第一版（瞬時模型），導致：

```text
Hard Stop → freeze 第二版（bounded convergence ＋ 觀測三態）
  → Owner 重新簽署 → 實作 → repair-01 → GO
```

重跑六步全過：`SCHEDULE_INSTALLED` → `PRESENT` → status 正確 →
`SCHEDULE_REMOVED` → `ABSENT` → plist 已移除。

## 4. 驗收 13：指定了正確的升級步驟

覆蓋解壓**不會**刪掉新版已無的舊檔，而殘留檔會改變 artifact identity：

| 情況 | artifact_id |
|---|---|
| 有殘留檔 | `fabb0b30…` |
| 先刪資料夾再解壓 | `44d977dc…`（與乾淨安裝一致） |

因此 `INSTALL.md` 指定「**先移除舊資料夾再解壓**」。已在模擬同事情境
（舊版已裝＋有資料）實跑升級：store 逐位元組不變、身分保留、新 surface 可用、
`doctor` 0 FAIL。

另記：`cp -R` 覆蓋會在 vendor 的唯讀 gem 檔上大量 `Permission denied`，
`unzip -o` 不會。

## 5. 驗收 14：交付方先前判斷錯誤，已更正

先前寫「人工 `xattr` 的 quarantine 不會觸發 Gatekeeper」——**錯的**。
當時是在同一目錄已成功 install 之後才補 xattr，量到的不是乾淨的首次載入。

重跑穩定重現 **4/4 被擋**（`library load disallowed by system policy`），
三子項全數達成，**不需外送 ZIP**。

此項**不進 conformance**：它會在執行測試者畫面跳系統對話框，其中一個按鈕是
「丟到垃圾桶」，按下去會破壞 artifact。維持為有紀錄的手動驗收。

## 6. 回歸

| 項目 | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | **353/353 PASS** |
| 3c（`TZ=Europe/Berlin`） | 353/353 PASS |
| validators | 40/40 |
| `git diff --check` | clean |
| 真實 launchd 殘留 | ABSENT |

## 7. 交付方主動揭露

1. **驗收 14 的「不進 conformance」是取捨**。它是本片唯一不在自動化套件內的
   驗收。若 reviewer 認為必須自動化，請指定如何在不彈窗的前提下驗證。
2. **驗收 8 需要新的 Owner 授權才能重跑**（契約規定），因此無法由 reviewer
   自行重播；本包附的是執行紀錄。
3. **本片被退回 7 次**，其中 repair-01～04 是同一根因，觸發 Hard Stop 並改開
   spec-freeze。這個過程本身記在
   `CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922` §0。

## 8. 不在本片

Acceptance #8 之外的真 Host 觸發（doctor 的 2 個 WARN 維持原狀）、
簽章／notarization、release pipeline、非 macOS。
