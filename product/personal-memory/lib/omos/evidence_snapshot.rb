# frozen_string_literal: true
#
# Personal Inbox 的 managed evidence snapshot。
#
# 為什麼要有這一層：匯入的來源檔是**使用者的檔案**，隨時可能被改名、移走或
# 刪掉。如果 Candidate 的 evidence 只剩一條指向原始路徑的參照，那份支撐隨時
# 會失效，而失效的方式是安靜的——下次要驗證時才發現東西不見了。因此匯入當下
# 就把原始 bytes 複製進我們自己管得住的位置。
#
# 以內容 digest 定址（`evidence/<sha256>/`），因此**同一份內容只會有一份
# snapshot**，重放不會長出第二份。只新增、不原地覆寫：同一個 digest 目錄已經
# 存在就代表內容相同，沒有任何需要改寫的理由；真要改寫反而說明 digest 算錯了。
#
# 這**不是**第二套 query DB。它只存 raw bytes 與 admission metadata，沒有索引、
# 沒有查詢介面；要找東西一律回 store 走既有的 row 查詢。

require "json"
require "digest"
require "securerandom"
require "fileutils"
require "time"

module OMOS
  module EvidenceSnapshot
    class Rejected < StandardError
      attr_reader :code, :detail

      def initialize(code, detail = nil)
        @code = code
        @detail = detail
        super(detail.nil? ? code : "#{code}: #{detail}")
      end
    end

    # v1 只收純文字。PDF／Office／圖片要的是 parser，那是另一張卡的東西；
    # 這裡**寧可明確拒絕**也不要收進來之後給出一份半懂的內容。
    SUPPORTED_EXTENSIONS = %w[.md .txt].freeze
    BYTES = "raw.bin"
    ENVELOPE = "envelope.json"

    module_function

    def root(store_path) = File.join(File.dirname(store_path), "evidence")

    def digest_of(bytes) = Digest::SHA256.hexdigest(bytes)

    def dir_for(store_path, digest) = File.join(root(store_path), digest)

    # 匯入一個檔案並回傳 envelope。
    #
    # 失敗一律 fail loud：不支援的副檔名、讀不到、不是合法 UTF-8、空檔。
    # 這些都在**寫任何東西之前**檢查完，所以失敗不會留下半套 snapshot。
    # before_rename 是注入的測試接縫，與既有 install(fail_after:)／
    # rollback(fail_before_receipt:) 同一做法。用途：讓 conformance 能**確定性**
    # 重現「兩個 process 同時第一次 capture」——真實的跨 process race 無法在
    # 測試裡穩定製造，而這條路徑正是 review P1-2 的缺陷所在。
    def capture(store_path, source_path, owner_ref:, tenant_id:, now: Time.now.utc,
                before_rename: nil)
      ext = File.extname(source_path).downcase
      unless SUPPORTED_EXTENSIONS.include?(ext)
        raise Rejected.new("INBOX_UNSUPPORTED_FORMAT",
                           "#{ext.empty? ? "（無副檔名）" : ext}；v1 只收 #{SUPPORTED_EXTENSIONS.join("／")}")
      end
      raise Rejected.new("INBOX_SOURCE_UNREADABLE", source_path) unless File.file?(source_path) && File.readable?(source_path)

      bytes = File.binread(source_path)
      raise Rejected.new("INBOX_SOURCE_EMPTY", source_path) if bytes.empty?

      text = bytes.dup.force_encoding(Encoding::UTF_8)
      raise Rejected.new("INBOX_SOURCE_NOT_UTF8", source_path) unless text.valid_encoding?

      digest = digest_of(bytes)
      dir = dir_for(store_path, digest)
      envelope_path = File.join(dir, ENVELOPE)

      # 已經有同一份內容 → 可能是重放。但**只有 bytes 相同還不夠**。
      #
      # review P1-3：原本只看 digest，於是 emp-A 先匯入、emp-B 再匯入相同
      # bytes 時，第二次回報「重放成功」，snapshot 與 Candidate 卻仍掛在
      # emp-A 身上——兩個人的 provenance 被靜默黏在一起。卡片寫的是
      # 「同一 bytes **＋ 同一 owner/source**」才算重放。
      #
      # 不同 provenance 一律 fail closed，而且分開兩個錯誤碼：owner/tenant
      # 不同是身分問題（嚴重），source 路徑不同是來源問題（通常是改名）。
      # 兩者都不靜默採用第一份。
      existing = adopt_existing(envelope_path, owner_ref, tenant_id, source_path)
      return [existing, true] unless existing.nil?

      envelope = {
        "evidence_ref" => evidence_ref(digest),
        "source_anchor_ref" => source_anchor_ref(digest),
        "source_anchor_profile" => ext == ".md" ? "MARKDOWN_TEXT_V1" : "PLAIN_TEXT_V1",
        "tenant_id" => tenant_id,
        "employee_owner_ref" => owner_ref,
        "content_sha256" => digest,
        "byte_size" => bytes.bytesize,
        "captured_at" => now.utc.iso8601,
        "origin" => {
          "original_filename" => File.basename(source_path),
          "original_path" => File.expand_path(source_path),
          "capture_surface" => "LOCAL_CLI_IMPORT"
        },
        "admission" => {
          "capture_scope" => "EMPLOYEE_PRIVATE",
          "consent_basis" => "EMPLOYEE_SELF_SUPPLIED",
          "content_encoding" => "UTF-8"
        }
      }

      # 先寫進暫存目錄再 rename：中途失敗不會留下一個只有 raw.bin、沒有
      # envelope 的半套 digest 目錄，而那種半套正是重放時最難判斷的狀態。
      FileUtils.mkdir_p(root(store_path))
      # tmp 名必須**真正唯一**（review P2）：只用 pid 的話，同一個 process 內
      # 兩個 thread 拿到同一個 digest 就會共用同一個暫存目錄，互相 rm_rf／
      # rename。目前 CLI 是單執行緒，但 capture 是 library seam。
      tmp = "#{dir}.writing-#{Process.pid}-#{SecureRandom.hex(8)}"
      FileUtils.rm_rf(tmp)
      begin
        FileUtils.mkdir_p(tmp)
        File.binwrite(File.join(tmp, BYTES), bytes)
        File.binwrite(File.join(tmp, ENVELOPE), "#{JSON.pretty_generate(envelope)}\n")
        before_rename&.call
        File.rename(tmp, dir)
      rescue Errno::ENOTEMPTY, Errno::EEXIST
        # 競態：別人剛好也在寫同一個 digest，而且贏了 rename。
        #
        # review P1-2：原本這裡直接 `return [JSON.parse(...), true]`，**沒有
        # 重新驗 provenance**——於是兩個 process 同時第一次 capture 時，輸掉
        # rename 的一方會靜默採用對方的 envelope 並回報 replay=true。這正是
        # P1-3 的併發版本：同一個缺陷，只是走另一條路進來。
        #
        # 正確做法是走**同一個** adopt_existing——採用既有那份的前提永遠是
        # provenance 相同，不因為「我是輸的那一方」而放寬。
        FileUtils.rm_rf(tmp)
        adopted = adopt_existing(envelope_path, owner_ref, tenant_id, source_path)
        raise Rejected.new("INBOX_EVIDENCE_RACE_UNRESOLVED", dir) if adopted.nil?

        return [adopted, true]
      rescue StandardError
        FileUtils.rm_rf(tmp)
        raise
      end

      [envelope, false]
    end

    # 採用既有 snapshot 的**唯一**入口。存在且 provenance 相同才算重放；
    # provenance 不同一律 raise；不存在回 nil 讓呼叫端自己決定。
    def adopt_existing(envelope_path, owner_ref, tenant_id, source_path)
      return nil unless File.file?(envelope_path)

      existing = JSON.parse(File.read(envelope_path))
      assert_same_provenance!(existing, owner_ref, tenant_id, source_path)
      existing
    end

    def assert_same_provenance!(existing, owner_ref, tenant_id, source_path)
      if existing["employee_owner_ref"] != owner_ref || existing["tenant_id"] != tenant_id
        raise Rejected.new(
          "INBOX_EVIDENCE_OWNER_CONFLICT",
          "相同內容已由 #{existing["employee_owner_ref"]}／#{existing["tenant_id"]} 匯入；" \
          "不得以 #{owner_ref}／#{tenant_id} 的身分沿用同一份 evidence"
        )
      end

      expected = File.expand_path(source_path)
      return if existing.dig("origin", "original_path") == expected

      raise Rejected.new(
        "INBOX_EVIDENCE_SOURCE_CONFLICT",
        "相同內容已由 #{existing.dig("origin", "original_path")} 匯入；" \
        "本次來源是 #{expected}"
      )
    end

    # snapshot 仍在、且 bytes 仍與 digest 相符。原始來源檔被移走也不影響。
    def verifiable?(store_path, digest)
      path = File.join(dir_for(store_path, digest), BYTES)
      File.file?(path) && digest_of(File.binread(path)) == digest
    end

    def list(store_path)
      base = root(store_path)
      return [] unless Dir.exist?(base)

      Dir.children(base).sort.filter_map do |d|
        f = File.join(base, d, ENVELOPE)
        JSON.parse(File.read(f)) if File.file?(f)
      end
    end

    # id 由內容 digest 決定，因此重放必然得到同一個 id——冪等不靠「查有沒有
    # 寫過」，而是**同樣的輸入本來就算得出同樣的 id**。
    #
    # 上游 id 模板是 UUIDv7（見 common-vocabulary 的 identifiers）。這裡不是
    # 在產生時間排序的 UUID，而是要一個**確定性**的、符合該模板的識別碼，
    # 所以取 digest 的位元組再把 version/variant nibble 蓋成 7 與 8。
    def deterministic_uuid(digest, salt)
      hex = Digest::SHA256.hexdigest("#{salt}:#{digest}")
      "#{hex[0, 8]}-#{hex[8, 4]}-7#{hex[13, 3]}-8#{hex[17, 3]}-#{hex[20, 12]}"
    end

    def evidence_ref(digest) = "urn:omos:evidence:#{deterministic_uuid(digest, "evidence")}"
    def source_anchor_ref(digest) = "urn:omos:source-anchor:#{deterministic_uuid(digest, "source-anchor")}"
    def link_ref(digest) = "urn:omos:personal-memory:support-link:#{deterministic_uuid(digest, "support-link")}"
    def candidate_ref(digest) = "urn:omos:personal-memory:candidate:#{deterministic_uuid(digest, "candidate")}"
  end
end
