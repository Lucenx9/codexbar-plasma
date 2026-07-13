#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected UI fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_block_fragment() {
  local file="$1"
  local block_id="$2"
  local needle="$3"
  if ! awk -v block_id="$block_id" -v needle="$needle" '
    index($0, block_id) { in_block = 1 }
    in_block && index($0, needle) { found = 1 }
    in_block && $0 ~ /^        }$/ { exit }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    echo "missing expected UI fragment near ${block_id} in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected stale UI fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$GENERAL_QML" "id: lastUpdateCheckLabel"
require_in_file "$GENERAL_QML" "id: lastUpdateStatusLabel"
require_block_fragment "$GENERAL_QML" "id: lastUpdateCheckLabel" "Layout.fillWidth: true"
require_block_fragment "$GENERAL_QML" "id: lastUpdateCheckLabel" "wrapMode: Text.WordWrap"
require_block_fragment "$GENERAL_QML" "id: lastUpdateStatusLabel" "Layout.fillWidth: true"
require_block_fragment "$GENERAL_QML" "id: lastUpdateStatusLabel" "wrapMode: Text.WordWrap"

require_in_file "$PROVIDERS_QML" "Provider-specific controls come from the CodexBar CLI descriptor"
reject_in_file "$PROVIDERS_QML" "Provider-specific editing stays in the CodexBar CLI until it exposes a stable settings descriptor"

python3 - "$ROOT_DIR" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
main_qml = root / "contents/ui/main.qml"
general_qml = root / "contents/ui/configGeneral.qml"
display_qml = root / "contents/ui/configDisplay.qml"
providers_qml = root / "contents/ui/configProviders.qml"
provider_header_qml = root / "contents/ui/components/ProviderHeader.qml"
provider_config_row_qml = root / "contents/ui/components/ProviderConfigRow.qml"


def function_body(text, name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"missing function {name}")
    brace = text.find("{", start)
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated function {name}")
    return text[brace + 1:index - 1]


def id_block(text, object_id):
    marker = f"id: {object_id}"
    marker_index = text.find(marker)
    if marker_index < 0:
        raise AssertionError(f"missing id {object_id}")
    brace = text.rfind("{", 0, marker_index)
    if brace < 0:
        raise AssertionError(f"missing object body for id {object_id}")
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated object body for id {object_id}")
    return text[brace + 1:index - 1]


def extract_switch_returns(text, name):
    body = function_body(text, name)
    values = {}
    pending = []
    for line in body.splitlines():
        stripped = line.strip()
        case_match = re.match(r'case "([^"]+)":', stripped)
        if case_match:
            pending.append(case_match.group(1))
            continue
        return_match = re.match(r'return "([^"]*)"', stripped)
        if return_match and pending:
            for provider in pending:
                values[provider] = return_match.group(1)
            pending = []
        elif stripped.startswith("default:"):
            pending = []
    return values


main_text = main_qml.read_text(encoding="utf-8")
general_text = general_qml.read_text(encoding="utf-8")
display_text = display_qml.read_text(encoding="utf-8")
providers_text = providers_qml.read_text(encoding="utf-8")
provider_header_text = provider_header_qml.read_text(encoding="utf-8")
provider_config_row_text = provider_config_row_qml.read_text(encoding="utf-8")


def assert_form_sections(text, filename, labels):
    for label in labels:
        pattern = re.compile(
            r"Kirigami\.Separator\s*\{[^}]*"
            + re.escape(f'Kirigami.FormData.label: i18n("{label}")')
            + r"[^}]*Kirigami\.FormData\.isSection:\s*true",
            re.S,
        )
        if not pattern.search(text):
            raise AssertionError(
                f"{filename} must expose a FormLayout section labelled {label!r}"
            )


assert_form_sections(
    general_text,
    "configGeneral.qml",
    ("Command", "Refresh", "Usage", "Notifications", "Updates"),
)
assert_form_sections(
    display_text,
    "configDisplay.qml",
    ("Panel", "Usage details", "Overview"),
)

if "—" in main_text or "–" in main_text:
    raise AssertionError("main.qml must avoid em dash/en dash placeholders in visible UI text")

for function_name in ("providerDashboardUrl", "providerLoginUrl"):
    main_values = extract_switch_returns(main_text, function_name)
    provider_values = extract_switch_returns(providers_text, function_name)
    if main_values != provider_values:
        missing = sorted(set(main_values) - set(provider_values))
        extra = sorted(set(provider_values) - set(main_values))
        changed = sorted(
            key for key in set(main_values) & set(provider_values)
            if main_values[key] != provider_values[key]
        )
        raise AssertionError(
            f"{function_name} drift between main.qml and configProviders.qml; "
            f"missing={missing}, extra={extra}, changed={changed}"
        )

for source_text, label in ((main_text, "main.qml"), (providers_text, "configProviders.qml")):
    docs_body = function_body(source_text, "providerDocsUrl")
    color_body = function_body(source_text, "providerColor")
    title_body = function_body(source_text, "providerTitle")
    if 'wayfinder: "wayfinder.md"' not in docs_body:
        raise AssertionError(f"{label} must expose the Wayfinder documentation link")
    if 'case "wayfinder":' not in color_body:
        raise AssertionError(f"{label} must expose the Wayfinder brand color")
    if '"wayfinder": i18n("Wayfinder")' not in title_body:
        raise AssertionError(f"{label} must expose the Wayfinder display name")

api_key_setup_body = function_body(providers_text, "supportsApiKeySetup")
for provider in ("crossmodel", "clawrouter"):
    if f'case "{provider}":' not in api_key_setup_body:
        raise AssertionError(
            f"supportsApiKeySetup must include released API-key provider {provider}"
        )

toggle_body = function_body(providers_text, "handleToggleResult")
if "stderrText.trim()" not in toggle_body or "exitCode" not in toggle_body:
    raise AssertionError("handleToggleResult must treat stderr/exit-code failures as errors")

handle_data_body = function_body(providers_text, "handleData")
for handler_call in (
    "handleSetApiKeyResult(descriptor, stdoutText, stderrText, exitCode)",
    "handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode)",
    "handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode)",
):
    if handler_call not in handle_data_body:
        raise AssertionError(
            "Provider mutation handlers must receive the executable exit code; "
            f"missing {handler_call!r}"
        )

set_api_key_body = function_body(providers_text, "handleSetApiKeyResult")
if "Number(exitCode) !== 0" not in set_api_key_body:
    raise AssertionError("handleSetApiKeyResult must reject non-zero CLI exits")

parse_command_payload_body = function_body(providers_text, "parseCommandPayload")
if "Number(exitCode) !== 0" not in parse_command_payload_body:
    raise AssertionError("parseCommandPayload must reject non-zero descriptor command exits")

# Overview selection is stored with the raw CLI provider IDs (e.g. groqcloud,
# alibaba-coding-plan) but matched at runtime against providerKey-normalized
# IDs (groq, alibaba). configuredOverviewProviderIDs must normalize on read so
# the custom selection is not silently ignored for aliased providers.
overview_body = function_body(main_text, "configuredOverviewProviderIDs")
if "providerKey(" not in overview_body:
    raise AssertionError(
        "configuredOverviewProviderIDs must normalize IDs via providerKey so "
        "aliased providers match runtime keys"
    )

provider_config_body = function_body(main_text, "parseProviderConfigOutput")
if "Array.isArray(payload) ? payload : [payload]" not in provider_config_body:
    raise AssertionError(
        "parseProviderConfigOutput must accept a single provider object as well "
        "as the normal provider-list array"
    )

config_watch_body = function_body(main_text, "buildProviderConfigWatchCommand")
for config_path_fragment in (
    "CODEXBAR_CONFIG",
    "XDG_CONFIG_HOME",
    "$HOME/.config/codexbar/config.json",
    "$HOME/.codexbar/config.json",
):
    if config_path_fragment not in config_watch_body:
        raise AssertionError(
            "buildProviderConfigWatchCommand must mirror the CLI config path resolver; "
            f"missing {config_path_fragment!r}"
        )
if config_watch_body.index("CODEXBAR_CONFIG") > config_watch_body.index("XDG_CONFIG_HOME"):
    raise AssertionError("CODEXBAR_CONFIG must take precedence over XDG_CONFIG_HOME")

retire_body = function_body(main_text, "retireUsageCommands")
for stale_account_fragment in (
    "for (var accountCommand in pendingAccountCommands)",
    "pendingAccountCommands = ({})",
    "accountLoading = ({})",
):
    if stale_account_fragment in retire_body:
        raise AssertionError(
            "retireUsageCommands must not drop in-flight account loads during "
            f"refresh; found {stale_account_fragment!r}"
        )

display_load_body = function_body(display_text, "loadOverviewProviders")
if "disconnectOverviewProviderCommands()" not in display_load_body:
    raise AssertionError(
        "loadOverviewProviders must invalidate older overview provider commands "
        "before connecting a replacement"
    )
if "function disconnectOverviewProviderCommands()" not in display_text:
    raise AssertionError("configDisplay.qml must define disconnectOverviewProviderCommands")

provider_index_body = function_body(main_text, "providerIndex")
if "return -1" not in provider_index_body or "return 0" in provider_index_body:
    raise AssertionError("providerIndex must return -1 instead of falling back to provider 0")
if "var nextProviderIndex = root.providerIndex(providerData)" not in main_text or "if (nextProviderIndex >= 0)" not in main_text:
    raise AssertionError("Overview provider selection must ignore missing providers instead of selecting index 0")

bounded_revision_body = function_body(main_text, "boundedConfigRevision")
if "2147480000" not in bounded_revision_body or "1000000" in bounded_revision_body:
    raise AssertionError("boundedConfigRevision must use the same cap as bumpProviderConfigRevision")

parse_cost_body = function_body(main_text, "parseCostOutput")
if "codexbar cost did not return JSON." not in parse_cost_body:
    raise AssertionError("parseCostOutput must keep a visible fallback error when cost returns no JSON")
for cost_error_fragment in (
    'var costMessage = ""',
    "item.error && item.error.message",
    'costErrorText = costCount === 0 ? costMessage : ""',
):
    if cost_error_fragment not in parse_cost_body:
        raise AssertionError(
            "parseCostOutput must surface CLI JSON errors when no cost rows are valid; "
            f"missing {cost_error_fragment!r}"
        )

token_cost_section_body = id_block(main_text, "tokenCostSection")
if "root.costErrorText" not in token_cost_section_body:
    raise AssertionError("tokenCostSection must surface costErrorText instead of dropping cost errors")
if "Cost unavailable: %1" not in token_cost_section_body:
    raise AssertionError("tokenCostSection must label visible cost errors")

normalize_token_cost_body = function_body(main_text, "normalizeTokenCost")
if "costHistoryWindowLabel(item)" not in normalize_token_cost_body:
    raise AssertionError("normalizeTokenCost must use the configured cost history window label fallback")
if "function costHistoryWindowLabel(item)" not in main_text:
    raise AssertionError("main.qml must define costHistoryWindowLabel")

add_window_body = function_body(main_text, "addWindow")
if "pace.expectedUsedPercent !== null" not in add_window_body or "pace.expectedUsedPercent !== undefined" not in add_window_body:
    raise AssertionError("addWindow must not treat null pace.expectedUsedPercent as 0")

accounts_body = function_body(main_text, "parseProviderAccountsOutput")
if "var dedupedOptions = dedupeAccountOptions(options)" not in accounts_body:
    raise AssertionError("parseProviderAccountsOutput must decide errors after account option dedupe")
if "var accountError = \"\"" not in accounts_body:
    raise AssertionError("parseProviderAccountsOutput must build account errors separately from account options")
if "dedupedOptions.length === 0" not in accounts_body or "else if (items.length > 0 && !sawMissingTokenAccountsError)" not in accounts_body:
    raise AssertionError("parseProviderAccountsOutput must not treat a valid empty account list as an error")
if "isMissingTokenAccountsError(normalized.error)" not in accounts_body:
    raise AssertionError(
        "parseProviderAccountsOutput must treat 'No token accounts configured' as an "
        "empty account list, not a red error, so OAuth/CLI-auth providers stay clean"
    )
if "function isMissingTokenAccountsError(errorMessage)" not in main_text:
    raise AssertionError("main.qml must define isMissingTokenAccountsError")
missing_accounts_body = function_body(main_text, "isMissingTokenAccountsError")
if 'String(errorMessage || "")' not in missing_accounts_body:
    raise AssertionError(
        "isMissingTokenAccountsError must coerce CLI error messages before "
        "calling string helpers so malformed JSON cannot abort account parsing"
    )
if "setAccountError(providerID, accountError)" not in accounts_body:
    raise AssertionError("parseProviderAccountsOutput must set the post-dedupe account error")
if "message.length > 0 ? message : i18n(\"codexbar did not return account data.\")" in accounts_body:
    raise AssertionError("parseProviderAccountsOutput must not fabricate an account error for JSON []")

dedupe_accounts_body = function_body(main_text, "dedupeAccountOptions")
if 'var key = "account:" + label' not in dedupe_accounts_body:
    raise AssertionError("dedupeAccountOptions must namespace labels before object-map lookup")
if "hasOwnKey(seen, key)" not in dedupe_accounts_body:
    raise AssertionError(
        "dedupeAccountOptions must use an own-property check so labels such as "
        "constructor and toString remain selectable"
    )
if "seen[label]" in dedupe_accounts_body:
    raise AssertionError("dedupeAccountOptions must not look up raw labels on Object.prototype")

header_sources = {
    "overviewHeaderRow": main_text,
    "providerHeaderRow": provider_header_text,
}
for header_id, source_text in header_sources.items():
    header_body = id_block(source_text, header_id)
    if "Layout.rightMargin: Kirigami.Units.smallSpacing" not in header_body:
        raise AssertionError(
            f"{header_id} must align header actions with the inset scroll content"
        )

for scroll_id in ("overviewScroll", "providerScroll"):
    scroll_body = id_block(main_text, scroll_id)
    if "readonly property real contentRightInset: Kirigami.Units.gridUnit" not in scroll_body:
        raise AssertionError(f"{scroll_id} must reserve a full scrollbar gutter on the right edge")
    if "rightPadding: contentRightInset" not in scroll_body:
        raise AssertionError(f"{scroll_id} must reserve padding on the right edge")
    if "contentWidth: availableWidth" not in scroll_body:
        raise AssertionError(f"{scroll_id} content width must follow Qt ScrollView availableWidth")
    if f"width: {scroll_id}.availableWidth" not in scroll_body:
        raise AssertionError(f"{scroll_id} content column must follow the padded available width")

provider_scroll_body = id_block(main_text, "providerScroll")
if "rightPadding: contentRightInset" not in provider_scroll_body:
    raise AssertionError(
        "providerScroll must keep provider details away from the right popup edge"
    )

provider_header_body = id_block(provider_header_text, "providerHeaderRow")
for header_fragment in (
    "id: providerTitleRow",
    "id: providerMetaRow",
    "id: providerAccountLabel",
    "id: providerPlanLabel",
):
    if header_fragment not in provider_header_body:
        raise AssertionError(f"providerHeaderRow must expose {header_fragment} for stable header layout")

provider_account_label_body = id_block(provider_header_text, "providerAccountLabel")
if "Layout.maximumWidth: Kirigami.Units.gridUnit * 16" not in provider_account_label_body:
    raise AssertionError("providerAccountLabel must cap long account text before the refresh edge")
if "providerHeaderRow.width" in provider_account_label_body or "providerMetaRow.width" in provider_account_label_body:
    raise AssertionError("providerAccountLabel must not bind its width to the header layout width")

provider_plan_label_body = id_block(provider_header_text, "providerPlanLabel")
if "Layout.maximumWidth: Kirigami.Units.gridUnit * 5" not in provider_plan_label_body:
    raise AssertionError("providerPlanLabel must keep plan text from crowding provider metadata")

cost_drill_down_body = id_block(main_text, "costDrillDownSection")
if "readonly property real metricValueColumnWidth: Kirigami.Units.gridUnit * 9" not in cost_drill_down_body:
    raise AssertionError("costDrillDownSection must define a stable value column width")
for value_label in ("costBreakdownValueLabel", "costModelValueLabel", "costDailyValueLabel"):
    value_label_body = id_block(main_text, value_label)
    if "Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth" not in value_label_body:
        raise AssertionError(f"{value_label} must use the shared metric value column width")
    if "Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth" not in value_label_body:
        raise AssertionError(f"{value_label} must cap the shared metric value column width")

action_rows_body = function_body(main_text, "actionRows")
if 'action: "refresh", enabled: true, separatorBefore: true' not in action_rows_body:
    raise AssertionError("actionRows must separate provider actions from widget-level actions")

provider_action_rows_body = id_block(main_text, "providerActionRows")
for action_fragment in (
    "id: providerActionGroupSeparator",
    "visible: modelData.separatorBefore === true",
):
    if action_fragment not in provider_action_rows_body:
        raise AssertionError(f"providerActionRows must expose {action_fragment} for grouped menu actions")

for selected_row_fragment in (
    "readonly property color selectedForeground",
    "readonly property color selectedSecondaryForeground",
    "color: providerRow.highlighted ? providerRow.selectedForeground",
    "color: providerRow.highlighted ? providerRow.selectedSecondaryForeground",
):
    if selected_row_fragment not in provider_config_row_text:
        raise AssertionError(
            "ProviderConfigRow selected state must set explicit contrast-aware "
            f"text colors; missing {selected_row_fragment!r}"
        )

# Status notifications must fire on first sight, worsened severity, and changed
# same-severity stable incident keys so active incident replacements are not
# missed without letting free-form status text changes spam notifications.
status_body = function_body(main_text, "processStatusNotification")
if "worsened" not in status_body:
    raise AssertionError("processStatusNotification must gate on severity worsening")
if (
    "incidentChanged" not in status_body
    or "previousIncidentKey" not in status_body
    or "currentIncidentKey" not in status_body
    or "previousIncidentKey !== currentIncidentKey" not in status_body
):
    raise AssertionError(
        "processStatusNotification must only notify for same-severity changes "
        "when a stable status incident key is present"
    )
if "previousValue !== value" in status_body:
    raise AssertionError(
        "processStatusNotification must compare incident keys instead of full "
        "severity-bearing memo values"
    )

status_value_body = function_body(main_text, "notificationStatusValue")
if "statusIncidentKey" not in status_value_body:
    raise AssertionError("notificationStatusValue must prefer stable incident keys when present")
if 'item.statusSeverity + "|" + incidentKey' not in status_value_body:
    raise AssertionError("notificationStatusValue must include severity and stable incident key")
if ': item.status' in status_value_body:
    raise AssertionError("notificationStatusValue must not fall back to provider-controlled status text")

# autoSelectProvider must not clobber an explicit Overview selection on every
# refresh; once the user picks Overview the selection has to survive.
select_body = function_body(main_text, "updateSelectedProvider")
if "overviewSelected" not in select_body:
    raise AssertionError(
        "updateSelectedProvider must preserve an explicit Overview selection "
        "when autoSelectProvider is enabled"
    )
PY

echo "UI regression checks passed."
