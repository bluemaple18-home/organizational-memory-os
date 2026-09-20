# shellcheck shell=sh
#
# 解析本產品鎖定的 Ruby，並把路徑放進 $OMOS_RUBY。
#
# 為什麼要有這支：`#!/usr/bin/env ruby` 依賴使用者的 PATH。實測在乾淨 PATH 下
# 會找到 macOS 系統 Ruby 2.6，載入為 3.4 編譯的原生 gem 後直接 SIGILL
# （exit 132）且毫無輸出。Ruby 端的版本守衛也救不了——守衛所在的檔案若含
# 新語法，2.6 會在 parse 階段就失敗，守衛沒有機會執行。
#
# 因此版本解析必須發生在 Ruby 之外。這支只用 POSIX sh。

OMOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OMOS_REQUIRED=$(cat "$OMOS_ROOT/.ruby-version" 2>/dev/null || echo "unknown")

# Slice B：判準不再是版本字串相等。
#
# Q6 Part 1 證明版本字串同時**過嚴**（拒絕 ABI 其實相容的 patch 升級——
# Homebrew 的 opt symlink 與 libruby install_name 都不隨 patch 改變）與
# **過鬆**（放行裝在別的路徑、實際載不動我們原生擴充的同版本 Ruby）。
#
# 這裡只做**便宜的候選篩選**：ABI 目錄（3.4 系列皆為 "3.4.0"）必須與
# artifact 宣告的一致。真正的 load probe 與 qualification 在開機路徑上由
# OMOS::RuntimeProfile 執行——產品本來就要載入那些擴充，不另開探針重做一次。
#
# 版本解析仍必須發生在 Ruby 之外：macOS 系統 Ruby 2.6 的 ABI 目錄是 "2.6.0"，
# 在這裡就會被排除，不會走到載入原生擴充而 SIGILL 的地步。
# 需要的 ABI 直接由 artifact 自己的內容推導：vendored 原生擴充就放在
# vendor/bundle/ruby/<ABI>/ 底下，那個目錄名**就是**它們被編譯時的 ABI。
# 不另外宣告一份，否則會多一個會漂移的來源。
OMOS_REQUIRED_ABI=$(ls -1 "$OMOS_ROOT/vendor/bundle/ruby" 2>/dev/null)
case "$OMOS_REQUIRED_ABI" in
  *"
"*) OMOS_REQUIRED_ABI="" ;;   # 不只一個 ABI 目錄 → 無法判定，fail closed
esac

omos_check() {
  [ -x "$1" ] || return 1
  [ -n "$OMOS_REQUIRED_ABI" ] || return 1
  [ "$("$1" -rrbconfig -e 'print RbConfig::CONFIG["ruby_version"]' 2>/dev/null)" = "$OMOS_REQUIRED_ABI" ]
}

if [ -n "$OMOS_RUBY" ]; then
  # 明確指定就以它為準；不合格要當場失敗，不得靜默改用別的直譯器。
  if ! omos_check "$OMOS_RUBY"; then
    echo "[omos-personal-memory] 指定的 OMOS_RUBY=$OMOS_RUBY 的 ABI 與本 artifact 不符。" >&2
    echo "  本 artifact 的原生擴充編譯於 ABI ${OMOS_REQUIRED_ABI}（參考版本 ${OMOS_REQUIRED}）。" >&2
    exit 78
  fi
else
  OMOS_RUBY=""
  for candidate in \
    "/opt/homebrew/opt/ruby@3.4/bin/ruby" \
    "/usr/local/opt/ruby@3.4/bin/ruby" \
    "$HOME/.rbenv/versions/$OMOS_REQUIRED/bin/ruby" \
    "$(command -v ruby 2>/dev/null)"
  do
    if omos_check "$candidate"; then OMOS_RUBY="$candidate"; break; fi
  done
fi

if [ -z "$OMOS_RUBY" ]; then
  echo "[omos-personal-memory] 找不到 ABI 相容的 Ruby。" >&2
  echo "  本 artifact 的原生擴充編譯於 ABI ${OMOS_REQUIRED_ABI}（參考版本 ${OMOS_REQUIRED}）；" >&2
  echo "  判準是 ABI 目錄相容，不是版本字串相等——同 3.4 系列的 patch 升級是可接受的。" >&2
  echo "  已試過 OMOS_RUBY、Homebrew ruby@3.4、rbenv 與 PATH 上的 ruby。" >&2
  echo "  安裝方式之一： brew install ruby@3.4" >&2
  echo "  或直接指定： OMOS_RUBY=/path/to/ruby <指令>" >&2
  exit 78
fi

export OMOS_RUBY OMOS_ROOT
