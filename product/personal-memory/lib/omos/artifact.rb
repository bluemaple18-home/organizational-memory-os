# frozen_string_literal: true
#
# Artifact identity：一個 artifact「是哪一份 build」的唯一依據。
#
# 為什麼是 content-derived：upgrade／rollback 要能證明 code、spec 與共用
# evaluator 屬於同一份 build。若拿安裝時間、路徑或 store 的 schema_version
# 當識別，換個安裝位置就變成另一個 id，而真正改了內容卻可能不變。
#
# 因此 id 只由「artifact 實際承載的內容」決定：每個檔案的**相對路徑**與
# **bytes**。刻意**不**納入的東西（它們屬於 activation，不屬於 artifact）：
#   - 安裝位置（versions/<id> 的絕對路徑、current symlink 指向何處）
#   - mtime／owner／inode
#   - install receipt
#
# 這個定義對「artifact 裡有哪些檔案」不做任何列舉。Slice A 之後若再往
# artifact 放東西（例如 Slice C 的驗證用資料），id 會自然涵蓋它，不必改算法。
#
# 流程是 stage → hash → rename：先把內容放進暫存目錄、算出 id、再更名成
# versions/<id>。若反過來先建目錄再算，id 就會參照到自己所在的路徑。

require "digest"

module OMOS
  module Artifact
    # 檔案模式只保留「可執行與否」——那會影響 artifact 能不能跑，屬於內容。
    # 其餘位元（owner、setuid 等）不納入，否則同一份內容在不同 umask 下會
    # 得到不同 id。
    def self.file_signature(path)
      mode = File.executable?(path) ? "x" : "-"
      "#{mode}:#{Digest::SHA256.file(path).hexdigest}"
    end

    # symlink 以「指向哪裡」入帳，不跟進去讀內容——跟進去會讓 artifact 內的
    # 相對 symlink 依安裝位置而變。
    def self.entry_signature(path)
      return "l:#{File.readlink(path)}" if File.symlink?(path)

      file_signature(path)
    end

    # 回傳 [[相對路徑, 簽章], ...]，依相對路徑排序。排序是必要的：
    # Dir.glob 的順序依檔案系統而異，不排序會讓同一份內容得到不同 id。
    def self.manifest(root)
      root = File.expand_path(root)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: root)
         .reject { |rel| rel == "." || rel == ".." || rel.end_with?("/.", "/..") }
         .map { |rel| [rel, File.join(root, rel)] }
         .reject { |_rel, abs| File.directory?(abs) && !File.symlink?(abs) }
         .sort_by { |rel, _abs| rel }
         .map { |rel, abs| [rel, entry_signature(abs)] }
    end

    # artifact id ＝ 對 manifest 取 SHA256。用 \u0000 當分隔，避免
    # 「a/b + c」與「a + b/c」這類拼接歧義。
    def self.identity(root)
      digest = Digest::SHA256.new
      manifest(root).each do |rel, sig|
        digest << rel << "\u0000" << sig << "\u0000"
      end
      digest.hexdigest
    end
  end
end
