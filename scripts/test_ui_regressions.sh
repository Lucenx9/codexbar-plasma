#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
ADVANCED_QML="${ROOT_DIR}/contents/ui/configAdvanced.qml"
README_MD="${ROOT_DIR}/README.md"

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
require_block_fragment "$GENERAL_QML" "id: usePathCommandButton" 'text: i18n("Use PATH")'
require_block_fragment "$GENERAL_QML" "id: usePathCommandButton" 'enabled: page.cfg_commandPath.trim() !== (page.cfg_commandPathDefault || "codexbar")'
require_block_fragment "$GENERAL_QML" "id: usePathCommandButton" 'page.cfg_commandPath = page.cfg_commandPathDefault || "codexbar"'

require_in_file "$README_MD" "command -v codexbar"
reject_in_file "$README_MD" "yay -S codexbar-cli"
reject_in_file "$README_MD" 'for example `/usr/bin/codexbar`'

require_in_file "$PROVIDERS_QML" "Provider-specific controls come from the CodexBar CLI descriptor"
reject_in_file "$PROVIDERS_QML" "Provider-specific editing stays in the CodexBar CLI until it exposes a stable settings descriptor"
require_in_file "$ADVANCED_QML" "id: advancedOverrideExplanation"

python3 - "$ROOT_DIR" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
main_qml = root / "contents/ui/main.qml"
general_qml = root / "contents/ui/configGeneral.qml"
display_qml = root / "contents/ui/configDisplay.qml"
providers_qml = root / "contents/ui/configProviders.qml"
advanced_qml = root / "contents/ui/configAdvanced.qml"
theme_contrast_js = root / "contents/ui/ThemeContrast.js"
provider_accounts_panel_qml = root / "contents/ui/components/ProviderAccountsPanel.qml"
provider_header_qml = root / "contents/ui/components/ProviderHeader.qml"
provider_config_row_qml = root / "contents/ui/components/ProviderConfigRow.qml"
provider_usage_row_qml = root / "contents/ui/components/ProviderUsageRow.qml"
overview_provider_row_qml = root / "contents/ui/components/OverviewProviderRow.qml"
provider_detail_section_qml = root / "contents/ui/components/ProviderDetailSection.qml"
compact_representation_qml = root / "contents/ui/components/CompactRepresentation.qml"


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
        return_match = re.match(r"return\s+(.+?);?$", stripped)
        if return_match and pending:
            for provider in pending:
                values[provider] = return_match.group(1)
            pending = []
        elif stripped.startswith("default:"):
            pending = []
    return values


def extract_object_entries(text, function_name, variable_name):
    body = function_body(text, function_name)
    marker = f"var {variable_name} = {{"
    start = body.find(marker)
    if start < 0:
        raise AssertionError(f"missing {variable_name} catalog in {function_name}")
    entries = {}
    for line in body[start + len(marker):].splitlines():
        stripped = line.strip()
        if stripped == "}":
            break
        match = re.match(r'(?:"([^"]+)"|([A-Za-z0-9_]+)):\s*(.+?)(?:,)?$', stripped)
        if match:
            key = match.group(1) or match.group(2)
            entries[key] = match.group(3).removesuffix(",")
    return entries


main_text = main_qml.read_text(encoding="utf-8")
general_text = general_qml.read_text(encoding="utf-8")
display_text = display_qml.read_text(encoding="utf-8")
providers_text = providers_qml.read_text(encoding="utf-8")
advanced_text = advanced_qml.read_text(encoding="utf-8")
theme_contrast_text = theme_contrast_js.read_text(encoding="utf-8")
provider_accounts_panel_text = provider_accounts_panel_qml.read_text(encoding="utf-8")
provider_header_text = provider_header_qml.read_text(encoding="utf-8")
provider_config_row_text = provider_config_row_qml.read_text(encoding="utf-8")
provider_usage_row_text = provider_usage_row_qml.read_text(encoding="utf-8")
overview_provider_row_text = overview_provider_row_qml.read_text(encoding="utf-8")
provider_detail_section_text = provider_detail_section_qml.read_text(encoding="utf-8")
compact_representation_text = compact_representation_qml.read_text(encoding="utf-8")


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

for runtime_cfg in (
    "cfg_autoUpdateLastCheck",
    "cfg_widgetUpdateLastStatus",
    "cfg_widgetUpdateLastError",
    "cfg_providerConfigRevision",
):
    if runtime_cfg in general_text:
        raise AssertionError(
            f"configGeneral.qml must not save runtime-owned {runtime_cfg} on Apply"
        )
for live_config_fragment in (
    "Plasmoid.configuration.autoUpdateLastCheck",
    "Plasmoid.configuration.widgetUpdateLastStatus",
    "Plasmoid.configuration.widgetUpdateLastError",
):
    if live_config_fragment not in general_text:
        raise AssertionError(
            "configGeneral.qml must read update status directly from runtime config; "
            f"missing {live_config_fragment!r}"
        )

if "—" in main_text or "–" in main_text:
    raise AssertionError("main.qml must avoid em dash/en dash placeholders in visible UI text")

for function_name in (
    "providerCliArgument",
    "providerColor",
    "providerDashboardUrl",
    "providerLoginUrl",
):
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

for function_name, variable_name in (
    ("providerKey", "aliases"),
    ("providerIconSource", "aliases"),
    ("providerTitle", "names"),
    ("providerDocsUrl", "docs"),
):
    main_values = extract_object_entries(main_text, function_name, variable_name)
    provider_values = extract_object_entries(providers_text, function_name, variable_name)
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
if "trimmed.length === 0" not in parse_command_payload_body or "codexbar did not return command data." not in parse_command_payload_body:
    raise AssertionError("parseCommandPayload must reject an empty successful descriptor response")

# Overview selection is stored with the raw CLI provider IDs (e.g. groqcloud,
# alibaba-coding-plan) but matched at runtime against providerKey-normalized
# IDs (groq, alibaba). configuredOverviewProviderIDs must validate and normalize on read so
# the custom selection is not silently ignored for aliased providers.
overview_body = function_body(main_text, "configuredOverviewProviderIDs")
if "normalizedProviderID(" not in overview_body:
    raise AssertionError(
        "configuredOverviewProviderIDs must normalize and validate provider IDs so "
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

provider_index_body = function_body(main_text, "providerIndexForID")
if "return -1" not in provider_index_body or "return 0" in provider_index_body:
    raise AssertionError("providerIndexForID must return -1 instead of falling back to provider 0")
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
    "costErrorText = costMessage",
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
if "supportsLocalCost" not in token_cost_section_body:
    raise AssertionError("tokenCostSection must scope global cost errors to supported providers")

normalize_token_cost_body = function_body(main_text, "normalizeTokenCost")
if "costHistoryWindowLabel(item)" not in normalize_token_cost_body:
    raise AssertionError("normalizeTokenCost must use the configured cost history window label fallback")
if "function costHistoryWindowLabel(item)" not in main_text:
    raise AssertionError("main.qml must define costHistoryWindowLabel")

add_window_body = function_body(main_text, "addWindow")
if "pace.expectedUsedPercent !== null" not in add_window_body or "pace.expectedUsedPercent !== undefined" not in add_window_body:
    raise AssertionError("addWindow must not treat null pace.expectedUsedPercent as 0")
for reset_source_fragment in (
    "resetsAt: boundedDisplayText(",
    "resetDescription: boundedDisplayText(",
    "reset: boundedDisplayText(",
):
    if reset_source_fragment not in add_window_body:
        raise AssertionError("addWindow must retain raw reset data for render-time formatting")
if "onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)" in main_text:
    raise AssertionError("changing reset formatting must not fan out new CLI requests")

refresh_body = function_body(main_text, "refreshNow")
if "refreshCost()" not in refresh_body:
    raise AssertionError("refreshNow must retire or refresh cost work before every return")
fallback_body = function_body(main_text, "canUseProviderFallback")
if not re.fullmatch(
    r"\s*return\s+source\.length\s*===\s*0\s*\|\|\s*hasSelectedAccountOverrides\(\)\s*",
    fallback_body,
    re.S,
):
    raise AssertionError("account overrides must force provider-scoped refreshes even with a source override")
selected_overrides_body = function_body(main_text, "hasSelectedAccountOverrides")
for selected_fragment in ("selectedAccounts", "hasOwnKey(selectedAccounts, providerID)", "String(selectedAccounts[providerID] || \"\").length > 0"):
    if selected_fragment not in selected_overrides_body:
        raise AssertionError(
            "hasSelectedAccountOverrides must detect configured provider accounts; "
            f"missing {selected_fragment!r}"
        )
if not re.search(
    r"if\s*\(hasOwnKey\(selectedAccounts,\s*providerID\).*?String\(selectedAccounts\[providerID\]\s*\|\|\s*\"\"\)\.length\s*>\s*0\)\s*\{\s*return\s+true\s*\}",
    selected_overrides_body,
    re.S,
):
    raise AssertionError("a populated selected-account override must return true")
if not re.search(r"return\s+false\s*$", selected_overrides_body):
    raise AssertionError("hasSelectedAccountOverrides must return false when no override exists")
empty_command_index = refresh_body.find("if (commandSource.length === 0)")
loading_false_index = refresh_body.find("loading = false", empty_command_index)
empty_return_index = refresh_body.find("return", empty_command_index)
if empty_command_index < 0 or loading_false_index < 0 or loading_false_index > empty_return_index:
    raise AssertionError("refreshNow must clear loading before returning for an empty command")

provider_token_cost_body = function_body(main_text, "providerTokenCost")
if "tokenCosts[key]" not in provider_token_cost_body:
    raise AssertionError("providerTokenCost must read the current token-cost map")
replace_snapshot_body = function_body(main_text, "replaceProviderSnapshot")
for snapshot_fragment in ("copyObject(snapshot)", "providerTokenCost(key)", "replacement"):
    if snapshot_fragment not in replace_snapshot_body:
        raise AssertionError(
            "replaceProviderSnapshot must preserve current token-cost state; "
            f"missing {snapshot_fragment!r}"
        )

if "checked = Qt.binding(function()" not in provider_accounts_panel_text:
    raise AssertionError("account buttons must restore their checked binding after clicks")
if "accountIsSelected(modelData, accountsPanel.providerData)" not in provider_accounts_panel_text:
    raise AssertionError("restored account bindings must follow the selected account state")

parse_accounts_body = function_body(main_text, "parseProviderAccountsOutput")
if "setAccountOptions(providerID, [])" in parse_accounts_body:
    raise AssertionError("transient account errors must preserve the last healthy account options")
replace_options_index = parse_accounts_body.find("setAccountOptions(providerID, dedupedOptions)")
no_error_guard_index = parse_accounts_body.rfind("if (accountError.length === 0)", 0, replace_options_index)
if replace_options_index < 0 or no_error_guard_index < 0:
    raise AssertionError("structured account errors must not replace the last healthy options")

parse_cost_body = function_body(main_text, "parseCostOutput")
if "tokenCosts = ({})" in parse_cost_body:
    raise AssertionError("transient cost errors must preserve the last healthy cost snapshot")

if 'String(modelData.value || "")' in providers_text:
    raise AssertionError("descriptor text fields must preserve numeric zero")
descriptor_value_body = function_body(providers_text, "descriptorValueText")
if "value === undefined || value === null" not in descriptor_value_body:
    raise AssertionError("descriptorValueText must only blank nullish values")
field_option_body = function_body(providers_text, "fieldOptionIndex")
if "descriptorValueText(field.value)" not in field_option_body:
    raise AssertionError("fieldOptionIndex must preserve numeric zero via descriptorValueText")

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
    if "contentWidth: availableWidth" not in scroll_body:
        raise AssertionError(f"{scroll_id} content width must follow Plasma ScrollView availableWidth")
    if f"{scroll_id}.availableWidth - Kirigami.Units.smallSpacing" not in scroll_body:
        raise AssertionError(f"{scroll_id} must retain one quiet content inset before its scrollbar")
    for stale_scroll_gutter in (
        "readonly property real contentRightInset:",
        "rightPadding: contentRightInset",
    ):
        if stale_scroll_gutter in scroll_body:
            raise AssertionError(
                f"{scroll_id} must not restore the doubled desktop scrollbar gutter"
            )

if main_text.count("PlasmaComponents.ScrollView {") < 2:
    raise AssertionError("popup content must use Plasma-native scroll views")
if "Controls.ScrollView {" in main_text:
    raise AssertionError("popup content must not restore desktop-framed scroll views")

if "readonly property real roundedSurfaceRadius: Kirigami.Units.cornerRadius" not in main_text:
    raise AssertionError("main.qml must derive its polished radius from Kirigami theme units")
if "readonly property real nestedSurfaceRadius: Kirigami.Units.cornerRadius" not in main_text:
    raise AssertionError(
        "main.qml must expose a concentric radius for surfaces nested inside a "
        "roundedSurfaceRadius container"
    )
if "readonly property real compactMeterTrackHeight: Math.round(Kirigami.Units.gridUnit" not in main_text:
    raise AssertionError(
        "list-row meters must derive their thinner track from gridUnit instead of "
        "pinning a device pixel count"
    )

# Section headings sit above metric rows that are already DemiBold. A Normal
# weight heading therefore reads as less important than its own content, so the
# structural labels stay Primary and the size scale carries the ranking.
heading_chunks = main_text.split("Kirigami.Heading {")[1:]
if len(heading_chunks) < 5:
    raise AssertionError("main.qml must keep its popup section headings")
for heading_chunk in heading_chunks:
    if "type: Kirigami.Heading.Type.Primary" not in heading_chunk[:300]:
        heading_head = heading_chunk.strip().splitlines()[0].strip()
        raise AssertionError(
            "popup section headings must outrank the DemiBold metric labels they "
            f"introduce; heading starting {heading_head!r} is not Primary"
        )
popup_surface_body = id_block(main_text, "popupInnerSurface")
for popup_surface_fragment in (
    "radius: root.roundedSurfaceRadius",
    "Kirigami.Theme.alternateBackgroundColor",
    "border.color: root.withAlpha(Kirigami.Theme.textColor, 0.09)",
):
    if popup_surface_fragment not in popup_surface_body:
        raise AssertionError(
            "popupInnerSurface must provide a restrained rounded inner frame; "
            f"missing {popup_surface_fragment!r}"
        )

provider_header_body = id_block(provider_header_text, "providerHeaderRow")
for header_fragment in (
    "id: providerIdentitySurface",
    "id: providerHeaderIcon",
    "id: providerTitleRow",
    "id: providerMetaRow",
    "id: providerAccountLabel",
    "id: providerPlanLabel",
):
    if header_fragment not in provider_header_body:
        raise AssertionError(f"providerHeaderRow must expose {header_fragment} for stable header layout")

if "providerIconSource(providerHeaderRow.providerData.provider)" not in provider_header_body:
    raise AssertionError("providerHeaderRow must reinforce provider identity with the canonical icon")
if "providerReadableColor(" not in provider_header_body:
    raise AssertionError("providerHeaderRow must keep provider identity visible on the active theme")
if "radius: providerHeaderRow.applet.nestedSurfaceRadius" not in provider_header_body:
    raise AssertionError("providerHeaderRow must share the nested rounded surface scale")
if "type: Kirigami.Heading.Type.Primary" not in provider_header_body:
    raise AssertionError(
        "the provider title must stay the heaviest label in the detail view so "
        "the section headings below it never outrank it"
    )

for function_name in (
    "linearColorChannel",
    "relativeLuminance",
    "contrastRatio",
    "interpolateColor",
    "maximumContrastColor",
    "readableAccentColor",
):
    if f"function {function_name}(" not in theme_contrast_text:
        raise AssertionError(f"ThemeContrast.js must define contrast helper {function_name}")

for function_name in ("readableAccentColor", "providerReadableColor"):
    if f"function {function_name}(" not in main_text:
        raise AssertionError(f"main.qml must expose theme contrast wrapper {function_name}")

rounded_bar_body = function_body(main_text, "paintRoundedTopBar")
for rounded_bar_fragment in (
    "Math.min(radius, safeWidth / 2, safeHeight)",
    "context.quadraticCurveTo(",
    "context.fill()",
):
    if rounded_bar_fragment not in rounded_bar_body:
        raise AssertionError(
            "paintRoundedTopBar must preserve restrained top rounding for Canvas bars; "
            f"missing {rounded_bar_fragment!r}"
        )

readable_accent_body = function_body(main_text, "readableAccentColor")
for contrast_fragment in (
    "ThemeContrast.readableAccentColor(",
    "accent",
    "surface",
    "Kirigami.Theme.textColor",
):
    if contrast_fragment not in readable_accent_body:
        raise AssertionError(
            "readableAccentColor must preserve provider hue while enforcing "
            f"non-text contrast; missing {contrast_fragment!r}"
        )

shared_readable_accent_body = function_body(theme_contrast_text, "readableAccentColor")
for contrast_fragment in (
    "contrastRatio(accent, background) >= minimumNonTextContrastRatio",
    "interpolateColor(accent, themeTextColor, step / 10)",
    "contrastRatio(candidate, background) >= minimumNonTextContrastRatio",
    "maximumContrastColor(background)",
):
    if contrast_fragment not in shared_readable_accent_body:
        raise AssertionError(
            "ThemeContrast.readableAccentColor must preserve hue while enforcing "
            f"non-text contrast; missing {contrast_fragment!r}"
        )

provider_readable_body = function_body(main_text, "providerReadableColor")
if "readableAccentColor(" not in provider_readable_body or "providerColor(value)" not in provider_readable_body:
    raise AssertionError("providerReadableColor must derive a safe color from canonical provider metadata")

config_provider_readable_body = function_body(providers_text, "providerReadableColor")
for contrast_fragment in (
    "ThemeContrast.readableAccentColor(",
    "providerColor(value)",
    "Kirigami.Theme.textColor",
):
    if contrast_fragment not in config_provider_readable_body:
        raise AssertionError(
            "configProviders.qml must share the provider contrast contract; "
            f"missing {contrast_fragment!r}"
        )
if "providerReadableColor(" not in provider_config_row_text:
    raise AssertionError("ProviderConfigRow must keep unselected provider icons theme-readable")

for source_name, source_text in (
    ("ProviderUsageRow.qml", provider_usage_row_text),
    ("ProviderDetailSection.qml", provider_detail_section_text),
    ("CompactRepresentation.qml", compact_representation_text),
    ("OverviewProviderRow.qml", overview_provider_row_text),
):
    if "providerReadableColor(" not in source_text:
        raise AssertionError(f"{source_name} must use a theme-readable provider accent")

compact_status_mouse_body = id_block(compact_representation_text, "compactStatusMouse")
if "acceptedButtons: Qt.NoButton" not in compact_status_mouse_body:
    raise AssertionError("the compact incident badge must not consume panel clicks")
for vertical_fragment in (
    "readonly property bool verticalPanel: applet.verticalFormFactor",
    "verticalPanel || !hasProviderMeters",
    "!compactRoot.verticalPanel",
):
    if vertical_fragment not in compact_representation_text:
        raise AssertionError(
            "CompactRepresentation must collapse to an icon in vertical panels; "
            f"missing {vertical_fragment!r}"
        )

vertical_status_badge_body = id_block(compact_representation_text, "compactVerticalStatusBadge")
for vertical_badge_fragment in (
    "visible: compactRoot.verticalPanel",
    "compactRoot.incidentProvider.hasIncident",
    "statusBadgeColor(compactRoot.incidentProvider.statusSeverity)",
):
    if vertical_badge_fragment not in vertical_status_badge_body:
        raise AssertionError(
            "collapsing to an icon must keep an at-a-glance incident marker; "
            f"missing {vertical_badge_fragment!r}"
        )

for tooltip_fragment in (
    "toolTipMainText: Plasmoid.title",
    "toolTipSubText: panelToolTipText()",
    "toolTipTextFormat: Text.PlainText",
    "function panelToolTipText()",
    "Plasmoid.formFactor === PlasmaCore.Types.Vertical",
):
    if tooltip_fragment not in main_text:
        raise AssertionError(f"the panel tooltip/form-factor contract is missing {tooltip_fragment!r}")

provider_tabs_body = id_block(main_text, "providerTabsBar")
for tabs_fragment in (
    "Layout.preferredHeight: Kirigami.Units.gridUnit * 2.35",
    "id: providerTabsSurface",
    "radius: root.roundedSurfaceRadius",
    "border.color: root.withAlpha(Kirigami.Theme.textColor, 0.06)",
    "anchors.margins: Kirigami.Units.smallSpacing / 2",
    "root.withAlpha(Kirigami.Theme.textColor, 0.045)",
    "anchors.bottomMargin: 2",
    "providerReadableColor(",
    "activeFocusOnTab: true",
    "Accessible.role: Accessible.PageTab",
    "Accessible.onPressAction:",
    "Keys.onPressed:",
    "scale:",
):
    if tabs_fragment not in provider_tabs_body:
        raise AssertionError(
            "providerTabsBar must preserve the compact, accent-led tab hierarchy; "
            f"missing {tabs_fragment!r}"
        )
if "Kirigami.Theme.highlightedTextColor" in provider_tabs_body:
    raise AssertionError("provider tabs must not depend on a heavy solid-highlight selected state")
for stale_selected_overlay in (
    "root.withAlpha(brandAccent, 0.12)",
    "selected ? root.withAlpha(accent, 0.32)",
):
    if stale_selected_overlay in provider_tabs_body:
        raise AssertionError(
            "provider tabs must not restore a persistent accent capsule; "
            f"found {stale_selected_overlay!r}"
        )
for tab_id in ("overviewTab", "providerTab"):
    tab_body = id_block(main_text, tab_id)
    for focus_fragment in (
        "property bool focusAcquiredByPointer: false",
        "readonly property bool keyboardFocusVisible: activeFocus && !focusAcquiredByPointer",
        "border.width: keyboardFocusVisible ? 1 : 0",
        "onActiveFocusChanged:",
        "focusAcquiredByPointer = false",
        f"{tab_id}.focusAcquiredByPointer = true",
        f"{tab_id}.focusAcquiredByPointer = false",
    ):
        if focus_fragment not in tab_body:
            raise AssertionError(
                f"{tab_id} must preserve pointer-neutral selection and keyboard focus; "
                f"missing {focus_fragment!r}"
            )

usage_percent_body = id_block(provider_usage_row_text, "usagePercentLabel")
if "font.weight: Font.DemiBold" not in usage_percent_body:
    raise AssertionError("usagePercentLabel must remain a prominent scan target")
if provider_usage_row_text.index("id: usagePercentLabel") > provider_usage_row_text.index("id: usageBar"):
    raise AssertionError("usage percentage must appear in the metric header before its bar")
usage_bar_body = id_block(provider_usage_row_text, "usageBar")
if "applet.withAlpha(Kirigami.Theme.textColor, 0.1)" not in usage_bar_body:
    raise AssertionError("usageBar must keep its pill track visually restrained")
# A marker that spans the track edge to edge reads as a gap in the accent fill
# rather than a threshold, so pace and quota markers share one inset geometry.
for marker_geometry_fragment in (
    "readonly property real meterMarkerInset:",
    "readonly property real meterMarkerWidth:",
):
    if marker_geometry_fragment not in provider_usage_row_text:
        raise AssertionError(
            "ProviderUsageRow must define one shared meter marker geometry; "
            f"missing {marker_geometry_fragment!r}"
        )
if usage_bar_body.count("y: usageRow.meterMarkerInset") != 2:
    raise AssertionError("both the pace marker and the quota markers must be inset in the track")
if usage_bar_body.count("width: usageRow.meterMarkerWidth") != 2:
    raise AssertionError("both the pace marker and the quota markers must share one marker width")
for full_height_marker in ("height: usageBar.height\n", "y: 0\n"):
    if full_height_marker in usage_bar_body:
        raise AssertionError(
            "quota markers must not span the meter track edge to edge again"
        )

credits_meter_index = main_text.find('text: i18n("Credits")')
if credits_meter_index < 0:
    raise AssertionError("main.qml must keep the Credits section")
if "visible: root.selectedProviderData && root.selectedProviderData.credits > 0" not in main_text[credits_meter_index:credits_meter_index + 900]:
    raise AssertionError(
        "a depleted credits balance must not draw an empty meter track that reads "
        "as a meter which has not loaded yet"
    )
for usage_metadata_id in ("usagePaceLabel", "usageResetLabel"):
    usage_metadata_body = id_block(provider_usage_row_text, usage_metadata_id)
    if "font: Kirigami.Theme.smallFont" not in usage_metadata_body:
        raise AssertionError(f"{usage_metadata_id} must retain the compact metadata type scale")

if "detailSection.applet.paintRoundedTopBar(" not in provider_detail_section_text:
    raise AssertionError("provider detail bar charts must use rounded top corners")
for detail_chart_fragment in (
    "detailSection.applet.buildChartBarGradient(",
    "detailSection.applet.chartBarGeometry(width, points.length)",
    "Math.max(2, (height - 3) * fraction)",
):
    if detail_chart_fragment not in provider_detail_section_text:
        raise AssertionError(
            "provider detail bar charts must retain the polished cost-chart language; "
            f"missing {detail_chart_fragment!r}"
        )

chart_gradient_body = function_body(main_text, "buildChartBarGradient")
for gradient_fragment in (
    "context.createLinearGradient",
    "gradient.addColorStop(0",
    "gradient.addColorStop(1",
):
    if gradient_fragment not in chart_gradient_body:
        raise AssertionError(
            "vertical bar charts must use the shared restrained gradient; "
            f"missing {gradient_fragment!r}"
        )

cost_sparkline_body = id_block(main_text, "costSparkline")
if "root.paintRoundedTopBar(" not in cost_sparkline_body:
    raise AssertionError("the cost sparkline must use rounded top corners")
if "onVisibleChanged: if (visible) requestPaint()" not in cost_sparkline_body:
    raise AssertionError("costSparkline must repaint after becoming visible again")
for sparkline_fragment in (
    "Layout.preferredHeight: Kirigami.Units.gridUnit * 3.25",
    "root.canvasColor(Kirigami.Theme.textColor, 0.1)",
    "root.chartBarGeometry(width, points.length)",
    "root.buildChartBarGradient(",
    "Math.max(2, (height - 3) * value / maxValue)",
):
    if sparkline_fragment not in cost_sparkline_body:
        raise AssertionError(
            "costSparkline must retain its compact, low-noise chart treatment; "
            f"missing {sparkline_fragment!r}"
        )

for summary_id, summary_fragment in (
    ("costSessionSummaryLabel", "font.weight: Font.DemiBold"),
    ("costMonthSummaryLabel", "font: Kirigami.Theme.smallFont"),
    ("costSparklineSummaryLabel", "font: Kirigami.Theme.smallFont"),
    ("costSparklineRangeLabel", "font: Kirigami.Theme.smallFont"),
):
    summary_body = id_block(main_text, summary_id)
    if summary_fragment not in summary_body:
        raise AssertionError(f"{summary_id} must preserve the intended cost hierarchy")

cost_history_header_body = id_block(main_text, "costHistoryHeaderRow")
if "costHistoryChartSection.averageLine" not in cost_history_header_body:
    raise AssertionError("cost history must keep the average aligned with its heading")
cost_history_row_body = id_block(main_text, "costHistoryMetricRow")
for history_row_fragment in (
    "id: costHistoryDateLabel",
    "id: costHistoryBarTrack",
    "Layout.preferredHeight: root.compactMeterTrackHeight",
    "root.withAlpha(Kirigami.Theme.textColor, 0.055)",
    "gradient: Gradient",
    "orientation: Gradient.Horizontal",
    "antialiasing: true",
    "id: costHistoryValueLabel",
    "font.pixelSize: Kirigami.Theme.smallFont.pixelSize",
):
    if history_row_fragment not in cost_history_row_body:
        raise AssertionError(
            "cost history rows must stay compact and scannable; "
            f"missing {history_row_fragment!r}"
        )

cost_history_rows_body = function_body(main_text, "costHistoryRows")
if "tokenCost.daily.length - 7" not in cost_history_rows_body:
    raise AssertionError("cost history must show only the latest seven detailed rows")
if "costSparklineMax(visibleDaily)" not in cost_history_rows_body:
    raise AssertionError("cost history bars must scale against the seven visible days")
if "tokenCost.daily.length - 14" in cost_history_rows_body:
    raise AssertionError("cost history must not dominate the popup with fourteen detailed rows")
if "function costDailyRows(tokenCost)" in main_text:
    raise AssertionError("cost details must not repeat the daily history below the chart")

overview_row_body = id_block(overview_provider_row_text, "overviewRow")
if "applet.withAlpha(Kirigami.Theme.textColor, 0.035)" not in overview_row_body:
    raise AssertionError("overview rows must keep a quiet neutral resting surface")
overview_row_surface_bindings = overview_row_body.split("RowLayout {", 1)[0]
if "border.width" in overview_row_surface_bindings:
    raise AssertionError("overview rows must not regress to a stack of outlined cards")
for polished_overview_fragment in (
    "radius: applet.roundedSurfaceRadius",
    "id: overviewProviderIdentitySurface",
    "radius: overviewRow.applet.nestedSurfaceRadius",
    "applet.withAlpha(overviewRow.accent, 0.1)",
):
    if polished_overview_fragment not in overview_row_body:
        raise AssertionError(
            "overview rows must retain the rounded provider identity treatment; "
            f"missing {polished_overview_fragment!r}"
        )
for interaction_fragment in (
    "activeFocusOnTab: true",
    "Accessible.role: Accessible.Button",
    "Accessible.onPressAction:",
    "Keys.onPressed:",
    "overviewRowMouse.pressed",
    "scale:",
):
    if interaction_fragment not in overview_row_body:
        raise AssertionError(
            "overview rows must preserve keyboard, assistive, and pressed feedback; "
            f"missing {interaction_fragment!r}"
        )

for message_id, message_type in (
    ("globalErrorMessage", "Kirigami.MessageType.Error"),
    ("providerErrorMessage", "Kirigami.MessageType.Error"),
):
    message_body = id_block(main_text, message_id)
    if f"type: {message_type}" not in message_body:
        raise AssertionError(f"{message_id} must use the native semantic message style")

provider_status_body = id_block(main_text, "providerStatusMessage")
if "root.selectedProviderData.hasIncident" not in provider_status_body:
    raise AssertionError("healthy provider status must not occupy a permanent inline banner")
if "root.statusMessageType(root.selectedProviderData.statusSeverity)" not in provider_status_body:
    raise AssertionError("incident banners must reflect the provider status severity")
status_message_type_body = function_body(main_text, "statusMessageType")
for semantic_type in ("Kirigami.MessageType.Error", "Kirigami.MessageType.Warning"):
    if semantic_type not in status_message_type_body:
        raise AssertionError(f"statusMessageType must expose {semantic_type}")

for placeholder_id in (
    "emptyProvidersMessage",
    "overviewPlaceholderMessage",
    "providerPlaceholderMessage",
):
    placeholder_body = id_block(main_text, placeholder_id)
    if "Kirigami.PlaceholderMessage.Type.Informational" not in placeholder_body:
        raise AssertionError(f"{placeholder_id} must use the native informational empty state")

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
if 'text: i18n("Cost details")' not in cost_drill_down_body:
    raise AssertionError("costDrillDownSection must use a plain, user-facing title")
for value_label in ("costBreakdownValueLabel", "costModelValueLabel"):
    value_label_body = id_block(main_text, value_label)
    if "Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth" not in value_label_body:
        raise AssertionError(f"{value_label} must use the shared metric value column width")
    if "Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth" not in value_label_body:
        raise AssertionError(f"{value_label} must cap the shared metric value column width")
    if "font.pixelSize: Kirigami.Theme.smallFont.pixelSize" not in value_label_body:
        raise AssertionError(f"{value_label} must use the compact numeric type scale")

cost_models_heading_body = id_block(main_text, "costModelsHeading")
for heading_fragment in (
    "font.pixelSize: Kirigami.Theme.smallFont.pixelSize",
    "font.weight: Font.DemiBold",
):
    if heading_fragment not in cost_models_heading_body:
        raise AssertionError("Models must remain distinct without adding another card")
if "costRecentDaysHeading" in cost_drill_down_body or 'i18n("Recent days")' in cost_drill_down_body:
    raise AssertionError("cost details must not duplicate the daily history after the models")

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
    "? providerRow.selectedForeground",
    "? providerRow.selectedSecondaryForeground",
):
    if selected_row_fragment not in provider_config_row_text:
        raise AssertionError(
            "ProviderConfigRow selected state must set explicit contrast-aware "
            f"text colors; missing {selected_row_fragment!r}"
        )

advanced_override_body = id_block(advanced_text, "advancedOverrideExplanation")
for explanation_fragment in (
    "Layout.fillWidth: true",
    "Layout.preferredWidth: Kirigami.Units.gridUnit * 18",
    "wrapMode: Text.WordWrap",
    "font: Kirigami.Theme.smallFont",
):
    if explanation_fragment not in advanced_override_body:
        raise AssertionError(
            "Advanced override guidance must remain a readable full-width form row; "
            f"missing {explanation_fragment!r}"
        )
if "Kirigami.FormData.label:" in advanced_override_body:
    raise AssertionError("Advanced override guidance must not masquerade as a field label")
if 'Kirigami.FormData.label: i18n("Advanced provider override")' not in advanced_text:
    raise AssertionError("Advanced settings must retain the provider override section title")
if "Kirigami.FormData.isSection: true" not in advanced_text:
    raise AssertionError("Advanced provider override must use the shared Kirigami section hierarchy")

provider_cli_toggle_body = id_block(providers_text, "providerCliCommandsToggle")
for toggle_fragment in (
    "checkable: true",
    'text: i18n("CLI commands")',
    'icon.name: checked ? "arrow-down" : "arrow-right"',
):
    if toggle_fragment not in provider_cli_toggle_body:
        raise AssertionError(
            "Provider CLI commands must remain available behind a compact native disclosure; "
            f"missing {toggle_fragment!r}"
        )

provider_cli_view_body = id_block(providers_text, "providerCliCommandsView")
if "visible: providerCliCommandsToggle.checked" not in provider_cli_view_body:
    raise AssertionError("Provider CLI command output must follow the disclosure state")

provider_list_heading_body = id_block(providers_text, "providerListHeading")
for heading_fragment in (
    'text: i18n("Providers")',
    'i18np("%1 provider enabled", "%1 providers enabled", page.enabledCount)',
    "font.weight: Font.DemiBold",
):
    if heading_fragment not in provider_list_heading_body:
        raise AssertionError(
            "The provider list must retain a distinct, compact heading; "
            f"missing {heading_fragment!r}"
        )

provider_list_separator_body = id_block(providers_text, "providerListSeparator")
if "Layout.fillWidth: true" not in provider_list_separator_body:
    raise AssertionError("The provider list boundary must span the available width")

ordered_provider_fragments = (
    "id: providerCliCommandsView",
    "id: providerListSeparator",
    "id: providerListHeading",
    "delegate: Components.ProviderConfigRow",
)
ordered_provider_indexes = [providers_text.index(fragment) for fragment in ordered_provider_fragments]
if ordered_provider_indexes != sorted(ordered_provider_indexes):
    raise AssertionError("Provider details, list boundary, heading, and rows must keep their visual order")

notification_scope_body = function_body(main_text, "notificationScopeKey")
for scope_fragment in ("providerMapKey(item.provider)", "selectedAccountForProvider", "accountLabel(item)", "JSON.stringify"):
    if scope_fragment not in notification_scope_body:
        raise AssertionError(
            "notificationScopeKey must include stable provider/account identity; "
            f"missing {scope_fragment!r}"
        )
pending_getter_body = function_body(main_text, "notificationProviderRefreshPending")
if not re.fullmatch(
    r"\s*var\s+key\s*=\s*providerMapKey\(providerID\)\s*"
    r"return\s+key\.length\s*>\s*0\s*&&\s*notificationRefreshPending\[key\]\s*===\s*true\s*",
    pending_getter_body,
    re.S,
):
    raise AssertionError("notificationProviderRefreshPending must read the provider pending map")
pending_setter_body = function_body(main_text, "setNotificationProviderRefreshPending")
for setter_fragment in (
    "var nextPending = copyObject(notificationRefreshPending)",
    "nextPending[key] = true",
    "delete nextPending[key]",
    "notificationRefreshPending = nextPending",
):
    if setter_fragment not in pending_setter_body:
        raise AssertionError(
            "setNotificationProviderRefreshPending must update the copied pending map; "
            f"missing {setter_fragment!r}"
        )
if not re.search(
    r"if\s*\(pending\)\s*\{\s*nextPending\[key\]\s*=\s*true\s*\}\s*else\s*\{\s*delete\s+nextPending\[key\]\s*\}",
    pending_setter_body,
    re.S,
):
    raise AssertionError("setNotificationProviderRefreshPending must set or clear the provider entry")

status_key_body = function_body(main_text, "statusNotificationKey")
if not re.fullmatch(
    r'\s*return\s+"status:"\s*\+\s*providerMapKey\(item\.provider\)\s*',
    status_key_body,
    re.S,
):
    raise AssertionError("statusNotificationKey must remain exclusively provider-scoped across account switches")
for key_function in ("quotaNotificationKey", "limitResetNotificationKey"):
    key_body = function_body(main_text, key_function)
    if "notificationScopeKey(item)" not in key_body:
        raise AssertionError(f"{key_function} must scope memo state by account")
primed_key_body = function_body(main_text, "notificationScopePrimedKey")
if "notificationScopeKey(item)" not in primed_key_body:
    raise AssertionError("notificationScopePrimedKey must identify each provider/account observation")
prime_account_body = function_body(main_text, "primeAccountNotificationScope")
for prime_fragment in (
    "notificationScopePrimedKey(item)",
    "quotaNotificationKey(item, rows[j], j)",
    "limitResetNotificationKey(item, resetRow, k)",
):
    if prime_fragment not in prime_account_body:
        raise AssertionError(
            "primeAccountNotificationScope must seed account state without notifying; "
            f"missing {prime_fragment!r}"
        )
for forbidden_prime_call in (
    "sendPlasmaNotification",
    "processStatusNotification",
    "processQuotaNotifications",
    "processLimitResetNotifications",
):
    if forbidden_prime_call in prime_account_body:
        raise AssertionError(
            "primeAccountNotificationScope must seed state without notification processing; "
            f"found {forbidden_prime_call!r}"
        )
prime_notifications_body = function_body(main_text, "primeNotifications")
if "notificationProviderRefreshPending(item.provider)" not in prime_notifications_body:
    raise AssertionError("primeNotifications must not seed memo state from a cached account snapshot")
process_notifications_body = function_body(main_text, "processNotifications")
for memo_fragment in (
    "copyObject(notificationMemo)",
    "notificationProviderRefreshPending(item.provider)",
    "notificationMemo[notificationScopePrimedKey(item)] !== \"1\"",
    "primeAccountNotificationScope(item, nextMemo)",
    "clearNotificationScopeMemo(nextMemo, item)",
):
    if memo_fragment not in process_notifications_body:
        raise AssertionError(
            "processNotifications must preserve, suppress, or silently prime account state; "
            f"missing {memo_fragment!r}"
        )
pending_guard_index = process_notifications_body.find("notificationProviderRefreshPending(item.provider)")
status_process_index = process_notifications_body.find("processStatusNotification(item, nextMemo)")
prime_guard_index = process_notifications_body.find("notificationMemo[notificationScopePrimedKey(item)] !== \"1\"")
quota_process_index = process_notifications_body.find("processQuotaNotifications(item, nextMemo)")
reset_process_index = process_notifications_body.find("processLimitResetNotifications(item, nextMemo)")
if pending_guard_index > status_process_index:
    raise AssertionError("cached account snapshots must be suppressed before any status or quota notification")
if not re.search(
    r"if\s*\(notificationProviderRefreshPending\(item\.provider\)\)\s*\{\s*continue\s*\}",
    process_notifications_body,
    re.S,
):
    raise AssertionError("cached account notification suppression must exit the provider loop")
if prime_guard_index > quota_process_index or prime_guard_index > reset_process_index:
    raise AssertionError("new account scopes must be primed before quota or reset notification processing")
if not re.search(
    r'if\s*\(notificationMemo\[notificationScopePrimedKey\(item\)\]\s*!==\s*"1"\)\s*\{'
    r"\s*primeAccountNotificationScope\(item,\s*nextMemo\)\s*continue\s*\}",
    process_notifications_body,
    re.S,
):
    raise AssertionError("first account observation must prime state and exit before notification processing")
status_process_body = function_body(main_text, "processStatusNotification")
if "var key = statusNotificationKey(item)" not in status_process_body:
    raise AssertionError("processStatusNotification must consume the provider-scoped status key helper")
clear_scope_body = function_body(main_text, "clearNotificationScopeMemo")
if "notificationScopeKey(item)" not in clear_scope_body or "delete nextMemo[key]" not in clear_scope_body:
    raise AssertionError("clearNotificationScopeMemo must remove stale quota/reset keys for the current account")
if "statusNotificationKey(item)" in clear_scope_body:
    raise AssertionError("clearing an account scope must not erase provider-scoped status state")

select_account_body = function_body(main_text, "selectAccount")
pending_index = select_account_body.find("setNotificationProviderRefreshPending(key, true)")
snapshot_index = select_account_body.find("replaceProviderSnapshot(key, options[i])")
refresh_index = select_account_body.find("Qt.callLater(refreshNow)", snapshot_index)
return_index = select_account_body.find("return", snapshot_index)
if pending_index < 0 or snapshot_index < 0 or pending_index > snapshot_index:
    raise AssertionError("selectAccount must suppress cached snapshots until fresh usage data arrives")
if refresh_index < 0 or return_index < 0 or refresh_index > return_index:
    raise AssertionError("selectAccount must schedule a fresh usage request before returning a cached snapshot")
for fresh_function in ("parseOutput", "finishProviderFallback"):
    fresh_body = function_body(main_text, fresh_function)
    fresh_index = fresh_body.find("markNotificationProvidersFresh(nextProviders)")
    providers_index = fresh_body.find("providers = nextProviders")
    if fresh_index < 0 or providers_index < 0 or fresh_index > providers_index:
        raise AssertionError(f"{fresh_function} must mark fresh provider data before publishing it")
mark_fresh_body = function_body(main_text, "markNotificationProvidersFresh")
error_guard = "if (!item || (item.error && String(item.error).length > 0))"
selected_guard = "selectedAccount.length > 0 && accountLabel(item) !== selectedAccount"
delete_pending_index = mark_fresh_body.find("delete nextPending[providerID]")
if error_guard not in mark_fresh_body or mark_fresh_body.find(error_guard) > delete_pending_index:
    raise AssertionError("markNotificationProvidersFresh must retain suppression for failed refreshes")
if not re.search(
    r"if\s*\(!item\s*\|\|\s*\(item\.error\s*&&\s*String\(item\.error\)\.length\s*>\s*0\)\)\s*\{\s*continue\s*\}",
    mark_fresh_body,
    re.S,
):
    raise AssertionError("failed refreshes must continue without clearing notification suppression")
if "var selectedAccount = selectedAccountForProvider(providerID)" not in mark_fresh_body:
    raise AssertionError("markNotificationProvidersFresh must correlate fresh data with the selected account")
if selected_guard not in mark_fresh_body or mark_fresh_body.find(selected_guard) > delete_pending_index:
    raise AssertionError("stale responses for a previous account must not clear notification suppression")
if not re.search(
    r"if\s*\(selectedAccount\.length\s*>\s*0\s*&&\s*accountLabel\(item\)\s*!==\s*selectedAccount\)\s*\{\s*continue\s*\}",
    mark_fresh_body,
    re.S,
):
    raise AssertionError("previous-account responses must continue without clearing notification suppression")

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
if "selectedProviderID" not in select_body:
    raise AssertionError("updateSelectedProvider must preserve selection by provider id")
if "function providerIndexForID(providerID)" not in main_text:
    raise AssertionError("the selected provider index must be derived from its provider id")

normalize_provider_body = function_body(main_text, "normalizeProvider")
for bounded_provider_fragment in (
    "title: boundedDisplayText(",
    "status: boundedDisplayText(",
    "error: boundedCliMessage(",
):
    if bounded_provider_fragment not in normalize_provider_body:
        raise AssertionError("new provider display surfaces must use bounded normalized text")
for extra_window_fragment in (
    "Array.isArray(usage.extraRateWindows)",
    "Math.min(extras.length, maximumExtraRateWindows)",
):
    if extra_window_fragment not in normalize_provider_body:
        raise AssertionError(
            "extra rate windows must reject pseudo-arrays and cap delegate work; "
            f"missing {extra_window_fragment!r}"
        )

if "onCfg_commandPathChanged: handleCommandPathChanged()" not in providers_text:
    raise AssertionError("the Providers page must reload when the configured CLI path changes")

descriptor_action_result_body = function_body(providers_text, "handleDescriptorActionResult")
if "bumpProviderConfigRevision()" not in descriptor_action_result_body:
    raise AssertionError("successful descriptor actions must invalidate the main applet snapshot")

parse_command_payload_body = function_body(providers_text, "parseCommandPayload")
for action_status_fragment in ('status === "error"', "payload.message"):
    if action_status_fragment not in parse_command_payload_body:
        raise AssertionError(
            "descriptor command payloads must honor structured error status/message; "
            f"missing {action_status_fragment!r}"
        )

tooltip_body = function_body(main_text, "panelToolTipText")
if "boundedDisplayText(errorText" not in tooltip_body:
    raise AssertionError("the panel tooltip must bound global CLI error text")
if 'i18n("%1 - %2", line, incident)' not in tooltip_body:
    raise AssertionError(
        "the panel tooltip must report incidents even when the provider also reports usage"
    )
if "function boundedDisplayText(value, maximumLength)" not in main_text:
    raise AssertionError("main.qml must expose a shared display-text bound")

if "applet.usageResetText(usageRow)" not in overview_provider_row_text:
    raise AssertionError("Overview reset labels must use render-time formatting")

dashboard_rows_body = function_body(main_text, "usageDashboardRows")
if "arguments[" in dashboard_rows_body:
    raise AssertionError("usageDashboardRows must declare its state and depth contract")
if "function usageDashboardRows(source, state, depth)" not in main_text:
    raise AssertionError("usageDashboardRows must expose named state and depth parameters")

reset_time_body = function_body(main_text, "resetLabelLooksLikeTime")
if r"\S+\s+\d{1,2}:\d{2}" not in reset_time_body:
    raise AssertionError("absolute weekday reset labels must be recognized as times")

# resetText() already emits compact durations such as "2h 30m". Splitting
# digit-then-letter rewrote those as "2 h 30 m" in the popup, the Overview rows
# and the resetTime panel mode. Only the letter-then-digit split (which
# separates a run-together "5h30m" into "5h 30m") may stay.
reset_label_body = function_body(main_text, "resetLabel")
if r'.replace(/([A-Za-z])(\d)/g, "$1 $2")' not in reset_label_body:
    raise AssertionError("resetLabel must split a unit letter that runs into the next number")
if r'.replace(/(\d)([A-Za-z])/g, "$1 $2")' in reset_label_body:
    raise AssertionError("resetLabel must not separate a number from its own unit")

# Bar charts are painted for up to 365 cost-history days and 120 detail-chart
# points. A fixed minimum gap or bar width pushed the last bars past the canvas
# width, silently hiding the newest data, so both charts share one step-derived
# geometry helper instead of computing their own bar pitch.
if "function chartBarGeometry(width, count)" not in main_text:
    raise AssertionError("main.qml must expose a shared bar-chart geometry helper")
chart_geometry_body = function_body(main_text, "chartBarGeometry")
for fragment in ("var step = Math.max(0, Number(width) || 0) / points", "Math.max(1, step - gap)"):
    if fragment not in chart_geometry_body:
        raise AssertionError(
            f"chartBarGeometry must derive gap and bar width from one step: {fragment}"
        )
for label, source_text in (
    ("main.qml", main_text),
    ("ProviderDetailSection.qml", provider_detail_section_text),
):
    if "chartBarGeometry(" not in source_text:
        raise AssertionError(f"{label} bar charts must use the shared geometry helper")
    if "barWidth + gap" in source_text:
        raise AssertionError(f"{label} bar charts must not recompute their own bar pitch")

reset_credits_body = function_body(main_text, "resetCreditsSection")
if 'i18np("%1 available", "%1 available"' not in reset_credits_body:
    raise AssertionError("reset credit counts must use plural-aware translations")
if "function providerCountText(count)" not in main_text:
    raise AssertionError("overview provider counts must use a plural-aware helper")
provider_count_body = function_body(main_text, "providerCountText")
if 'i18np("%1 provider", "%1 providers", total)' not in provider_count_body:
    raise AssertionError("providerCountText must select the correct singular form")

if "readonly property var overviewProviderItems: overviewProviders()" not in main_text:
    raise AssertionError("overview provider rows must be cached in a QML property binding")
if "root.overviewProviders()" in main_text:
    raise AssertionError("overview UI bindings must reuse overviewProviderItems")

# Text de-emphasis had drifted into eleven ad-hoc opacity literals, several
# below the WCAG AA 4.5:1 floor for Kirigami.Theme.textColor on Breeze Light.
# Keep the scale in one place so a new section cannot reintroduce a dimmer step.
for token_definition in (
    "readonly property real secondaryTextOpacity: 0.7",
    "readonly property real valueTextOpacity: 0.85",
    "readonly property real meterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.4)",
):
    if token_definition not in main_text:
        raise AssertionError(
            f"main.qml must define the shared presentation scale: {token_definition!r}"
        )
if "readonly property real secondaryTextOpacity: 0.7" not in providers_text:
    raise AssertionError(
        "configProviders.qml must mirror main.qml's secondaryTextOpacity step"
    )
if main_text.count("Layout.preferredHeight: root.meterTrackHeight") != 2:
    raise AssertionError(
        "the credits and provider-cost meters must both consume meterTrackHeight"
    )
if provider_usage_row_text.count(
    "Layout.preferredHeight: usageRow.applet.meterTrackHeight"
) != 1:
    raise AssertionError("the provider-usage meter must consume meterTrackHeight")


popup_and_provider_surfaces = (
    (main_qml, main_text),
    (providers_qml, providers_text),
    (provider_accounts_panel_qml, provider_accounts_panel_text),
    (provider_header_qml, provider_header_text),
    (provider_config_row_qml, provider_config_row_text),
    (provider_usage_row_qml, provider_usage_row_text),
    (provider_detail_section_qml, provider_detail_section_text),
    (overview_provider_row_qml, overview_provider_row_text),
    (compact_representation_qml, compact_representation_text),
)


def enclosing_element(source_lines, index):
    for cursor in range(index, -1, -1):
        opener = re.match(r"\s*([A-Z][A-Za-z.]*)\s*\{", source_lines[cursor])
        if opener:
            return opener.group(1)
    return ""


for surface, surface_text in popup_and_provider_surfaces:
    surface_lines = surface_text.splitlines()
    for line_number, line in enumerate(surface_lines):
        if not re.match(r"\s*opacity:\s", line):
            continue
        element = enclosing_element(surface_lines, line_number)
        if "Label" not in element and "Heading" not in element:
            continue
        if re.search(r"\b0\.\d+", line):
            raise AssertionError(
                f"{surface.name}:{line_number + 1} sets text opacity from a literal; "
                "use secondaryTextOpacity or valueTextOpacity so the de-emphasis "
                "scale stays consistent and above WCAG AA contrast"
            )

for surface, surface_text in popup_and_provider_surfaces:
    hardcoded_font = re.search(r"font\.pixelSize:\s*\d+(?:\.\d+)?", surface_text)
    if hardcoded_font:
        raise AssertionError(
            "popup and provider-config text must size from Kirigami.Theme fonts, "
            f"not device pixels: {surface.name}: {hardcoded_font.group(0)!r}"
        )
PY

echo "UI regression checks passed."
