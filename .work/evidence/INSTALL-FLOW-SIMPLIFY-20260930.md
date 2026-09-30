---
id: INSTALL-FLOW-SIMPLIFY-20260930
card: CARD-INSTALL-FLOW-SIMPLIFY-20260930
type: delivery-evidence
---

# 安裝交付線｜最終交付物與驗收證據

## 0. 被驗收的實物

```text
OMOS-Personal-Memory.zip
SHA-256  887be53245dc5403aea99ec1bd0240b925fcda0b5d01bd2df38da4c2b12c9ed7
```

**ZIP 一旦重打，驗收 13／14 必須重跑。** 本包的 INSTALL.md 已納入 repo
（`product/personal-memory/INSTALL.md`），所以之後改文件也算重打包。

交付包與 repo 產品目錄逐檔一致：`diff -rq` 除 `test/`／`.gitignore` 無差異。

## 1. 驗收 13：升級路徑

步驟固定為 **先刪舊的解壓資料夾 → 再解壓新版 ZIP**；不得 `cp -R`、不得直接
覆蓋；`~/.omos` 的 Personal Store 不刪。

| 項 | 結果 |
|---|---|
| store 逐位元組不變 | PASS（`f374e253f11b6aa0…` 前後同值） |
| 身分保留 | PASS（`urn:omos:employee:lettie`） |
| `weekly_review_origin_at` 保留 | PASS |
| evidence 檔數不變 | PASS（2 → 2） |
| `doctor` | PASS（23 OK / 4 WARN / 0 FAIL） |
| `artifact_id` 與乾淨安裝一致 | PASS（`dda818e98db54795…`） |
| `~/.omos` 無 quarantine 殘留 | PASS（0 個） |

## 2. 驗收 14：帶 quarantine 的交付路徑

在沙箱解壓最終 ZIP，對整包 `xattr -w -r com.apple.quarantine`
（模擬從通訊軟體收到），確認 10 個 `.bundle` 全部帶標記後執行。

| 項 | 結果 |
|---|---|
| 14-1 install 在載入原生擴充前擋下 | PASS：`exit=78`、**0 秒**、`INSTALL_SOURCE_QUARANTINED` ＋ 修法那一行、`~/.omos` 未被建立 |
| 14-2 照印出的那行解除後同一指令就過 | PASS：`INSTALLED`、2 秒、`hosts: Codex, Claude Code` |
| 14-3 安裝出來的不帶 quarantine | PASS：複製 10 個、帶隔離 0 個 |

**彈窗 0 次。** 先前每跑一次會連續彈 5 次系統對話框（舊版逐一嘗試載入原生
擴充，每個被擋就彈一次）。入口前置檢查把整條彈窗路徑消掉了。

`minitest` 唯讀文件的 `Permission denied` 屬既知可忽略，INSTALL.md 已載明。

## 3. 反證

| | 變異 | 結果 |
|---|---|---|
| Q1 | 拿掉 `strip_quarantine!` | RED |
| Q2b | strip 對象由 `stage` 改成 `@home` | RED（原始碼檢查攔下） |
| Q3 | 入口不做隔離前置檢查 | RED |
| Q4 | 隔離檢查只警告不中斷 | RED |

Q2 原本用「實際執行」來證明，代價是在 Owner 家目錄造成一次無法還原的
quarantine 清除；已改為原始碼檢查，理由寫在測試註解。見卡片 §6.5。

## 4. 回歸

```text
3a 26/26  ·  3b 46/46  ·  3c 443/443
40/40 validators  ·  git diff --check clean  ·  launchd 殘留 0
```
