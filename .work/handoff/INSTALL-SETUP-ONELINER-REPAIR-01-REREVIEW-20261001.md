# setup 一條指令 repair-01 — 定點 re-review 交付包

## 鎖定

```
base              ffa0bcf   安裝流程化簡（已收，immutable）
original_review   a33e5fc   setup 第 1 版（NO_GO，P1×2 P2×2，immutable）
repair_01         2c3fa05   本次修復
branch            main（尚未 push，依 reviewer 指示 hold）
```

定點 diff：`git diff a33e5fc..2c3fa05`

## 這一輪只審那四點

你上一輪確認沒被打壞的三件（schedule 沒併入 install transaction、
Codex trust 沒被 installer 自動批准、quarantine 邊界）本輪沒有改動。

### P1-1 setup 把排程失敗吃成 exit 0

`setup` 現在檢查 `cmd_schedule` 的回傳值；失敗時印 `SETUP_INCOMPLETE`
並回 **exit 3**。**不回滾安裝、仍跑完 doctor** —— 邊界不變。

**補測試時發現你指的那條路原本也沒被測到。**
卡上原有的案例走的是「plist 寫不進去 → 丟例外」那條，而你指的是
「`cmd_schedule` 自己的 rescue 轉成 `return 2`」。兩條分別由不同的判斷守，
只測一條的話改掉另一個不會轉紅。新增 (3c) 覆蓋後者：conformance 下不帶
`--no-schedule`，`remove` 先回 `NOT_INSTALLED`（不碰 launchctl），
`install` 寫完 plist 去呼叫 launchctl 被機器強制擋下 → `Schedule::Failed`
→ `cmd_schedule` 回 2 → `setup` 必須回 3。

反證 R1（拿掉 exit 3）RED；R2b（不看回傳值，＝你報的原始形狀）RED。

### P1-2 測試會碰到真人 launchd

**這條沒有只修那一條測試。**

`schedule.rb` 的註解一直寫著「conformance 必須注入替身」，但那是靠人遵守，
而你的 review 證明不夠。現在兩層：

1. `test/support.rb` 頂端設 `ENV["OMOS_CONFORMANCE"] = "1"`（子行程繼承）。
2. `Schedule.launchctl` 的**第一件事**就是檢查它，有設就 raise
   `SCHEDULE_REAL_LAUNCHCTL_IN_CONFORMANCE`。
3. setup 的子行程測試另外一律帶 `--no-schedule`。

加上這道 guard 之後重跑，**立刻抓到你指的那條測試**（3c 一度 454/455），
修完才回到全綠。

反證 R3b（把 guard 挪到 `Open3.capture3` 之後）RED。

### P2-1 doctor 的時間點

`setup` 結尾現在明講這份 doctor 發生在重開與批准 Codex hook **之前**，
並印出重開後要再跑的那一行完整指令。INSTALL.md 的「已經自動跑過了」改成
「那是重開之前的，做完第 5 步再跑一次，那一份才是要貼回去的」。

反證 R4b（拿掉提示）RED。

### P2-2 hosts 只列一個

**你是對的，那句是假的。** 用完全空白的 fake HOME 實測，仍然得到
`hosts: Codex, Claude Code`，而且會幫沒裝 Codex 的人建 `~/.codex/config.toml`。

選了「刪掉那句、說實話」而不是加 host presence detection：後者是行為改變，
偵測錯了會比現在更難解釋，且不在這張 T0 卡的範圍。現在寫的是
「兩個 host 一定都會列出來；本產品目前不偵測你裝了哪些工具，而是照契約把
兩邊的設定都寫好；沒用到的那份就放著不動」。

**若你認為應該真的做 presence detection，請直接說，我另開卡。**

## 交付方自己揭露：同一根因第三次

測試／變異透過 process 級狀態逃出沙箱，這是第三次：

1. 變異把 `xattr -dr` 範圍改成 `File.expand_path("~")` 並實際執行 →
   在 Owner 家目錄遞迴清除 quarantine 約十分鐘，無法還原。
2. 你這次抓到的 setup 測試（fake HOME + 真 `gui/<uid>`）。
3. **為了反證 §P1-2 那道新 guard，我把 guard 關掉再跑整套** → 又在真人
   session 留下一個 job（`state = not running`，已 `bootout`，
   `~/Library/LaunchAgents` 無 plist，現在殘留 0）。

依「同一 blocker 第 3 次失敗即停」改結構，新增硬規則：

> **安全 guard 的反證一律用原始碼斷言，不得用執行。**

落地成一條測試：斷言 `OMOS_CONFORMANCE` 檢查必須在 `Open3.capture3`
**之前**。這樣「拿掉 guard」在原始碼層被抓到，不必真的讓它跑一次。

請特別看這條的形狀對不對 —— 這是本輪唯一的結構性改動。

## 交付方自己跑過

```text
3a 26/26  ·  3b 46/46  ·  3c 461/461  ·  40/40 validators  ·  diff --check clean
真人 launchd 殘留 0

最終 ZIP  SHA-256  6df5fa8953945b387c81eeafccb67f2cf43c8821ec264b40ca07b01ae15ebc33
驗收 13 七項全 PASS（artifact_id 5d4f0607aa624d16…）
驗收 14 三項全 PASS，彈窗 0 次
```

> 驗收 13／14 一律帶 `--no-schedule`。沙箱 home 的 plist 路徑雖然被 `--home`
> 導走，但 `bootstrap` 的 domain 是執行者真實的 session——那正是 P1-2。
> 排程路徑由 conformance 以注入替身覆蓋；真 launchd 的驗收在 Slice B
> 驗收 8 已完成。**若你認為這個取捨不成立，請直接指出。**

## 要求

只就上面四點給 GO 或 NO_GO。每一條 P0/P1 請附可重現的變異：改哪一行、
哪條測試轉紅，或證明沒有測試會轉紅。

若仍 NO_GO，請說明是不是又是同一個根因換一個位置——若是，下一輪不再 repair。
