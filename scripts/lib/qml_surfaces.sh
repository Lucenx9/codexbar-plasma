#!/usr/bin/env bash
# Shared fragment assertions for the static checks in scripts/.
#
# Source this, do not execute it, and set ROOT_DIR first:
#
#   ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   . "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
#
# Prefer the `*_in_surface` helpers for rules that belong to the plasmoid runtime
# or a config page as a whole: they keep passing when the rule moves to another
# file in the same surface. Use `*_in_file` only when the assertion is genuinely
# about one file, such as a component delegate contract. Surface membership lives
# in `qml_surfaces.py`.

QML_SURFACES_PY="${ROOT_DIR}/scripts/lib/qml_surfaces.py"

declare -A _qml_surface_cache=()

qml_surface_files() {
  local surface="$1"
  if [[ -z "${_qml_surface_cache[$surface]:-}" ]]; then
    _qml_surface_cache[$surface]="$(python3 "$QML_SURFACES_PY" files "$surface")"
  fi
  printf '%s\n' "${_qml_surface_cache[$surface]}"
}

_qml_relative_paths() {
  sed "s|^${ROOT_DIR}/||"
}

require_in_surface() {
  local surface="$1"
  local needle="$2"
  local -a files
  mapfile -t files < <(qml_surface_files "$surface")
  if ! grep -Fq -e "$needle" -- "${files[@]}"; then
    echo "missing expected fragment in surface ${surface}: ${needle}" >&2
    exit 1
  fi
}

reject_in_surface() {
  local surface="$1"
  local needle="$2"
  local -a files
  mapfile -t files < <(qml_surface_files "$surface")
  local hits
  hits="$(grep -Fl -e "$needle" -- "${files[@]}" || true)"
  if [[ -n "$hits" ]]; then
    {
      echo "unexpected fragment in surface ${surface}: ${needle}"
      printf '%s\n' "$hits" | _qml_relative_paths | sed 's/^/  found in /'
    } >&2
    exit 1
  fi
}

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -e "$needle" -- "$file"; then
    echo "missing expected fragment in ${file#"$ROOT_DIR"/}: ${needle}" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -e "$needle" -- "$file"; then
    echo "unexpected fragment in ${file#"$ROOT_DIR"/}: ${needle}" >&2
    exit 1
  fi
}
