#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
# Parity rules use require_in_surface so extracting popup UI or a controller out
# of main.qml does not need an edit here. The per-component variables below stay
# file-scoped: those are delegate contracts about one specific component.
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
DISPLAY_QML="${ROOT_DIR}/contents/ui/configDisplay.qml"
ADVANCED_QML="${ROOT_DIR}/contents/ui/configAdvanced.qml"
DEBUG_QML="${ROOT_DIR}/contents/ui/configDebug.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
PROVIDER_IDENTITY_JS="${ROOT_DIR}/contents/ui/ProviderIdentity.js"
COMPACT_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/CompactRepresentation.qml"
PROVIDER_HEADER_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/ProviderHeader.qml"
USAGE_ROW_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/ProviderUsageRow.qml"
PROVIDER_DETAIL_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/ProviderDetailSection.qml"
INTERACTIVE_CHART_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/InteractiveChart.qml"
SESSIONS_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/SessionsView.qml"
SPEND_COMPONENT_QML="${ROOT_DIR}/contents/ui/components/SpendView.qml"
USAGE_DETAILS_JS="${ROOT_DIR}/contents/ui/UsageDetails.js"
README_MD="${ROOT_DIR}/README.md"
TODO_MD="${ROOT_DIR}/TODO.md"
AGENTS_MD="${ROOT_DIR}/AGENTS.md"
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

require_in_file "$PROVIDERS_QML" "property string selectedProviderID"
require_in_file "$PROVIDERS_QML" "function setApiKey(providerID)"
require_in_file "$PROVIDERS_QML" "function loadProviderSettings(providerID)"
require_in_file "$PROVIDERS_QML" "function runProviderListCommand(includeDescriptors)"
require_in_file "$PROVIDERS_QML" "function shouldRetryProviderListWithoutDescriptors(stdoutText, stderrText)"
require_in_file "$PROVIDERS_QML" "function descriptorListUnsupportedMessage(stdoutText, stderrText)"
require_in_file "$PROVIDERS_QML" "var message = commandError(payload)"
reject_in_file "$PROVIDERS_QML" "stdoutText + \"\\n\" + stderrText"
require_in_file "$PROVIDERS_QML" "function normalizeProviderDescriptor(raw)"
require_in_file "$PROVIDERS_QML" "function descriptorFieldRows(item)"
require_in_file "$PROVIDERS_QML" "function descriptorHasAction(item, actionID)"
require_in_file "$PROVIDERS_QML" "function writeDescriptorField(providerID, field, value)"
require_in_file "$PROVIDERS_QML" "function promptDescriptorSecret(providerID, field)"
require_in_file "$PROVIDERS_QML" "function runDescriptorCommand(commandTokens, replacements)"
require_in_file "$PROVIDERS_QML" "function fieldOptionIndex(field)"
require_in_file "$PROVIDERS_QML" "token === \"codexbar\" && commandPath.length > 0"
require_in_file "$PROVIDERS_QML" "function handleDiagnoseResult(descriptor, stdoutText, stderrText)"
require_in_file "$PROVIDERS_QML" "function handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode)"
require_in_file "$PROVIDERS_QML" "function handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode)"
require_in_file "$PROVIDERS_QML" "function providerSettingsRows(item)"
require_in_file "$PROVIDERS_QML" "function providerCliCommandText(item)"
require_in_file "$PROVIDERS_QML" "property var providerDiagnostics"
require_in_file "$PROVIDERS_QML" "property var providerFieldPending"
require_in_file "$PROVIDERS_QML" "--descriptors"
require_in_file "$PROVIDERS_QML" "runProviderListCommand(false)"
require_in_file "$PROVIDERS_QML" "descriptor.includeDescriptors === true"
require_in_file "$PROVIDERS_QML" "descriptor: normalizeProviderDescriptor(item.descriptor)"
require_in_file "$PROVIDERS_QML" "field.writeCommand"
require_in_file "$PROVIDERS_QML" "action.command"
require_in_file "$PROVIDERS_QML" "!descriptorHasAction(item, \"openDashboard\")"
require_in_file "$PROVIDERS_QML" "kind: \"descriptorField\""
require_in_file "$PROVIDERS_QML" "kind: \"descriptorAction\""
require_in_file "$PROVIDERS_QML" "page.reload(true)"
require_in_file "$PROVIDERS_QML" "Provider descriptor fields"
require_in_file "$PROVIDERS_QML" "modelData.kind === \"secret\""
require_in_file "$PROVIDERS_QML" "modelData.kind === \"enum\""
require_in_file "$PROVIDERS_QML" "modelData.kind === \"boolean\""
reject_in_file "$PROVIDERS_QML" "return field.options.length > 0 ? 0 : -1"
require_in_file "$PROVIDERS_QML" "kdialog --password"
require_in_file "$PROVIDERS_QML" "config set-api-key --provider"
require_in_file "$PROVIDERS_QML" "diagnose --provider"
require_in_file "$PROVIDERS_QML" "--format json --redact"
require_in_file "$PROVIDERS_QML" "--stdin --format json --json-only"
require_in_file "$PROVIDERS_QML" "function providerDocsUrl(providerID)"
require_in_file "$PROVIDERS_QML" "function providerLoginUrl(providerID)"
require_in_file "$PROVIDERS_QML" "function providerCliArgument(value)"
require_in_file "$PROVIDERS_QML" "function supportsApiKeySetup(providerID)"
require_in_file "$PROVIDERS_QML" "action: \"set-api-key\""
require_in_file "$PROVIDERS_QML" "Provider settings"
require_in_file "$PROVIDERS_QML" "Load redacted settings"
require_in_file "$PROVIDERS_QML" "CLI commands"
require_in_file "$PROVIDER_IDENTITY_JS" "\"openai\": \"openai.md\""
require_in_file "$PROVIDER_IDENTITY_JS" "\"openrouter\": \"openrouter.md\""
# Provider identity is one table set in ProviderIdentity.js, so the parity facts
# below are asserted once against that module rather than once per surface. The
# display names are the exception: `i18n` needs literal strings in a file gettext
# scans, so those stay in each QML surface and are checked in both.
python3 - "$PROVIDER_IDENTITY_JS" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
failures = []

def table(name):
    match = re.search(r"var " + name + r" = \{(.*?)\n\}", text, re.S)
    if not match:
        failures.append(f"missing {name} table in ProviderIdentity.js")
        return {}
    body = match.group(1)
    entries = dict(re.findall(r'"([^"]+)":\s*"([^"]*)"', body))
    entries.update(
        (key, value.strip())
        for key, value in re.findall(r'"([^"]+)":\s*(\[[^\]]*\])', body)
    )
    return entries

def require(name, entries, expected):
    for key, value in expected.items():
        if entries.get(key) != value:
            failures.append(f"{name}: expected {key} -> {value!r}, found {entries.get(key)!r}")

def reject(name, entries, unwanted):
    for key, value in unwanted.items():
        if entries.get(key) == value:
            failures.append(f"{name}: {key} still points at the stale value {value!r}")

require("providerDocsPaths", table("providerDocsPaths"), {
    "aiand": "aiand.md",
    "azureopenai": "providers.md#azure-openai",
    "clawrouter": "clawrouter.md",
    "copilot": "copilot.md",
    "crossmodel": "crossmodel.md",
    "deepinfra": "deepinfra.md",
    "fireworks": "fireworks.md",
    "ibmbob": "ibm-bob.md",
    "mistral": "providers.md#mistral",
    "neuralwatt": "neuralwatt.md",
    "notion": "notion.md",
    "openai": "openai.md",
    "openrouter": "openrouter.md",
    "perplexity": "providers.md#perplexity",
    "poe": "poe.md",
    "qoder": "qoder.md",
    "qwencloud": "qwen-cloud.md",
    "sakana": "sakana.md",
    "stepfun": "stepfun.md",
    "sub2api": "sub2api.md",
    "synthetic": "providers.md#synthetic",
    "t3chat": "providers.md#t3-chat",
    "venice": "venice.md",
    "wayfinder": "wayfinder.md",
    "xai": "xai.md",
    "zed": "zed.md",
    "zenmux": "zenmux.md",
    "zoommate": "zoommate.md",
})

# Official CLI spellings and historical aliases the widget must keep accepting.
require("providerAliases", table("providerAliases"), {
    "11labs": "elevenlabs",
    "abacus-ai": "abacus",
    "ai&": "aiand",
    "ai-and": "aiand",
    "alibaba-token": "alibabatokenplan",
    "aoai": "azureopenai",
    "azure-openai": "azureopenai",
    "bailian": "alibaba",
    "bailian-token-plan": "alibabatokenplan",
    "bob": "ibmbob",
    "bobshell": "ibmbob",
    "chutes.ai": "chutes",
    "claw-router": "clawrouter",
    "cm": "crossmodel",
    "command-code": "commandcode",
    "deep-infra": "deepinfra",
    "deep-seek": "deepseek",
    "fw": "fireworks",
    "groq-api": "groq",
    "ibm-bob": "ibmbob",
    "notion-ai": "notion",
    "openai-api": "openai",
    "qwen-cloud": "qwencloud",
    "step-fun": "stepfun",
    "sub-2-api": "sub2api",
    "synthetic.new": "synthetic",
    "t3-chat": "t3chat",
    "warp-terminal": "warp",
    "wayfinder-router": "wayfinder",
    "xiaomi-mimo": "mimo",
    "z.ai": "zai",
    "zen-mux": "zenmux",
})

require("providerBrandChannels", table("providerBrandChannels"), {
    "aiand": "[226 / 255, 92 / 255, 43 / 255]",
    "clawrouter": "[89 / 255, 110 / 255, 246 / 255]",
    "crossmodel": "[124 / 255, 58 / 255, 237 / 255]",
    "commandcode": "[160 / 255, 77 / 255, 253 / 255]",
    "fireworks": "[242 / 255, 91 / 255, 28 / 255]",
    "ibmbob": "[14 / 255, 97 / 255, 250 / 255]",
    "poe": "[93 / 255, 92 / 255, 222 / 255]",
    "qoder": "[16 / 255, 185 / 255, 129 / 255]",
})

dashboards = table("providerDashboardUrls")
require("providerDashboardUrls", dashboards, {
    "aiand": "https://console.aiand.com",
    "amp": "https://ampcode.com/settings/usage",
    "clawrouter": "https://clawrouter.openclaw.ai/dashboard/access",
    "claude": "https://console.anthropic.com/settings/billing",
    "clinepass": "https://app.cline.bot/dashboard/subscription?personal=true",
    "crof": "https://crof.ai/dashboard",
    "crossmodel": "https://crossmodel.ai/console/usage",
    "deepinfra": "https://deepinfra.com/dash",
    "fireworks": "https://app.fireworks.ai",
    "groq": "https://console.groq.com/dashboard/usage",
    "ibmbob": "https://bob.ibm.com",
    "wayfinder": "http://127.0.0.1:8088/router",
    "notion": "https://app.notion.com/",
    "qoder": "https://qoder.com/account/usage",
    "sakana": "https://console.sakana.ai/billing",
    "xai": "https://console.x.ai",
})
# Dashboards that moved upstream; landing on the old page looks like working UI.
reject("providerDashboardUrls", dashboards, {
    "amp": "https://ampcode.com/settings#billing",
    "claude": "https://claude.ai/settings/usage",
    "groq": "https://console.groq.com/dashboard/metrics",
})

require("providerLoginUrls", table("providerLoginUrls"), {
    "opencode": "https://opencode.ai/auth",
    "opencodego": "https://opencode.ai/auth",
})
reject("providerLoginUrls", table("providerLoginUrls"), {"opencode": "https://opencode.ai"})

require("providerStatusUrls", table("providerStatusUrls"), {
    "augment": "https://status.augmentcode.com",
    "ibmbob": "https://status.bob.ibm.com",
    "mistral": "https://status.mistral.ai",
})

if failures:
    for failure in failures:
        print(failure, file=sys.stderr)
    sys.exit(1)
PY

for qml_file in "$MAIN_QML" "$PROVIDERS_QML"; do
  require_in_file "$qml_file" '"clawrouter": i18n("ClawRouter")'
  require_in_file "$qml_file" '"crossmodel": i18n("CrossModel")'
  require_in_file "$qml_file" '"elevenlabs": i18n("ElevenLabs")'
  require_in_file "$qml_file" '"fireworks": i18n("Fireworks")'
  require_in_file "$qml_file" '"ibmbob": i18n("IBM Bob")'
  require_in_file "$qml_file" '"kimi": i18n("Kimi Code")'
  require_in_file "$qml_file" '"minimax": i18n("MiniMax")'
  require_in_file "$qml_file" '"moonshot": i18n("Moonshot / Kimi Open Platform")'
  require_in_file "$qml_file" '"qoder": i18n("Qoder")'
  require_in_file "$qml_file" '"stepfun": i18n("StepFun")'
  require_in_file "$qml_file" '"wayfinder": i18n("Wayfinder")'
  require_in_file "$qml_file" '"zai": i18n("z.ai / GLM")'
done

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
if 'case "fireworks":' in body:
    print("Fireworks setup must stay hidden until the CLI can also set accountSlug", file=sys.stderr)
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

require_in_surface applet "daily: Normalizer.normalizeCostDaily(item.daily, currency, historyDays)"
require_in_surface applet "totals: Normalizer.normalizeCostTotals(item.totals, item.last30DaysCostUSD, item.last30DaysTokens, currency)"
require_in_surface applet "models: Normalizer.normalizeCostModels(item.daily, currency, historyDays)"
require_in_surface applet "function normalizeCostDaily(items, currency, days)"
require_in_surface applet "result.length < historyDays"
require_in_surface applet "inspectedItems < maximumCostHistoryScanItems"
require_in_surface applet "result.unshift({"
require_in_surface applet "function normalizeCostTotals(totals, fallbackCost, fallbackTokens, currency)"
require_in_surface applet "function normalizeCostModels(items, currency, days)"
require_in_surface applet "function costBreakdownRows(tokenCost)"
require_in_surface applet "function costModelRows(tokenCost)"
require_in_surface applet "function costHistoryRows(tokenCost)"
require_in_surface applet "function costPeakLine(points)"
require_in_surface applet "function costAverageDailyLine(points)"
require_in_surface applet "function costPerMillionLine(tokenCost)"
# Cost presentation moved behind CostPresentation.js. Assert the delegation so
# the maths cannot quietly grow a second copy back inside main.qml.
require_in_surface applet "function spendSnapshots(tokenCosts, historyDays, titleFor)"
require_in_surface applet "CostPresentation.spendSnapshots(tokenCosts, costHistoryDays"
require_in_surface applet "CostPresentation.breakdownRows("
require_in_surface applet "CostPresentation.modelRows("
require_in_surface applet "CostPresentation.historyRows("
require_in_surface applet "CostPresentation.averageDailyValue("
require_in_surface applet "CostPresentation.perMillionAmount("
require_in_surface applet "CostPresentation.spendTotals("
require_in_surface applet "CostPresentation.historyStillBuilding("
require_in_surface applet "CostPresentation.numberFormat("
reject_in_surface applet "function appendTokenBreakdownRow("
require_in_surface applet "function compactCostTokenSummary(cost, tokens, currency)"
require_in_surface applet "function usageDashboard(providerID, usage, item)"
require_in_surface applet 'import "UsageDetails.js" as UsageDetails'
require_in_surface applet "var providerDetails = UsageDetails.normalizeSections(usage.details)"
require_in_surface applet "providerDetails: providerDetails"
require_in_surface applet "var providerUsageDashboard = providerDetails.length > 0 ? null : usageDashboard(providerID, usage, item)"
require_in_surface applet "var hasSupplementalUsage = providerDetails.length > 0 || providerUsageDashboard !== null"
require_in_surface applet "providerPlaceholder(providerID, rows, usage, item, error, hasSupplementalUsage)"
require_in_surface applet "usageDashboard: providerUsageDashboard"
require_in_surface applet "hasSupplementalUsage === true"
require_in_surface applet "function usageDashboardRows(source, state, depth)"
require_in_surface applet "function appendDashboardMetric(rows, label, value, kind)"
require_in_surface applet "openaiDashboard"
require_in_surface applet "openAIAPIUsage"
require_in_surface applet "openRouterUsage"
require_in_surface applet "claudeAdminAPIUsage"
require_in_surface applet "poeUsage"
require_in_surface applet "deepseekUsage"
require_in_surface applet "minimaxUsage"
require_in_surface applet "zaiUsage"
require_in_surface applet "id: usageDashboardSection"
require_in_surface applet "text: i18n(\"Usage dashboard\")"
require_in_surface applet "model: usageDashboardSection.kpis"
require_in_surface applet "model: usageDashboardSection.rows"
require_in_surface applet "Components.ProviderDetailSection"
require_in_file "$PROVIDER_DETAIL_COMPONENT_QML" "required property var modelData"
require_in_file "$PROVIDER_DETAIL_COMPONENT_QML" "modelData.secondaryValue"
require_in_file "$PROVIDER_DETAIL_COMPONENT_QML" "InteractiveChart {"
require_in_file "$PROVIDER_DETAIL_COMPONENT_QML" "visible: detailSection.chartData !== null"
require_in_file "$INTERACTIVE_CHART_COMPONENT_QML" 'if (chart.kind === "line")'
require_in_file "$INTERACTIVE_CHART_COMPONENT_QML" "activeFocusOnTab: true"
require_in_file "$INTERACTIVE_CHART_COMPONENT_QML" "Keys.onPressed:"
require_in_file "$INTERACTIVE_CHART_COMPONENT_QML" "onPositionChanged:"
require_in_file "$USAGE_DETAILS_JS" "maximumSectionsPerSnapshot = 8"
require_in_file "$USAGE_DETAILS_JS" "maximumRowsPerSection = 24"
require_in_file "$USAGE_DETAILS_JS" "maximumPointsPerChart = 120"
require_in_file "$USAGE_DETAILS_JS" "maximumStringCodeUnitsForSafety = maximumStringLength * 32"
require_in_file "$USAGE_DETAILS_JS" "QML JavaScript has no grapheme segmenter"
require_in_file "$USAGE_DETAILS_JS" "Math.min(rawSections.length, maximumSectionsPerSnapshot)"
require_in_file "$USAGE_DETAILS_JS" "Math.min(rawRows.length, maximumRowsPerSection)"
require_in_file "$USAGE_DETAILS_JS" "Math.min(rawPoints.length, maximumPointsPerChart)"
reject_in_file "$USAGE_DETAILS_JS" "sections.length < maximumSectionsPerSnapshot"
reject_in_file "$USAGE_DETAILS_JS" "rows.length < maximumRowsPerSection"
reject_in_file "$USAGE_DETAILS_JS" "points.length < maximumPointsPerChart"
require_in_surface applet "Components.InteractiveChart"
require_in_surface applet "function costChartPoints(points)"
require_in_surface applet "id: costHistoryChartSection"
require_in_surface applet "id: costDrillDownSection"
require_in_surface applet "model: costDrillDownSection.breakdownRows"
require_in_surface applet "model: costDrillDownSection.modelRows"
require_in_surface applet "model: costHistoryChartSection.rows"
require_in_surface applet "function providerDocsUrl(providerID)"
require_in_surface applet "function providerLoginUrl(providerID)"
require_in_surface applet "action: \"docs\""
require_in_surface applet "function buildProviderAccountsCommand(providerID)"
require_in_surface applet "--all-accounts"
require_in_surface applet "function selectedAccountForProvider(providerID)"
require_in_surface applet "--account"
require_in_surface applet "function selectAccount(providerID, accountLabel)"
require_in_surface applet "function accountOptionsForProvider(providerID)"
require_in_surface applet "action: \"accounts\""
require_in_surface applet "property string menuBarDisplayMode"
require_in_surface applet "property bool resetTimesShowAbsolute"
require_in_surface applet "function menuBarDisplayText(item)"
require_in_surface applet "function safeMenuBarDisplayMode(value)"
require_in_surface applet "function primaryPaceText(item)"
require_in_surface applet "function primaryResetText(item)"
# The run-out token reports a duration only when the CLI predicts exhaustion,
# so it must stay tied to the pace forecast instead of the percent used.
require_in_surface applet "function primaryRunOutText(item)"
require_in_surface applet 'mode === "runOut"'
require_in_surface applet "if (!paceWarningActive(row)) {"
require_in_file "$DISPLAY_QML" 'value: "runOut"'
require_in_surface applet "function resetText(window, absolute)"
require_in_surface applet "function usageResetText(row)"
require_in_surface applet "function resetLabelLooksLikeTime(value)"
require_in_surface applet "var resetLine = resetLabel(usageResetText(row))"
require_in_surface applet "Plasmoid.configuration.menuBarDisplayMode"
reject_in_surface applet "onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)"
require_in_file "$USAGE_ROW_COMPONENT_QML" "usageRow.applet.usageResetText(usageRow.rowData)"
require_in_surface applet "property bool showQuotaWarningMarkers"
# Quota thresholds are user-configurable and shared by the notifications and the
# markers drawn on the usage bars, so they must come from one bounded source.
require_in_file "$CONFIG_XML" 'name="quotaWarningPercent"'
require_in_file "$CONFIG_XML" 'name="quotaCriticalPercent"'
require_in_surface applet 'import "QuotaThresholds.js" as QuotaThresholds'
require_in_surface applet "readonly property int quotaWarningPercent: QuotaThresholds.warningPercent("
require_in_surface applet "readonly property int quotaCriticalPercent: QuotaThresholds.criticalPercent("
require_in_surface applet "onQuotaWarningPercentChanged: resetNotificationMemo()"
require_in_surface applet "onQuotaCriticalPercentChanged: resetNotificationMemo()"
require_in_file "$GENERAL_QML" "cfg_quotaWarningPercent"
require_in_file "$GENERAL_QML" "cfg_quotaCriticalPercent"
require_in_file "$GENERAL_QML" "from: quotaWarningPercentSpin.value"
require_in_surface applet "function statusSeverity(status)"
require_in_surface applet "function statusBadgeColor(severity)"
require_in_surface applet "function primaryIncidentProvider()"
require_in_file "$COMPACT_COMPONENT_QML" "id: compactStatusBadge"
require_in_file "$PROVIDER_HEADER_COMPONENT_QML" "id: providerStatusBadge"
require_in_surface applet "function quotaWarningMarkers(row)"
require_in_file "$USAGE_ROW_COMPONENT_QML" "quotaWarningMarkerRepeater"
require_in_surface applet "showQuotaWarningMarkers"
require_in_surface applet "property bool enableNotifications"
require_in_surface applet "property bool updateChecksEnabled"
require_in_surface applet "function buildUpdateCommand(installMode)"
require_in_surface applet "function processUpdateCheck(payload)"
require_in_surface applet "function notifyAvailableUpdate(version, url)"
require_in_surface applet "function boundedWidgetUpdateText(value)"
require_in_surface applet "boundedWidgetUpdateText(errorText)"
require_in_surface applet "property bool autoSelectProvider"
require_in_surface applet "property string selectedProviderID"
require_in_surface applet "readonly property int selectedProviderIndex: providerIndexForID(selectedProviderID)"
reject_in_surface applet "    property int selectedProviderIndex:"
require_in_surface applet "function boundedConfigRevision(value)"
require_in_surface applet "property string overviewProviderIDsRaw"
require_in_surface applet "readonly property int maxOverviewProviders: 3"
require_in_surface applet "function configuredOverviewProviderIDs()"
require_in_surface applet "result.length >= maxOverviewProviders"
require_in_surface applet "onOverviewProviderIDsRawChanged: updateSelectedProvider()"
require_in_surface applet "Math.max(0, Number(Plasmoid.configuration.refreshInterval))"
require_in_surface applet "function updateSelectedProvider()"
require_in_surface applet "function autoSelectedProviderIndex()"
require_in_surface applet "function autoSelectScore(item)"
require_in_surface applet "function autoSelectUsedPercent(item)"
require_in_surface applet "function selectedCompactProvider()"
require_in_surface applet "id: usageRefreshTimer"
require_in_surface applet "interval: Math.max(1, root.refreshIntervalSec) * 1000"
require_in_surface applet "property var notificationMemo"
require_in_surface applet "function processNotifications()"
require_in_surface applet "function primeNotifications()"
require_in_surface applet "function quotaNotificationLevel(row)"
require_in_surface applet "function notificationUrgency(severity)"
require_in_surface applet "function sendPlasmaNotification(title, body, urgency)"
require_in_surface applet "function processLimitResetNotifications(item, nextMemo)"
require_in_surface applet "function processPaceNotifications(item, nextMemo)"
require_in_surface applet "notify-send --app-name=CodexBar"
require_in_surface applet 'notificationSource.connectSource(commandWithRunNonce(":; " + command))'
require_in_surface applet "property bool costUsageEnabled"
require_in_surface applet "property int costHistoryDays"
# Cost and tokens both come from one cost payload: switching the plotted metric
# must never add a CLI call, and the bars must rescale with the choice.
require_in_surface applet "property string costHistoryMetric"
require_in_surface applet "function safeCostHistoryMetric(value)"
require_in_surface applet "function setCostHistoryMetric(metric)"
require_in_surface applet "function metricValue(point, showsTokens)"
require_in_surface applet "Number(showsTokens ? point.tokens : point.cost)"
# Every cost chart follows one metric: the provider detail chart must not stay
# on cost while the rows beneath it switch to tokens.
require_in_surface applet "CostPresentation.chartPoints(costNumberFormat, points, costHistoryShowsTokens)"
require_in_surface applet 'applet.costHistoryShowsTokens'
# The chart's "Latest" summary annotates the same series the bars plot, so it
# must follow the metric instead of always printing the cost amount.
require_in_surface applet "function sparklineSummary(fmt, points, showsTokens)"
require_in_surface applet "metricText(fmt, metricValue(last, showsTokens), last.currency, showsTokens)"
reject_in_surface applet 'i18n("%1: %2", label, amountString(last.cost'
# Token counts carry no currency, so the money-only filter must not drop
# providers from the token aggregation.
require_in_surface applet "(!showsTokens && pointCurrency !== currency)"
# The peak and average annotations must name the same day the bars highlight.
require_in_surface applet "function peakPoint(points, showsTokens)"
require_in_surface applet "return peak && peak.magnitude > 0 ? peak : null"
require_in_surface applet "CostPresentation.peakPoint(points, costHistoryShowsTokens)"
reject_in_surface applet 'i18n("Average/day: %1", amountString('
require_in_surface applet "function spendHistoryStillBuilding()"
require_in_surface applet "historyCoverageEstablished: item.historyCoverageIsEstablished !== false"
require_in_file "$SPEND_COMPONENT_QML" "function metricOptions()"
require_in_file "$SPEND_COMPONENT_QML" "view.applet.setCostHistoryMetric(metricCombo.valueAt(index))"
require_in_file "$SPEND_COMPONENT_QML" "view.applet.spendHistoryStillBuilding()"
require_in_surface applet "if (!costUsageEnabled) {"
require_in_surface applet "--days"
require_in_surface applet "Math.max(1, Math.min(365, Number(Plasmoid.configuration.costHistoryDays)"

require_in_file "$GENERAL_QML" "Fetch provider status"
require_in_file "$GENERAL_QML" "Show local cost usage"
require_in_file "$GENERAL_QML" "Cost history days:"
require_in_file "$GENERAL_QML" "Enable Plasma notifications"
require_in_file "$GENERAL_QML" "Notify status incidents"
require_in_file "$GENERAL_QML" "Notify quota warnings"
require_in_file "$GENERAL_QML" "Notify predicted quota exhaustion"
require_in_file "$GENERAL_QML" "Notify limit resets"
require_in_file "$GENERAL_QML" "Check for widget updates"
require_in_file "$GENERAL_QML" "Notify when a widget update is available"
require_in_file "$GENERAL_QML" "Install widget updates automatically"
require_in_file "$GENERAL_QML" "Update check interval:"
require_in_file "$GENERAL_QML" "Last update status:"
require_in_file "$GENERAL_QML" "Plasmoid.configuration.widgetUpdateLastError"
require_in_file "$GENERAL_QML" "widgetUpdateLastError.slice(0, 500)"
reject_in_file "$GENERAL_QML" "cfg_widgetUpdateLastError"
require_in_file "$GENERAL_QML" "Refresh preset:"
require_in_file "$GENERAL_QML" "function refreshPresetIndex(value)"
require_in_file "$GENERAL_QML" "onCfg_refreshIntervalChanged"
require_in_file "$GENERAL_QML" "Manual"
require_in_file "$GENERAL_QML" "1 min"
require_in_file "$GENERAL_QML" "2 min"
require_in_file "$GENERAL_QML" "5 min"
require_in_file "$GENERAL_QML" "15 min"
require_in_file "$GENERAL_QML" "Custom"

require_in_file "$CONFIG_QML" "configDisplay.qml"
require_in_file "$CONFIG_QML" "configAdvanced.qml"
require_in_file "$CONFIG_QML" "configDebug.qml"
reject_in_file "$CONFIG_QML" "configAbout.qml"
reject_in_file "$CONFIG_QML" "name: i18n(\"About\")"

require_in_file "$MAKEFILE" "scripts/test_qml_hardening.sh"
require_in_file "$MAKEFILE" "scripts/test_update_widget.sh"
require_in_file "$MAKEFILE" "scripts/test_theme_boundaries.sh"
require_in_file "$MAKEFILE" "scripts/test_i18n_catalog.sh"
require_in_file "$MAKEFILE" "scripts/test_cli_descriptor_contract.sh"
require_in_file "$MAKEFILE" "translations:"
require_in_file "$MAKEFILE" "QMLLINT_FLAGS ?= --unqualified disable"
require_in_file "$MAKEFILE" "update:"
reject_in_file "$MAKEFILE" "contents/ui/configAbout.qml"

require_in_file "$DISPLAY_QML" "Display mode:"
require_in_file "$DISPLAY_QML" "Show usage as percent used"
require_in_file "$DISPLAY_QML" "Show quota warning markers"
require_in_file "$DISPLAY_QML" "Show reset times as clock time"
require_in_file "$DISPLAY_QML" "Show multi-provider details in panel"
require_in_file "$DISPLAY_QML" "Element order:"
require_in_file "$DISPLAY_QML" "PanelElements.movedOrder("
require_in_file "$DISPLAY_QML" "Auto-select highest-usage provider"
require_in_file "$DISPLAY_QML" "cfg_overviewProviderIDs"
require_in_file "$DISPLAY_QML" "Overview providers:"
require_in_file "$DISPLAY_QML" "Choose up to %1 providers"
require_in_file "$DISPLAY_QML" 'i18np("Choose up to %1 provider", "Choose up to %1 providers"'
require_in_file "$DISPLAY_QML" "function toggleOverviewProvider(providerID, checked)"

require_in_file "$ADVANCED_QML" "Advanced provider override"
require_in_file "$ADVANCED_QML" "Provider id (blank = all enabled)"
require_in_file "$ADVANCED_QML" "Provider default (blank)"

require_in_file "$DEBUG_QML" "function runDiagnostic()"
require_in_file "$DEBUG_QML" "diagnose --provider"
require_in_file "$DEBUG_QML" "--format json --redact"
require_in_file "$DEBUG_QML" "id: diagnosticOutputArea"

require_in_file "$CONFIG_XML" "autoSelectProvider"
require_in_file "$CONFIG_XML" "notifyLimitResets"
require_in_file "$CONFIG_XML" "notifyPredictivePaceWarnings"
require_in_file "$CONFIG_XML" "panelElementOrder"
require_in_surface applet '"sessions", "--json-v2"'
require_in_surface applet "function parseSessionsOutput(stdoutText, stderrText)"
require_in_surface applet "function normalizeSession(item)"
reject_in_file "$SESSIONS_COMPONENT_QML" "transcriptPath"
reject_in_file "$SESSIONS_COMPONENT_QML" "cwd"
require_in_file "$SPEND_COMPONENT_QML" "InteractiveChart"
require_in_file "$SPEND_COMPONENT_QML" "Activity heatmap"
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

require_in_file "$README_MD" "Display mode"
require_in_file "$README_MD" "incident badge"
require_in_file "$README_MD" "quota warning markers"
require_in_file "$README_MD" "Plasma notifications"
require_in_file "$README_MD" "Check for widget updates"
require_in_file "$README_MD" "heavily used limit resets back to empty"
require_in_file "$README_MD" "cost drill-down"
require_in_file "$README_MD" "configurable cost history window"
require_in_file "$README_MD" "Usage dashboard summaries"
require_in_file "$README_MD" "Refresh presets"
require_in_file "$README_MD" "Auto-select highest-usage provider"
require_in_file "$README_MD" "Overview providers"
require_in_file "$README_MD" "latest release"
require_in_file "$README_MD" "codexbar-plasma.plasmoid"
require_in_file "$README_MD" "## Troubleshooting"
require_in_file "$README_MD" "## Development"
reject_in_file "$README_MD" "about links"

reject_in_file "$TODO_MD" "Release automation:"
require_in_file "$TODO_MD" "Provider-specific editable settings"
require_in_file "$TODO_MD" "Existing detail and cost charts now support hover"
require_in_file "$TODO_MD" "Dashboard extras"
require_in_file "$TODO_MD" '`usage.details` rows and bounded bar/line charts'
require_in_file "$TODO_MD" "Translations"

require_in_file "$README_MD" "official CodexBar release tarballs"
require_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -i codexbar-plasma.plasmoid"
require_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -u codexbar-plasma.plasmoid"
require_in_file "$README_MD" "make install"
reject_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -u ."
require_in_file "$TODO_MD" "all 69 provider IDs"
require_in_file "$README_MD" '`usage.details` contract'
require_in_file "$README_MD" "all 69 providers"
require_in_file "$AGENTS_MD" "69 provider IDs released in CodexBar v0.49.1"
require_in_file "$README_MD" "systemctl --user restart plasma-plasmashell.service"
require_in_file "$README_MD" "codexbar usage --provider codex --all-accounts --format json --json-only"

reject_in_surface applet "console.log(\"CodexBar"
reject_in_file "$PROVIDERS_QML" "console.log(\"CodexBar"

echo "KDE plasmoid feature parity checks passed."
