#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLCHECK="${SHELLCHECK:-shellcheck}"

if ! command -v "$SHELLCHECK" >/dev/null 2>&1; then
  echo "ShellCheck not found: $SHELLCHECK" >&2
  exit 1
fi

REPOSITORY_FILES="$(mktemp)"
trap 'rm -f "$REPOSITORY_FILES"' EXIT

if ! find "$ROOT_DIR" \
    -path "$ROOT_DIR/.git" -prune -o \
    -path "$ROOT_DIR/dist" -prune -o \
    -type f -print0 \
    | sort -z > "$REPOSITORY_FILES"; then
  echo "failed to discover repository files" >&2
  exit 1
fi

SHELL_FILES=()
while IFS= read -r -d '' source_path; do
  [[ -f "$source_path" ]] || continue

  if [[ "$source_path" == *.sh ]]; then
    SHELL_FILES+=("$source_path")
    continue
  fi

  [[ -x "$source_path" ]] || continue
  first_line=""
  if ! IFS= read -r first_line < "$source_path" \
      && [[ -s "$source_path" && -z "$first_line" ]]; then
    echo "failed to inspect executable: ${source_path#"$ROOT_DIR"/}" >&2
    exit 1
  fi
  if [[ "$first_line" =~ ^\#!.*[/[:space:]](ba|da|k)?sh([[:space:]]|$) ]]; then
    SHELL_FILES+=("$source_path")
  fi
done < "$REPOSITORY_FILES"

if [[ "${#SHELL_FILES[@]}" -eq 0 ]]; then
  echo "no shell scripts found" >&2
  exit 1
fi

"$SHELLCHECK" --norc -x "${SHELL_FILES[@]}"

echo "ShellCheck passed."
