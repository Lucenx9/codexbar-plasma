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
    _qml_surface_cache[$surface]="$(python3 "$QML_SURFACES_PY" files "$surface")" || return 1
  fi
  printf '%s\n' "${_qml_surface_cache[$surface]}"
}

_qml_relative_paths() {
  sed "s|^${ROOT_DIR}/||"
}

require_in_surface() {
  local surface="$1"
  local needle="$2"
  local file_list
  file_list="$(qml_surface_files "$surface")" || exit 1
  local -a files
  mapfile -t files <<< "$file_list"
  if ! grep -F -e "$needle" -- "${files[@]}" >/dev/null; then
    echo "missing expected fragment in surface ${surface}: ${needle}" >&2
    exit 1
  fi
}

reject_in_surface() {
  local surface="$1"
  local needle="$2"
  local file_list
  file_list="$(qml_surface_files "$surface")" || exit 1
  local -a files
  mapfile -t files <<< "$file_list"
  local hits
  if hits="$(grep -Fl -e "$needle" -- "${files[@]}")"; then
    {
      echo "unexpected fragment in surface ${surface}: ${needle}"
      printf '%s\n' "$hits" | _qml_relative_paths | sed 's/^/  found in /'
    } >&2
    exit 1
  else
    local status=$?
    [[ "$status" -eq 1 ]] || exit "$status"
  fi
}

# Helper declarations are a per-file contract: QML and JS files share no function
# scope, so `require_in_surface "function hasOwnKey("` is satisfied by any sibling
# that happens to declare it, and deleting the copy live callers depend on passes.
# This asserts the declaration exists in every file that calls the helper, so the
# rule still follows the code without losing its teeth. An optional third argument
# is a fragment every declaration's body must keep.
require_definition_where_used() {
  local surface="$1"
  local function_name="$2"
  local body_fragment="${3:-}"
  if [[ -n "$body_fragment" ]]; then
    python3 "$QML_SURFACES_PY" definition "$surface" "$function_name" "$body_fragment" || exit 1
  else
    python3 "$QML_SURFACES_PY" definition "$surface" "$function_name" || exit 1
  fi
}

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -F -e "$needle" -- "$file" >/dev/null; then
    echo "missing expected fragment in ${file#"$ROOT_DIR"/}: ${needle}" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -F -e "$needle" -- "$file" >/dev/null; then
    echo "unexpected fragment in ${file#"$ROOT_DIR"/}: ${needle}" >&2
    exit 1
  else
    local status=$?
    [[ "$status" -eq 1 ]] || exit "$status"
  fi
}
