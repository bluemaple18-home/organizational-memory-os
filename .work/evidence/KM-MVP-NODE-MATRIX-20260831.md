# KM MVP 工程甬道：節點證據矩陣

- authority SHA：`91610b249041956f3e004e378c30a6600221a33d`
- use case：Tenant 0「廣告投放排查」
- maturity axis：`MVP / NEXT / NORTH STAR`；不得與 `P0/P1/P2` 或 `L1-L4` 混用。
- reading rule：每個節點都含 UI Worker 必填欄位；`UNKNOWN` 代表 authority 尚未選型或定量，不能由視覺稿補成產品承諾。
- invariant：`Evidence != Candidate != Canonical`、`EXECUTED != VERIFIED != ACCEPTED`、`Permission-before-Retrieval`、`Proposal != Canonical Write`。

## 視覺資料模型

UI 應把 `N01 → N15` 畫成主甬道，把 `R01` 畫成橫跨全程的治理軌；`L-CORRECTION` 從 `N14` 經 `N15` 回到 `N06`，不得回寫或覆蓋 `N03`。節點常駐顯示 `id / title / phase / owner / control badges`；Hover、Focus、Tap 展開本文件其餘欄位。

控制 badge 固定四種：

- `D`：deterministic gate
- `H`：human authority / approval
- `A?`：Agent Team 只在條件成立時啟動，不是常駐 topology
- `↺`：bounded loop；詳見全域 Loop 表

## 節點索引

| ID | 節點 | Phase | 主責任 | 控制 badge |
|---|---|---|---|---|
| N01 | 文件／Jira 來源入口 | MVP | Source owner / connector operator | H |
| N02 | Source Adapter／Evidence Admission | MVP | Evidence ingestion service | D |
| N03 | Raw Evidence＋Provenance | MVP | Evidence authority | D |
| N04 | Normalize／Parse／Validate | MVP | Parser worker | D |
| N05 | Atomic Extraction／Object Linking／Work Record | MVP | Object / Work Context service | D |
| N06 | Knowledge Candidate／Staging Queue | MVP | Knowledge staging service | D, ↺ |
| N07 | Evidence／Conflict／Domain Review | MVP | Domain reviewer | H, A? |
| N08 | Required／Actual Verification | MVP | Evaluation service＋reviewer | D, H, A? |
| N09 | Acceptance／Promotion Gate | MVP | Authorized approver / governance | D, H, ↺ |
| N10 | Canonical Single Writer | MVP | Canonical knowledge writer | D |
| N11 | Canonical Knowledge | MVP | Knowledge authority | D |
| N12 | Rebuildable Projection／Hybrid Index | MVP | Projection builder | D |
| N13 | Permission-first Bounded Retrieval | MVP | Authz＋retrieval policy service | D |
| N14 | Answer／API／Outline＋Citation／Trace | MVP | Delivery service | D, H |
| N15 | Evaluation Failure／Correction／Revision Candidate | MVP | User / domain owner＋governance | H, ↺ |
| R01 | Identity／ACL／Provenance／Chronology 治理軌 | MVP | Tenant identity / permission / evidence authority | D |

## 逐節點矩陣

### N01 — 文件／Jira 來源入口

- `phase`：MVP；Outlook／Teams 是 NEXT source tranche。
- `technology`：文件 upload／import；Jira Cloud REST v3 或已封版本的 Jira Data Center REST。Webhook 只列 NEXT，且不能取代 reconciliation。文件 parser 不在本節點執行。
- `input`：Jira Issue／Comment／Attachment／Changelog／Worklog／Link、ADF；SOP／既有文件原檔；來源 tenant、instance、native ID、版本與來源 ACL。
- `output`：source fetch result / uploaded bytes＋source metadata；尚未是 Evidence 或 Knowledge。
- `owner`：Source owner 授權；connector operator 執行。
- `agent_team_required`：否；資料取得與授權沒有 bounded fan-out 的必要。
- `agent_team_why`：多 Agent 不增加來源真實性，反而可能模糊 credential 與 source authority。
- `hook_event`：MVP 無 runtime hook；人工 upload 或明示 batch pull。NEXT 可接 Jira webhook／source change event，只觸發 capture request。
- `hook_why`：hook 只縮短偵測延遲，不得宣告 ingestion、verification 或 acceptance 成功。
- `loop_type_bounds`：`L-CAPTURE`；每個明示來源版本形成一個 capture attempt。自動 retry cap=`UNKNOWN`，未定前 fail-loud、不得無限重試。
- `deterministic_gate`：connector grant、source identity tuple、版本／ETag、media type、payload 可讀性與 ACL snapshot 必填。
- `human_approval`：初次 connector grant、capture scope 與敏感來源納入。
- `failure_stop_rollback`：401/403、來源不存在、版本未知或 payload 不完整即停止 admission；不產生假 Evidence；撤銷 connector 不刪歷史 receipt。
- `evidence`：fetch/upload receipt、source version、permission snapshot、raw payload digest；[A1:15-19]、[A5:84-97]。

### N02 — Source Adapter／Evidence Admission

- `phase`：MVP。
- `technology`：同一 Raw Evidence contract；JSON Schema 2020-12；UUIDv7；SHA-256；CloudEvents 只可作 transport envelope；Jira adapter mapping 的實作語言／framework=`UNKNOWN`。
- `input`：N01 source result＋tenant／source instance／entity type／native ID／source version／ACL。
- `output`：validated admission command 或 rejected receipt；準備建立 `RawEvidenceEnvelope`。
- `owner`：Evidence ingestion service；不由 parser、LLM 或 Agent Runtime 擁有 authority。
- `agent_team_required`：否。
- `agent_team_why`：identity、hash、schema、ACL propagation 都應 deterministic first。
- `hook_event`：`source.capture.requested` 可作產品內 neutral event 名稱，但 authority 未封 event vocabulary，故 UI 標 `event seam / name UNKNOWN`；不得冒充 runtime-native hook。
- `hook_why`：只解耦 adapter 與 admission；事件本身不等於 Evidence persisted。
- `loop_type_bounds`：`L-CAPTURE`；以 `(tenant, source_system, source_instance, entity_type, native_id, source_version/payload_digest)` 做冪等。retry cap=`UNKNOWN`，collision 直接停。
- `deterministic_gate`：schema、required fields、identity separation、raw digest、chronology、ACL snapshot、idempotency check。
- `human_approval`：正常既授權來源不需逐筆；identity collision、scope/permission ambiguity 必須人工裁決。
- `failure_stop_rollback`：驗證失敗寫 reject receipt；不可降格成自由文字繼續；重跑同一 input 必須不重複 admission。
- `evidence`：admission receipt、schema validation report、idempotency result、digest；[A2:72-80]、[A4:115-145]、[A5:19-25,62-64]。

### N03 — Raw Evidence＋Provenance

- `phase`：MVP。
- `technology`：RawEvidenceEnvelope；append-only chronology pattern；SHA-256 raw digest；RFC 8785 JCS 可選 canonical digest；W3C PROV vocabulary；OpenLineage activity vocabulary。Evidence store／object store 產品=`UNKNOWN`。
- `input`：N02 validated admission payload。
- `output`：immutable `evidence_id`、payload／payload_ref、source/version、occurred/observed/received/persisted timestamps、ACL snapshot、provenance chain。
- `owner`：Evidence authority。
- `agent_team_required`：否。
- `agent_team_why`：保存與溯源是 deterministic contract，Agent 只可能是 producer。
- `hook_event`：持久化成功後可發薄通知供 parser 消費；event name=`UNKNOWN`。通知遺失不得等於 Evidence 遺失。
- `hook_why`：只推進 downstream work，不取得 lifecycle authority。
- `loop_type_bounds`：不做內容修訂 loop；同 source 新版本新增 Evidence。重放由 idempotency key 限定。
- `deterministic_gate`：raw digest、identity uniqueness、timestamp format、ACL/provenance 欄位齊全、payload retention state 合法。
- `human_approval`：一般無；retention/legal hold／來源刪除例外需 policy owner。
- `failure_stop_rollback`：部分寫入必須 transaction rollback；已持久化 Evidence 不因下游失敗刪除；來源撤銷以狀態／tombstone 表達。
- `evidence`：persist receipt、checksum、provenance/ACL snapshot；[A2:72-80]、[A4:101-114]、[A5:19-24]。

### N04 — Normalize／Parse／Validate

- `phase`：MVP。
- `technology`：Docling Core pinned commit `dedc35...` 作 normalized provenance donor；輕量文件可評估 MarkItDown；Apache Tika／Unstructured 只作 fallback prior art；JSON Schema validator。實際 MVP parser 組合=`UNKNOWN`。
- `input`：N03 Evidence payload/ref＋media type＋source anchor context。
- `output`：NormalizedDocument、blocks、tables/images/formula/code、SourceAnchor、parser/extraction receipt、quality gaps。
- `owner`：Parser worker；Evidence authority 保留 source truth。
- `agent_team_required`：否。
- `agent_team_why`：parser execution、format routing、required-field validation 優先 deterministic；多 parser fallback 不等於 Agent Team。
- `hook_event`：N03 post-persist notification 可排入 parser job；只傳 refs，不傳未授權全文到任意 runtime。
- `hook_why`：避免 ingestion synchronous coupling；不做語意判斷。
- `loop_type_bounds`：parser fallback chain 必須固定且有限；實際順序／cap=`UNKNOWN`，未封前不得自動巡迴所有 parser。
- `deterministic_gate`：parser exit、block/schema validation、normalized digest、anchor range、coverage／quality gap receipt。
- `human_approval`：OCR／表格／anchor 品質不足且影響候選時人工判斷是否可繼續。
- `failure_stop_rollback`：產出 `PARTIAL/FAIL`，不得冒充 PASS；刪除可重建 normalized artifact，保留 Raw Evidence 與 receipt。
- `evidence`：parser receipt、schema report、checksums、quality gaps；[A2:12-16]、[A5:7-10,64]、[A6:1.1-1.2]。

### N05 — Atomic Extraction／Object Linking／Work Record

- `phase`：MVP。
- `technology`：deterministic exact link／ID rules＋bounded model 做 claim extraction、semantic classification、ambiguous linking；OCEL 2.0／DayTrail pattern 可作 object-link prior art；model/provider=`UNKNOWN`。
- `input`：N04 blocks／anchors＋既有 Jira、Client、Order、Project、Thread、Person objects。
- `output`：Assertions、EvidenceLinks、ObjectLinkAssertions、WorkRecord projection、0..N Knowledge Candidates 的原料。
- `owner`：Object / Work Context service；ambiguity 由 domain reviewer 裁決。
- `agent_team_required`：否；單一 bounded extractor 足夠。
- `agent_team_why`：只有 conflict／low-confidence 升級到 N07 才可能有獨立 counter-evidence，不能把每次 extraction 變 team。
- `hook_event`：N04 completion receipt 可 enqueue extraction；不得把 parser completed 映射成 candidate accepted。
- `hook_why`：薄 orchestration；語意輸出仍須驗證。
- `loop_type_bounds`：屬 `L-CONSOLIDATION`；一個 evidence revision 一次主 extraction；model retry cap=`UNKNOWN`，低信心改送人工而非無限重試。
- `deterministic_gate`：每 assertion 必須有 exact evidence/source-anchor ref；object link status／score reason；WorkRecord 可重建。
- `human_approval`：ambiguous link、跨 tenant/scope link、關鍵 claim 分類不明。
- `failure_stop_rollback`：找不到 anchor 不產出可 promotion claim；刪除 derived extraction 可由 N03/N04 重建；不改 Raw Evidence。
- `evidence`：extraction receipt、model/rule version、link reasons、anchor resolution；[A2:16-18,90-94]、[A3:72-76,93-99]、[A5:32-33]。

### N06 — Knowledge Candidate／Staging Queue

- `phase`：MVP。
- `technology`：OMOS-KNOWLEDGE candidate contract；JSON Schema；durable staging/queue 的 datastore／broker=`UNKNOWN`，不可因前圖寫了 Queue 就建立第二套 runtime/FSM。
- `input`：N05 assertions／links／WorkRecord＋scope、applicability、freshness、provenance、ACL。
- `output`：versioned Candidate / Mutation Proposal，狀態 `PENDING`，進 staging worklist。
- `owner`：Knowledge staging service；Candidate owner / domain owner 可補資料。
- `agent_team_required`：否。
- `agent_team_why`：排程與持久化是 mechanics；Candidate 不是 Agent-owned truth。
- `hook_event`：candidate persisted 後可通知 review worklist；不得由 hook 自動 promotion。
- `hook_why`：建立待辦，不取代 verification/acceptance。
- `loop_type_bounds`：`L-CONSOLIDATION` 與 `L-CORRECTION` 的重新入口；每次修正建新 revision，不原地抹除歷史。
- `deterministic_gate`：required fields、candidate/canonicality enum、evidence support、ACL/scope、revision/supersedes chain、duplicate key。
- `human_approval`：候選建立可自動；scope 擴張或敏感性降級要人工。
- `failure_stop_rollback`：缺 support／scope／owner 留在 rejected/blocked staging；可撤銷候選 revision，不碰 Evidence。
- `evidence`：candidate manifest、validation report、staging transition receipt；[A2:18-24,82-88]、[A3:13-17]、[A6:1.3]。

### N07 — Evidence／Conflict／Domain Review

- `phase`：MVP；conditional Agent Team 是 NEXT escalation，不是 MVP happy path。
- `technology`：conflict taxonomy／rule checks＋review UI；bounded LLM 可做 conflict interpretation／summary；review tool 與 model=`UNKNOWN`。
- `input`：N06 Candidate、support/contradict evidence、scope/time/source-authority/freshness metadata。
- `output`：review findings、conflict resolution proposal、qualified scope/time、counter-evidence request 或 ready-for-verification。
- `owner`：Domain reviewer；模型只能 advisory。
- `agent_team_required`：正常否；High Risk、Conflict、Low Confidence、Evidence disagreement 時可條件式啟動。
- `agent_team_why`：此處存在可獨立責任：primary evidence review 與 counter-evidence search；只有其獨立輸出可合併時才值得 fan-out。
- `hook_event`：candidate-ready 通知只建立 review item；review completed 只產 receipt，不直寫 acceptance。
- `hook_why`：防止 callback 把模型／reviewer「做完」誤當 governance decision。
- `loop_type_bounds`：`L-CONSOLIDATION`；conditional team fan-out branches/cycle cap=`UNKNOWN`，未定即維持單 reviewer＋人工；結果回 N06 補候選或進 N08。
- `deterministic_gate`：evidence links 可解析、conflict type/resolution enum、所有 finding disposition、reviewer identity。
- `human_approval`：domain meaning、source authority、scope/time qualification、insufficient evidence。
- `failure_stop_rollback`：衝突未解不得 promotion；保留多版本或標 insufficient evidence；撤銷 review proposal 不動 Candidate history。
- `evidence`：review receipt、conflict set、counter-evidence refs、disposition；[A2:20-26]、[A3:117-125]、[A4 common enums conflict]。

### N08 — Required／Actual Verification

- `phase`：MVP；Multi-Agent Evaluation 是 NEXT / P1-B escalation。
- `technology`：fixture/test/eval harness；DeepEval 可作 prior art但產品採用=`UNKNOWN`；verification receipt schema 與 deterministic validators 必須存在。
- `input`：N07 reviewed Candidate＋Required Verification plan＋test/eval fixtures。
- `output`：Actual Verification receipt：`PASS/FAIL/PARTIAL/NOT_RUN/STATIC_ONLY`，含 coverage 與 evidence refs。
- `owner`：Evaluation service 執行；human reviewer 對語意／風險項覆核。
- `agent_team_required`：正常否；高風險／證據分歧可條件式 second evaluator／counter-evidence reviewer。
- `agent_team_why`：只在獨立評估能降低 correlated error 時使用；多數 deterministic schema/test 不需 team。
- `hook_event`：verification job completion 只寫 immutable receipt；不得發 direct ACCEPTED。
- `hook_why`：強制保留 `EXECUTED != VERIFIED != ACCEPTED`。
- `loop_type_bounds`：失敗進 N15；同 Candidate revision 的 evaluator retry cap=`UNKNOWN`，不得用重跑洗成 PASS。
- `deterministic_gate`：required vs actual coverage、status enum、fixture identity/version、PARTIAL/NOT_RUN 不得 aggregate PASS。
- `human_approval`：高影響 procedure、衝突裁決、machine metric 無法覆蓋的 domain acceptance。
- `failure_stop_rollback`：FAIL/PARTIAL/NOT_RUN 阻擋 N09；receipt append-only；模型自評不得硬改 status。
- `evidence`：verification plan/receipt、fixture outputs、coverage map；[A1:48-50]、[A2:138-148]、[A3:27-37]、[A5:17]。

### N09 — Acceptance／Promotion Gate

- `phase`：MVP。
- `technology`：policy/rule gate＋immutable Governance Decision / AcceptanceReceipt；OpenFGA/OPA/Cerbos 哪一套承擔檢查=`UNKNOWN`，不可三套並建；approval UI=`UNKNOWN`。
- `input`：N06 Candidate、N07 review disposition、N08 verification receipt、permission/scope decision。
- `output`：`ACCEPTED/REJECTED/BLOCKED/PENDING` AcceptanceReceipt；ACCEPTED 才產 canonical mutation command。
- `owner`：Authorized human approver / governance authority；service 只 enforce prerequisites。
- `agent_team_required`：否。
- `agent_team_why`：多數票不等於 authority；Agent 不可持有 acceptance authority。
- `hook_event`：approval action 可觸發 mutation command；任何 runtime `TaskCompleted/turn.completed` 不得映射 ACCEPTED。
- `hook_why`：只在已驗證的人類／治理決策後推進 Single Writer。
- `loop_type_bounds`：`L-PROMOTION`；每個 Candidate revision 一次決策；REJECT/BLOCK 回 N06/N15，重新提交必須新 revision 或補 evidence。
- `deterministic_gate`：Permission＋Verification PASS/required coverage＋Review disposition＋Approver authority；不符合即 fail closed。
- `human_approval`：必須；尤其 scope promotion、敏感性與 conflict resolution。
- `failure_stop_rollback`：拒絕不刪 Candidate/Evidence；錯誤決策以新 decision/supersession 修正，不修改舊 receipt。
- `evidence`：AcceptanceReceipt、policy decision ref、approver identity、decision timestamp；[A1:40-53]、[A3:33-43]、[A5:142-159]。

### N10 — Canonical Single Writer

- `phase`：MVP。
- `technology`：單一 authoritative write service／transaction boundary；canonical datastore=`UNKNOWN`；idempotency、optimistic concurrency、audit receipt 必須 deterministic。
- `input`：N09 accepted mutation command＋Candidate revision＋Acceptance/Verification/Permission refs。
- `output`：CanonicalWriteReceipt＋canonical resource revision／supersession relation。
- `owner`：Canonical Knowledge Writer；唯一寫入權限。
- `agent_team_required`：否。
- `agent_team_why`：fan-out writer 破壞 single-writer invariant。
- `hook_event`：canonical committed 後可發 projection rebuild request；事件不能先於 transaction commit。
- `hook_why`：下游 projection 解耦，且只有 receipt 可證明正式寫入。
- `loop_type_bounds`：不做 autonomous retry loop；冪等重送只接受相同 mutation key。concurrency conflict 停止並回 governance。
- `deterministic_gate`：valid accepted receipt、writer identity、expected revision、mutation idempotency、transaction commit。
- `human_approval`：寫入本身不再重複審批；其 authority 來自 N09 receipt。
- `failure_stop_rollback`：transaction rollback；若已 commit，後續更正走新 mutation/supersession，禁止覆寫歷史。
- `evidence`：CanonicalWriteReceipt、transaction/mutation ID、before/after revision；[A2:24-33]、[A3:39-43]。

### N11 — Canonical Knowledge

- `phase`：MVP。
- `technology`：OMOS-KNOWLEDGE／PROCEDURE contract；canonical store 產品=`UNKNOWN`；Markdown/Outline 只是 human view，不是唯一 machine truth。
- `input`：N10 committed canonical revision。
- `output`：Canonical Knowledge／Claim／Relation／Procedure relation＋lifecycle/version/supersession。
- `owner`：Knowledge authority / domain owner；只有 N10 可 mutate。
- `agent_team_required`：否。
- `agent_team_why`：正式知識是 domain state，不是 Agent shared blackboard。
- `hook_event`：committed revision 可通知 N12 build；不得讓 projection callback 回寫 canonical。
- `hook_why`：維持 canonical/projection 邊界。
- `loop_type_bounds`：lifecycle 變更皆走 proposal→verification→acceptance→writer；無直接自循環。
- `deterministic_gate`：canonicality、revision chain、evidence/acceptance/write receipt refs、owner/ACL/lifecycle 欄位。
- `human_approval`：新知識及重大修訂已由 N09 核准；archive/supersede 仍需相應 authority。
- `failure_stop_rollback`：projection 失敗不回退 canonical truth；錯誤知識以 N15 revision 修正。
- `evidence`：canonical manifest、checksums、write/acceptance refs；[A2:28-39,125-136]、[A6:1.3-1.5]。

### N12 — Rebuildable Projection／Hybrid Index

- `phase`：MVP（最小 chunk/search/vector projection）；Knowledge Graph／impact views 是 NEXT/NORTH STAR。
- `technology`：chunk/search index＋embedding/vector；Qdrant 可作 hybrid retrieval prior art；Outline 可作正式 consumption view；embedding/reranker/index datastore=`UNKNOWN`。
- `input`：N11 canonical revision＋projection config/version＋ACL/scope metadata。
- `output`：rebuildable chunks、vector/search documents、Outline/FAQ view、ProjectionManifest/build receipt。
- `owner`：Projection builder；不得取得 Knowledge authority。
- `agent_team_required`：否。
- `agent_team_why`：chunk、embed、index、rebuild 是 deterministic/bounded worker pipeline。
- `hook_event`：canonical committed→projection build request；source deletion/permission change 可請求 invalidation/rebuild，是否 MVP 自動化=`UNKNOWN`。
- `hook_why`：projection 是 derived cache，可非同步重建。
- `loop_type_bounds`：build/rebuild 依單一 canonical revision；automatic retry cap=`UNKNOWN`，達 cap 停並標 stale/unavailable，不回寫 N11。
- `deterministic_gate`：source canonical revision、build config/model version、checksum、ACL payload/filter completeness、index parity。
- `human_approval`：換 embedding/ranking 模型需 change approval；單次重建不需內容審批。
- `failure_stop_rollback`：保留上一個健康 projection 或 fail unavailable；可刪除重建；絕不可把 vector DB 當 canonical DB。
- `evidence`：ProjectionManifest、build receipt、index counts/checksums、model/config version；[A2:35-39,96-107]、[A3:78-91]、[A5:14]。

### N13 — Permission-first Bounded Retrieval

- `phase`：MVP。
- `technology`：Identity→Role/Group/Scope→Managed Policy Floor→Authorized Retrieval Space→hybrid filter→Context Budget；OpenFGA 是 ReBAC prior art、OPA/Cerbos 是 policy alternatives，最終選型=`UNKNOWN`。
- `input`：requester identity/scope/capability、intent/domain、context budget、N12 projection metadata。
- `output`：authorized bounded context＋permission decision ref＋omitted/gap notice＋budget usage。
- `owner`：Tenant identity/permission authority＋Retrieval Policy service。
- `agent_team_required`：否；Normal Query 固定 single authorized retrieval。
- `agent_team_why`：Agent/LLM 不能是 permission enforcement boundary；先過 filter 才可看內容。
- `hook_event`：query request 是 API call，不是 lifecycle hook；可發 telemetry receipt，但不可洩露 rejected content。
- `hook_why`：觀測成本／錯誤，不做授權決策。
- `loop_type_bounds`：retrieval expansion 最多受 context budget／result cap 約束；具體 token/result cap=`UNKNOWN`，未封 contract 前不得無界擴搜。
- `deterministic_gate`：authorization filter before vector/graph/keyword access、tenant isolation、freshness/source routing、budget enforcement。
- `human_approval`：正常查詢依既有 policy；例外存取／scope 擴張需 permission authority。
- `failure_stop_rollback`：authz error fail closed；budget exhausted 回 gap/omission；不得先 retrieve 再讓 LLM 過濾。
- `evidence`：permission decision、retrieval trace（只含允許 refs）、budget usage、filter test；[A2:109-123]、[A3:19-25,101-105]、[A5:11-16]。

### N14 — Answer／API／Outline＋Citation／Trace

- `phase`：MVP。
- `technology`：Internal Web API＋Q&A Bot；Outline 作正式消費面；bounded answer model＋citation verifier；API framework、LLM、citation engine=`UNKNOWN`。
- `input`：N13 authorized bounded context＋user query／排查 intent。
- `output`：PM/RD answer/action guidance＋citations/source refs＋AnswerTrace＋confidence/gap notice。
- `owner`：Delivery service；使用者／domain owner 消費與回饋。
- `agent_team_required`：正常否；High Risk／Low Confidence／Evidence disagreement 才可 NEXT escalation 到 second retrieval/reviewer。
- `agent_team_why`：一般問答用 single retrieval＋answer＋citation verification；team 不是預設 topology。
- `hook_event`：answer delivered／feedback submitted 可產 usage/evaluation evidence；不自動改知識。
- `hook_why`：記錄實際使用與觸發 N15，不具 correction/write authority。
- `loop_type_bounds`：單 request 有 context/token/time cap=`UNKNOWN`；second retrieval branch/cycle cap=`UNKNOWN`，未封前 MVP 不啟用 team escalation。
- `deterministic_gate`：所有 material claim citation 必須指向 N13 allowed refs；trace 保存 `evidence_refs_used_at_execution` 與時間戳；API schema/tenant check。
- `human_approval`：排查答案預設由人判斷是否採取外部 action；此 MVP 不授權 Bot 自動執行投放變更。
- `failure_stop_rollback`：無 citation／低 confidence 顯示 gap、不杜撰；answer 是 response，不改 canonical；錯誤送 N15。
- `evidence`：AnswerTrace、citations、permission ref、model/config version、usage/feedback receipt；[A1:31-35]、[A2:45-54,78-80,82-88]、[A3:117-125]。

### N15 — Evaluation Failure／Correction／Revision Candidate

- `phase`：MVP。
- `technology`：feedback/evaluation receipt、CorrectionProposal、version/supersession contract；修正 UI 與 datastore=`UNKNOWN`。
- `input`：使用者指出錯誤、N14 feedback、N08/N14 evaluation failure、新 Evidence refs。
- `output`：CorrectionProposal／Revision Candidate＋supersedes relation，回 N06 重走 review→verification→acceptance→single writer。
- `owner`：User/domain owner 提出；governance 驗證與接受。
- `agent_team_required`：否；若錯誤伴隨多來源衝突，可在 N07 條件式啟動 counter-evidence team。
- `agent_team_why`：修正提案本身不需要 team，且 team 不可繞過人類接受。
- `hook_event`：explicit `feedback submitted`／evaluation FAIL 可建立 correction work item；不得直接修改 Canonical。
- `hook_why`：把錯誤變成可追蹤工作，不把 telemetry 當 truth。
- `loop_type_bounds`：`L-CORRECTION`；每次只處理一個明示 correction revision，自動 retry=0；每輪停在 N09 human approval。可由人再次開新輪，但沒有常駐自動循環。
- `deterministic_gate`：correction evidence ref、target canonical revision、reason、proposed change、supersedes chain、verification requirement。
- `human_approval`：每一輪 N09 必須重新核准。
- `failure_stop_rollback`：證據不足標 BLOCKED，不覆寫舊知識；若修正被拒保留既有 canonical；成功以 supersession 保留歷史。
- `evidence`：CorrectionProposal、new evidence refs、new verification/acceptance/write receipts；[A1:34-35,48]、[A2:53-54,125-136]、[A4:303-309]。

### R01 — Identity／ACL／Provenance／Chronology 治理軌

- `phase`：MVP，橫跨 N01-N15。
- `technology`：tenant identity、role/group/scope、Managed Policy Floor、ACL snapshots／permission refs、W3C PROV vocabulary、append-only receipts、RFC3339 UTC chronology。產品級 identity/authz/store 選型=`UNKNOWN`。
- `input`：每節點 actor/resource identity、source ACL、timestamps、event/operation refs。
- `output`：可追溯的 permission/provenance/chronology chain；不得形成第二套 truth。
- `owner`：Tenant identity authority、permission authority、Evidence/Knowledge authority 各守其界線。
- `agent_team_required`：否；Agent 是 actor/executor，不是 authority。
- `agent_team_why`：共享 Agent context 不能取代 tenant isolation 或 audit trail。
- `hook_event`：所有 event 先成 immutable receipt 再作 neutral mapping；native event 不可 direct ACCEPTED/CLOSED。
- `hook_why`：保留 native fact 與 domain decision 的分離。
- `loop_type_bounds`：治理軌不自行重試；每個 operation/loop iteration 都產生新的 correlation/revision refs。
- `deterministic_gate`：tenant match、actor authorization、ACL propagation、timestamp/receipt completeness、evidence chronology。
- `human_approval`：policy exception、scope escalation、retention/legal hold、canonical acceptance。
- `failure_stop_rollback`：缺 identity/ACL/provenance fail closed；後補 Evidence 只能觸發新 re-evaluation，不能偽裝成先前 answer 已使用。
- `evidence`：permission decision refs、NativeEvent/Execution/Evaluation receipts、chronology chain；[A2:72-80,109-123]、[A3:19-25]、[A5:142-176]。

## Agent Team 全域邊界

| Team seam | Phase | Trigger | Bounded fan-out / 合併 | Authority／停止條件 |
|---|---|---|---|---|
| AT01 Conflict counter-evidence（N07） | NEXT，MVP 只保留 seam | High Risk、Conflict、Low Confidence、Evidence disagreement | primary review 與 counter-evidence search 為兩個獨立輸出；實際 branch/cycle cap=`UNKNOWN`，未封不得啟用自動 fan-out | Domain reviewer 合併；任一 unresolved P0/conflict 停在人審；Team 不可 acceptance/write |
| AT02 Independent evaluation（N08） | NEXT / P1-B | 高影響 procedure、machine/human 結果衝突、使用者明確要求獨立驗證 | evaluator 與 reviewer 責任分離；branch/cycle cap=`UNKNOWN`，未封不得啟用 | N09 authorized approver 裁決；多數票不等於 PASS/ACCEPTED |
| AT03 Second retrieval／answer review（N14） | NEXT | High Risk／Low Confidence／citation disagreement | second retrieval 只讀 N13 已授權空間；輸出 counter-evidence/citation report | budget 或 unresolved disagreement 即停止、回 gap/human；不得擴權 |

MVP 結論：**沒有任何節點需要常駐 Agent Team。** Agent Team 只在上表條件成立、責任可獨立、輸入輸出可驗證且 bounds 已封之後啟用。不得新增 Multi-Agent Runtime、Mailbox、Agent Room、wake daemon 或 shared blackboard。[A3:117-125]、[A1:71-85]

## Hook 全域邊界

| Hook seam | Phase | 允許事件／資料 | 不允許 |
|---|---|---|---|
| H01 Evidence admitted→parse request（N03→N04） | MVP 可用內部薄 event；名稱 UNKNOWN | IDs、refs、tenant、correlation、receipt；可重播／冪等 | 直接生成 Candidate/Canonical；把通知當持久化證據 |
| H02 Candidate ready→review work item（N06→N07） | MVP | Candidate ref、required review、due/status | 自動 ACCEPTED；把 model confidence 當 verification |
| H03 Canonical committed→projection build（N10→N12） | MVP | CanonicalWriteReceipt ref、revision、projection target | projection 回寫 canonical；commit 前先通知成功 |
| H04 Answer feedback/eval FAIL→correction item（N14→N15） | MVP | AnswerTrace ref、feedback/eval receipt、target revision | 直接覆寫知識；自動 promotion |
| H05 Jira webhook/source change（N01→N02） | NEXT | transport delivery＋reconciliation cursor | 用 webhook 當完整歷史或 evidence identity |
| H06 Runtime-native event→Evidence／Work proposal | NORTH STAR / donor seam | native event→immutable receipt→neutral mapping→proposal | `TaskCompleted/turn.completed → ACCEPTED/CLOSED`；Universal Hook FSM |

所有 Hook 都是「薄事件擷取／通知」，不推理、不做 domain decision、不擁有 lifecycle。至少帶 event/native ID、tenant、occurred/observed/received time、payload/ref、correlation/idempotency key；缺值 fail closed。[A5:20,28,135-176]

## Loop 全域邊界

| Loop | Phase | 路徑 | Bounds | Gate／停止／rollback |
|---|---|---|---|---|
| L-CAPTURE | MVP | N01→N02→N03；需要時 N03→N04 | 每來源版本一個 attempt；冪等；retry cap=`UNKNOWN`，未定前 fail-loud | schema/identity/hash/ACL gate；不合格不產 Evidence；保留 reject receipt |
| L-CONSOLIDATION | MVP | N04→N05→N06→N07；補證據／解衝突回 N06 | 每 Candidate revision 一次 review；model/team retry cap=`UNKNOWN`，低信心轉人工 | unresolved conflict 停；derived artifacts 可重建，Raw Evidence 不變 |
| L-PROMOTION | MVP | N06→N07→N08→N09→N10→N11 | 每 Candidate revision 一次 acceptance decision；重提必須新 revision／新 evidence | Permission＋Verification＋Acceptance＋Single Writer；拒絕保留歷史 |
| L-CORRECTION | MVP | N14/Eval FAIL→N15→N06→…→N11 | 每輪一個 correction revision；自動 retry=0；每輪停在 N09 人核准 | 不能原地覆寫；supersession 可回退到先前有效 revision |
| L-CLOSEOUT | NEXT | WorkRecord→CloseoutProposal→result verification | exact trigger/cap=`UNKNOWN`，MVP 不自動 close | Runtime completed 不等於 work accepted/closed；人或 existing lifecycle 決定 |
| L-PROJECTION-REBUILD | NEXT（MVP 可手動 rebuild） | N10/N11→N12 | 每 canonical revision / config version 一個 build；retry cap=`UNKNOWN` | build failure 不動 canonical；保留上一健康 index或標 unavailable |

Four-loop 名稱只作 domain operation grouping：Capture、Closeout、Consolidation、Promotion，不得實作成四個 Agent／服務／DB／FSM。Correction 是 MVP 業務回圈，仍重用 Consolidation/Promotion authority seam。[A5:178-187]

## MVP／NEXT／NORTH STAR 邊界

### MVP — 這張圖的可驗收主甬道

- 文件＋Jira；共用 Raw Evidence contract。
- N01-N15＋R01；人工 upload/batch 可完成一輪，不依賴 webhook/daemon。
- deterministic-first admission、identity/hash/schema/ACL/permission/gates。
- Candidate staging、domain review、machine/human verification、human acceptance、Single Writer。
- 最小 rebuildable search/vector projection、permission-first bounded retrieval、answer＋citation＋trace。
- 錯誤→CorrectionProposal→新 revision→重新驗證／核准；不覆寫歷史。
- 常駐 Agent Team：無；自動 retry：不得無界，未封 cap 的路徑 fail-loud 或轉人工。

### NEXT — 有 seam，但不得畫成 MVP 已完成

- Outlook／Teams source tranche、Jira webhook＋reconciliation、自動 source monitoring。
- conditional Agent Team：counter-evidence、independent evaluation、second retrieval/reviewer。
- WorkRecord Closeout loop、permission/source change propagation、自動 projection rebuild、較完整 regression。
- Knowledge Graph／reviewer/impact view；確切 datastore/model/runtime 仍需 measured gap 與 admission。

### NORTH STAR — 僅虛線遠景

- continuous stale/conflict/gap monitoring、correction/promotion proposals、成熟 regression/observability。
- Runtime-native event adapter／advanced agent executor；仍只產 receipt/proposal。
- 不自建 Multi-Agent Runtime／Universal Hook FSM／第二套 registry、database、canonical writer 或 authority ledger。

## Agentic Workflow Audit 六項

| 檢查 | 設計判定 | 證據／缺口 |
|---|---|---|
| 1 Task 邊界 | PASS（design） | N01-N15 每步有獨立 I/O、owner、stop；可按 ref 單步執行。runtime implementation 未驗證。 |
| 2 I/O 契約 | PASS（design） | RawEvidence、NormalizedDocument、Candidate、Verification/Acceptance/Write/Projection/Answer receipts 已分離；數個 schema 尚是 DRAFT。 |
| 3 可程式化成功標準 | PARTIAL | 每節點已列 deterministic gate；datastore、parser chain、budget/retry cap、模型與 eval threshold 多處 UNKNOWN，未可宣稱 runtime PASS。 |
| 4 獨立 SOP / Skill | PARTIAL | authority 文件可定位，並非 mega-prompt；逐節點 executable SOP／fixtures 尚未提供。 |
| 5 控制流歸屬 | PASS（design） | 主路由固定、hook 只通知、N09/N10 authority 明確；實際 orchestrator/trace 未驗證。 |
| 6 失敗處理與回退 | PARTIAL | fail-closed、history/supersession、projection rollback 已定；所有 `UNKNOWN` retry cap 在實作前必須封死。 |

- `單步隔離執行`：NOT_RUN；本卡是 architecture evidence matrix，尚無 runtime artifact。
- `憑 trace 重建流程`：NOT_RUN；需 implementation Worker 提供一次 end-to-end run manifest。
- `總體判定`：設計上是拆解式 workflow；runtime 證據不足，不能宣稱已實作或已通過。
- `最高風險`：P1—permission-before-retrieval、single writer、verification/acceptance 若被 UI 或 implementation 合併，會破壞 Truth Boundary。P1—未封 retry/fan-out/budget cap 前啟用自動 loop/team。

## UI Worker 交付約束

1. UI 不得把 `UNKNOWN` 隱藏；以「待選型／待定上限」顯示。
2. 主圖必須在不 Hover 時仍看得到 phase、資料流、`D/H/A?/↺`；Hover／Focus／Tap 顯示逐節點完整欄位。
3. `A?` 只出現在 N07/N08/N14 的 NEXT escalation，且 tooltip 必須說「MVP 不需要常駐 Agent Team」。
4. Hook 畫成細側線或 event port，不得畫成會做審核／決策的 Agent。
5. Loop 用實線顯示 MVP correction；NEXT/NORTH STAR 必須虛線並有 phase legend。
6. N09 與 N10 必須是兩個節點：Acceptance Decision 不等於 Canonical Write。
7. N11 與 N12 必須是兩個節點：Canonical Knowledge 不等於 vector/index/Outline projection。
8. N13 權限 gate 必須在任何 retrieval/LLM 之前；不能畫成答案後過濾。
9. Detail panel 必須支援鍵盤 Focus/Escape、touch Tap、ARIA relation；essential content 不可只靠 Hover。

## Authority 索引

以下皆以唯讀命令 `git -C <authority-repo> show 91610b249041956f3e004e378c30a6600221a33d:<path>` 取得：

- `[A1]` `文件/MVP與優先級.md`：15-35（MVP tranche/vertical loop）、38-85（P0/P1/P2 與 multi-agent/runtime 邊界）。
- `[A2]` `文件/核心知識主幹.md`：5-55（唯一 spine）、57-70（Minimal Core／executor）、72-88（evidence chronology／staging／Outline）、90-123（object/projection/permission）、138-161（verification/executor policy）。
- `[A3]` `文件/架構憲章.md`：5-76（Truth Boundary、deterministic first）、78-105（projection/permission）、117-140（Multi-Agent、AI Core 邊界）。
- `[A4]` `規格/v0.1/personal-harness-integration.yaml`：89-145（pipeline/contracts）、186-215（record minimum）、286-327（recall/correction/promotion）、358-385（runtime/pilot）、413-438（hard stops/negative fixtures）。
- `[A5]` `文件/先例技術來源地圖.md`：7-48（technology donors）、56-97（exact pins/Jira pin policy）、122-198（runtime/hook/loop donor 與 boundaries）。
- `[A6]` `文件/知識庫標準文件規格-v0.1-草案.md`：5（DRAFT/NOT_CANONICAL）、9-35（source→evidence→document→candidate→canonical→projection）、39-60（目的與非目標）、64-124（五個 contract families）。
- `[A7]` 前版 `.work/CARD-KM-MVP-TUNNEL-20260831.md`：來源→Candidate→Review→Gate→Canonical/Retrieval→Q&A/API→人工修正回圈及 NEXT 禁區。

## 完整性檢查

- required node fields：`technology,input,output,owner,agent_team_required,agent_team_why,hook_event,hook_why,loop_type_bounds,deterministic_gate,human_approval,failure_stop_rollback,evidence,phase`。
- 覆蓋結果：N01-N15＋R01 均有 14/14 欄位；未決項均顯式標 `UNKNOWN`。
- SC trace：`SC-KM-01`→逐節點矩陣；`SC-KM-02`→Agent Team/Hook/Loop 三張全域表；`SC-KM-03`→MVP/NEXT/NORTH STAR 邊界。
