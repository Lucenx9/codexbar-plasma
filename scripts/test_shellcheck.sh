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

if ! git -C "$ROOT_DIR" ls-files --cached --others --exclude-standard -z \
    > "$REPOSITORY_FILES"; then
  echo "failed to discover repository files" >&2
  exit 1
fi

SHELL_FILES=()
while IFS= read -r -d '' repository_path; do
  absolute_path="${ROOT_DIR}/${repository_path}"
  [[ -f "$absolute_path" ]] || continue

  if [[ "$repository_path" == *.sh ]]; then
    SHELL_FILES+=("$absolute_path")
    continue
  fi

  [[ -x "$absolute_path" ]] || continue
  first_line=""
  if ! IFS= read -r first_line < "$absolute_path" \
      && [[ -s "$absolute_path" && -z "$first_line" ]]; then
    echo "failed to inspect executable: $repository_path" >&2
    exit 1
  fi
  if [[ "$first_line" =~ ^\#!.*[/[:space:]](ba|da|k)?sh([[:space:]]|$) ]]; then
    SHELL_FILES+=("$absolute_path")
  fi
done < "$REPOSITORY_FILES"

if [[ "${#SHELL_FILES[@]}" -eq 0 ]]; then
  echo "no shell scripts found" >&2
  exit 1
fi

"$SHELLCHECK" --norc -x "${SHELL_FILES[@]}"

echo "ShellCheck passed."
