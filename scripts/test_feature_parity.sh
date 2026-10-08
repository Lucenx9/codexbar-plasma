#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
# Parity rules use require_in_surface so extracting popup UI or a controller out
# of main.qml does not need an edit here. The per-component variables below stay
# file-scoped: those are delegate contracts about one specific component.
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
SESSIONS_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/SessionsView.qml"
USAGE_DETAILS_JS="${ROOT_DIR}/contents/ui/UsageDetails.js"
README_MD="${ROOT_DIR}/README.md"
CONFIG_XML="${ROOT_DIR}/contents/config/main.xml"
CONFIG_QML="${ROOT_DIR}/contents/config/config.qml"
MAKEFILE="${ROOT_DIR}/Makefile"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file "$PROVIDERS_QML" "stdoutText + \"\\n\" + stderrText"
reject_in_file "$PROVIDERS_QML" "return field.options.length > 0 ? 0 : -1"
# Provider fallback metadata is exercised through public functions in
# tests/tst_provider_metadata.qml; no table layout is required here.

# Display names live once in the shared component; the late-added provider
# fallback titles are executed by tests/tst_provider_names.qml against the
# real ProviderNames.titleForKey.

python3 - "$PROVIDERS_QML" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("    function supportsApiKeySetup(providerID)")
end = text.index("    function providerDocsUrl(providerID)", start)
body = text[start:end]
descriptor_owned = {"aiand", "clinepass", "deepinfra", "neuralwatt", "sub2api", "xai", "zenmux"}
hardcoded = sorted(descriptor_owned.intersection(re.findall(r'case "([^"]+)":', body)))
if hardcoded:
    print("descriptor-owned API key capability hardcoded in QML: " + ", ".join(hardcoded), file=sys.stderr)
    sys.exit(1)

if 'case "ibmbob":' not in body:
    print("IBM Bob must offer the official generic set-api-key setup path", file=sys.stderr)
    sys.exit(1)
if 'case "fireworks":' not in body:
    print("Fireworks must offer generic API-key setup now that the CLI discovers accountSlug", file=sys.stderr)
    sys.exit(1)
if "return fireworksSingleKeySetupSupported" not in body:
    print("Fireworks API-key setup must require CLI 0.54.0 slug discovery", file=sys.stderr)
    sys.exit(1)

for function_name in ("setEnabled", "setApiKey", "loadProviderSettings", "providerCliCommandText"):
    marker = f"    function {function_name}("
    start = text.index(marker)
    end = text.find("\n    function ", start + len(marker))
    body = text[start:end if end >= 0 else len(text)]
    if "var cliProviderID = providerCliArgument(providerID)" not in body:
        print(f"{function_name} does not convert the provider ID to its CLI argument", file=sys.stderr)
        sys.exit(1)

# The provider ID the CLI accepts is not always the canonical key, and both the
# popup and this page must send the same one, so the overrides live once in
# ProviderIdentity.js.
identity = pathlib.Path(sys.argv[1]).parent / "ProviderIdentity.js"
cli_body = identity.read_text(encoding="utf-8")
cli_table = re.search(r"var providerCliArguments = \{(.*?)\n\}", cli_body, re.S)
if not cli_table:
    print("missing providerCliArguments table in ProviderIdentity.js", file=sys.stderr)
    sys.exit(1)
cli_arguments = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', cli_table.group(1)))
for provider_id, cli_name in {
    "abacus": "abacusai",
    "alibaba": "alibaba-coding-plan",
    "alibabatokenplan": "alibaba-token-plan",
    "azureopenai": "azure-openai",
    "groq": "groqcloud",
    "qwencloud": "qwen-cloud",
}.items():
    if cli_arguments.get(provider_id) != cli_name:
        print(f"missing CLI argument mapping for {provider_id}", file=sys.stderr)
        sys.exit(1)
PY

# The project cost section is executed by tests/test_cost_sections.py, which
# renders the real component with cost-heavy/token-heavy/unpriced rows:
# metric ordering, the per-metric values and the unavailable fallback each
# go red there when broken.
# Cost presentation moved behind CostPresentation.js. Assert the delegation so
# the maths cannot quietly grow a second copy back inside main.qml.
require_in_surface applet "CostPresentation.costTrustSummary("
# The locale separator wiring is unobservable in executed tests: the
# costNumberFormat property initializer cannot be extracted, so fixtures
# declare the format themselves and swapping the separators keeps every cost
# test green. This stays as the only pin on the locale wiring.
require_in_surface applet "CostPresentation.numberFormat("
reject_in_surface applet "function appendTokenBreakdownRow("
# The popup dashboard sections are executed by tests/test_usage_dashboard.py,
# which extracts the production providerDetailsSection and usageDashboardSection
# blocks and renders them with hostile data: heading, KPI/row models, and the
# per-entry detail delegate each go red there when broken.
# The section's secondary-value label, chart element and chart visibility are
# executed by tst_visual_layout.qml (providerDetailValuesStayWithinPopup and
# providerDetailChartFollowsChartData). The `required modelData` scoping rule
# for Components delegates stays owned by tests/test_ui_qml_conventions.py.
# The interactive chart is executed by tests/tst_interactive_chart.qml against
# the real component: keyboard selection, hover inspection, the line-kind
# plot path and tab reachability each go red there when broken.
require_in_file "$USAGE_DETAILS_JS" "QML JavaScript has no grapheme segmenter"
reject_in_file "$USAGE_DETAILS_JS" "sections.length < maximumSectionsPerSnapshot"
reject_in_file "$USAGE_DETAILS_JS" "rows.length < maximumRowsPerSection"
reject_in_file "$USAGE_DETAILS_JS" "points.length < maximumPointsPerChart"
# The provider cost section is executed by tests/test_cost_sections.py, which
# renders the real component: the chart, the drill-down/history blocks and
# their breakdown/model/history models each go red there when broken.
require_in_surface applet "--all-accounts"
require_in_surface applet "--account"
# The menu-bar mode and reset-time initializers read Plasmoid.configuration,
# which is absent under test (fixtures declare these properties themselves),
# so no executed test can pin the wiring: hardcoding either value keeps every
# panel test green. Mode routing through these values is covered by the
# MenuBarText executed tests.
require_in_surface applet "property string menuBarDisplayMode"
require_in_surface applet "property bool resetTimesShowAbsolute"
require_in_surface applet 'import "PanelDisplay.js" as PanelDisplay'
# The run-out token reports a duration only when the CLI predicts exhaustion,
# so it must stay tied to the pace forecast instead of the percent used.
require_in_surface applet "id: panelClockTimer"
require_in_surface applet "root.panelClockMs = Date.now()"
require_in_surface applet "Plasmoid.configuration.menuBarDisplayMode"
reject_in_surface applet "onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)"
# The usage row's reset-text source and quota-marker repeater are executed by
# tst_visual_layout.qml (providerUsageRowResetTextComesFromRowData and
# providerUsageRowDrawsQuotaWarningMarkers).
# Quota thresholds are user-configurable and shared by the notifications and the
# markers drawn on the usage bars, so they must come from one bounded source.
require_in_file "$CONFIG_XML" 'name="quotaWarningPercent"'
require_in_file "$CONFIG_XML" 'name="quotaCriticalPercent"'
# Kept: the import, the readonly Plasmoid-backed bounds and their reset
# handlers below have no executed pin — every fixture declares its own
# threshold values, so renaming the import or zeroing either bound keeps
# all naming modules green.
require_in_surface applet 'import "QuotaThresholds.js" as QuotaThresholds'
require_in_surface applet "readonly property int quotaWarningPercent: QuotaThresholds.warningPercent("
require_in_surface applet "readonly property int quotaCriticalPercent: QuotaThresholds.criticalPercent("
require_in_surface applet "onQuotaWarningPercentChanged: resetNotificationMemo()"
require_in_surface applet "onQuotaCriticalPercentChanged: resetNotificationMemo()"
# The standalone status badge id stays load-bearing for
# tests/test_ui_panel.py, which extracts the compactStatusBadge block
# and asserts its fallback wiring: renaming the id fails that extraction, so
# the literal token is not pinned here as well.
# The provider incident badge is executed by tst_popup_controls.qml
# (incidentBadgeGrowsWithItsText); its id has no references outside the
# component, so the token itself is unobservable in the harness.
# Kept: the Plasmoid-backed state defaults and declarative change handlers
# kept below have no executed pin — fixtures declare their own values, so
# flipping any default or no-opping any handler keeps all naming modules
# green. The logic behind them is pinned by the selection/pipeline tests.
require_in_surface applet "property bool enableNotifications"
require_in_surface applet "property bool autoSelectProvider"
require_in_surface applet "property string selectedProviderID"
require_in_surface applet "readonly property int selectedProviderIndex: providerIndexForID(selectedProviderID)"
reject_in_surface applet "    property int selectedProviderIndex:"
require_in_surface applet "property string overviewProviderIDsRaw"
require_in_surface applet "onOverviewProviderIDsRawChanged: updateSelectedProvider()"
require_in_surface applet "Math.max(0, Number(Plasmoid.configuration.refreshInterval))"
require_in_surface applet "property var notificationMemo"
# Kept: main.qml's Plasmoid-backed copy has no executed pin — every fixture
# declares its own flag, so flipping the default keeps all naming modules
# green. The cost controller's own copy is proven covered by executed tests
# (deleting it turns test_startupRunsWhileHiddenAndReentryKeepsFreshData
# red: no command can start when the guard property is missing).
require_in_surface applet "property bool costUsageEnabled"
require_in_surface applet "property int costHistoryDays"
# Cost and tokens both come from one cost payload: switching the plotted metric
# must never add a CLI call, and the bars must rescale with the choice.
require_in_surface applet "property string costHistoryMetric"
# Every cost chart follows one metric: the section render tests in
# tests/test_cost_sections.py flip the flag and pin the project ordering,
# the provider combo/chart title/day selection and the spend history
# wording, so a stuck metric goes red there instead of here.
# The chart's "Latest" summary annotates the same series the bars plot, so it
# must follow the metric instead of always printing the cost amount.
reject_in_surface applet 'i18n("%1: %2", label, amountString(last.cost'
# The peak and average annotations must name the same day the bars highlight.
reject_in_surface applet 'i18n("Average/day: %1", amountString('
# The spend metric controls are executed by tests/test_cost_sections.py, which
# renders the real SpendView: the metric options, the combo-to-settings
# setter and the still-building notice each go red there when broken.
# The 365-day clamp is unobservable in executed tests: the property
# initializer reads Plasmoid.configuration, which is absent under test, so
# fixtures declare their own day count and 365 -> 30 keeps every naming test
# green. This stays as the only pin on the bound.
require_in_surface applet "Math.max(1, Math.min(365, Number(Plasmoid.configuration.costHistoryDays)"

# The 500-char truncation cap is unobservable in executed tests: the
# readonly Plasmoid-backed error is always empty without a host, so 500 -> 5
# keeps every settings test green. This stays as the only pin on the bound,
# and the rejection keeps the runtime-owned error out of the saved config.
require_in_file "$GENERAL_QML" "widgetUpdateLastError.slice(0, 500)"
reject_in_file "$GENERAL_QML" "cfg_widgetUpdateLastError"

# The dialog page registration is executed by tests/tst_config_model.qml,
# which instantiates the real ConfigModel and pins all six sources:
# removing any page fails it. The About rejections below stay: absence has
# no runtime equivalent beyond the source set the model test already pins.
reject_in_file "$CONFIG_QML" "configAbout.qml"
reject_in_file "$CONFIG_QML" "name: i18n(\"About\")"

# Every check script must be reachable from `make check`; an unwired script is
# a check that silently never runs. Derived from the directory, so a new script
# is covered without editing this list.
for check_script in "${ROOT_DIR}"/scripts/test_*.sh; do
  require_in_file "$MAKEFILE" "scripts/$(basename "$check_script")"
done
require_in_file "$MAKEFILE" "translations:"
require_in_file "$MAKEFILE" "QMLLINT_FLAGS ?= --unqualified disable"
require_in_file "$MAKEFILE" "update:"
reject_in_file "$MAKEFILE" "contents/ui/configAbout.qml"




require_in_file "$CONFIG_XML" "autoSelectProvider"
require_in_file "$CONFIG_XML" "notifyLimitResets"
require_in_file "$CONFIG_XML" "notifyPredictivePaceWarnings"
require_in_file "$CONFIG_XML" "panelElementOrder"
require_in_file "$CONFIG_XML" 'name="panelQuotaLane"'
require_in_file "$CONFIG_XML" 'name="panelVisibilityRules"'
# The lane and rules normalizers are unobservable in executed tests: both
# readonly initializers read Plasmoid.configuration, which is absent under
# test, so fixtures declare their own lane and rules and bogus replacements
# keep every naming test green. These stay as the only pins on the wiring;
# routing through these values is covered by the menu-bar and compact
# provider selection tests.
require_in_surface applet "PanelDisplay.safeLane(Plasmoid.configuration.panelQuotaLane)"
require_in_surface applet "PanelRules.normalizedRules(Plasmoid.configuration.panelVisibilityRules)"
reject_in_surface applet "onPanelQuotaLaneChanged: Qt.callLater(refreshNow)"
reject_in_surface applet "onPanelVisibilityRulesChanged: Qt.callLater(refreshNow)"
# Session cards must never carry filesystem paths: transcript locations and
# working directories would leak local paths into the view and persisted
# state. Absence has no runtime equivalent, so these rejections stay.
reject_in_file "$SESSIONS_COMPONENT_QML" "transcriptPath"
reject_in_file "$SESSIONS_COMPONENT_QML" "cwd"
# The spend chart and heatmap are executed by tests/test_cost_sections.py,
# which renders the real SpendView: removing either element goes red there.
require_in_file "$CONFIG_XML" "updateChecksEnabled"
require_in_file "$CONFIG_XML" "updateNotificationsEnabled"
require_in_file "$CONFIG_XML" "autoUpdateEnabled"
require_in_file "$CONFIG_XML" "autoUpdateIntervalHours"
require_in_file "$CONFIG_XML" "autoUpdateLastCheck"
require_in_file "$CONFIG_XML" "widgetUpdateLastStatus"
require_in_file "$CONFIG_XML" "widgetUpdateLastError"
require_in_file "$CONFIG_XML" "costUsageEnabled"
require_in_file "$CONFIG_XML" "costHistoryDays"
require_in_file "$CONFIG_XML" "overviewProviderIDs"

require_in_file "$README_MD" "codexbar-plasma.plasmoid"
reject_in_file "$README_MD" "about links"


require_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -i codexbar-plasma.plasmoid"
require_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -u codexbar-plasma.plasmoid"
require_in_file "$README_MD" "make install"
reject_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -u ."
require_in_file "$README_MD" "systemctl --user restart plasma-plasmashell.service"
require_in_file "$README_MD" "codexbar usage --provider codex --all-accounts --format json --json-only"

reject_in_surface applet "console.log(\"CodexBar"
reject_in_file "$PROVIDERS_QML" "console.log(\"CodexBar"

echo "KDE plasmoid feature parity checks passed."
