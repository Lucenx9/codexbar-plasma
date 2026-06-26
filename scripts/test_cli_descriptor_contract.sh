#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_MD="${ROOT_DIR}/docs/cli-provider-settings-descriptor.md"
TODO_MD="${ROOT_DIR}/TODO.md"
AGENTS_MD="${ROOT_DIR}/AGENTS.md"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected CLI descriptor contract fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

if [[ ! -f "$CONTRACT_MD" ]]; then
  echo "docs/cli-provider-settings-descriptor.md must document the provider settings descriptor contract" >&2
  exit 1
fi

require_in_file "$CONTRACT_MD" "codexbar config providers --descriptors --format json --json-only"
require_in_file "$CONTRACT_MD" "codexbar config set"
require_in_file "$CONTRACT_MD" "codexbar config action"
require_in_file "$CONTRACT_MD" "\"schemaVersion\": 1"
require_in_file "$CONTRACT_MD" "\"fields\""
require_in_file "$CONTRACT_MD" "\"actions\""
require_in_file "$CONTRACT_MD" "\"redactedValue\""
require_in_file "$CONTRACT_MD" "\"writeCommand\""
require_in_file "$CONTRACT_MD" "\"command\""
require_in_file "$CONTRACT_MD" "\"kind\": \"secret\""
require_in_file "$CONTRACT_MD" "\"kind\": \"enum\""
require_in_file "$CONTRACT_MD" "\"kind\": \"command\""
require_in_file "$CONTRACT_MD" "After a successful write/action"
require_in_file "$CONTRACT_MD" "Plasma renderer rules"
require_in_file "$CONTRACT_MD" "Do not expose raw secrets"

require_in_file "$TODO_MD" "docs/cli-provider-settings-descriptor.md"
require_in_file "$AGENTS_MD" "docs/cli-provider-settings-descriptor.md"

echo "CLI descriptor contract checks passed."
