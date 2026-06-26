#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${ROOT_DIR}/po/codexbar-plasma.pot"
MODE="update"

usage() {
  printf '%s\n' "usage: $0 [--check] [--output PATH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    MODE="check"
    shift
    ;;
  --output)
    [[ $# -ge 2 ]] || { usage >&2; exit 2; }
    OUTPUT_PATH="$2"
    shift 2
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done

command -v xgettext >/dev/null 2>&1 || {
  echo "missing required command: xgettext" >&2
  exit 1
}

QML_SOURCES=(
  contents/config/config.qml
  contents/ui/configAdvanced.qml
  contents/ui/configDebug.qml
  contents/ui/configDisplay.qml
  contents/ui/configGeneral.qml
  contents/ui/configProviders.qml
  contents/ui/main.qml
)

generate_catalog() {
  local output="$1"
  mkdir -p "$(dirname "$output")"
  {
    cat <<'HEADER'
# CodexBar Plasma translation template.
# This file is distributed under the same license as the codexbar-plasma package.
msgid ""
msgstr ""
"Project-Id-Version: codexbar-plasma\n"
"Report-Msgid-Bugs-To: https://github.com/Lucenx9/codexbar-plasma/issues\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"

HEADER
    (
      cd "$ROOT_DIR"
      LC_ALL=C.utf8 xgettext \
        --from-code=UTF-8 \
        --language=JavaScript \
        --keyword=i18n \
        --keyword=i18nc:1c,2 \
        --keyword=i18np:1,2 \
        --keyword=i18ncp:1c,2,3 \
        --add-location=file \
        --sort-by-file \
        --omit-header \
        -o - \
        "${QML_SOURCES[@]}"
    )
  } > "$output"
}

if [[ "$MODE" == "check" ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  generate_catalog "$tmp"
  if ! cmp -s "$tmp" "$OUTPUT_PATH"; then
    echo "translation template is out of date; run make translations" >&2
    diff -u "$OUTPUT_PATH" "$tmp" >&2 || true
    exit 1
  fi
  exit 0
fi

generate_catalog "$OUTPUT_PATH"
