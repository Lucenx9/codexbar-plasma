#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
QML_IMPORT_DIR="${QML_IMPORT_DIR:-/usr/lib/qt6/qml}"
QMLLINT_FLAGS="${QMLLINT_FLAGS:---unqualified disable}"

# The `all` surface in scripts/lib/qml_surfaces.py is the one list of QML/JS
# sources; the Makefile and scripts/update_translations.sh read it too, so a new
# or moved file cannot fall out of one list while staying in another.
mapfile -t QML_FILES < <(cd "$ROOT_DIR" && python3 scripts/lib/qml_surfaces.py files all)
if [[ "${#QML_FILES[@]}" -eq 0 ]]; then
  echo "scripts/lib/qml_surfaces.py produced no files for surface 'all'" >&2
  exit 1
fi

# The manifest globs by directory, so an unglobbed directory is the real drift
# risk: assert every QML/JS source on disk is actually covered.
while IFS= read -r qml_source; do
  if [[ " ${QML_FILES[*]} " != *" ${ROOT_DIR}/${qml_source} "* ]]; then
    echo "QML source is not covered by any glob in scripts/lib/qml_surfaces.py: ${qml_source}" >&2
    exit 1
  fi
done < <(cd "$ROOT_DIR" && find contents -type f \( -name '*.qml' -o -name '*.js' \) -print | sort)

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
