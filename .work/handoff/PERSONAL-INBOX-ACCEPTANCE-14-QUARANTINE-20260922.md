---
id: PERSONAL-INBOX-ACCEPTANCE-14-QUARANTINE-20260922
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
type: evidence
verdict: PASS
supersedes: PERSONAL-INBOX-SLICE-B-DELIVERY-PATH-EVIDENCE-20260922.md 的驗收 14 段落
---

# 驗收 14｜帶 quarantine 的交付路徑 — **PASS**

## 先更正一個錯誤的判斷

2026-09-22 稍早的證據包寫：

> 用 `xattr -w` 人工寫上的 quarantine 屬性，在本機**不會**真的觸發
> Gatekeeper 攔截——`doctor` 照常通過。

**這是錯的。** 人工寫上的 quarantine **確實會**觸發攔截。重跑後穩定重現
2/2，再加上本次的完整驗收共 4 次，每次都被擋：

```text
dlopen(...bigdecimal.bundle): code signature ... not valid for use in process:
library load disallowed by system policy
```

先前判斷錯誤的原因：那一次是在**同一個目錄已經成功跑過 install 之後**才補上
xattr 再跑 `doctor`，量到的不是乾淨的首次載入。**條件沒控好就下結論。**

因此驗收 14 不需要外送 ZIP、也不需要麻煩同事——本機就做得完。

## 三個子項

| 子項 | 結果 |
|---|---|
| 對解壓後整包實際寫入 `com.apple.quarantine` 並**重現攔截** | **PASS**：11 個 `.bundle` 被標記；`install` 被擋，回 `OMOS_NATIVE_REQUIRE_FAILED`，底層訊息為 `library load disallowed by system policy` |
| 解除指令後殘留 **0**，且安裝與 `doctor` 正常 | **PASS**：殘留 0、`INSTALLED`、`18 OK / 2 WARN / 0 FAIL` |
| 安裝說明明確警告**不得**按「丟到垃圾桶」 | **PASS**：`INSTALL.md` 出現 2 次 |

## 攔截次數的實況

連跑四輪，執行者的畫面上**至少跳了 5 次**對話框。這與同事端 2026-09-21 首次
交付時「連續攔截約 10 次」一致——artifact 內有 11 個未簽章的原生 `.bundle`，
Gatekeeper 每個各擋一次。

## 為什麼**不**放進 conformance

這一項會在**執行測試的人畫面上跳出系統對話框**，而且其中一個按鈕是
「丟到垃圾桶」——按下去會破壞 artifact。把它放進 3c 等於讓每個跑測試的人
都被彈窗轟炸，並暴露在誤按的風險下。

因此維持為**有紀錄的手動驗收**，不進自動化套件。本檔即為那份紀錄。

## 交付路徑的實況補充

同事端 2026-09-22 升級時**完全沒有跳攔截**——因為他照新版 `INSTALL.md` 的
順序，在跑任何東西之前就先清掉隔離。**這是文件寫對了**：走 happy path 本來
就不該看到攔截。本驗收是刻意跳過第 2 步去重現它。
