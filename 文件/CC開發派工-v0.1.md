# CC 開發派工工作流 v0.1

- 狀態：`DRAFT_OWNER_REVIEW`
- 日期：2026-09-07
- 適用範圍：`organizational-memory-os` 中由 Claude Code 承接實作的 Jira 線 —— 目前是 `SSP-286`（員工個人記憶閉環）與 `SSP-287`（AI 工作紀錄自動化執行層），子任務 `SSP-288`～`SSP-305`。
- 授權輸入：`~/.claude/CLAUDE.md`（AI 共用規則 Lite）、`~/ai-core/rules/16-codex-multi-machine-workflow.md`、`文件/待辦重整.md` 第五節、`.work/handoff/CC-SCHEMA-FOUNDATION-HANDOFF-20260904.md`。

## 0. 為什麼要 CC 版

AI Core 的 `model-role-routing`（minimal→Luna、standard→Terra、strict→GPT-5.5、critical→Sol）是 Codex mainline 依風險把卡片派給不同模型 lane。Claude Code session 是單一模型（預設 Sonnet），沒有 model-tier fan-out，也叫不到那些 lane。因此本工作流把「用哪個模型」改成「用多少 ceremony＋要不要 Owner 先簽核」，並把大 review 抽離成一份可被任何平台審的交接卡。

## 1. 職責邊界

- **實作全部在 CC。** 所有難易度的卡都由 Claude Code 完成，不外送 Codex/GPT-5.5 lane 做實作。
- **主 session 模型由 Owner 的 `/model` 設定決定**，CC 不在任務中途自動換模型。
- **CC 唯一主動挑模型的地方是 subagent**：機械量大的活可派 `haiku` subagent，重切片可派 `opus` subagent；研究 fan-out（CodeGraph 未命中、prior-art 掃）走 `Explore` / `general-purpose` subagent，且 subagent 無 correctness authority。
- **大 review 是唯一外送項**：CC 把待審內容寫成交接卡、commit 進 git、凍結 commit，然後交給 Owner。由哪個平台或模型執行 review 完全是 Owner 的決定，CC 不圍繞特定 reviewer 設計、不假設 reviewer 數量、不詢問 reviewer 平台能力。
- 外部 reviewer 只回結構化 findings，不得寫 `.work/current/*` 或 `.work/<TASK_ID>/status.md`；由 mainline（CC）驗證後寫回 repo。

## 2. Ceremony 分級（取代 model routing）

| Tier | 觸發條件 | 做法 |
|---|---|---|
| **T0 直接做** | fixture / 文件 / 註解修正，不動契約 | 薄卡（Objective＋Acceptance＋Likely files）→ 本地 gate → checkpoint。量大時派 `haiku` subagent。不發大 review 交接卡。 |
| **T1 標準切片** | 一條契約切片（schema/spec＋fixtures＋validator＋evidence），多數 EMEM / AIWR 子任務 | 完整任務卡（含本文件第 4 節必填欄位）→ Sonnet 主 session 實作 → 本地 gate → checkpoint 凍結 SHA → 發大 review 交接卡。 |
| **T2 規格先凍結** | 契約鎖版、blast radius 大、動到 schema authority 表達 | 先產出 requirements / spec 凍結文件 → **停，等 Owner 簽凍結點** → 再依 T1 實作（必要時 `opus` subagent）→ 發大 review 交接卡。 |
| **T3 停** | 動到 authority 邊界、六條 Truth Boundary、或要新增 subsystem | **不自行開工。** 回 Owner 做 level / scope 決策（`PRODUCT_FIT_TRIGGER`）。 |

分級寫在任務卡的 `Tier` 欄；分級改變要在卡上留一行理由。

## 3. 單票執行迴圈

1. 挑下一張依賴已滿足的票；多候選時問 Owner 一題。
2. 卡片開頭一行 `👉 [假設與目標確認]`：目標 / 邊界 / 驗收。
3. source decision 前查 CodeGraph；無結果或失敗才限域 `rg`。
4. 寫 `.work/CARD-<TICKET>-<slug>-<date>.md`（第 4 節必填欄位）＋ `.ai/cc_task_<ticket>.md`（CC 自我 brief）。
5. 判 Tier。T2 → 先寫凍結文件並停；T3 → 停回 Owner。
6. 在 lane 專屬 worktree／branch `cc/<ticket-slug>` 實作，走 RED → GREEN → checkpoint。
7. 本地 gate 全綠：受影響 validators、標準 schema engine、`git diff --check`、無無關檔案異動。
8. checkpoint commit（凍結 SHA）＋ `.work/evidence/<TICKET>-<date>.md`。
9. 寫 `.work/handoff/<TICKET>-REVIEW-<date>.md`（第 5 節結構）＋ commit，把凍結 SHA 交 Owner。
10. Owner 帶回 findings：
    - 任一 reviewer `P0`／`P1` → `NO_GO`。開 `.work/CARD-<TICKET>-REPAIR-NN-<date>.md`，同 branch 定點修，沿同一 review line 做定點複審（只驗原 finding＋regression），原 review SHA 保持 immutable。
    - `P2`／`P3` → 記 `文件/待辦重整.md` backlog；若其實能繞過主要契約或權限／resource binding，升為 `P1`。
    - 無 `P0`／`P1` 且 binding／zero-mutation PASS → 寫 `.work/evidence/<TICKET>-REVIEW-<date>.yaml` receipt → 更新 `文件/待辦重整.md`＋Jira 狀態 → Owner accept。
11. 下一票。

## 4. 任務卡必填欄位

延用 `文件/待辦重整.md` 第五節，並補三欄：

- `id` / `status` / `type`（frontmatter）
- `Tier`（T0–T3）與分級理由
- `Objective`
- `Root question`
- `Traces to`（授權文件節點；spec 若無 `US-*`／`FR-*`／`SC-*` 就用穩定 slice ID 追溯，空白不算完成證明）
- `Dependencies` / `Blockers` / `Current frontier`
- `Scope` / `Constraints`
- `Product fit`：`Measured gap`、`Why not less`、`Why not more`、`Do not absorb`、`Rollback`
- `Acceptance`
- `Likely files`
- `Evidence`（`.work/evidence/<TICKET>-<date>.md` 路徑）

## 5. 大 review 交接卡結構

沿用 `.work/handoff/CC-SCHEMA-FOUNDATION-HANDOFF-20260904.md` 八段，寫成平台無關、對著凍結 commit 自足：

1. 審查身份與不可變邊界：repo、base SHA、review SHA、tree SHA、唯一 diff range、綁定檢查命令。
2. In-scope allowlist：路徑＋commit blob OID 表，可用 `git diff-tree` 重算。
3. 明確排除範圍。
4. Normative authority 與可重跑命令（`uv run` schema engine、各 Ruby validator、`git diff --check`）。
5. Spec claim → exact enforcement → fixture parity 表。
6. 指定加壓面：presence-only、duplicate JSON／YAML key、`$ref` resolution、`if/then` vacuous match、`additionalProperties` closure、cross-layer real resolution。
7. 結構化輸出契約（YAML）：`review_input`、`verdict`、`counts`、`findings[]`（每筆含 fixed-commit `path:line`、`trigger`、`observed`、`risk`、`recommendation`）、`verification`。
8. Gate 與 targeted re-review 規則（見第 3 節第 10 步）。

## 6. 兩條 lane 與 worktree

各 lane 一個 worktree，branch 前綴 `cc/`，避免 branch 衝突。

- **Lane A（EPM / `SSP-286`）**：`SSP-290 → SSP-292 → SSP-293 →`〔repo backlog：Document Adapter Mapping、Jira Adapter Mapping〕`→ SSP-291 → SSP-294 → SSP-295`。`SSP-296`／`SSP-297` 維持 Deferred。
- **Lane B（AIWR / `SSP-287`）**：`SSP-298 → SSP-299 → SSP-300 → SSP-301 ∥ SSP-302 → SSP-303 → SSP-304 → SSP-305`。零外部依賴，可與 Lane A 並行。
- 匯流點：`SSP-295`（EMEM-06 pilot），MVP 完成判定（DoD：`SSP-291`～`SSP-295` 全驗收）。

## 7. 常駐約束（不變）

繁體中文文件／註解／docstring，程式碼保留原語言；Python `uv + .venv`，Node/TS `pnpm`；工具鏈先讀 `~/ai-core/config/toolchain_paths.sh`；開工後預設靜默，只在 blocker 需 Owner 介入、交付契約或 scope 改變、里程碑、同一 blocker 第 3 次失敗才回一句；卡片流先驗證實體 `.md`；`save / verification / evidence / acceptance` 先鎖契約；code／config／workflow／docs 契約變更補測試、跑受影響 gate、`git diff --check` 後才可完成；不 merge／push，除非 Owner 明示。

## 8. Rollback

本工作流是文件與卡片流程約定，不連任何 runtime。移除方式：刪除本文件與 `.ai/cc_task_*.md`，卡片與 evidence 保留作歷史。既有 `.work/` 卡片流與 `~/ai-core/skills/{mainline-workflow-gates, project-development, evidence-first-acceptance}` 不受影響。
