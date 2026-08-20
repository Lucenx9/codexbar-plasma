#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
# Rules that must hold once per surface use require_in_surface. The loops below
# keep explicit file lists on purpose: "every one of these files must carry the
# safe icon fallback" is a per-file contract, and a surface-wide check would be
# satisfied by any single file having it.
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
DISPLAY_QML="${ROOT_DIR}/contents/ui/configDisplay.qml"
DEBUG_QML="${ROOT_DIR}/contents/ui/configDebug.qml"
SAFE_TEXT_JS="${ROOT_DIR}/contents/ui/SafeText.js"
PROVIDER_IDENTITY_JS="${ROOT_DIR}/contents/ui/ProviderIdentity.js"
NOTIFICATION_PLANNER_JS="${ROOT_DIR}/contents/ui/NotificationPlanner.js"
WORKFLOW="${ROOT_DIR}/.github/workflows/ci.yml"
MAKEFILE="${ROOT_DIR}/Makefile"
UPDATER="${ROOT_DIR}/scripts/update-widget.sh"
FULL_REPRESENTATION_QML="${ROOT_DIR}/contents/ui/components/FullRepresentation.qml"
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
require_in_file "$WORKFLOW" "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
reject_text "workflow" "$(cat "$WORKFLOW")" "actions/checkout@v4"
reject_text "workflow" "$(cat "$WORKFLOW")" "image: kdeneon/plasma:user"
require_in_file "$WORKFLOW" "dist/codexbar-plasma.plasmoid.sha256"
require_in_file "$MAKEFILE" "sha256sum codexbar-plasma.plasmoid > codexbar-plasma.plasmoid.sha256"
require_in_file "$UPDATER" "sha256sum --check --strict"

for qml_file in "$MAIN_QML" "$PROVIDERS_QML" "$DISPLAY_QML" "$DEBUG_QML"; do
  require_in_file "$qml_file" 'import "SafeText.js" as SafeText'
done
require_in_surface applet "SafeText.cliMessage"
require_in_surface providers "SafeText.cliMessage"
require_in_file "$DISPLAY_QML" "SafeText.cliMessage"
require_in_file "$DEBUG_QML" "SafeText.cliDiagnostic"
require_in_file "$SAFE_TEXT_JS" "function redactCredentials(value, inspectionLimit)"
require_in_file "$SAFE_TEXT_JS" "maximumDiagnosticLength = 65536"
require_in_file "$SAFE_TEXT_JS" "maximumCliJsonLength = 4 * 1024 * 1024"
require_in_file "$SAFE_TEXT_JS" "function boundedInspectionText(value, inspectionLimit, lookaheadLength)"
require_in_file "$SAFE_TEXT_JS" 'chunk.search(/[^\s\u0000-\u001f\u007f]/)'
require_in_file "$SAFE_TEXT_JS" "credentialRedactionLookaheadLength"
require_in_file "$SAFE_TEXT_JS" 'redactedLookaheadText.slice(0, redactedText.length) !== redactedText'
require_in_file "$SAFE_TEXT_JS" "function cliJsonText(value)"

GUARDS_JS="${ROOT_DIR}/contents/ui/Guards.js"

# QML and JS files share no function scope, so every file that calls these
# unqualified must still declare them. The body is now a delegation, so the
# guard itself lives once in Guards.js and is covered behaviourally by
# tests/tst_guards.qml instead of being searched for inside each copy.
require_definition_where_used applet hasOwnKey
require_definition_where_used applet isUnsafeObjectKey
require_definition_where_used applet copyObject
require_definition_where_used applet shellQuote
require_definition_where_used providers hasOwnKey

# The guards themselves live once. `require_definition_where_used` above keeps
# every calling file bound to a declaration; these assert the declaration is a
# delegation and that exactly one file still carries the implementation, so a
# re-inlined copy cannot drift away from the tested one.
require_in_file "$GUARDS_JS" "Object.prototype.hasOwnProperty.call(item, key)"
require_in_file "$GUARDS_JS" 'var value = String(key || "")'
require_in_file "$GUARDS_JS" 'value === "__proto__" || value === "constructor" || value === "prototype"'
require_in_file "$GUARDS_JS" "String(value).replace(/'/g"
require_in_file "$NOTIFICATION_PLANNER_JS" "return Guards.copyObject(memo || ({}))"

for guard_body in \
  "Object.prototype.hasOwnProperty.call(item, key)" \
  "String(value).replace(/'/g" \
; do
  guard_files="$(cd "$ROOT_DIR" && grep -rlF "$guard_body" --include='*.qml' --include='*.js' contents/ | sort | tr '\n' ' ')"
  if [[ "$guard_files" != "contents/ui/Guards.js " ]]; then
    echo "guard implementation must live only in contents/ui/Guards.js: ${guard_body}" >&2
    echo "found in: ${guard_files}" >&2
    exit 1
  fi
done
require_in_surface applet "function providerMapKey(providerID)"
require_in_surface applet 'import "ProviderIdentity.js" as ProviderIdentity'
# The applet reaches the shared screen through the normalizer, which resolves CLI
# aliases first so an alias cannot smuggle in a key the screen would have caught.
require_in_surface applet "return ProviderIdentity.providerMapKey(ProviderIdentity.resolveProviderKey(providerID))"
require_in_file "$PROVIDER_IDENTITY_JS" "Object.prototype.hasOwnProperty.call(Object.prototype, key)"
require_in_surface applet "if (name.length === 0 || isUnsafeObjectKey(name))"
require_in_surface applet "if (!hasOwnKey(byName, name))"
require_in_surface applet "if (!hasOwnKey(byName, modelName))"
require_in_surface applet "if (!hasOwnKey(item, key) || isUnsafeObjectKey(key))"
require_in_surface applet "var providerID = normalizedProviderID(items[i].provider)"
require_in_surface applet "var providerID = providerMapKey(item.provider)"
require_in_surface applet "var providerID = providerMapKey(item.provider || \"unknown\")"
require_in_surface applet "var key = providerMapKey(providerID)"
require_in_surface providers "function providerMapKey(providerID)"
require_in_surface providers "return ProviderIdentity.providerMapKey(key)"
# Guards.js is not part of the providers surface, so assert the delegation here;
# the filtering rule itself is covered by tests/tst_guards.qml.
require_in_surface providers "return Guards.copyObject(item)"
require_in_surface providers 'import "Guards.js" as Guards'
require_definition_where_used providers hasOwnKey "Guards.hasOwnKey(item, key)"
require_in_surface applet "maximumConcurrentProviderFallbackCommands: 8"
require_in_surface applet "nextProviders.length < maximumProviderSnapshots"
require_in_surface applet "value: boundedDisplayText(parts.join(\" · \"), 500)"
# The icon file name is built from a provider-controlled key, so that key is
# bounded and pattern-checked before it can name a path. Both surfaces reach that
# validation through providerIconFileName, so it is asserted once where it lives.
require_in_file "$PROVIDER_IDENTITY_JS" "var key = providerMapKey(resolveProviderKey(value))"
require_in_file "$PROVIDER_IDENTITY_JS" 'if (!/^[a-z0-9][a-z0-9._-]*$/.test(key) || key.indexOf("..") !== -1) {'
require_in_surface applet "var fileName = ProviderIdentity.providerIconFileName(value)"
require_in_surface providers "var fileName = ProviderIdentity.providerIconFileName(value)"
require_in_surface providers "function isAllowedCommand(commandTokens, purpose)"
require_in_surface providers "String(commandTokens[0]) !== \"codexbar\""
require_in_surface providers "String(commandTokens[1]) !== \"config\""
require_in_surface providers "subcommand === \"set\" || subcommand === \"set-api-key\""
require_in_surface providers "subcommand === \"action\""
require_in_surface providers "command.length === 0 || !isAllowedCommand(command, \"field\")"
require_in_surface providers "command.length === 0 || !isAllowedCommand(command, \"action\")"
require_in_surface providers "!isAllowedCommand(field.writeCommand, \"field\")"
require_in_surface providers "!isAllowedCommand(action.command, \"action\")"
# A descriptor secret must never reach a command line at all. /proc/<pid>/cmdline
# is world-readable, so routing the value through `sh -c script _ "$secret"`
# leaks it exactly like an expanded `{value}` placeholder would. Only
# promptDescriptorSecret may carry a secret, and it reads the value inside the
# script instead of receiving it as an argument.
require_in_surface providers 'if (field.kind === "secret") {'
require_in_surface providers "function planSecretPrompt(field, commandPath)"
reject_in_surface providers 'shellQuote(stdinValue)'
reject_in_surface providers '({ "{value}": value }), field.kind === "secret" ? value : null)'
require_in_surface providers "function safeHttpsUrl(value)"
require_in_surface providers "text.toLowerCase().indexOf(\"https://\") === 0"
require_in_surface providers "var url = String(payload.value.url)"
require_in_surface providers "var safeUrl = ProviderDescriptor.safeHttpsUrl(url)"
# The key validation itself is asserted once above, against ProviderIdentity.js.
# What each surface still owns is the refusal: an unusable key must fall back to
# a generic icon rather than reaching Qt.resolvedUrl.
for qml_file in "$MAIN_QML" "$PROVIDERS_QML"; do
  require_in_file "$qml_file" 'if (fileName.length === 0) {'
  require_in_file "$qml_file" 'return "view-statistics"'
done
for qml_file in \
  "$FULL_REPRESENTATION_QML" \
  "$PROVIDERS_QML" \
  "$ROOT_DIR/contents/ui/components/CompactRepresentation.qml" \
  "$ROOT_DIR/contents/ui/components/OverviewProviderRow.qml" \
  "$ROOT_DIR/contents/ui/components/ProviderConfigRow.qml" \
  "$ROOT_DIR/contents/ui/components/ProviderHeader.qml"; do
  require_in_file "$qml_file" 'fallback: "view-statistics"'
done
require_in_surface providers "function descriptorPendingFieldKey(fieldID)"
require_in_surface providers "return JSON.stringify(value)"
require_in_surface providers "var field = descriptorPendingFieldKey(fieldID)"
reject_text "configProviders.qml" "$(cat "$PROVIDERS_QML")" "var field = providerMapKey(fieldID)"

reject_text "main.qml" "$(cat "$MAIN_QML")" '"sh", "-lc"'
reject_text "configProviders.qml" "$(cat "$PROVIDERS_QML")" '"sh", "-lc"'
require_in_surface applet '["sh", "-c", shellQuote(script)]'
require_in_file "$PROVIDERS_QML" '["sh", "-c", shellQuote(script), "_", shellQuote(prompt)'

require_in_surface applet "function safeStatusUrl(providerID, url)"
require_in_surface applet "function httpsUrlHost(url)"
require_in_surface applet "statusUrl: safeStatusUrl(providerID, status && status.url ? status.url : \"\")"
require_in_surface applet "Qt.openUrlExternally(safeStatusUrl(item.provider, item.statusUrl))"

require_in_surface applet "notify-send --app-name=CodexBar --icon=view-statistics --urgency="
require_in_surface applet "+ \" -- \" + shellQuote(cleanTitle)"

for qml_file in "$PROVIDER_DETAIL_SECTION_QML" "$INTERACTIVE_CHART_QML"; do
  label_count="$(grep -c -F 'PlasmaComponents.Label {' "$qml_file" || true)"
  plain_text_count="$(grep -c -F 'textFormat: Text.PlainText' "$qml_file" || true)"
  if [[ "$plain_text_count" -ne "$label_count" ]]; then
    echo "every CLI/provider-controlled label must force plain text in ${qml_file#"$ROOT_DIR"/}" >&2
    exit 1
  fi
done

require_in_file "$MAKEFILE" "scripts/test_security_regressions.sh"
require_in_file "$MAKEFILE" "scripts/test_qml_hardening.sh"
reject_text "Makefile" "$(cat "$MAKEFILE")" 'QML_FILES := $(shell'
reject_text "Makefile" "$(cat "$MAKEFILE")" '$(QML_FILES)'

echo "Security regression checks passed."
