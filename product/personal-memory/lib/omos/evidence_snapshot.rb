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
    def capture(store_path, source_path, owner_ref:, tenant_id:, now: Time.now.utc)
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

      # 已經有同一份內容 → 重放。回既有 envelope，**不重寫**。
      return [JSON.parse(File.read(envelope_path)), true] if File.file?(envelope_path)

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
      tmp = "#{dir}.writing-#{Process.pid}"
      FileUtils.rm_rf(tmp)
      begin
        FileUtils.mkdir_p(tmp)
        File.binwrite(File.join(tmp, BYTES), bytes)
        File.binwrite(File.join(tmp, ENVELOPE), "#{JSON.pretty_generate(envelope)}\n")
        File.rename(tmp, dir)
      rescue Errno::ENOTEMPTY, Errno::EEXIST
        # 競態：別人剛好也寫好了同一個 digest。內容相同，採既有那份。
        FileUtils.rm_rf(tmp)
        return [JSON.parse(File.read(envelope_path)), true]
      rescue StandardError
        FileUtils.rm_rf(tmp)
        raise
      end

      [envelope, false]
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
