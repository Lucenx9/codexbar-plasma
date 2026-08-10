#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_MD="${ROOT_DIR}/docs/cli-provider-settings-descriptor.md"
TODO_MD="${ROOT_DIR}/TODO.md"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected CLI descriptor contract fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected CLI descriptor contract fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
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
reject_in_file "$CONTRACT_MD" "- \`\"kind\": \"command\"\`: read-only row"
require_in_file "$CONTRACT_MD" "After a successful write/action"
require_in_file "$CONTRACT_MD" "Plasma renderer rules"
require_in_file "$CONTRACT_MD" "Do not expose raw secrets"
require_in_file "$CONTRACT_MD" "32 fields"
require_in_file "$CONTRACT_MD" "32 actions"
require_in_file "$CONTRACT_MD" "64 options"
require_in_file "$CONTRACT_MD" '[A-Za-z0-9][A-Za-z0-9._-]*'
require_in_file "$CONTRACT_MD" "reject invalid IDs"

require_in_file "$PROVIDERS_QML" "readonly property int maximumDescriptorFields: 32"
require_in_file "$PROVIDERS_QML" "readonly property int maximumDescriptorActions: 32"
require_in_file "$PROVIDERS_QML" "readonly property int maximumDescriptorOptions: 64"
require_in_file "$PROVIDERS_QML" "Math.min(rawFields.length, maximumDescriptorFields)"
require_in_file "$PROVIDERS_QML" "Math.min(rawActions.length, maximumDescriptorActions)"
require_in_file "$PROVIDERS_QML" "Math.min(rawOptions.length, maximumDescriptorOptions)"
require_in_file "$PROVIDERS_QML" "value.length > maximumDescriptorTokenLength"
require_in_file "$PROVIDERS_QML" "function descriptorIdentifier(value)"
require_in_file "$PROVIDERS_QML" 'return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value) ? value : ""'
reject_in_file "$PROVIDERS_QML" "SafeText.boundedDisplayText(raw.id, 128)"
reject_in_file "$PROVIDERS_QML" "SafeText.boundedDisplayText(option.id, 128)"
require_in_file "$PROVIDERS_QML" "title: raw.title ? SafeText.cliMessage(raw.title, 120)"
require_in_file "$PROVIDERS_QML" "description: raw.description ? SafeText.cliMessage(raw.description, 500)"
require_in_file "$PROVIDERS_QML" "title: option.title ? SafeText.cliMessage(option.title, 120)"

require_in_file "$TODO_MD" "docs/cli-provider-settings-descriptor.md"

echo "CLI descriptor contract checks passed."
