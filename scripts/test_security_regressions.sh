#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
DISPLAY_QML="${ROOT_DIR}/contents/ui/configDisplay.qml"
DEBUG_QML="${ROOT_DIR}/contents/ui/configDebug.qml"
SAFE_TEXT_JS="${ROOT_DIR}/contents/ui/SafeText.js"
PROVIDER_IDENTITY_JS="${ROOT_DIR}/contents/ui/ProviderIdentity.js"
WORKFLOW="${ROOT_DIR}/.github/workflows/ci.yml"
MAKEFILE="${ROOT_DIR}/Makefile"
UPDATER="${ROOT_DIR}/scripts/update-widget.sh"
PROVIDER_DETAIL_SECTION_QML="${ROOT_DIR}/contents/ui/components/ProviderDetailSection.qml"
INTERACTIVE_CHART_QML="${ROOT_DIR}/contents/ui/components/InteractiveChart.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected security hardening fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_text() {
  local label="$1"
  local text="$2"
  local needle="$3"
  if ! grep -Fq -- "$needle" <<<"$text"; then
    echo "missing expected security hardening fragment in ${label}: $needle" >&2
    exit 1
  fi
}

reject_text() {
  local label="$1"
  local text="$2"
  local needle="$3"
  if grep -Fq -- "$needle" <<<"$text"; then
    echo "unexpected security-sensitive fragment in ${label}: $needle" >&2
    exit 1
  fi
}

workflow_job_block() {
  local job="$1"
  awk -v marker="  ${job}:" '
    $0 == marker { in_job = 1; print; next }
    in_job && /^  [A-Za-z0-9_-]+:/ { exit }
    in_job { print }
  ' "$WORKFLOW"
}

if ! awk '
  /^permissions:/ { in_permissions = 1; next }
  /^jobs:/ { exit }
  in_permissions && /contents: read/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$WORKFLOW"; then
  echo "missing top-level read-only workflow permissions in .github/workflows/ci.yml" >&2
  exit 1
fi

CHECK_JOB="$(workflow_job_block check)"
RELEASE_JOB="$(workflow_job_block release)"
require_text "check job" "$CHECK_JOB" "contents: read"
require_text "check job" "$CHECK_JOB" "persist-credentials: false"
reject_text "check job" "$CHECK_JOB" "contents: write"
require_text "release job" "$RELEASE_JOB" "if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')"
require_text "release job" "$RELEASE_JOB" "contents: write"
require_text "release job" "$RELEASE_JOB" "persist-credentials: false"
require_text "release job" "$RELEASE_JOB" "Verify release tag matches metadata"
require_text "release job" "$RELEASE_JOB" "^v[0-9]+\\.[0-9]+\\.[0-9]+$"
require_text "release job" "$RELEASE_JOB" "jq -r '.KPlugin.Version // empty' metadata.json"
# shellcheck disable=SC2016 # Match the literal shell expression in the workflow.
require_text "release job" "$RELEASE_JOB" '"v${metadata_version}" != "$GITHUB_REF_NAME"'
require_in_file "$WORKFLOW" "image: kdeneon/plasma@sha256:"
require_in_file "$WORKFLOW" "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"
reject_text "workflow" "$(cat "$WORKFLOW")" "actions/checkout@v4"
reject_text "workflow" "$(cat "$WORKFLOW")" "image: kdeneon/plasma:user"
require_in_file "$WORKFLOW" "dist/codexbar-plasma.plasmoid.sha256"
require_in_file "$MAKEFILE" "sha256sum codexbar-plasma.plasmoid > codexbar-plasma.plasmoid.sha256"
require_in_file "$UPDATER" "sha256sum --check --strict"

for qml_file in "$MAIN_QML" "$PROVIDERS_QML" "$DISPLAY_QML" "$DEBUG_QML"; do
  require_in_file "$qml_file" 'import "SafeText.js" as SafeText'
done
require_in_file "$MAIN_QML" "SafeText.cliMessage"
require_in_file "$PROVIDERS_QML" "SafeText.cliMessage"
require_in_file "$DISPLAY_QML" "SafeText.cliMessage"
require_in_file "$DEBUG_QML" "SafeText.cliDiagnostic"
require_in_file "$SAFE_TEXT_JS" "function redactCredentials(value, inspectionLimit)"
require_in_file "$SAFE_TEXT_JS" "maximumDiagnosticLength = 65536"
require_in_file "$SAFE_TEXT_JS" "maximumCliJsonLength = 4 * 1024 * 1024"
require_in_file "$SAFE_TEXT_JS" "function boundedInspectionText(value, inspectionLimit)"
require_in_file "$SAFE_TEXT_JS" 'chunk.search(/[^\s\u0000-\u001f\u007f]/)'
require_in_file "$SAFE_TEXT_JS" "function cliJsonText(value)"

require_in_file "$MAIN_QML" "function hasOwnKey(item, key)"
require_in_file "$MAIN_QML" "Object.prototype.hasOwnProperty.call(item, key)"
require_in_file "$MAIN_QML" "function isUnsafeObjectKey(key)"
require_in_file "$MAIN_QML" "value === \"__proto__\" || value === \"prototype\" || value === \"constructor\""
require_in_file "$MAIN_QML" "function providerMapKey(providerID)"
require_in_file "$MAIN_QML" 'import "ProviderIdentity.js" as ProviderIdentity'
require_in_file "$MAIN_QML" "return ProviderIdentity.providerMapKey(key)"
require_in_file "$PROVIDER_IDENTITY_JS" "Object.prototype.hasOwnProperty.call(item, key)"
require_in_file "$PROVIDER_IDENTITY_JS" "Object.prototype.hasOwnProperty.call(Object.prototype, key)"
require_in_file "$MAIN_QML" "if (name.length === 0 || isUnsafeObjectKey(name))"
require_in_file "$MAIN_QML" "if (!hasOwnKey(byName, name))"
require_in_file "$MAIN_QML" "if (!hasOwnKey(byName, modelName))"
require_in_file "$MAIN_QML" "if (!hasOwnKey(item, key) || isUnsafeObjectKey(key))"
require_in_file "$MAIN_QML" "var providerID = normalizedProviderID(items[i].provider)"
require_in_file "$MAIN_QML" "var providerID = providerMapKey(item.provider)"
require_in_file "$MAIN_QML" "var providerID = providerMapKey(item.provider || \"unknown\")"
require_in_file "$MAIN_QML" "var key = providerMapKey(providerID)"
require_in_file "$PROVIDERS_QML" "function providerMapKey(providerID)"
require_in_file "$PROVIDERS_QML" "return ProviderIdentity.providerMapKey(key)"
require_in_file "$PROVIDERS_QML" "if (!hasOwnKey(item, key) || isUnsafeObjectKey(key))"
require_in_file "$PROVIDERS_QML" "Object.prototype.hasOwnProperty.call(item, key)"
require_in_file "$MAIN_QML" "maximumConcurrentProviderFallbackCommands: 8"
require_in_file "$MAIN_QML" "nextProviders.length < maximumProviderSnapshots"
require_in_file "$MAIN_QML" "value: boundedDisplayText(parts.join(\" · \"), 500)"
require_in_file "$MAIN_QML" "key = ProviderIdentity.providerKey(key, aliases)"
require_in_file "$PROVIDERS_QML" "key = ProviderIdentity.providerKey(key, aliases)"
require_in_file "$MAIN_QML" "var key = ProviderIdentity.providerMapKey(providerKey(value))"
require_in_file "$PROVIDERS_QML" "var key = ProviderIdentity.providerMapKey(providerKey(value))"
require_in_file "$PROVIDERS_QML" "function isAllowedDescriptorCommand(commandTokens, purpose)"
require_in_file "$PROVIDERS_QML" "String(commandTokens[0]) !== \"codexbar\""
require_in_file "$PROVIDERS_QML" "String(commandTokens[1]) !== \"config\""
require_in_file "$PROVIDERS_QML" "subcommand === \"set\" || subcommand === \"set-api-key\""
require_in_file "$PROVIDERS_QML" "subcommand === \"action\""
require_in_file "$PROVIDERS_QML" "command.length === 0 || !isAllowedDescriptorCommand(command, \"field\")"
require_in_file "$PROVIDERS_QML" "command.length === 0 || !isAllowedDescriptorCommand(command, \"action\")"
require_in_file "$PROVIDERS_QML" "if (!isAllowedDescriptorCommand(field.writeCommand, \"field\"))"
require_in_file "$PROVIDERS_QML" "if (!isAllowedDescriptorCommand(action.command, \"action\"))"
# A descriptor secret must only travel on the child process stdin. Expanding it
# into the `{value}` placeholder as well would also publish it in the process
# argv, where any local process can read it from /proc.
require_in_file "$PROVIDERS_QML" 'var isSecretField = field.kind === "secret"'
require_in_file "$PROVIDERS_QML" 'isSecretField ? ({}) : ({ "{value}": value }),'
require_in_file "$PROVIDERS_QML" 'isSecretField ? value : null)'
reject_text "configProviders.qml" "$(cat "$PROVIDERS_QML")" '({ "{value}": value }), field.kind === "secret" ? value : null)'
require_in_file "$PROVIDERS_QML" "function isSafeDescriptorUrl(url)"
require_in_file "$PROVIDERS_QML" "text.indexOf(\"https://\") === 0"
require_in_file "$PROVIDERS_QML" "var url = String(payload.value.url)"
require_in_file "$PROVIDERS_QML" "if (isSafeDescriptorUrl(url))"
for qml_file in "$MAIN_QML" "$PROVIDERS_QML"; do
  require_in_file "$qml_file" '!/^[a-z0-9][a-z0-9._-]*$/.test(key) || key.indexOf("..") !== -1'
  require_in_file "$qml_file" 'return "view-statistics"'
done
for qml_file in \
  "$MAIN_QML" \
  "$PROVIDERS_QML" \
  "$ROOT_DIR/contents/ui/components/CompactRepresentation.qml" \
  "$ROOT_DIR/contents/ui/components/OverviewProviderRow.qml" \
  "$ROOT_DIR/contents/ui/components/ProviderConfigRow.qml" \
  "$ROOT_DIR/contents/ui/components/ProviderHeader.qml"; do
  require_in_file "$qml_file" 'fallback: "view-statistics"'
done
require_in_file "$PROVIDERS_QML" "function descriptorPendingFieldKey(fieldID)"
require_in_file "$PROVIDERS_QML" "return JSON.stringify(value)"
require_in_file "$PROVIDERS_QML" "var field = descriptorPendingFieldKey(fieldID)"
reject_text "configProviders.qml" "$(cat "$PROVIDERS_QML")" "var field = providerMapKey(fieldID)"

reject_text "main.qml" "$(cat "$MAIN_QML")" '"sh", "-lc"'
reject_text "configProviders.qml" "$(cat "$PROVIDERS_QML")" '"sh", "-lc"'
require_in_file "$MAIN_QML" '["sh", "-c", shellQuote(script)]'
require_in_file "$PROVIDERS_QML" '["sh", "-c", shellQuote(script), "_", shellQuote(prompt)'

require_in_file "$MAIN_QML" "function safeStatusUrl(providerID, url)"
require_in_file "$MAIN_QML" "function httpsUrlHost(url)"
require_in_file "$MAIN_QML" "statusUrl: safeStatusUrl(providerID, status && status.url ? status.url : \"\")"
require_in_file "$MAIN_QML" "Qt.openUrlExternally(safeStatusUrl(item.provider, item.statusUrl))"

require_in_file "$MAIN_QML" "notify-send --app-name=CodexBar --icon=view-statistics --urgency="
require_in_file "$MAIN_QML" "+ \" -- \" + shellQuote(cleanTitle)"

for qml_file in "$PROVIDER_DETAIL_SECTION_QML" "$INTERACTIVE_CHART_QML"; do
  label_count="$(rg -c -F 'PlasmaComponents.Label {' "$qml_file")"
  plain_text_count="$(rg -c -F 'textFormat: Text.PlainText' "$qml_file")"
  if [[ "$plain_text_count" -ne "$label_count" ]]; then
    echo "every CLI/provider-controlled label must force plain text in ${qml_file#"$ROOT_DIR"/}" >&2
    exit 1
  fi
done

require_in_file "$MAKEFILE" "scripts/test_security_regressions.sh"

echo "Security regression checks passed."
