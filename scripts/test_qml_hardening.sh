#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
QML_IMPORT_DIR="${QML_IMPORT_DIR:-/usr/lib/qt6/qml}"
QMLLINT_FLAGS="${QMLLINT_FLAGS:---unqualified disable}"

QML_FILES=(
  contents/ui/main.qml
  contents/ui/configGeneral.qml
  contents/ui/configProviders.qml
  contents/ui/configDisplay.qml
  contents/ui/configAdvanced.qml
  contents/ui/configDebug.qml
)

set +e
output="$(
  cd "$ROOT_DIR"
  # shellcheck disable=SC2086
  "$QMLLINT" $QMLLINT_FLAGS -I "$QML_IMPORT_DIR" "${QML_FILES[@]}" 2>&1
)"
status=$?
set -e

if [[ "$status" -ne 0 ]] || grep -Eq '^(Warning|Error):' <<<"$output"; then
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "KDE plasmoid QML hardening checks passed."
