---
id: EMEM11-QUALIFICATION-SECOND-MACHINE-EVIDENCE-20260922
card: CARD-EMEM11-CLEAN-MACOS-QUALIFICATION-20260921
type: evidence
verdict: PASS
closes: 本卡驗收第 1 項（判準跨 OS version 成立）
---

# 第二台機器的實證 — 驗收 1 **PASS**

## 觀測

同事機（真實使用者環境）升級到含 qualification key 修正的新版 artifact 後
回報：

```text
macOS: 15.6.1 (arm64)
ruby:  /opt/homebrew/opt/ruby@3.4/bin/ruby
profile: darwin24 / arm64 / 3.4.0
doctor: 18 OK / 2 WARN / 0 FAIL
```

**並且明確回報：這次沒有再跳 `UNQUALIFIED_RUNTIME_PROFILE`。**

## 這證明了什麼

| 機器 | `host_os` | 結果 |
|---|---|---|
| 本機 | `darwin25` | QUALIFIED |
| 同事機（**真實**，非模擬） | `darwin24` | QUALIFIED，無警告 |

兩個**不同**的 `host_os`、同一包 artifact、都判為 qualified——這正是驗收第 1
項要的「判準跨 OS version 成立」，而且是**真實觀測**，不是本機模擬。

修正前同事機是會印 `UNQUALIFIED_RUNTIME_PROFILE` 的（2026-09-21 的回報）；
修正後同一台機器不再印。**同一台機器的前後對照**比兩台機器的橫向對照更有
說服力：變的只有 artifact。

## 一個要澄清的誤解

同事端的助理在回報裡寫「看起來 darwin24 已經在你們的驗證矩陣裡了」。

**這個說法不對，而且方向剛好相反。** 我們並沒有把 `darwin24` 加進任何矩陣
——正好相反，是把 `host_os` **移出**了 qualification key。現在的 key 是
`os_family + host_cpu + ruby_engine + ruby_abi`，`darwin24` 的 os_family 是
`darwin`，所以直接命中。

這個區別重要：若真的是「加進矩陣」，下一個 `darwin26` 的同事又會看到警告；
而現在**任何** darwin + arm64 + Ruby 3.4 的機器都不會再看到。

## 本卡狀態

驗收 8 項全數通過，**可結案**。
