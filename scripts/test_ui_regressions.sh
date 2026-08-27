#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
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

require_in_surface providers "Provider-specific controls come from the CodexBar CLI descriptor"
reject_in_surface providers "Provider-specific editing stays in the CodexBar CLI until it exposes a stable settings descriptor"
# Successful provider commands must be classified by the shared outcome
# contract, never re-inlined with stderr consulted before the parsed payload:
# loader diagnostics make successful runs print to stderr, and the inlined
# order reported those runs as failures.
require_in_surface providers "ProviderConfigProtocol.commandOutcome("
# Plasma injects cfg_* creation properties, so declarative cfg_* bindings do not
# stay live. The General surface must observe the runtime values explicitly and
# keep user edits pending until Apply.
require_in_surface general 'import "general/ConfigValueSync.js" as ConfigValueSync'
require_in_surface general "ConfigValueSync.afterPersistedChange("
require_in_surface general "ConfigValueSync.afterUserEdit("
require_in_surface general "ConfigValueSync.afterSave("
reject_in_surface general "cfg_costHistoryDays: Plasmoid.configuration.costHistoryDays"
reject_in_surface general "cfg_costHistoryMetric: Plasmoid.configuration.costHistoryMetric"
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
config_xml = root / "contents/config/main.xml"
theme_contrast_js = root / "contents/ui/ThemeContrast.js"
cost_presentation_js = root / "contents/ui/CostPresentation.js"
provider_accounts_panel_qml = root / "contents/ui/components/ProviderAccountsPanel.qml"
provider_header_qml = root / "contents/ui/components/ProviderHeader.qml"
provider_config_row_qml = root / "contents/ui/components/ProviderConfigRow.qml"
provider_usage_row_qml = root / "contents/ui/components/ProviderUsageRow.qml"
overview_provider_row_qml = root / "contents/ui/components/OverviewProviderRow.qml"
provider_detail_section_qml = root / "contents/ui/components/ProviderDetailSection.qml"
compact_representation_qml = root / "contents/ui/components/CompactRepresentation.qml"
global_tab_qml = root / "contents/ui/components/GlobalTab.qml"
interactive_chart_qml = root / "contents/ui/components/InteractiveChart.qml"
sessions_view_qml = root / "contents/ui/components/SessionsView.qml"
copyable_value_qml = root / "contents/ui/components/CopyableValue.qml"
spend_view_qml = root / "contents/ui/components/SpendView.qml"
full_representation_qml = root / "contents/ui/components/FullRepresentation.qml"
cost_trust_notice_qml = root / "contents/ui/components/CostTrustNotice.qml"


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


sys.path.insert(0, str(root / "scripts/lib"))
from qml_surfaces import Surface

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
providers_surface = Surface("providers", root)
providers_surface_text = providers_surface.text
debug_surface = Surface("debug", root)
general_surface = Surface("general", root)
general_text = general_surface.text
display_text = display_qml.read_text(encoding="utf-8")
providers_text = providers_qml.read_text(encoding="utf-8")
advanced_text = advanced_qml.read_text(encoding="utf-8")
config_text = config_xml.read_text(encoding="utf-8")
theme_contrast_text = theme_contrast_js.read_text(encoding="utf-8")
cost_presentation_text = cost_presentation_js.read_text(encoding="utf-8")
provider_accounts_panel_text = provider_accounts_panel_qml.read_text(encoding="utf-8")
provider_header_text = provider_header_qml.read_text(encoding="utf-8")
provider_config_row_text = provider_config_row_qml.read_text(encoding="utf-8")
provider_usage_row_text = provider_usage_row_qml.read_text(encoding="utf-8")
overview_provider_row_text = overview_provider_row_qml.read_text(encoding="utf-8")
provider_detail_section_text = provider_detail_section_qml.read_text(encoding="utf-8")
compact_representation_text = compact_representation_qml.read_text(encoding="utf-8")
global_tab_text = global_tab_qml.read_text(encoding="utf-8")
interactive_chart_text = interactive_chart_qml.read_text(encoding="utf-8")
sessions_view_text = sessions_view_qml.read_text(encoding="utf-8")
copyable_value_text = copyable_value_qml.read_text(encoding="utf-8")
spend_view_text = spend_view_qml.read_text(encoding="utf-8")
full_representation_text = full_representation_qml.read_text(encoding="utf-8")
cost_trust_notice_text = cost_trust_notice_qml.read_text(encoding="utf-8")

internal_config_keys = {
    "autoUpdateLastCheck",
    "widgetUpdateLastStatus",
    "widgetUpdateLastError",
    "lastNotifiedUpdateVersion",
    "providerConfigRevision",
}
all_config_keys = set(re.findall(r'<entry name="([^"]+)"', config_text))
resettable_config_keys = all_config_keys - internal_config_keys
restore_defaults_body = function_body(general_text, "restoreUserDefaults")
defaults_check_body = function_body(general_text, "userSettingsAreDefault")
restore_statements = {
    "costHistoryDays": "editCostHistoryDays(cfg_costHistoryDaysDefault)",
    "costHistoryMetric": "editCostHistoryMetric(cfg_costHistoryMetricDefault)",
}
for config_key in sorted(resettable_config_keys):
    property_pattern = re.compile(
        rf"\bproperty\s+(?:alias|string|int|bool)\s+cfg_{re.escape(config_key)}(?::|\s|$)"
    )
    default_property_pattern = re.compile(
        rf"\bproperty\s+(?:string|int|bool)\s+cfg_{re.escape(config_key)}Default(?:\s|$)"
    )
    if not property_pattern.search(general_text) or not default_property_pattern.search(general_text):
        raise AssertionError(
            f"global defaults must declare the value and default for {config_key} on General"
        )
    expected_assignment = restore_statements.get(
        config_key, f"cfg_{config_key} = cfg_{config_key}Default"
    )
    if expected_assignment not in restore_defaults_body:
        raise AssertionError(f"global defaults must restore {config_key}")
    expected_pair = f"[cfg_{config_key}, cfg_{config_key}Default]"
    if expected_pair not in defaults_check_body:
        raise AssertionError(f"global defaults button state must account for {config_key}")
for internal_key in sorted(internal_config_keys):
    if f"cfg_{internal_key}" in restore_defaults_body:
        raise AssertionError(f"global defaults must preserve internal state {internal_key}")

restore_defaults_button = id_block(general_text, "restoreAllDefaultsButton")
for restore_button_fragment in (
    'text: i18n("Restore all defaults")',
    "enabled: !page.userSettingsAreDefault()",
    "onClicked: page.restoreUserDefaults()",
):
    if restore_button_fragment not in restore_defaults_button:
        raise AssertionError(
            "the global defaults action must remain explicit and cancelable; "
            f"missing {restore_button_fragment!r}"
        )
if "defaultsActionRequested = false" not in function_body(general_text, "saveConfig"):
    raise AssertionError("saving global defaults must clear the pending confirmation message")


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

command_path_row_body = general_surface.id_block("commandPathRow")
command_path_row_layout = command_path_row_body.split("Controls.TextField {", 1)[0]
if "Layout.maximumWidth: Kirigami.Units.gridUnit * 24" not in command_path_row_layout:
    raise AssertionError(
        "the command path row must stay bounded in the FormLayout control column so resizing "
        "cannot push Use PATH outside the visible page"
    )

# The dash rule follows the visible text, not the file it lives in: an em dash
# in an extracted component reads the same in the popup as one in main.qml, so
# assert it across the whole surface.
for dash, dash_name in (("\u2014", "em dash"), ("\u2013", "en dash")):
    applet.reject(dash, f"visible UI text must avoid {dash_name} placeholders")

# Provider identity used to be two copies, and this file carried a drift check
# that compared them entry by entry. The tables now live once in
# ProviderIdentity.js, so what is worth asserting is that neither surface has
# grown a private copy again: both must read the shared module.
for source_text, label in ((main_text, "main.qml"), (providers_text, "configProviders.qml")):
    for function_name, shared_call in (
        ("providerKey", "ProviderIdentity.resolveProviderKey(value)"),
        ("providerCliArgument", "ProviderIdentity.providerCliArgument(value)"),
        ("providerColor", "ProviderIdentity.providerBrandColorChannels(value)"),
        ("providerIconSource", "ProviderIdentity.providerIconFileName(value)"),
        ("providerDashboardUrl", "ProviderIdentity.providerDashboardUrl(providerID)"),
        ("providerDocsUrl", "ProviderIdentity.providerDocsUrl(providerID)"),
        ("providerLoginUrl", "ProviderIdentity.providerLoginUrl(providerID)"),
    ):
        body = function_body(source_text, function_name)
        if shared_call not in body:
            raise AssertionError(
                f"{label}: {function_name} must read provider identity from "
                f"ProviderIdentity.js instead of a local table"
            )
        if 'case "' in body or "var aliases = {" in body:
            raise AssertionError(
                f"{label}: {function_name} has grown a local provider table again"
            )

# The display names cannot move: i18n needs literal strings in a file gettext
# scans, so this one table stays duplicated and still needs a drift check.
main_titles = extract_object_entries(main_text, "providerTitle", "names")
provider_titles = extract_object_entries(providers_text, "providerTitle", "names")
if main_titles != provider_titles:
    missing = sorted(set(main_titles) - set(provider_titles))
    extra = sorted(set(provider_titles) - set(main_titles))
    changed = sorted(
        key for key in set(main_titles) & set(provider_titles)
        if main_titles[key] != provider_titles[key]
    )
    raise AssertionError(
        "providerTitle drift between main.qml and configProviders.qml; "
        f"missing={missing}, extra={extra}, changed={changed}"
    )

# Wayfinder was added late and is the canary for a half-finished provider.
identity_text = (root / "contents/ui/ProviderIdentity.js").read_text(encoding="utf-8")
for identity_fragment, requirement in (
    ('"wayfinder": "wayfinder.md"', "documentation link"),
    ('"wayfinder": [', "brand color"),
):
    if identity_fragment not in identity_text:
        raise AssertionError(f"ProviderIdentity.js must expose the Wayfinder {requirement}")
for source_text, label in ((main_text, "main.qml"), (providers_text, "configProviders.qml")):
    if '"wayfinder": i18n("Wayfinder")' not in function_body(source_text, "providerTitle"):
        raise AssertionError(f"{label} must expose the Wayfinder display name")

api_key_setup_body = function_body(providers_text, "supportsApiKeySetup")
for provider in ("crossmodel", "clawrouter"):
    if f'case "{provider}":' not in api_key_setup_body:
        raise AssertionError(
            f"supportsApiKeySetup must include released API-key provider {provider}"
        )

# Failure precedence for provider mutations lives in
# ProviderConfigProtocol.commandOutcome, covered adversarially by
# tests/tst_provider_config_protocol.qml. The pages must classify results by
# delegating to it instead of re-inlining an ordering around stderr.
for mutation_handler in (
    function_body(providers_text, "handleToggleResult"),
    function_body(providers_text, "handleSetApiKeyResult"),
    function_body(providers_text, "parseCommandPayload"),
):
    if "ProviderConfigProtocol.commandOutcome(" not in mutation_handler:
        raise AssertionError(
            "provider mutation handlers must classify CLI results through "
            "ProviderConfigProtocol.commandOutcome"
        )

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

if "codexbar did not return command data." not in function_body(providers_text, "parseCommandPayload"):
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

provider_config_body = function_body(main_text, "normalizeProviderConfigEntries")
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
if "var nextProviderIndex = applet.providerIndex(providerData)" not in main_text or "if (nextProviderIndex >= 0)" not in main_text:
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
if "normalizeTokenCost(item, requestedHistoryDays)" not in parse_cost_body:
    raise AssertionError("cost snapshots must retain the range of the request that produced them")
if "Normalizer.costRecordHasError(item)" not in parse_cost_body:
    raise AssertionError("cost error records must use the shared envelope contract")
if "Normalizer.mergeCostSnapshotsAfterPartialFailure(" not in parse_cost_body:
    raise AssertionError("partial cost errors must retain only explicitly failed providers")

parse_usage_body = function_body(main_text, "parseOutput")
if "Normalizer.dedupeProviderSnapshots(nextProviders)" not in parse_usage_body:
    raise AssertionError("direct usage payloads must not create duplicate provider tabs")

token_cost_section_body = id_block(main_text, "tokenCostSection")
if "applet.costErrorText" not in token_cost_section_body:
    raise AssertionError("tokenCostSection must surface costErrorText instead of dropping cost errors")
if "Cost unavailable: %1" not in token_cost_section_body:
    raise AssertionError("tokenCostSection must label visible cost errors")
if "supportsLocalCost" not in token_cost_section_body:
    raise AssertionError("tokenCostSection must scope global cost errors to supported providers")

normalize_token_cost_body = function_body(main_text, "normalizeTokenCost")
for ranged_cost_fragment in (
    "costHistoryWindowLabel(item, historyDays)",
    "historyDays: historyDays",
    "normalizeCostModels(item.daily, currency, historyDays)",
    "normalizeCostDaily(item.daily, currency, historyDays)",
):
    if ranged_cost_fragment not in normalize_token_cost_body:
        raise AssertionError(
            "normalizeTokenCost must retain and apply its bounded history range; "
            f"missing {ranged_cost_fragment!r}"
        )
if "function costHistoryWindowLabel(item, requestedHistoryDays)" not in main_text:
    raise AssertionError("main.qml must define costHistoryWindowLabel")
cost_history_label_body = function_body(main_text, "costHistoryWindowLabel")
if "rawDays = Number(requestedHistoryDays)" not in cost_history_label_body:
    raise AssertionError("invalid emitted cost ranges must fall back to the captured request range")

# The aggregation moved into CostPresentation.js; the rule did not. A snapshot
# answered for another window must still be excluded from the selected range.
spend_snapshots_body = function_body(cost_presentation_text, "spendSnapshots")
if "snapshotMatchesRange(tokenCost, historyDays)" not in spend_snapshots_body:
    raise AssertionError("global spend aggregates must exclude snapshots from another selected range")
cost_range_match_body = function_body(cost_presentation_text, "snapshotMatchesRange")
for range_match_fragment in ("Number(tokenCost.historyDays)", "Number(historyDays)"):
    if range_match_fragment not in cost_range_match_body:
        raise AssertionError(
            "cost snapshot range matching must compare normalized snapshot and selected ranges; "
            f"missing {range_match_fragment!r}"
        )
if "CostPresentation.spendSnapshots(" not in function_body(main_text, "spendProviderCosts"):
    raise AssertionError("main.qml must read spend snapshots from CostPresentation.js")

rate_window_body = function_body(main_text, "rateWindowMetrics")
if "pace.expectedUsedPercent !== null" not in rate_window_body or "pace.expectedUsedPercent !== undefined" not in rate_window_body:
    raise AssertionError("rateWindowMetrics must not treat null pace.expectedUsedPercent as 0")
for clamped_percent_fragment in (
    "clamp(used, 0, 100)",
    "clamp(100 - used, 0, 100)",
    "clamp(Number(pace.expectedUsedPercent), 0, 100)",
):
    if clamped_percent_fragment not in rate_window_body:
        raise AssertionError(
            "CLI percentages must be clamped before they reach a meter; "
            f"missing {clamped_percent_fragment!r}"
        )

add_window_body = function_body(main_text, "addWindow")
for reset_source_fragment in (
    "resetsAt: Normalizer.boundedDisplayText(",
    "resetDescription: Normalizer.boundedDisplayText(",
    "reset: Normalizer.boundedDisplayText(",
):
    if reset_source_fragment not in add_window_body:
        raise AssertionError("addWindow must retain raw reset data for render-time formatting")
if "onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)" in main_text:
    raise AssertionError("changing reset formatting must not fan out new CLI requests")

refresh_body = function_body(main_text, "refreshNow")
if "refreshCost(" in refresh_body or 'retireUsageCommandKind("cost")' in refresh_body:
    raise AssertionError("quota refreshes must not start or retire independent cost scans")
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
descriptor_value_body = providers_surface.function_body("valueText")
if "value === undefined || value === null" not in descriptor_value_body:
    raise AssertionError("descriptor value text must only blank nullish values")
if "valueText: normalizedValueText" not in providers_surface_text:
    raise AssertionError("normalized descriptor fields must retain nullish-safe display text")
if "selectedOptionIndex: optionIndex(options, normalizedValueText)" not in providers_surface_text:
    raise AssertionError("descriptor enum selection must read the nullish-safe value text")
if "text: modelData.valueText" not in providers_text:
    raise AssertionError("descriptor text fields must render normalized value text")
if "currentIndex: modelData.selectedOptionIndex" not in providers_text:
    raise AssertionError("descriptor enum fields must render the normalized selection")

descriptor_enum_box = providers_surface.id_block("descriptorEnumBox")
for fragment in (
    "property bool restoreBindingAfterWrite: false",
    "readonly property bool descriptorWritePending:",
    "onDescriptorWritePendingChanged:",
    "if (descriptorWritePending || !restoreBindingAfterWrite)",
    "restoreBindingAfterWrite = false",
    "currentIndex = Qt.binding(function()",
):
    if fragment not in descriptor_enum_box:
        raise AssertionError(
            "descriptor enum must restore its selection binding after a write result; "
            f"missing {fragment!r}"
        )
if "onActivated:" in descriptor_enum_box:
    raise AssertionError("descriptor enum activation must preserve the user's choice until Save")
descriptor_enum_save = providers_surface.id_block("descriptorEnumSaveButton")
descriptor_write_index = descriptor_enum_save.find("page.writeDescriptorField(")
descriptor_restore_arm_index = descriptor_enum_save.find(
    "descriptorEnumBox.restoreBindingAfterWrite ="
)
if descriptor_write_index < 0 or descriptor_restore_arm_index < descriptor_write_index:
    raise AssertionError(
        "descriptor enum Save must submit the selected value before arming binding restore"
    )


def assert_dismissible_message_restores_visibility(surface, object_id, state_property):
    block = surface.id_block(object_id)
    for fragment in (
        f"if (visible || {state_property}.length === 0)",
        f'{state_property} = ""',
        f"visible = Qt.binding(function() {{ return {state_property}.length > 0 }})",
    ):
        if fragment not in block:
            raise AssertionError(
                f"dismissible message {object_id!r} must clear only on close and restore "
                f"its visibility binding; missing {fragment!r}"
            )


assert_dismissible_message_restores_visibility(
    providers_surface, "providerErrorMessage", "page.errorText"
)
assert_dismissible_message_restores_visibility(
    providers_surface, "providerStatusMessage", "page.statusText"
)
assert_dismissible_message_restores_visibility(
    debug_surface, "diagnosticErrorMessage", "page.diagnosticError"
)

accounts_body = function_body(main_text, "parseProviderAccountsOutput")
if "var dedupedOptions = Normalizer.dedupeAccountOptions(options)" not in accounts_body:
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
heading_chunks = main_text.split("PlainHeading {")[1:]
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
    "radius: applet.roundedSurfaceRadius",
    "Kirigami.Theme.alternateBackgroundColor",
    "border.color: applet.withAlpha(Kirigami.Theme.textColor, 0.09)",
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

rounded_bar_body = function_body(cost_presentation_text, "paintRoundedTopBar")
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

compact_row_body = id_block(compact_representation_text, "compactRow")
for centering_fragment in (
    "anchors.centerIn: parent",
    "implicitWidth))",
):
    if centering_fragment not in compact_row_body:
        raise AssertionError(
            "the compact row must stay centred when the panel reserves more width "
            f"than the content needs; missing {centering_fragment!r}"
        )
if "anchors.fill: parent" in compact_row_body:
    raise AssertionError("the compact row must not stretch its content to the reserved panel width again")

compact_meter_body = id_block(compact_representation_text, "compactMeter")
for meter_fragment in (
    "Layout.preferredWidth: compactRoot.meterWidth",
    "Layout.preferredWidth: compactRoot.meterIconSize",
    "Layout.preferredHeight: compactRoot.meterIconSize",
    "Layout.preferredHeight: compactRoot.meterBarHeight",
):
    if meter_fragment not in compact_meter_body:
        raise AssertionError(
            "panel provider meters must scale with the panel instead of using "
            f"fixed pixel sizes; missing {meter_fragment!r}"
        )
for provider_click_fragment in (
    "id: compactMeterMouse",
    "anchors.fill: parent",
    "function activate()",
    "activeFocusOnTab: true",
    "visible: compactMeter.activeFocus",
    "Accessible.role: Accessible.Button",
    "Accessible.name: i18n(\"Open %1\", modelData.title)",
    "Accessible.onPressAction: compactMeter.activate()",
    "Keys.onPressed:",
    "case Qt.Key_Space:",
    "case Qt.Key_Enter:",
    "compactRoot.applet.openProviderFromPanel(compactMeter.modelData.provider)",
    "onClicked: compactMeter.activate()",
):
    if provider_click_fragment not in compact_meter_body:
        raise AssertionError(
            "each panel provider meter must be keyboard- and assistive-accessible "
            "and open its matching provider tab; "
            f"missing {provider_click_fragment!r}"
        )
if "forceActiveFocus(Qt.MouseFocusReason)" in compact_meter_body:
    raise AssertionError(
        "a mouse click on a panel meter must not leave the keyboard focus ring active"
    )
if "Controls.ToolTip" in compact_meter_body:
    raise AssertionError(
        "panel meters must rely on the plasmoid tooltip instead of stacking a second tooltip"
    )

open_panel_provider_body = function_body(main_text, "openProviderFromPanel")
for panel_selection_fragment in (
    "providerIndexForID(providerID)",
    "selectedProviderID = providers[index].provider",
    "selectionInitialized = true",
    "expanded = true",
):
    if panel_selection_fragment not in open_panel_provider_body:
        raise AssertionError(
            "panel meter selection must stay in the applet state owner; "
            f"missing {panel_selection_fragment!r}"
        )
if "readonly property int meterContentHeight: Math.max(0, height" not in compact_representation_text:
    raise AssertionError("panel meter geometry must derive from the compact representation height")
if "compactRoot.applet.compactProviders().length * compactRoot.meterWidth" not in compact_representation_text:
    raise AssertionError("the meters element must reserve panel width from the shared meter width")

vertical_status_badge_body = id_block(compact_representation_text, "compactVerticalStatusBadge")
for vertical_badge_fragment in (
    "visible: compactRoot.verticalPanel",
    "compactRoot.incidentProvider.hasIncident",
    "statusBadgeColor(compactRoot.incidentProvider.statusSeverity)",
    "border.width: 1",
    "border.color: Kirigami.Theme.backgroundColor",
):
    if vertical_badge_fragment not in vertical_status_badge_body:
        raise AssertionError(
            "collapsing to an icon must keep an at-a-glance incident marker; "
            f"missing {vertical_badge_fragment!r}"
        )

horizontal_status_badge_body = id_block(compact_representation_text, "compactStatusBadge")
for horizontal_badge_fragment in (
    "visible: !compactRoot.verticalPanel",
    "compactRoot.incidentProvider.hasIncident",
    "statusBadgeColor(compactRoot.incidentProvider.statusSeverity)",
    "border.width: 1",
    "border.color: Kirigami.Theme.backgroundColor",
):
    if horizontal_badge_fragment not in horizontal_status_badge_body:
        raise AssertionError(
            "horizontal status badge must keep a contrast contour against the panel; "
            f"missing {horizontal_badge_fragment!r}"
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
    "radius: applet.roundedSurfaceRadius",
    "border.color: applet.withAlpha(Kirigami.Theme.textColor, 0.06)",
    "anchors.margins: Kirigami.Units.smallSpacing / 2",
    "applet.withAlpha(Kirigami.Theme.textColor, 0.045)",
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
provider_tabs_flickable_body = id_block(main_text, "providerTabsFlickable")
for scroll_fragment in (
    "WheelHandler {",
    "acceptedDevices: PointerDevice.Mouse",
    "function ensureVisible(item)",
    "function focusAdjacentTab(item, forward)",
    "function scrollBy(delta)",
):
    if scroll_fragment not in provider_tabs_flickable_body:
        raise AssertionError(
            "the tab strip must stay reachable without touch gestures; "
            f"missing {scroll_fragment!r}"
        )
# The scroll arithmetic moved into TabStripGeometry.js, where the edge cases are
# tested. Assert the delegation, and that neither decision grew a second copy
# back inside the strip.
for tab_geometry_fragment in (
    "TabStripGeometry.boundedPosition(position, contentWidth, width)",
    "TabStripGeometry.revealPosition(",
    "if (target !== null) {",
):
    if tab_geometry_fragment not in provider_tabs_flickable_body:
        raise AssertionError(
            "the tab strip must take its scroll positions from TabStripGeometry.js; "
            f"missing {tab_geometry_fragment!r}"
        )
for inlined_tab_geometry in (
    "Math.min(contentWidth - width, position)",
    "right + margin > contentX + width",
):
    if inlined_tab_geometry in provider_tabs_flickable_body:
        raise AssertionError(
            "tab strip scroll arithmetic must not be re-inlined beside the module; "
            f"found {inlined_tab_geometry!r}"
        )

if main_text.count("providerTabsFlickable.focusAdjacentTab(") != 4:
    raise AssertionError("both the overview tab and the provider tabs must move focus with arrow keys")
if "providerTabsFlickable.ensureVisible(overviewTab)" not in main_text:
    raise AssertionError("focusing the overview tab must pull it back into view")
if "providerTabsFlickable.ensureVisible(providerTab)" not in main_text:
    raise AssertionError("focusing a provider tab must pull it back into view")
if "function claimSelectedTab(item, isSelected)" not in provider_tabs_flickable_body:
    raise AssertionError("the tab strip must track which tab is selected in one place")
# Every tab kind must report selection, or the strip keeps revealing a stale tab
# after the user switches between a provider and a global view.
if main_text.count("providerTabsFlickable.claimSelectedTab(") != 2:
    raise AssertionError("the overview tab and the provider tabs must both report selection")
for claim_fragment in (
    "onSelectedChanged: overviewTab.claimSelectedTab()",
    "onSelectedChanged: providerTab.claimSelectedTab()",
):
    if claim_fragment not in main_text:
        raise AssertionError(f"selection tracking is missing {claim_fragment!r}")
if "tab.tabStrip.claimSelectedTab(tab, tab.selected)" not in global_tab_text:
    raise AssertionError("global tabs must report selection to the strip")
if "onSelectedChanged: tab.claimSelectedTab()" not in global_tab_text:
    raise AssertionError("global tabs must report selection changes to the strip")
if "tab.tabStrip.focusAdjacentTab(tab" not in global_tab_text:
    raise AssertionError("global tabs must take part in arrow-key tab navigation")
if "tab.tabStrip.ensureVisible(tab)" not in global_tab_text:
    raise AssertionError("a focused global tab must be scrolled into view")

for fade_id, fade_direction in (
    ("providerTabsLeftFade", "-providerTabsFlickable.tabPageStep"),
    ("providerTabsRightFade", "providerTabsFlickable.tabPageStep"),
):
    fade_body = id_block(main_text, fade_id)
    for fade_fragment in (
        "Accessible.role: Accessible.Button",
        "cursorShape: Qt.PointingHandCursor",
        f"onClicked: providerTabsFlickable.scrollBy({fade_direction})",
    ):
        if fade_fragment not in fade_body:
            raise AssertionError(
                f"{fade_id} must be a clickable scroll affordance; missing {fade_fragment!r}"
            )

if "Kirigami.Theme.highlightedTextColor" in provider_tabs_body:
    raise AssertionError("provider tabs must not depend on a heavy solid-highlight selected state")
for stale_selected_overlay in (
    "applet.withAlpha(brandAccent, 0.12)",
    "selected ? applet.withAlpha(accent, 0.32)",
):
    if stale_selected_overlay in provider_tabs_body:
        raise AssertionError(
            "provider tabs must not restore a persistent accent capsule; "
            f"found {stale_selected_overlay!r}"
        )
for tab_id in ("overviewTab", "providerTab"):
    tab_body = id_block(main_text, tab_id)
    focus_id = "overviewFocus" if tab_id == "overviewTab" else "providerFocus"
    for focus_fragment in (
        f"readonly property bool keyboardFocusVisible: {focus_id}.visualFocus",
        "border.width: keyboardFocusVisible ? 1 : 0",
        f"id: {focus_id}",
        "activeFocusOnTab: true",
        f"{focus_id}.forceActiveFocus(Qt.MouseFocusReason)",
    ):
        if focus_fragment not in tab_body:
            raise AssertionError(
                f"{tab_id} must transfer pointer focus without drawing a keyboard ring; "
                f"missing {focus_fragment!r}"
            )
    for stale_pointer_focus_fragment in ("focusAcquiredByPointer",):
        if stale_pointer_focus_fragment in tab_body:
            raise AssertionError(
                f"{tab_id} must not retain a pointer-assigned focus overlay after the popup reopens; "
                f"found {stale_pointer_focus_fragment!r}"
            )

for global_tab_focus_fragment in (
    "readonly property bool keyboardFocusVisible: tabFocus.visualFocus",
    "border.width: keyboardFocusVisible ? 1 : 0",
    "id: tabFocus",
    "activeFocusOnTab: true",
    "tabFocus.forceActiveFocus(Qt.MouseFocusReason)",
):
    if global_tab_focus_fragment not in global_tab_text:
        raise AssertionError(
            "global tabs must preserve keyboard focus without pointer focus state; "
            f"missing {global_tab_focus_fragment!r}"
        )
for stale_global_pointer_focus_fragment in ("focusAcquiredByPointer",):
    if stale_global_pointer_focus_fragment in global_tab_text:
        raise AssertionError(
            "global tabs must not retain a pointer-assigned focus overlay after the popup reopens; "
            f"found {stale_global_pointer_focus_fragment!r}"
        )

provider_tab_body = id_block(main_text, "providerTab")
if (
    "color: providerTab.meter >= 0" not in provider_tab_body
    or "providerTab.selected ? providerTab.accent : \"transparent\"" not in provider_tab_body
):
    raise AssertionError(
        "providerTab must show the accent underline when selected for unmetered providers"
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

credits_section_index = main_text.find('text: i18n("Credits")')
if credits_section_index < 0:
    raise AssertionError("main.qml must keep the Credits section")
credits_section_text = main_text[credits_section_index:credits_section_index + 900]
if "Remaining: %1" not in credits_section_text:
    raise AssertionError("the Credits section must keep the remaining-balance line")
if re.search(r"credits\s*(?:,|/)\s*\d", credits_section_text):
    raise AssertionError(
        "the credits balance must not be plotted against an invented denominator; "
        "`usage.credits` reports only `remaining`, so a meter here fills for "
        "reasons the payload never describes. Add a meter back only once the CLI "
        "reports the matching allowance"
    )

quota_meter_color_body = function_body(main_text, "quotaMeterColor")
if "statusBadgeColor(" not in quota_meter_color_body:
    raise AssertionError(
        "quotaMeterColor must reuse statusBadgeColor so the quota level and the "
        "provider status badge stay one colour vocabulary"
    )
quota_severity_body = function_body(main_text, "quotaSeverity")
if "showQuotaWarningMarkers" not in quota_severity_body:
    raise AssertionError(
        "the setting that hides the quota markers must also hide the quota "
        "meter colour, so one switch owns the whole warning presentation"
    )
for meter_surface, meter_surface_text in (
    (overview_provider_row_qml, overview_provider_row_text),
    (provider_usage_row_qml, provider_usage_row_text),
    (compact_representation_qml, compact_representation_text),
):
    if "quotaMeterColor(" not in meter_surface_text:
        raise AssertionError(
            f"{meter_surface.name} must colour its meter fill through "
            "quotaMeterColor; a meter that stays provider-coloured at 99% used "
            "reads exactly like an idle one"
        )

overview_header_body = id_block(main_text, "overviewHeaderRow")
provider_header_body = id_block(provider_header_text, "providerHeaderRow")
for header_id, header_body in (
    ("overviewHeaderRow", overview_header_body),
    ("providerHeaderRow", provider_header_body),
):
    if "Controls.BusyIndicator" not in header_body or "running: visible" not in header_body:
        raise AssertionError(
            f"{header_id} must show a running busy indicator while a refresh "
            "runs over data that is already on screen; a greyed button is not "
            "feedback"
        )

if "fullRepresentation:" not in main_text:
    raise AssertionError("the applet must keep a fullRepresentation root")
full_representation_head = id_block(main_text, "fullRoot")[:900]
if "popupContent.implicitHeight" not in full_representation_head:
    raise AssertionError(
        "the popup height must follow its content; a fixed height leaves the "
        "Overview half empty whenever few providers are configured"
    )
if re.search(r"implicitHeight:\s*Kirigami\.Units\.gridUnit\s*\*\s*\d", full_representation_head):
    raise AssertionError(
        "the popup must not pin implicitHeight to a constant again; the "
        "constants belong in the clamp around the content height"
    )

format_number_body = function_body(main_text, "formatNumber")
if "groupedDecimalString(" not in format_number_body:
    raise AssertionError(
        "formatNumber must route through groupedDecimalString so credit balances "
        "carry group separators and the locale decimal mark like every other "
        "figure in the popup"
    )
if "toFixed(" in format_number_body:
    raise AssertionError(
        "formatNumber must not format digits itself again; toFixed hardcodes the "
        "decimal mark and prints a whole balance as '0.0'"
    )
for usage_metadata_id in ("usagePaceLabel", "usageResetLabel"):
    usage_metadata_body = id_block(provider_usage_row_text, usage_metadata_id)
    if "font: Kirigami.Theme.smallFont" not in usage_metadata_body:
        raise AssertionError(f"{usage_metadata_id} must retain the compact metadata type scale")

if "chart.applet.paintRoundedTopBar(" not in interactive_chart_text:
    raise AssertionError("provider detail bar charts must use rounded top corners")
for detail_chart_fragment in (
    "chart.applet.buildChartBarGradient(",
    "chart.applet.chartBarGeometry(width, chart.points.length)",
    "Math.max(2, (height - 3) * fraction)",
):
    if detail_chart_fragment not in interactive_chart_text:
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

if "Components.InteractiveChart" not in main_text or "applet.costChartPoints(" not in main_text:
    raise AssertionError("the provider cost sparkline must use the interactive shared chart")

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
    "Layout.preferredHeight: applet.compactMeterTrackHeight",
    "applet.withAlpha(Kirigami.Theme.textColor, 0.055)",
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

cost_history_rows_body = function_body(cost_presentation_text, "historyRows")
if "tokenCost.daily.length - 7" not in cost_history_rows_body:
    raise AssertionError("cost history must show only the latest seven detailed rows")
if "sparklineMax(visibleDaily, showsTokens)" not in cost_history_rows_body:
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

global_error_body = id_block(main_text, "globalErrorMessage")
provider_usage_loading_body = id_block(main_text, "providerUsageLoadingRow")
for scoped_feedback_body, feedback_name in (
    (global_error_body, "globalErrorMessage"),
    (provider_usage_loading_body, "providerUsageLoadingRow"),
):
    if "applet.providerUsageFeedbackVisible" not in scoped_feedback_body:
        raise AssertionError(
            f"{feedback_name} must stay hidden on the independent Spend and Sessions tabs"
        )

# A RowLayout inherits its children's maximum height, so it cannot absorb the
# leftover popup height: the layout engine then spreads the slack across every
# row and drops the tab bar into the middle of an otherwise empty popup.
if not re.search(r"Item \{\s*\n\s*id: providerUsageLoadingRow", main_text):
    raise AssertionError(
        "providerUsageLoadingRow must be a plain Item so it absorbs the leftover "
        "popup height and keeps the tab bar pinned to the top while usage loads"
    )
for filler_owner_source, filler_owner_text in (
    ("SessionsView.qml", sessions_view_text),
    ("SpendView.qml", spend_view_text),
):
    if "Controls.BusyIndicator {\n            anchors.centerIn: parent" not in filler_owner_text:
        raise AssertionError(
            f"{filler_owner_source} must center its busy indicator inside a filler item "
            "so the heading stays pinned to the top while loading"
        )

provider_status_body = id_block(main_text, "providerStatusMessage")
if "applet.selectedProviderData.hasIncident" not in provider_status_body:
    raise AssertionError("healthy provider status must not occupy a permanent inline banner")
if "applet.statusMessageType(applet.selectedProviderData.statusSeverity)" not in provider_status_body:
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

notification_memo_js = (root / "contents/ui/NotificationMemo.js").read_text(encoding="utf-8")
notification_planner_js = (root / "contents/ui/NotificationPlanner.js").read_text(encoding="utf-8")
status_memo_key_body = function_body(notification_memo_js, "statusMemoKey")
if "providerID" not in status_memo_key_body or "account" in status_memo_key_body:
    raise AssertionError("statusMemoKey must remain exclusively provider-scoped across account switches")

# NotificationPlanner owns the opaque memo and every cross-signal transition.
# The direct QtTest suite pins priming, pending refreshes, account scopes,
# escalation/reset behavior, and intent ordering; these static assertions keep
# QML as the thin observation/effect adapter instead of reintroducing policy.
# Private planner helpers deliberately stay out of this check so a
# behavior-preserving internal refactor does not have to rewrite the safety net.
if "function transition(observations, previousMemo, options)" not in notification_planner_js:
    raise AssertionError("NotificationPlanner.js must expose its transition boundary")
for forbidden_planner_fragment in (
    "sendPlasmaNotification",
    "notify-send",
    "i18n(",
    "Qt.",
    "selectedAccountForProvider",
    "notificationRefreshPending",
):
    if forbidden_planner_fragment in notification_planner_js:
        raise AssertionError(
            "NotificationPlanner must stay pure and independent of QML lifecycle/effects; "
            f"found {forbidden_planner_fragment!r}"
        )

observations_body = applet.function_body("notificationObservations")
for observation_fragment in (
    "providerID: providerMapKey(item.provider)",
    "scopeID: notificationScopeKey(item)",
    "pending: notificationProviderRefreshPending(item.provider)",
    "statusIncidentKey: String(item.statusIncidentKey || \"\")",
    "rows: notificationObservationRows(item)",
):
    if observation_fragment not in observations_body:
        raise AssertionError(
            "notificationObservations must resolve normalized identity and freshness before the planner; "
            f"missing {observation_fragment!r}"
        )
observation_rows_body = applet.function_body("notificationObservationRows")
for row_fragment in (
    "hasPercent: row && row.hasPercent === true",
    "usedPercent: row ? Number(row.usedPercent) : NaN",
    "quotaLevel: quotaNotificationLevel(row)",
    "paceActive: paceWarningActive(row)",
):
    if row_fragment not in observation_rows_body:
        raise AssertionError(
            "notificationObservationRows must adapt display rows into semantic planner input; "
            f"missing {row_fragment!r}"
        )

process_notifications_body = applet.function_body("processNotifications")
for delegation_fragment in (
    "var observations = notificationObservations()",
    "NotificationPlanner.transition(",
    "notificationPlannerOptions(mode)",
    "notificationMemo = result.nextMemo",
    "dispatchNotificationIntents(result.intents, observations)",
):
    if delegation_fragment not in process_notifications_body:
        raise AssertionError(
            "processNotifications must delegate the whole transition and apply its result; "
            f"missing {delegation_fragment!r}"
        )
memo_commit_index = process_notifications_body.find("notificationMemo = result.nextMemo")
dispatch_index = process_notifications_body.find("dispatchNotificationIntents")
if memo_commit_index < 0 or dispatch_index < 0 or memo_commit_index > dispatch_index:
    raise AssertionError("the complete notification memo must commit before any intent side effect")
for old_policy_fragment in (
    "NotificationMemo.statusDecision(",
    "quotaNotificationKey(",
    "paceNotificationKey(",
    "limitResetNotificationKey(",
):
    if old_policy_fragment in process_notifications_body:
        raise AssertionError("processNotifications must not reimplement planner policy in QML")

dispatch_body = applet.function_body("dispatchNotificationIntents")
for intent_fragment in (
    'intent.kind === "status"',
    'intent.kind === "quota"',
    'intent.kind === "pace"',
    'intent.kind === "reset"',
    "sendPlasmaNotification(",
):
    if intent_fragment not in dispatch_body:
        raise AssertionError(
            "dispatchNotificationIntents must keep every localized effect in QML; "
            f"missing {intent_fragment!r}"
        )

reset_memo_body = applet.function_body("resetNotificationMemo")
if "NotificationPlanner.transition(" not in reset_memo_body or 'mode: "reset"' not in reset_memo_body:
    raise AssertionError("resetNotificationMemo must reset the opaque memo through NotificationPlanner")
if re.search(r"notificationMemo\s*=\s*\(\{\}\)", reset_memo_body):
    raise AssertionError("resetNotificationMemo must not clear the whole memo, including status state")

# NotificationMemo remains an internal seam for provider-scoped status rules.
for memo_function in (
    "function statusMemoKey(providerID)",
    "function statusPrimedMemoKey(providerID)",
    "function isStatusMemoKey(key)",
    "function preservedMemoAfterReset(memo)",
    "function carryStatusMemo(memo, providerID, nextMemo)",
    "function statusDecision(memo, providerID, value, severity)",
    "function applyStatusDecision(nextMemo, providerID, decision)",
    "function severityRank(severity)",
):
    if memo_function not in notification_memo_js:
        raise AssertionError(f"NotificationMemo.js must keep {memo_function!r}")
if "sendPlasmaNotification" in notification_memo_js or "i18n(" in notification_memo_js:
    raise AssertionError("NotificationMemo.js must stay free of side effects and user-facing text")
status_decision_body = function_body(notification_memo_js, "statusDecision")
if 'statusPrimedMemoKey(providerID)] !== "1"' not in status_decision_body:
    raise AssertionError(
        "statusDecision must silently baseline a provider that was never primed, so an incident "
        "predating the memo cannot be announced as new"
    )
unprimed_index = status_decision_body.find('statusPrimedMemoKey(providerID)] !== "1"')
worsened_index = status_decision_body.find("worsened")
if unprimed_index < 0 or worsened_index < 0 or unprimed_index > worsened_index:
    raise AssertionError("statusDecision must settle the unprimed case before comparing severities")

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
status_body = function_body(notification_memo_js, "statusDecision")
if "worsened" not in status_body:
    raise AssertionError("statusDecision must gate on severity worsening")
if (
    "incidentChanged" not in status_body
    or "previousIncidentKey" not in status_body
    or "currentIncidentKey" not in status_body
    or "previousIncidentKey !== currentIncidentKey" not in status_body
):
    raise AssertionError(
        "statusDecision must only notify for same-severity changes "
        "when a stable status incident key is present"
    )
if "previousValue !== text" in status_body:
    raise AssertionError(
        "statusDecision must compare incident keys instead of full "
        "severity-bearing memo values"
    )

status_value_body = function_body(notification_planner_js, "statusValue")
if "observation.statusIncidentKey" not in status_value_body:
    raise AssertionError("NotificationPlanner must prefer stable incident keys when present")
if "NotificationMemo.statusMemoValue(" not in status_value_body:
    raise AssertionError("NotificationPlanner must encode severity and stable incident key through NotificationMemo")
if 'String(severity || "") + "|" + String(incidentKey || "")' not in function_body(
    notification_memo_js, "statusMemoValue"
):
    raise AssertionError("statusMemoValue must encode severity and incident key, and nothing else")
if "statusText" in status_value_body:
    raise AssertionError("NotificationPlanner must not use provider-controlled status text as incident identity")

# autoSelectProvider must not clobber an explicit global-tab selection on every
# refresh; once the user picks Overview, Spend, or Sessions it has to survive.
select_body = function_body(main_text, "updateSelectedProvider")
if "globalViewSelected" not in select_body:
    raise AssertionError(
        "updateSelectedProvider must preserve an explicit global-tab selection "
        "when autoSelectProvider is enabled"
    )
if "selectedProviderID" not in select_body:
    raise AssertionError("updateSelectedProvider must preserve selection by provider id")
if "function providerIndexForID(providerID)" not in main_text:
    raise AssertionError("the selected provider index must be derived from its provider id")

for global_view_fragment in (
    'applet.selectGlobalView("spend")',
    'applet.selectGlobalView("sessions")',
    "Components.SpendView",
    "Components.SessionsView",
):
    if global_view_fragment not in main_text:
        raise AssertionError(f"global popup navigation is missing {global_view_fragment!r}")

for session_contract_fragment in (
    '"sessions", "--json-v2"',
    'retireUsageCommandKind("sessions")',
    "maximumSessions = 128",
    "function normalizeSession(item)",
):
    if session_contract_fragment not in main_text:
        raise AssertionError(f"sessions lifecycle is missing {session_contract_fragment!r}")
for forbidden_session_value in ("transcriptPath", "cwd"):
    if forbidden_session_value in sessions_view_text:
        raise AssertionError(
            "SessionsView must never render or follow local session paths; "
            f"found {forbidden_session_value!r}"
        )

normalize_session_body = function_body(main_text, "normalizeSession")
for activity_fallback_fragment in (
    "item.lastActivityAt",
    "item.startedAt",
    "activityAt: activityAt",
    "activityMs: activityMs",
):
    if activity_fallback_fragment not in normalize_session_body:
        raise AssertionError(
            "session activity must prefer lastActivityAt and safely fall back to startedAt; "
            f"missing {activity_fallback_fragment!r}"
        )
if "lastActivityMs" in main_text:
    raise AssertionError("session ordering must use the normalized activity fallback")

for shared_copy_fragment in (
    "function copySessionValue(text, valueKey)",
    "id: clipboardBuffer",
    "id: copiedTimer",
):
    if shared_copy_fragment not in sessions_view_text:
        raise AssertionError(
            "SessionsView must own one shared clipboard lifecycle; "
            f"missing {shared_copy_fragment!r}"
        )
if sessions_view_text.count("Controls.TextField {") != 1 or sessions_view_text.count("Timer {") != 2:
    raise AssertionError("SessionsView must instantiate exactly one clipboard field and two shared timers")
for per_delegate_copy_fragment in ("Controls.TextField {", "Timer {"):
    if per_delegate_copy_fragment in copyable_value_text:
        raise AssertionError(
            "CopyableValue delegates must not allocate clipboard controls or timers; "
            f"found {per_delegate_copy_fragment!r}"
        )
if "valueRow.copyRevealed || valueRow.copied || hovered || activeFocus" not in copyable_value_text:
    raise AssertionError(
        "the copy action must stay reachable by keyboard and while confirming a copy, "
        "not only while the owning row is hovered"
    )
if "PlainPlasmaLabel {" not in copyable_value_text:
    raise AssertionError("CopyableValue must render untrusted CLI values as plain text")
if sessions_view_text.count("PlainPlasmaLabel {") < 3:
    raise AssertionError("all direct session labels must render CLI-derived text as plain text")
if sessions_view_text.count("copyRevealed: sessionCardHover.hovered") != 2:
    raise AssertionError(
        "both session copy actions must be revealed by the shared card hover handler "
        "instead of crowding every card permanently"
    )

# The shape check lives in the normalizer and the error text in the applet, so
# the rule is asserted on both halves: an unrecognized payload must return the
# "unsupported" sentinel rather than an empty list, and the caller must turn that
# sentinel into a visible error instead of an empty successful snapshot.
normalize_sessions_body = function_body(main_text, "normalizeSessions")
for rejected_shape_fragment in (
    "Array.isArray(payload)",
    "Array.isArray(payload.sessions)",
    "return null",
):
    if rejected_shape_fragment not in normalize_sessions_body:
        raise AssertionError(
            "unexpected session payload shapes must be rejected, not emptied; "
            f"missing {rejected_shape_fragment!r}"
        )
if ": []" in normalize_sessions_body:
    raise AssertionError("unexpected session payload shapes must not become an empty successful snapshot")

parse_sessions_body = function_body(main_text, "parseSessionsOutput")
for rejected_shape_fragment in (
    "nextSessions === null",
    "codexbar sessions returned an unsupported JSON payload.",
):
    if rejected_shape_fragment not in parse_sessions_body:
        raise AssertionError(
            "unexpected session payload shapes must preserve the previous snapshot and surface an error; "
            f"missing {rejected_shape_fragment!r}"
        )
if "sessions = []" in parse_sessions_body:
    raise AssertionError("an unsupported sessions payload must not clear the visible sessions")

session_activity_body = function_body(main_text, "sessionActivityText")
for live_age_fragment in (
    "Number(nowMs)",
    "currentTimeMs - Number(item.activityMs)",
):
    if live_age_fragment not in session_activity_body:
        raise AssertionError(
            "relative session ages must depend on a periodically updated clock; "
            f"missing {live_age_fragment!r}"
        )
for session_clock_fragment in (
    "property double sessionClockMs: Date.now()",
    "id: sessionAgeTimer",
    "sessionActivityText(modelData, view.sessionClockMs)",
):
    if session_clock_fragment not in sessions_view_text:
        raise AssertionError(
            "SessionsView must refresh relative ages even when CLI refresh is manual; "
            f"missing {session_clock_fragment!r}"
        )

for chart_interaction_fragment in (
    "activeFocusOnTab: true",
    "Keys.onPressed:",
    "onPositionChanged:",
    "selectedIndex",
):
    if chart_interaction_fragment not in interactive_chart_text:
        raise AssertionError(
            "InteractiveChart must support pointer and keyboard inspection; "
            f"missing {chart_interaction_fragment!r}"
        )
for stable_chart_fragment in (
    "readonly property bool hasActivePoint",
    "if (chart.hoveredIndex >= chart.points.length)",
):
    if stable_chart_fragment not in interactive_chart_text:
        raise AssertionError(
            "InteractiveChart must keep hover geometry stable and clamp stale state; "
            f"missing {stable_chart_fragment!r}"
        )
if "visible: chart.activeIndex" in interactive_chart_text:
    raise AssertionError("InteractiveChart must reserve readout space while pointer state changes")
if (
    "id: compactTextMeasurer" not in compact_representation_text
    or "Math.ceil(compactTextMeasurer.implicitWidth)" not in compact_representation_text
    or "maximumCompactWidth: Kirigami.Units.gridUnit * 18" not in compact_representation_text
):
    raise AssertionError(
        "compact panel text must use a bounded wide cap and round independent measurement up"
    )
if "elementLoader.implicitWidth" in compact_representation_text:
    raise AssertionError("compact panel text measurement must not feed back through its Loader width")
if "rangeCombo.valueAt(index)" not in spend_view_text:
    raise AssertionError("the cost range selector must use the activated option instead of stale currentValue")
if "view.applet.refreshCost(true)" not in spend_view_text:
    raise AssertionError("the cost refresh button must explicitly bypass the automatic hourly throttle")
for cost_loading_fragment in (
    "enabled: !view.applet.costLoading",
    "visible: view.applet.costLoading && view.providerCosts.length === 0",
    "visible: !view.applet.costLoading",
):
    if cost_loading_fragment not in spend_view_text:
        raise AssertionError(
            "SpendView must distinguish a range refresh from an empty result; "
            f"missing {cost_loading_fragment!r}"
        )
if ('readonly property bool costLoading: CommandLedger.hasKind(activeUsageCommands, "cost")'
        not in main_text):
    raise AssertionError("cost loading state must follow the active cost command lifecycle")
if "required property int index" not in display_text:
    raise AssertionError("the panel element editor delegate must explicitly receive its model index")
for localized_pair_source, localized_pair_text in (
    ("InteractiveChart.qml", interactive_chart_text),
    ("SpendView.qml", spend_view_text),
):
    if '+ ": " +' in localized_pair_text:
        raise AssertionError(
            f"{localized_pair_source} must localize label/value separators with placeholders"
        )
if "InteractiveChart" not in spend_view_text or "Activity heatmap" not in spend_view_text:
    raise AssertionError("SpendView must expose the interactive chart and bounded activity heatmap")
for heatmap_range_fragment in (
    "Math.ceil(view.dailyPoints.length / rows)",
    "readonly property int fittingColumns",
    "readonly property real cellSize",
    "Layout.preferredHeight: heatmapGrid.rows * heatmapGrid.cellSize",
    "+ (heatmapGrid.rows - 1) * heatmapGrid.rowSpacing",
):
    if heatmap_range_fragment not in spend_view_text:
        raise AssertionError(
            "the activity heatmap must follow the selected cost range and size cells "
            f"from the available width; missing {heatmap_range_fragment!r}"
        )
if "modelData.monthLine" in spend_view_text:
    raise AssertionError(
        "the Usage & Spend provider rows must not repeat the window label that the "
        "range selector already states; use the windowValueLine figures"
    )
if "windowValueLine: costValueLine(" not in main_text:
    raise AssertionError(
        "normalized token costs must expose a window-free value line for range-scoped surfaces"
    )
for trust_owner_source, trust_owner_text in (
    ("FullRepresentation.qml", full_representation_text),
    ("SpendView.qml", spend_view_text),
):
    if "Components.CostTrustNotice" not in trust_owner_text:
        raise AssertionError(
            f"{trust_owner_source} must render the shared cost-trust notice"
        )
    if "CostPresentation.costTrustSummary(" not in trust_owner_text:
        raise AssertionError(
            f"{trust_owner_source} must delegate cost-trust policy to CostPresentation"
        )
for persistent_notice_fragment in (
    "property var costTrustNoticeStates: ({})",
    "function updateCostTrustNoticeState(",
    "CostPresentation.costTrustNoticeStoreTransition(",
):
    if persistent_notice_fragment not in main_text:
        raise AssertionError(
            "the applet root must preserve scoped cost-notice dismissals across popup recreation; "
            f"missing {persistent_notice_fragment!r}"
        )
for cost_trust_fragment in (
    "PlainInlineMessage",
    "property var summary: null",
    "property var stateOwner: null",
    'property string noticeScope: ""',
    "property bool presentationVisible: false",
    "showCloseButton: true",
    "stateOwner.updateCostTrustNoticeState(",
    "onNoticeScopeChanged:",
    "onStateOwnerChanged:",
    'typeof stateOwner.updateCostTrustNoticeState !== "function"',
    "onSummaryChanged: scheduleRefreshNoticeState()",
    "onNoticeScopeChanged: scheduleRefreshNoticeState()",
    "onStateOwnerChanged: scheduleRefreshNoticeState()",
    "function scheduleRefreshNoticeState()",
    "noticeRefresh.restart()",
    "onTriggered: noticeRoot.refreshNoticeState()",
    "onVisibleChanged: {",
    "&& presentationVisible",
    'i18n("%1 %2"',
    'i18n("The displayed range total',
):
    if cost_trust_fragment not in cost_trust_notice_text:
        raise AssertionError(
            "CostTrustNotice must own the shared localized message and standard styling; "
            f"missing {cost_trust_fragment!r}"
        )
for non_atomic_notice_fragment in (
    "onSummaryChanged: refreshNoticeState()",
    "onNoticeScopeChanged: refreshNoticeState()",
    "onStateOwnerChanged: refreshNoticeState()",
):
    if non_atomic_notice_fragment in cost_trust_notice_text:
        raise AssertionError(
            "cost notice scope and summary changes must be coalesced before mutating shared dismissal state; "
            f"found {non_atomic_notice_fragment!r}"
        )
for provider_notice_fragment in (
    'noticeScope: "provider:" +',
    "stateOwner: fullRoot.applet",
    "presentationVisible: fullRoot.visible && !applet.globalViewSelected",
):
    if provider_notice_fragment not in full_representation_text:
        raise AssertionError(
            "provider cost notices must use a persistent provider scope and visible context; "
            f"missing {provider_notice_fragment!r}"
        )
for spend_notice_fragment in (
    'noticeScope: "spend"',
    "stateOwner: view.applet",
    "presentationVisible: view.visible",
):
    if spend_notice_fragment not in spend_view_text:
        raise AssertionError(
            "Spend cost notices must use a persistent aggregate scope and visible context; "
            f"missing {spend_notice_fragment!r}"
        )
for qualified_value_fragment in (
    'i18n("%1 (estimated)"',
    'i18n("%1 (partial)"',
    'i18n("%1 (approximate)"',
):
    if qualified_value_fragment not in main_text:
        raise AssertionError(
            "cost amount lines must carry their trust qualifier in localized text; "
            f"missing {qualified_value_fragment!r}"
        )
if not re.search(
        r'sessionLine:\s*costLine\(i18n\("Today"\),\s*item\.sessionCostUSD,\s*'
        r'item\.sessionTokens,\s*currency\)',
        main_text):
    raise AssertionError(
        "window-level cost trust must not qualify the independent Today/session amount"
    )
if "view.dailyPoints.length - 42" in spend_view_text:
    raise AssertionError(
        "the activity heatmap must not pin itself to a fixed 42-day window while the "
        "range selector offers 7/30/90 days"
    )
if 'valueRow.copied ? "checkmark" : "edit-copy"' not in copyable_value_text:
    raise AssertionError("CopyableValue must provide immediate checkmark icon feedback when copied")
if "heatmapMouse.containsMouse ? 1 : 0" not in spend_view_text:
    raise AssertionError("SpendView activity heatmap cells must display hover highlight feedback")

normalize_provider_body = function_body(main_text, "normalizeProvider")
for bounded_provider_fragment in (
    "title: Normalizer.boundedDisplayText(",
    "status: Normalizer.boundedDisplayText(",
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

tooltip_body = function_body(main_text, "panelToolTipText")
if "boundedDisplayText(errorText" not in tooltip_body:
    raise AssertionError("the panel tooltip must bound global CLI error text")
if 'i18n("%1 - %2", line, incident)' not in tooltip_body:
    raise AssertionError(
        "the panel tooltip must report incidents even when the provider also reports usage"
    )
# Every file that calls this unqualified must declare it: QML and JS share no
# function scope, so a surface-wide search would be satisfied by SafeText.js while
# the applet root's callers were left with an undefined function.
applet.require_definition_where_used("boundedDisplayText")

if "applet.usageResetText(usageRow)" not in overview_provider_row_text:
    raise AssertionError("Overview reset labels must use render-time formatting")

dashboard_rows_body = function_body(main_text, "usageDashboardRows")
if "arguments[" in dashboard_rows_body:
    raise AssertionError("usageDashboardRows must declare its state and depth contract")
if "function usageDashboardRows(source, state, depth)" not in main_text:
    raise AssertionError("usageDashboardRows must expose named state and depth parameters")

# The 80/95 steps used to be literals in these two functions, so the notification
# level and the markers drawn on the bar could drift apart and neither could be
# configured. Both now delegate to one bounded library.
if "QuotaThresholds.level(" not in function_body(main_text, "quotaNotificationLevel"):
    raise AssertionError("quotaNotificationLevel must delegate to QuotaThresholds.level")
if "QuotaThresholds.markers(" not in function_body(main_text, "quotaWarningMarkers"):
    raise AssertionError("quotaWarningMarkers must delegate to QuotaThresholds.markers")
for retired_literal in ("usageBarsShowUsed ? 80 : 20", "usageBarsShowUsed ? 95 : 5", "used >= 95", "used >= 80"):
    if retired_literal in main_text:
        raise AssertionError(
            f"quota thresholds must stay configurable; found hardcoded {retired_literal!r}"
        )

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
# points. Their one-pixel minimum width can exceed a dense point slot, so the
# shared geometry helper must distribute the drawable bar edges inside the
# canvas instead of using the nominal slot as the drawing step.
if "function chartBarGeometry(width, count)" not in cost_presentation_text:
    raise AssertionError("CostPresentation.js must expose a shared bar-chart geometry helper")
chart_geometry_body = function_body(cost_presentation_text, "chartBarGeometry")
for fragment in (
    "var slotStep = safeWidth / points",
    "var barWidth = Math.max(1, slotStep - gap)",
    "Math.max(0, safeWidth - barWidth) / (points - 1)",
    "offset: Math.max(0, slotStep - barWidth) / 2",
):
    if fragment not in chart_geometry_body:
        raise AssertionError(
            f"chartBarGeometry must keep sparse and dense bars inside the canvas: {fragment}"
        )
for label, source_text in (
    ("main.qml", main_text),
    ("InteractiveChart.qml", interactive_chart_text),
):
    if "chartBarGeometry(" not in source_text:
        raise AssertionError(f"{label} bar charts must use the shared geometry helper")
    if "barWidth + gap" in source_text:
        raise AssertionError(f"{label} bar charts must not recompute their own bar pitch")
if "geometry.offset + barIndex * geometry.step" not in interactive_chart_text:
    raise AssertionError("provider detail bars must apply the shared canvas offset")

# The active line-chart point grows to a 3.5px radius. Both axes and pointer hit
# testing must use the shared inset geometry so the visible marker stays inside
# Canvas and resolves back to its own point.
for helper_name in ("chartLineX", "chartLineIndexAt", "chartLineY"):
    if f"function {helper_name}(" not in cost_presentation_text:
        raise AssertionError(f"CostPresentation.js must expose {helper_name} marker geometry")
    if f"function {helper_name}(" not in main_text:
        raise AssertionError(f"main.qml must expose {helper_name} to presentation components")
    if f"chart.applet.{helper_name}(" not in interactive_chart_text:
        raise AssertionError(f"provider detail line charts must use {helper_name}")

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
if ".overviewProviders()" in main_text:
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
if main_text.count("Layout.preferredHeight: applet.meterTrackHeight") != 1:
    raise AssertionError(
        "the provider-cost meter must consume meterTrackHeight, and it is the "
        "only meter left in the popup now that the credits balance has no "
        "allowance to plot against"
    )
if provider_usage_row_text.count(
    "Layout.preferredHeight: usageRow.applet.meterTrackHeight"
) != 1:
    raise AssertionError("the provider-usage meter must consume meterTrackHeight")


# Derived from the manifest rather than listed by hand, so a newly extracted
# component is covered the moment it exists instead of when someone remembers to
# add it here. JS helpers are excluded: these rules are about QML elements.
popup_and_provider_surfaces = tuple(
    (path, applet.texts[path]) for path in applet.files if path.suffix == ".qml"
) + ((providers_qml, providers_text),)


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

for qml_path in sorted(root.glob("contents/**/*.qml")):
    qml_content = qml_path.read_text(encoding="utf-8")
    for match in re.finditer(r"delegate:\s*([A-Za-z0-9_.]+)\s*\{", qml_content):
        element_type = match.group(1)
        if element_type.startswith("Components."):
            component_name = element_type.split(".", 1)[1]
            component_path = root / "contents/ui/components" / f"{component_name}.qml"
            if not component_path.exists():
                raise AssertionError(f"missing external component delegate file: {component_path}")
            component_content = component_path.read_text(encoding="utf-8")
            if "required property var modelData" not in component_content:
                raise AssertionError(
                    f"{component_path.name} must declare "
                    "'required property var modelData' for Qt 6 QML scoping safety"
                )
            continue
        start_index = match.end() - 1
        brace_depth = 1
        cursor = start_index + 1
        while cursor < len(qml_content) and brace_depth > 0:
            if qml_content[cursor] == "{":
                brace_depth += 1
            elif qml_content[cursor] == "}":
                brace_depth -= 1
            cursor += 1
        delegate_body = qml_content[start_index + 1:cursor - 1]
        if "required property var modelData" not in delegate_body:
            raise AssertionError(
                f"{qml_path.name} delegate {element_type} must declare "
                "'required property var modelData' for Qt 6 QML scoping safety"
            )
PY

echo "UI regression checks passed."
