---
id: SSP295-PILOT-OBSERVABILITY-20260923
status: READY_TO_IMPLEMENT_LOCAL_PILOT
jira: SSP-295_PREP
parent: SSP295-FULL-PRODUCT-PILOT-20260921
type: pilot-preflight
priority: MVP
authority: organizational-memory-os
blocks:
  - SSP295_PILOT_START
---

# SSP-295 Pilot Observability｜單人 pilot 的本機 content-free receipt

👉 [假設與目標確認]
- **目標**：第一輪只有 1 位真人 pilot。她不必主動寫 bug report；產品在**本機**輸出 content-free review receipt，由她手動貼給 Owner，Owner 可判斷該週閉環是否完成。
- **邊界**：不自動傳回公司、不走 SSP-324 Minimal Evidence Package、不新增 reverse-access／telemetry channel／DB／daemon／uploader；Personal Store 仍只在本人機器。
- **驗收**：一份人工貼回的 receipt 足以回答「哪個週期、Friday trigger 有沒有被觀測到、review 是否 terminal、是否需列 `P1_CANDIDATE`」，且不含任何個人知識內容。

## 1. Measured gap

SSP-295 已要求真人使用，但若成功與失敗只靠使用者口頭描述，則「沒回報」會被誤當成「沒問題」。目前產品另有兩個實測 gap：

1. **沒有 content-free review receipt emitter**：`review history` 只在本機讀 store 並印給人看，沒有一個可直接貼回 Owner、欄位封閉的 pilot receipt。
2. **Friday trigger 沒有結構化的 per-period 證據**：launchd 已把 `review due --notify` 的 stdout/stderr 寫進既有 `~/.omos/personal-memory/schedule.log`，所以**不需要新狀態檔**；但目前 log 只有人類輸出，沒有可穩定判定某個 `review_period_id` 曾被 launchd 喚醒的 marker。
這對以下失敗尤其危險：

- import 沒留下 Candidate／寫錯 owner 或 tenant；
- Friday trigger 沒觸發；
- review due 算錯週期；
- review done／skip 沒形成 terminal closeout；
- doctor/runtime 明確 FAIL；
- 整個週期沒有任何可提交的 closeout receipt。

## 2. Owner 裁決：第一輪採 local-only，不開公司端通道

採用 **C｜單人 local-only pilot**：

- receipt 只在 pilot 使用者的 Mac 上生成；
- 使用者以人工 copy/paste 交給 Owner；
- 不把 pilot health receipt 塞進 SSP-324 `company_side_evidence_boundary`。該 boundary 的 purpose 是封閉 allowlist，pilot observability 不屬於其中任何一項；本卡不得為此重開已鎖契約；
- 第一輪只有一人，不建立中央 pilot view service；Owner 收到的一份 receipt 本身就是一列 pilot view。

### 2.1 最小實作 seam

只補兩個 bounded 能力：

1. **`review receipt --period YYYY-Www`**：純本機 read-only emitter。從既有 install receipt、週期帳／closeout 與 schedule log 組出封閉欄位；不建立新 table／writer。
2. **structured Friday-trigger marker**：launchd 的 ProgramArguments 增加僅供排程使用的內部旗標；該路徑在既有 `schedule.log` 寫一行 content-free marker（至少含 `review_period_id`、`observed_at`）。人工執行一般 `review due` 不得冒充 launchd trigger。

Pilot receipt 最多包含：

```text
employee_ref
review_period_id
review_status          # 沿用既有 final_status；沒有 terminal 時為 MISSING
attempt_count
schedule_observed      # true / unknown；absence of evidence 不宣稱 false
terminal_closeout      # true / false
observed_at
```

可額外輸出 bounded error code，但不得輸出 note／prompt／Evidence snapshot／Candidate body／disposition reason 等內容。

這是本機 pilot projection；**Personal Store 仍是私有來源，receipt 不是知識副本。**

## 3. P1 candidate 規則

以下任一條成立，pilot control 面必須標成 `P1_CANDIDATE`，不得等待同事主動報錯：

1. 已進入應完成的週期，receipt 顯示 `MISSING`。
2. schedule 預期已啟用，但該週期 `schedule_observed=unknown`；到週期 closeout 時仍 unknown，不得顯示健康。
3. terminal closeout 應存在卻不存在。
4. 主要流程回傳非零／明確 error code，造成 import、review、closeout 無法完成。
5. doctor/runtime 出現 `FAIL`（WARN 不自動升 P1）。
6. receipt 自相矛盾，例如 `review_status=DONE` 但 `terminal_closeout=false`。

`P1_CANDIDATE` 是「需要查」而不是自動宣判產品 P1；確認後才開 defect card。

## 4. 隱私與 authority

- 公司端不得因 pilot 取得 Personal Store reverse-access。
- 不傳 note/content/prompt/evidence snapshot/candidate body。
- error 只傳 bounded code；需要除錯內容時另走明示的人工 evidence 流程。
- **本輪沒有對外自動傳輸。** SSP-324 submission boundary 不承載 pilot health receipt。
- Owner 只接收使用者明示 copy/paste 的 content-free receipt；沒有 receipt 時只能標 `NO_RECEIPT/UNKNOWN`，不得反向讀 Personal Store 補資料。

## 5. Acceptance

1. `review receipt --period` 可產生 content-free receipt，且欄位封閉、不含任何 personal content。
2. 刻意拿掉 terminal closeout → `P1_CANDIDATE`。
3. 真 launchd 路徑對該 period 寫入 structured marker；普通人工 `review due` 不得產生同一 marker。
4. marker 缺席 → `schedule_observed=unknown`，不得被轉成 `false` 或健康。
5. receipt 的 review status／attempt count／terminal 必須由既有 closeout/history 事實推導，不接受 caller 自報。
6. 公司端無法從 receipt 反查 Personal Store 或知識內容；本輪沒有自動 upload。
7. 不新增 telemetry DB、background agent、reverse-access API、第二套 submission writer 或第二個 trigger-state file。
8. 單人 pilot 時，人工貼回的 receipt 即為 pilot view；擴到多人前才另行裁決是否需要中央觀測通道。

## 6. Minimum Sufficient

- **why_not_less**：只靠同事口頭描述會把 silent failure 當成功；現有人類文字輸出也不足以穩定證明 launchd 哪一期真的觸發。
- **why_not_more**：第一輪只有一人；不值得為此重開 SSP-324 或建立公司端 observability channel。沿用既有 `schedule.log` + 本機 closeout 事實即可。
- **do_not_absorb**：不吸收 doctor P2、Codex cross-host、clean-macOS qualification；它們維持原卡。
