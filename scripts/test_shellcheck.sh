#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLCHECK="${SHELLCHECK:-shellcheck}"

if ! command -v "$SHELLCHECK" >/dev/null 2>&1; then
  echo "ShellCheck not found: $SHELLCHECK" >&2
  exit 1
fi

mapfile -d '' -t SHELL_FILES < <(
  find "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts" -type f -name '*.sh' -print0 \
    | sort -z
)

if [[ "${#SHELL_FILES[@]}" -eq 0 ]]; then
  echo "no shell scripts found" >&2
  exit 1
fi

"$SHELLCHECK" --norc -x "${SHELL_FILES[@]}"

echo "ShellCheck passed."
