# EMEM-11 切片 2｜Codex + Claude Code Host Binding — Review Handoff

- repo：`organizational-memory-os`
- base：`251a0d85624532b492bd7ebe82985a9abb070cd8`
- branch：`codex/emem11-host-binding`
- review target：**目前 branch working tree**
- local commit：目前執行環境拒絕建立 `.git/index.lock`，因此尚無 review SHA；沒有 merge / push。

> 這是本機 sandbox 的 Git metadata 寫入限制，不是測試失敗。所有 source / fixture /
> evidence 已落在工作區，可直接 review；不要把「尚未 commit」誤讀為產品驗證已失敗。

## 1. Scope

只收 EMEM-11 Slice 2：Codex + Claude Code Host Binding。

### why_not_less

只補 Slice 1 的 `supported_hosts_v1` / `effective_scope` residual，會讓主卡已明列的
safe merge、SessionStart、shadow / disabled / incompatible fail-closed 仍只存在 prose。

### why_not_more

正式 installer、doctor、live config discovery、cross-host 真人測試與 rollback receipt
屬 Slice 3；SSP-295 真人產品 pilot 還要等 EMEM-10 + EMEM-11 都 ready。

### do_not_absorb

不吸 vendor-native memory、per-project store、central DB、新 scope enum、新 lifecycle、
background agent 或 Company Canonical authority。

## 2. 主要交付

1. `personal_memory_host_binding_v1` machine-readable contract。
2. `scripts/lib/personal_memory_host_binding.rb` 共用 evaluator。
3. `scripts/validate_personal_memory_host_binding_contract.rb` 常設 gate。
4. `personal-memory-host-binding-fixtures.json`：2 base + 4 positive + 53 negative。
5. 接回 `validate_personal_memory_contract.rb` aggregator；全庫 validator 38 → 39。

## 3. Reviewer 請重點打的四個面

### A. `supported_hosts_v1` 是否真的從子集變成 v1 精確集合

目前不是硬在 runtime validator 再抄一份 host 名單：Host Binding contract 必須存在
兩個 concrete profile，profile keys 與 runtime `supported_hosts_v1` 完全相等；profile
本身再各自綁既有 native-adapter spec。只往 runtime list 加第三個 executor 的 drift
probe 會 RED。

請特別判斷：`EXPECTED_V1_HOSTS = [Codex, Claude Code]` 放在 Slice 2 gate 是否是正確的
**delivery-scope freeze**，而非不應存在的第二份 domain vocabulary。

### B. `effective_scope` 的語意是否正確

本片沒有把 `effective_scope` 硬等同 `employee_memory_scope_modes`。流程是：

```text
runtime_scope_mode
  -> existing mode_definitions
  -> baseline visibility_scope
project_visibility_scope (optional)
  -> existing visibility_scopes.default_readers
  -> subset/equal 才可套用
  -> produced_binding.effective_scope
```

互不包含也當作不能證明收窄，fail closed。請覆核這個 conservative relation 是否與
既有 SSP-294C scope-ceiling 的「無法證明收窄就不能當收窄」一致。

### C. Safe merge / shadow 是否被 caller 決定檢查範圍

已修掉兩個 self-scoping 洞：

- declared higher-precedence scopes 必須 **exactly present**，不能省略 LOCAL / PROJECT；
- install.after、effective user config、uninstall.before 必須是同一份 chain，不接受三份
  各自自洽的 snapshot。

請再找是否仍有第四個「被驗方自己決定檢查集合」的位置。

### D. Static contract 與 live truth 的邊界

`input_authority` 明確分 Host native / runtime policy / project context / derived output。
本片只證明 normalized semantics；不宣稱 fixture 是 live `~/.codex` / Claude settings
觀測。Slice 3 doctor/conformance 才要證明實際 discovery 與 runtime observation。

請判斷這個 defer 是正確切片邊界，還是 Slice 2 已經必須取得某一種 live evidence。

## 4. 開發過程自己抓到的 finding

- higher-precedence scope 可省略 → 已修；
- install/effective/uninstall snapshot 未串成同一條 chain → 已修；
- composition guard 檢查順序造成 malformed uninstall TypeError → 已修；
- 初次 return-site sweep 53/56，三個 config forwarding site 沒有隔離負例 → 已補，現 56/56。

## 5. 驗證

```text
Host Binding validator                 PASS
Personal Memory aggregator             PASS
全庫 validators                         39 / 39 PASS
逐 return-site mutation                 56 / 56 RED, 0 GREEN
MCP shadow composition probe            target RED + aggregator RED
probe restore                           byte-identical
git diff --check                        clean
```

完整證據：`.work/evidence/EMEM11-SLICE-2-HOST-BINDING-20260919.md`

## 6. 請回覆

`GO / NO_GO + P0～P3`。

若 `NO_GO`，請指明 repair 只收哪些 finding；不要重開 Slice 1 或把 Slice 3 installer /
doctor / SSP-295 真人 pilot 混進本輪。

