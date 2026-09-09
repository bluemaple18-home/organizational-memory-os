# Jira 對帳｜AIWR Codex／Claude Code Adapter

- 建立日期：2026-09-10
- Project：`SSP`
- Parent：`SSP-287`
- Feature identity：`FEAT-20260910-AIWR-ADAPTERS`
- Owner confirmation：已確認建立
- 結果：4 張子任務與 6 條 issue link 建立後回讀成功
- Assignee／開始日／截止日：未設定

## 建立結果

| 順序 | Jira | 工作 | 狀態 | Blocking edge |
|---:|---|---|---|---|
| 1 | [SSP-307](https://multiforcedatateam.atlassian.net/browse/SSP-307) | `AIWR-09` Codex Native Adapter／Runtime Probe | 待辦事項 | blocks `SSP-309` |
| 2 | [SSP-308](https://multiforcedatateam.atlassian.net/browse/SSP-308) | `AIWR-10` Claude Code Native Adapter／Runtime Probe | 待辦事項 | blocks `SSP-309` |
| 3 | [SSP-309](https://multiforcedatateam.atlassian.net/browse/SSP-309) | `AIWR-11` 跨平台一致性驗收 | 待辦事項 | blocked by `SSP-307/308`；blocks `SSP-310` |
| 4 | [SSP-310](https://multiforcedatateam.atlassian.net/browse/SSP-310) | `AIWR-12` PM 同事輕量 Pilot | 待辦事項 | blocked by `SSP-309` |

## 關聯回讀

- `SSP-307` relates to `SSP-297`。
- `SSP-308` relates to `SSP-297`。
- `SSP-307` blocks `SSP-309`。
- `SSP-308` blocks `SSP-309`。
- `SSP-309` blocks `SSP-310`。
- `SSP-310` relates to `SSP-295`。

## 研究與施工裁決

官方文件研究方向通過，但文件研究本身不足以證明 runtime 相容。`SSP-307/308` 必須先以版本綁定與真實 payload probe 補齊證據，才能鎖定 Adapter 行為。

已接受的共同邊界：

- Codex／Claude Code lifecycle event 是 Evidence，不是 AIWR `complete` authority。
- Adapter 使用 native-first 薄 mapping，不建立第二套 runtime、ledger、registry、FSM 或 writer。
- 預設 project／local scope；不得直接改寫同事全域規則。
- `SSP-297` 是 AI Core accepted artifact → Personal Memory 的 Optional Adapter，不與平台 lifecycle Adapter 合併。
- `SSP-295` 是 Personal Memory vertical pilot；`SSP-310` 只驗 AIWR 工作紀錄落地，兩者相互關聯但不互相冒充完成。

## Current frontier

1. 先做 `SSP-307`，因目前實際使用面是 Codex Desktop。
2. 有第二個施工者時，`SSP-308` 可與 `SSP-307` 平行；沒有時接續執行。
3. `SSP-307/308` 均通過 checkpoint 後才做 `SSP-309`。
4. `SSP-309` 通過後才把 `SSP-310` 交給 PM 同事。

此 lane 不改寫企業知識 SaaS 的 Document／Jira Adapter、Permission／Retention／Deletion 與 Canonical Direct-Write Audit 優先級。
