#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
QMLLINT_FLAGS="${QMLLINT_FLAGS:---unqualified disable}"

resolve_qml_import_dir() {
  local current="${1:-}"
  local root_prefix="${2:-/usr/lib}"
  if [[ -n "$current" && -d "$current" ]]; then
    echo "$current"
    return 0
  fi
  # Mirror the Makefile priority: the standard path wins when present and the
  # multiarch trees are only a fallback when it is absent.
  if [[ -d "${root_prefix}/qt6/qml" ]]; then
    echo "${root_prefix}/qt6/qml"
    return 0
  fi
  local triplet
  triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  if [[ -z "$triplet" ]]; then
    local arch
    arch="$(uname -m 2>/dev/null || true)"
    if [[ -n "$arch" && -d "${root_prefix}/${arch}-linux-gnu/qt6/qml" ]]; then
      triplet="${arch}-linux-gnu"
    fi
  fi
  if [[ -n "$triplet" && -d "${root_prefix}/${triplet}/qt6/qml" ]]; then
    echo "${root_prefix}/${triplet}/qt6/qml"
    return 0
  fi
  for candidate in "${root_prefix}"/*-linux-gnu/qt6/qml; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "${root_prefix}/qt6/qml"
}

test_resolve_qml_import_dir() {
  local fixture_dir
  fixture_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$fixture_dir'" RETURN
  local triplet
  triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  [[ -z "$triplet" ]] && triplet="$(uname -m 2>/dev/null || true)-linux-gnu"
  mkdir -p "$fixture_dir/aaaa-linux-gnu/qt6/qml" "$fixture_dir/${triplet}/qt6/qml"
  local resolved
  resolved="$(resolve_qml_import_dir "" "$fixture_dir")"
  if [[ "$resolved" != "$fixture_dir/${triplet}/qt6/qml" ]]; then
    echo "resolve_qml_import_dir failed: got '$resolved', expected '$fixture_dir/${triplet}/qt6/qml'" >&2
    exit 1
  fi
  # The standard path wins when both layouts exist (Makefile `or` priority).
  mkdir -p "$fixture_dir/qt6/qml"
  resolved="$(resolve_qml_import_dir "" "$fixture_dir")"
  if [[ "$resolved" != "$fixture_dir/qt6/qml" ]]; then
    echo "resolve_qml_import_dir failed: got '$resolved', expected '$fixture_dir/qt6/qml'" >&2
    exit 1
  fi
}
test_resolve_qml_import_dir

resolve_qmllint_flags() {
  local current="${1:-}"
  local import_dir="${2:-}"
  if [[ -n "$current" && "$current" == *"--import"* ]]; then
    echo "$current"
    return 0
  fi
  local base="${current:---unqualified disable}"
  if [[ -n "$import_dir" && ( ! -d "${import_dir}/org/kde/plasma/plasmoid" || ! -d "${import_dir}/org/kde/plasma/configuration" ) ]]; then
    echo "--import info --unresolved-type info --missing-property info $base"
    return 0
  fi
  echo "$base"
}

test_resolve_qmllint_flags() {
  local fixture_dir
  fixture_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$fixture_dir'" RETURN
  local resolved
  resolved="$(resolve_qmllint_flags "" "$fixture_dir")"
  if [[ "$resolved" != *"--import info"* ]]; then
    echo "resolve_qmllint_flags failed: expected info downgrade when plasma modules absent, got '$resolved'" >&2
    exit 1
  fi
  mkdir -p "$fixture_dir/org/kde/plasma/plasmoid" "$fixture_dir/org/kde/plasma/configuration"
  resolved="$(resolve_qmllint_flags "" "$fixture_dir")"
  if [[ "$resolved" != "--unqualified disable" ]]; then
    echo "resolve_qmllint_flags failed: expected standard flags when plasma modules present, got '$resolved'" >&2
    exit 1
  fi
  resolved="$(resolve_qmllint_flags "--import error --unqualified disable" "$fixture_dir")"
  if [[ "$resolved" != "--import error --unqualified disable" ]]; then
    echo "resolve_qmllint_flags failed: expected explicit --import flag to be preserved, got '$resolved'" >&2
    exit 1
  fi
}
test_resolve_qmllint_flags

QML_IMPORT_DIR="$(resolve_qml_import_dir "${QML_IMPORT_DIR:-}")"
QMLLINT_FLAGS="$(resolve_qmllint_flags "${QMLLINT_FLAGS:-}" "$QML_IMPORT_DIR")"

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
