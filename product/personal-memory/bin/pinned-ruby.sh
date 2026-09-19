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

omos_check() {
  [ -x "$1" ] || return 1
  [ "$("$1" -e 'print RUBY_VERSION' 2>/dev/null)" = "$OMOS_REQUIRED" ]
}

if [ -n "$OMOS_RUBY" ]; then
  # 明確指定就以它為準；不合格要當場失敗，不得靜默改用別的直譯器。
  if ! omos_check "$OMOS_RUBY"; then
    echo "[omos-personal-memory] 指定的 OMOS_RUBY=$OMOS_RUBY 不是 $OMOS_REQUIRED。" >&2
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
  echo "[omos-personal-memory] 找不到鎖定的 Ruby $OMOS_REQUIRED。" >&2
  echo "  已試過 OMOS_RUBY、Homebrew ruby@3.4、rbenv 與 PATH 上的 ruby。" >&2
  echo "  安裝方式之一： brew install ruby@3.4" >&2
  echo "  或直接指定： OMOS_RUBY=/path/to/ruby <指令>" >&2
  exit 78
fi

export OMOS_RUBY OMOS_ROOT
