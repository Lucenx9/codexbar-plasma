#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
QML_IMPORT_DIR="${QML_IMPORT_DIR:-/usr/lib/qt6/qml}"
QMLLINT_FLAGS="${QMLLINT_FLAGS:---unqualified disable}"

# The `all` surface in scripts/lib/qml_surfaces.py is the one list of QML/JS
# sources; this check and scripts/update_translations.sh read it, so a new or
# moved file cannot fall out of one list while staying in another. Keep the
# paths in this Bash array: expanding a generated path list in a Make recipe
# would let shell metacharacters in a source or checkout name become commands.
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

# The Qt 6.7 QML parser the CI runs on (KDE neon) still treats the ECMAScript
# future-reserved words as reserved, while newer local Qt builds parse them as
# ordinary identifiers. A local named `long` compiled here and failed there
# twice, so reject them by name instead of relying on whichever Qt the developer
# happens to have. qmllint does not catch this: the file never reaches it.
reserved_hits="$(
  cd "$ROOT_DIR" || exit 1
  grep -nE \
    '\b(var|let|const)[[:space:]]+(abstract|boolean|byte|char|double|enum|export|extends|final|float|goto|implements|import|int|interface|long|native|package|private|protected|public|short|static|super|synchronized|throws|transient|volatile)\b' \
    "${QML_FILES[@]}" tests/*.qml 2>/dev/null || true
)"
if [[ -n "$reserved_hits" ]]; then
  echo "reserved word used as a local name; the CI Qt parser rejects these:" >&2
  printf '%s\n' "$reserved_hits" >&2
  exit 1
fi

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
