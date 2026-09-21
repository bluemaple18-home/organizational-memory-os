# frozen_string_literal: true
#
# Personal Inbox / manual capture。
#
# 契約早就宣告了 manual_capture，缺的只是使用面：`write` 只收**已經組好的**
# resource JSON，一般人手上有的是一個 .md 檔。這一層把「一個檔案」翻譯成既有
# 的治理物件鏈，**不新增任何一種資源型別**：
#
#   FILE → managed evidence snapshot → MemorySupportLink → PersonalMemoryCandidate(PROPOSED)
#
# 三件刻意不做的事：
#
#   1. 不直接建 PersonalMemoryRecord。Candidate 是提案，要變成 Record 需要
#      獨立的 record_id、verification receipt 與 personal acceptance——那是人
#      在週五 review 時做的決定，不是匯入的副作用。
#   2. 不旁路 resource evaluator。support link 與 candidate 都走
#      Runtime#write_row，因此與 CLI／MCP 走同一套治理與交易層。
#   3. 缺欄位時不用猜的補。memory_kind 決定這筆記憶的語意，猜錯會讓一筆
#      本來該被 review 的東西安靜地分類錯，所以缺它就回 NEEDS_CANDIDATE_INPUT，
#      snapshot 留著、Candidate 不生成。

require "time"
require_relative "evidence_snapshot"
require_relative "runtime"

module OMOS
  module Inbox
    # 身分缺失與「內容有問題」是兩種失敗：前者是呼叫端沒給夠，後者是檔案
    # 本身不合格。分開才能給出對的修法提示。
    class IdentityRequired < StandardError; end
    class IdentityIncomplete < StandardError; end

    # resolved identity tuple 的形狀驗證。
    #
    # review P2 裁決：receipt lookup 留在 CLI（explicit > receipt > env），
    # 但**驗證下沉到這裡**——未來 MCP 或其他 caller 直接呼叫 Inbox.import
    # 時，不會各寫一套，也不會完全不驗。
    #
    # 驗到什麼程度，以**契約實際宣告的**為準，不自行發明：
    #
    #   employee_owner_ref  common-vocabulary 的 identifiers.omos_generated
    #                       宣告 ref_template "urn:omos:{resource-kind}:{uuid}"，
    #                       所以至少必須是 urn:omos: 開頭、有 kind 與 id 兩段
    #                       的 ref。**不**強制 UUIDv7——既有資料與 fixture 用
    #                       的是 urn:omos:employee:emp-001，強制會把既有安裝
    #                       打掛，而那不是本次 repair 的授權範圍。
    #   tenant_id           契約**沒有**宣告任何 shape（只有
    #                       tenant_id_required: true）。因此這裡只驗「非空、
    #                       不含空白與控制字元」，**不自行發明 tenant regex**。
    #                       真正的 tenant 形狀該由契約決定，見 repair-01 回報。
    OWNER_REF = %r{\Aurn:omos:[a-z0-9][a-z0-9-]*:[^\s:][^\s]*\z}
    TENANT_ID = /\A[^\s[:cntrl:]]+\z/

    MEMORY_KINDS = %w[
      WORK_PREFERENCE WORKING_STYLE DOMAIN_FACT DEFINITION RULE DECISION
      LESSON PROCEDURE PROJECT_CONTEXT RELATIONSHIP_CONTEXT LONG_LIVED_CONSTRAINT
    ].freeze

    # 契約的 not_long_lived_memory_by_default：這些 kind 預設就不該成為長期
    # 記憶，必須 fail closed。匯入是最容易夾帶它們的入口。
    REFUSED_KINDS = %w[
      CURRENT_TASK_STATUS ONE_OFF_COMMAND_OUTPUT TRANSIENT_OPEN_LOOP
      TEMPORARY_BRANCH_OR_WORKTREE_STATE RUNTIME_COMPLETION_MESSAGE
      UNVERIFIED_MODEL_SUGGESTION SHORT_LIVED_SCHEDULE
    ].freeze

    # Candidate 的 content 只放**來源的可讀摘錄**，不放模型摘要——契約明寫
    # model_summary_as_support: forbidden。這裡取原文前若干字元，並在截斷時
    # 說清楚它被截斷了，免得看的人以為那就是全文。
    EXCERPT_LIMIT = 800

    module_function

    def validate_identity!(owner_ref, tenant_id)
      unless owner_ref.is_a?(String) && OWNER_REF.match?(owner_ref)
        raise EvidenceSnapshot::Rejected.new(
          "INBOX_OWNER_REF_MALFORMED",
          "#{owner_ref.inspect}；須為 urn:omos:<kind>:<id> 形式（契約 ref_template）"
        )
      end
      return if tenant_id.is_a?(String) && TENANT_ID.match?(tenant_id)

      raise EvidenceSnapshot::Rejected.new("INBOX_TENANT_ID_MALFORMED", tenant_id.inspect)
    end

    def import(runtime, store_path, source_path, memory_kind: nil, owner_ref:, tenant_id:,
               surface: Runtime::SURFACES[:cli], now: Time.now.utc)
      # 身分與 kind 的檢查都在 capture **之前**：打錯字或夾帶一個預設不長存的 kind，
      # 都不該讓內容先被收進來。缺 kind（還沒決定）與 kind 錯誤（決定錯了）
      # 是兩回事——前者保留 snapshot 等使用者補，後者連收都不收。
      validate_identity!(owner_ref, tenant_id)

      kind = memory_kind.nil? ? nil : memory_kind.to_s.strip.upcase
      unless kind.nil? || kind.empty?
        if REFUSED_KINDS.include?(kind)
          raise EvidenceSnapshot::Rejected.new("INBOX_MEMORY_KIND_NOT_LONG_LIVED", kind)
        end
        unless MEMORY_KINDS.include?(kind)
          raise EvidenceSnapshot::Rejected.new("INBOX_MEMORY_KIND_UNKNOWN",
                                               "#{kind}；可用：#{MEMORY_KINDS.join(", ")}")
        end
      end

      envelope, snapshot_replayed =
        EvidenceSnapshot.capture(store_path, source_path, owner_ref: owner_ref,
                                                         tenant_id: tenant_id, now: now)
      digest = envelope.fetch("content_sha256")

      if kind.nil? || kind.empty?
        return { status: "NEEDS_CANDIDATE_INPUT", evidence_ref: envelope["evidence_ref"],
                 content_sha256: digest, snapshot_replayed: snapshot_replayed,
                 detail: "缺 memory_kind；evidence snapshot 已保留，補上 --memory-kind 後重跑即可" }
      end

      link_id = EvidenceSnapshot.link_ref(digest)
      candidate_id = EvidenceSnapshot.candidate_ref(digest)

      # 先寫 support link，再寫 candidate。順序是被契約決定的：candidate 的
      # support_link_refs 必須解析到 store 裡**已經存在**、且 target_ref 指回
      # 自己的 link，反過來寫會被 evaluator 當場擋下。
      link = runtime.write_row(kind: "MemorySupportLink",
                               resource: link_body(link_id, candidate_id, envelope),
                               idempotency_key: "inbox-link-#{digest}", surface: surface)
      cand = runtime.write_row(kind: "PersonalMemoryCandidate",
                               resource: candidate_body(candidate_id, link_id, envelope,
                                                        kind, store_path),
                               idempotency_key: "inbox-candidate-#{digest}", surface: surface)

      { status: "CANDIDATE_PROPOSED", candidate_id: candidate_id, link_id: link_id,
        evidence_ref: envelope["evidence_ref"], content_sha256: digest,
        snapshot_replayed: snapshot_replayed,
        replayed: link[:replayed] && cand[:replayed] }
    end

    def link_body(link_id, target_ref, envelope)
      { "link_id" => link_id,
        "tenant_id" => envelope.fetch("tenant_id"),
        "employee_owner_ref" => envelope.fetch("employee_owner_ref"),
        "target_ref" => target_ref,
        "evidence_ref" => envelope.fetch("evidence_ref"),
        "source_anchor_ref" => envelope.fetch("source_anchor_ref"),
        "source_anchor_profile" => envelope.fetch("source_anchor_profile"),
        "relation" => "SUPPORTS",
        "anchor_resolution" => "EXACT_MATCH",
        "provenance" => { "created_by" => envelope.fetch("employee_owner_ref"),
                          "created_at" => envelope.fetch("captured_at") } }
    end

    # review P1-2：chronology.created_at 原本吃呼叫端當下的 now，於是同一份
    # 內容隔幾秒再匯入就算出不同的 canonical，撞上 PMR_IN_PLACE_ROW_OVERWRITE。
    # 原本的「連跑 3 次」全落在同一秒，所以假綠。
    #
    # 正確的時間是**第一次 capture 的時間**，它存在 envelope 裡而且重放時
    # 直接沿用——與 id 一樣，同樣的輸入本來就該算出同樣的東西。
    def candidate_body(candidate_id, link_id, envelope, memory_kind, store_path)
      { "candidate_id" => candidate_id,
        "tenant_id" => envelope.fetch("tenant_id"),
        "employee_owner_ref" => envelope.fetch("employee_owner_ref"),
        "memory_kind" => memory_kind,
        "content" => { "statement_or_structured_content" => excerpt(store_path, envelope) },
        "applicability" => { "scope_mode" => "EMPLOYEE_PRIVATE",
                             "applies_to_refs" => [envelope.fetch("evidence_ref")] },
        "validity_interval" => { "effective_from" => envelope.fetch("captured_at") },
        "support_link_refs" => [link_id],
        "provenance" => { "generated_from_refs" => [envelope.fetch("evidence_ref")],
                          "proposed_by" => envelope.fetch("employee_owner_ref") },
        # 匯入**不做** verification、也**不做** acceptance：兩者都停在「還沒跑」
        # 的狀態。把它們填成 PASS/ACCEPTED 就是把提案偽裝成已驗收的記憶。
        "governance" => { "ownership_mode" => "EMPLOYEE_OWNED",
                          "visibility_scope" => "EMPLOYEE_PRIVATE",
                          "sensitivity" => "NORMAL",
                          "acl_ref" => "urn:omos:acl:employee-private",
                          "verification_status" => "NOT_RUN",
                          "acceptance_status" => "PENDING" },
        "chronology" => { "created_at" => envelope.fetch("captured_at") },
        "candidate_status" => "PROPOSED" }
    end

    def excerpt(store_path, envelope)
      path = File.join(EvidenceSnapshot.dir_for(store_path, envelope.fetch("content_sha256")),
                       EvidenceSnapshot::BYTES)
      text = File.binread(path).force_encoding(Encoding::UTF_8).strip
      return text if text.length <= EXCERPT_LIMIT

      "#{text[0, EXCERPT_LIMIT]}…（節錄自 #{envelope.dig("origin", "original_filename")}；" \
        "全文見 evidence snapshot #{envelope.fetch("content_sha256")[0, 12]}）"
    end

    # inbox list 的資料一律由既有事實重算：snapshot 目錄 ＋ store 裡的 row。
    # 不新增 inbox table——多一張表就多一份會漂移的狀態。
    def entries(runtime, store_path, surface: Runtime::SURFACES[:cli])
      rows = runtime.read_rows(surface: surface)
      candidates = rows.select { |r| r[:kind] == "PersonalMemoryCandidate" }
                       .to_h { |r| [r[:row_id], r[:resource]] }

      EvidenceSnapshot.list(store_path).map do |env|
        digest = env.fetch("content_sha256")
        cid = EvidenceSnapshot.candidate_ref(digest)
        cand = candidates[cid]
        { "content_sha256" => digest,
          "original_filename" => env.dig("origin", "original_filename"),
          "captured_at" => env["captured_at"],
          "evidence_verifiable" => EvidenceSnapshot.verifiable?(store_path, digest),
          "candidate_id" => cand ? cid : nil,
          "memory_kind" => cand && cand["memory_kind"],
          "candidate_status" => cand ? cand["candidate_status"] : "NEEDS_CANDIDATE_INPUT" }
      end
    end
  end
end
