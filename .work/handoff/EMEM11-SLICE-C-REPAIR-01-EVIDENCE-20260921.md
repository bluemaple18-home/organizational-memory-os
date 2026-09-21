---
id: EMEM11-SLICE-C-REPAIR-01-EVIDENCE-20260921
card: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921
slice: C
repair: 01
type: evidence
status: READY_FOR_REVIEW
base: 46370a5
---

# Slice C repair-01 證據包｜兩筆 P1 的修法與反證

回應 `EMEM11-SLICE-C-STANDALONE-PACKAGING-REVIEW-20260921`（NO_GO、2×P1）。
本包只記錄**本 session 實際跑出來**的結果。每一項都附鑑別力反證——
沒有反證過的測試不算證據。

## 1. 交付內容與行數

| 檔案 | +/- |
|---|---|
| `product/personal-memory/lib/omos/installer.rb` | +74 / −20 |
| `product/personal-memory/test/conformance_3c.rb` | +89 / −0 |
| 合計 | +163 / −20（淨 +143） |

installer.rb 的 +74 拆開是 **程式 40、註解 28、空白 6**，淨增程式約 +20 行
（40 加入 − 20 刪除）。兩筆 P1 都是**把兩份狀態收斂成一份**，不是加機制：
沒有新 model、新 form、新 Reviewer、新 registry。

`fail_before_receipt:` 是唯一的新增介面，且只在 `#rollback` 的參數上，
與既有 `install(fail_after:)` 同形。**待 Owner／reviewer 裁定**（見 §5）。

## 2. 兩筆 P1 的修法

### P1-1｜同內容重裝會把真正能回退的那一版 GC 掉

- 根因：install 的 GC 保留集另外推導一份狀態——傳的是
  `previous["artifact_id"]`（上一次安裝時的 current）。同內容重裝時它等於
  這次的 `artifact_id`，保留集塌成一個元素，真正能回退的那一版被刪。
  receipt 說得出 previous、`versions/` 裡卻沒有它。
- 修法：新增 `rollback_reachable_ids`，保留集直接讀**剛寫好的 receipt** 的
  `artifact_id` ＋ `previous_artifact_id`。rollback 認 receipt，GC 就只能
  認 receipt；狀態只留一份來源。

### P1-2｜rollback 在 receipt 寫失敗時留下 pointer／receipt 分裂

- 根因：先 `activate` 再寫 receipt。receipt 寫不進去時 pointer 已經切過去，
  留下「current=A、receipt 說 current=B」——而 receipt 正是下一次 rollback
  與 GC 的唯一依據，分裂之後兩邊都會做錯決定。
- 修法：`#rollback` 成為交易。先存下 pointer 目標與 receipt 位元組，
  失敗就兩者一起復原，**不碰 Host 設定**（rollback 本來就沒動過它）。
- 連帶：receipt 一律 `temp + rename` 原子寫入（`write_receipt_bytes`）；
  `restore_pointer` 抽出共用，`restore_activation` 不再自己重寫一遍
  symlink 還原邏輯。

## 3. 驗證結果

### 3.1 全綠（repo）

| suite | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | 134/134 PASS |
| validator（40 支） | 40 PASS / 0 FAIL |

3c 由 124 增為 134：repair-01 新增 10 項。

### 3.2 鑑別力反證（本線既定紀律）

兩筆各做一次**單點反轉**，確認新測試轉紅、還原後轉綠。

| 反轉 | 結果 | 轉紅的項目 |
|---|---|---|
| GC 保留集改回 `[artifact_id, previous["artifact_id"]]` | 3c **131/134**（−3） | 「同內容重裝不得把 receipt 指得出的 previous GC 掉」／「因此同內容重裝之後 rollback 仍然走得通」（`ROLLBACK_ARTIFACT_MISSING`）／「rollback 後再重裝，保留集仍等於 receipt 的 current ＋ previous」 |
| 拿掉 `#rollback` rescue 內的 `restore_pointer` ＋ `write_receipt_bytes` | 3c **132/134**（−2） | 「rollback 失敗後 current 復原成失敗前的那一版」／「rollback 失敗後 pointer 與 receipt 仍然一致」 |
| 還原後 | 3c **134/134** | — |

兩次轉紅的**形狀與 reviewer 的重播一致**：

- P1-1 反轉時「同內容重裝後 receipt 仍指得出 previous」**仍然 PASS**——
  壞掉的是 `versions/` 而不是 receipt，正是 reviewer 描述的那個不一致。
- P1-2 反轉時「receipt 位元組不變」與「不碰 Host 設定」**仍然 PASS**——
  注入點在 receipt 寫入之前，壞掉的只有 pointer。紅的正好是分裂本身。

這兩點也說明新測試不是「一反轉就整片紅」的粗測試：它們各自只鎖住
自己那一個不變式。

### 3.3 workspace B（無 source checkout）

- B ＝ `mktemp -d /tmp/omos-wsB.XXXXXX`，artifact 送到 `$B/omos-artifact`，
  isolated HOME ＝ `$B/home`。**未改名或移走主工作區。**
- 隔離實測（`find` 計數）：B、`$B`、`/tmp`、`/` 四層的
  `規格` ＝ 0、`scripts/lib` ＝ 0。

| suite | repo | workspace B |
|---|---|---|
| 3a | 26/26 | 26/26 |
| 3b | 34/34 | 34/34 |
| 3c | 134/134 | 132/132 PASS ＋ 3 N/A |

B 的 3 項 N/A 是「與 repo 原件逐位元組相同」——B 沒有原件可比，本機
**無從驗證**，故印 `N/A` 而非 PASS，由 repo 側 `validate_packaged_governance_drift.rb`
負責。B 的檢查總數 135 比 repo 的 134 多一項：B 把「自我安裝產生的 artifact
仍帶齊 9 份治理檔」與「與原件 byte-identical」拆成兩項，後者才是 N/A。

**repair-01 的 10 項在 B 同樣全綠**（含 `ROLLBACK_INJECTED_FAILURE` 與
「rollback 失敗後 pointer 與 receipt 仍然一致」）。

四個交付面在 B 全部可用：

| 面 | 結果 |
|---|---|
| `install` | `INSTALLED`，store schema 0.1.0，hosts = Claude Code |
| CLI `status` | store／sqlite 3.53.2／wal／schema 0.1.0／rows 0 |
| SessionStart hook | 依 Host 設定裡**實際註冊的 argv** 經 launcher 呼叫，回 `hookSpecificOutput`，`effective_scope=SELF_ONLY` |
| MCP `initialize` | 經 launcher，回 protocolVersion 2024-11-05 ＋ serverInfo 0.1.0 |
| `doctor` | 18 OK / 2 WARN / 0 FAIL |

附帶實測：Host 設定（`.claude/settings.json`、`.claude.json`）內
`versions/` 與 artifact-id 字樣**計數 0**；安裝只放兩支 Host 面向的
launcher（`-mcp`、`-session-start`），CLI 走 artifact 的 `exe/`。

以錯誤的 `--host claude-code` 呼叫 SessionStart 會得到
`REFUSED HBV1_HOST_NOT_SUPPORTED`——這是 host binding 的既有保護在 B 內
一樣生效，不是缺陷。

## 4. 沒有驗到的東西

- **真實的 receipt 寫入失敗**（磁碟滿、目錄權限、行程被砍）沒有實測。
  測到的是**注入**的失敗點。改成 `temp + rename` 之後，「把 receipt 設成
  唯讀」製造不出失敗——`rename(2)` 看的是目錄權限不是檔案權限。
- **真 Host 觸發**：doctor 的 2 個 WARN 維持原狀（已依官方 schema 寫入，
  尚未由真 Host 實際觸發過）。本片不宣稱改善這一項。
- B 的 3 項 byte-identity 如 §3.3 所述，本機無從驗證。

## 5. 待裁定

`Installer#rollback(fail_before_receipt:)` 是為了測試而開的注入接縫。
理由見 §4 第一點：原子寫入之後，這個失敗情境沒有辦法從外部穩定製造。
做法與既有 `install(fail_after:)` 同形，不是新機制。

**請 reviewer／Owner 裁定可不可以收。** 若判定不可收，替代方案是把
receipt 寫入抽成可注入的 writer seam，成本較高且會多一層間接；本包
不預先實作。
