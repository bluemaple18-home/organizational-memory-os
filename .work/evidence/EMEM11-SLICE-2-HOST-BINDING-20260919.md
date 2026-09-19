# EMEM-11 切片 2｜Host Binding Evidence

日期：2026-09-19  
Base：`251a0d85624532b492bd7ebe82985a9abb070cd8`  
分支：`codex/emem11-host-binding`

## 1. 驗證單位

本片驗證的是一個完整的 **Host Binding scenario**，不是單一設定片段：

1. user-scope install safe merge；
2. install 結果就是實際 effective user config；
3. uninstall 的輸入必須是同一份 install 結果，且只移除 OMOS 自有 entry；
4. 檢查所有已宣告的 higher-precedence scope，任何同名 OMOS registration 都 fail closed；
5. Host health 必須完整且為 ready；
6. SessionStart bootstrap 產生的 HostSessionBinding 必須綁回既有 executor identity；
7. project context 只能把 runtime baseline visibility 收窄或維持，不得放寬。

共用 evaluator：`scripts/lib/personal_memory_host_binding.rb`。Slice 3 的 installer / doctor
應重用這支 evaluator，不另抄 safe-merge、shadow、health 或 scope narrowing 規則。

## 2. 既有 authority 綁定

- v1 Host 集合由 `personal_memory_host_binding_v1.host_profiles` 的實體 profile
  鎖為 `Codex` + `Claude Code`，並要求與
  `personal_memory_runtime.supported_hosts_v1` **集合完全相等**；仍同時要求它是
  `runtime_policy.optional_executors` 的子集。這收掉 Slice 1 的
  `supported_hosts_v1` P2 residual：只加 `DeepSeek Harness` 會轉紅。
- HostSessionBinding 身分仍使用
  `runtime_policy.portable_record_contract.executor_provenance_fields`，本片沒有再造
  `host` / `host_session_id` 身分詞彙。
- `runtime_scope_mode` 只作為 **runtime-policy input**；project context 不得提供它。
  它先由 `employee_memory_scope_modes.modes` 驗詞彙，再經
  `ownership_visibility_contract.mode_definitions` 解析出 baseline visibility scope。
- project narrowing 使用既有 `ownership_visibility_contract.visibility_scopes.*.default_readers`
  的集合包含關係：目標 readers 必須是 baseline readers 的 subset。互不包含或更寬一律拒絕。
- `produced_binding.effective_scope` 是推導出的 **visibility scope key**，不是 caller
  自報的 employee scope mode。

## 3. Evidence boundary

本片沒有修改 `~/.codex`、Claude Code user settings 或任何真人 Host。

靜態 fixture 能證明的是 normalized Host Binding 的語意：設定 merge、conflict、health、
identity mapping、scope narrowing。它**不能證明**某份 fixture 真的是 live Host / runtime
觀測。因此契約新增 `input_authority` 與 `evidence_boundary`：

- Host native input：`native_session_id`、`cwd`
- Runtime policy input：`runtime_scope_mode`
- Project context input：`project_ref`、`project_visibility_scope`
- Derived output：`produced_binding`

真人設定讀取、實際 shadow 偵測、實際 runtime scope observation 與 cross-host 行為仍屬
Slice 3 installer / doctor / conformance；SSP-295 再做真人產品 pilot。

## 4. Fixtures / negative isolation

- 2 個完整合法 base：Codex / Claude Code
- 4 個 positive cases
- 53 個 negative cases
- 負例採 **base + 明寫 mutation**；validator 另斷言 mutation 非空且真的改變 base。

開發後自我 review 額外抓到並修掉三類問題：

1. `higher_precedence` 原本允許整個 PROJECT / LOCAL scope 被省略，caller 可自己決定
   掃描範圍。現在 profile 宣告哪些 precedence scope，就必須全部提供；少一個即
   `HBV1_HIGHER_PRECEDENCE_SCOPE_MISSING`。
2. install / effective config / uninstall 原本可各自提供三份彼此無關但各自自洽的
   snapshot。現在要求 `effective_user_config == install.after` 且
   `uninstall.before == install.after`。
3. 加入上述 composition guard 時，一度讓 malformed `uninstall=[]` 在 guard 前觸發
   `Hash#dig` TypeError。已調整檢查順序：先驗各區塊 shape，再做跨區塊 equality；
   malformed case 回原本 machine code，不噴例外。

## 5. Return-site / composition evidence

逐 `return` site mutation sweep：

```text
return_sites=56 red=56 green=0
```

第一輪 sweep 曾得到 `53 RED / 3 GREEN`，三個 GREEN 分別是：

- install `after` 的 `config_problem` 轉送；
- `effective_user_config` 的 `config_problem` 轉送；
- higher-precedence child config 的 `config_problem` 轉送。

三者都補了隔離 malformed fixture 後，第二輪為 56/56 RED。

Aggregator composition probe：暫時中和共用 evaluator 的 `HBV1_MCP_SHADOWED` guard：

```text
target_rc=1 agg_rc=1 byte_identical=yes
```

證明一個共用 guard 同時會讓本片 validator 與 `validate_personal_memory_contract.rb`
總入口轉紅；還原後 helper SHA 逐位元相同。

## 6. 全庫驗證

```text
ruby scripts/validate_personal_memory_host_binding_contract.rb
PASS personal memory host binding contract validation

ruby scripts/validate_personal_memory_contract.rb
PASS personal memory contract validation

all validators: 39 / 39 PASS
git diff --check: clean
```

## 7. 交付量測

- Host Binding contract：+134 行
- 共用 evaluator：167 行
- validator：264 行
- fixture：209 行
- aggregator wiring：+1 行
- 合計約 **775 行**，落在開工前估計 760–1,060 行內。

## 8. 不在本片

- 不寫正式 installer / doctor；
- 不改真人 user config；
- 不做 cross-host 真人測試；
- 不建立 per-project / per-host store；
- 不新增 scope vocabulary、lifecycle、ledger、DB；
- 不接 vendor-native memory fallback；
- Slice 1 另兩筆 P2（`transaction.mode`、`owner_authorization` substring）未碰。

