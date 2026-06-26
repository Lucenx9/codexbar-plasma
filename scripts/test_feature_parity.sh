#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
README_MD="${ROOT_DIR}/README.md"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected fragment in ${file#$ROOT_DIR/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected fragment in ${file#$ROOT_DIR/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$PROVIDERS_QML" "property string selectedProviderID"
require_in_file "$PROVIDERS_QML" "function setApiKey(providerID)"
require_in_file "$PROVIDERS_QML" "kdialog --password"
require_in_file "$PROVIDERS_QML" "config set-api-key --provider"
require_in_file "$PROVIDERS_QML" "--stdin --format json --json-only"
require_in_file "$PROVIDERS_QML" "function providerDocsUrl(providerID)"
require_in_file "$PROVIDERS_QML" "function providerLoginUrl(providerID)"
require_in_file "$PROVIDERS_QML" "function supportsApiKeySetup(providerID)"
require_in_file "$PROVIDERS_QML" "action: \"set-api-key\""

require_in_file "$MAIN_QML" "daily: normalizeCostDaily(item.daily, currency)"
require_in_file "$MAIN_QML" "totals: normalizeCostTotals(item.totals, item.last30DaysCostUSD, item.last30DaysTokens, currency)"
require_in_file "$MAIN_QML" "models: normalizeCostModels(item.daily, currency)"
require_in_file "$MAIN_QML" "function normalizeCostDaily(items, currency)"
require_in_file "$MAIN_QML" "function normalizeCostTotals(totals, fallbackCost, fallbackTokens, currency)"
require_in_file "$MAIN_QML" "function normalizeCostModels(items, currency)"
require_in_file "$MAIN_QML" "function costBreakdownRows(tokenCost)"
require_in_file "$MAIN_QML" "function costModelRows(tokenCost)"
require_in_file "$MAIN_QML" "function costDailyRows(tokenCost)"
require_in_file "$MAIN_QML" "function costPerMillionLine(tokenCost)"
require_in_file "$MAIN_QML" "Canvas {"
require_in_file "$MAIN_QML" "id: costSparkline"
require_in_file "$MAIN_QML" "id: costDrillDownSection"
require_in_file "$MAIN_QML" "model: root.costBreakdownRows(tokenCostSection.tokenCost)"
require_in_file "$MAIN_QML" "model: root.costModelRows(tokenCostSection.tokenCost)"
require_in_file "$MAIN_QML" "model: root.costDailyRows(tokenCostSection.tokenCost)"
require_in_file "$MAIN_QML" "function providerDocsUrl(providerID)"
require_in_file "$MAIN_QML" "function providerLoginUrl(providerID)"
require_in_file "$MAIN_QML" "action: \"docs\""
require_in_file "$MAIN_QML" "function buildProviderAccountsCommand(providerID)"
require_in_file "$MAIN_QML" "--all-accounts"
require_in_file "$MAIN_QML" "function selectedAccountForProvider(providerID)"
require_in_file "$MAIN_QML" "--account"
require_in_file "$MAIN_QML" "function selectAccount(providerID, accountLabel)"
require_in_file "$MAIN_QML" "function accountOptionsForProvider(providerID)"
require_in_file "$MAIN_QML" "action: \"accounts\""
require_in_file "$MAIN_QML" "property string menuBarDisplayMode"
require_in_file "$MAIN_QML" "property bool resetTimesShowAbsolute"
require_in_file "$MAIN_QML" "function menuBarDisplayText(item)"
require_in_file "$MAIN_QML" "function primaryPaceText(item)"
require_in_file "$MAIN_QML" "function primaryResetText(item)"
require_in_file "$MAIN_QML" "function resetText(window, absolute)"
require_in_file "$MAIN_QML" "Plasmoid.configuration.menuBarDisplayMode"
require_in_file "$MAIN_QML" "onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)"
require_in_file "$MAIN_QML" "property bool showQuotaWarningMarkers"
require_in_file "$MAIN_QML" "function statusSeverity(status)"
require_in_file "$MAIN_QML" "function statusBadgeColor(severity)"
require_in_file "$MAIN_QML" "function primaryIncidentProvider()"
require_in_file "$MAIN_QML" "id: compactStatusBadge"
require_in_file "$MAIN_QML" "id: providerStatusBadge"
require_in_file "$MAIN_QML" "function quotaWarningMarkers(row)"
require_in_file "$MAIN_QML" "quotaWarningMarkerRepeater"
require_in_file "$MAIN_QML" "showQuotaWarningMarkers"
require_in_file "$MAIN_QML" "property bool enableNotifications"
require_in_file "$MAIN_QML" "property var notificationMemo"
require_in_file "$MAIN_QML" "function processNotifications()"
require_in_file "$MAIN_QML" "function primeNotifications()"
require_in_file "$MAIN_QML" "function quotaNotificationLevel(row)"
require_in_file "$MAIN_QML" "function notificationUrgency(severity)"
require_in_file "$MAIN_QML" "function sendPlasmaNotification(title, body, urgency)"
require_in_file "$MAIN_QML" "notify-send --app-name=CodexBar"
require_in_file "$MAIN_QML" "notificationSource.connectSource(command)"

require_in_file "$GENERAL_QML" "Fetch provider status"
require_in_file "$GENERAL_QML" "Show quota warning markers"
require_in_file "$GENERAL_QML" "Enable Plasma notifications"
require_in_file "$GENERAL_QML" "Notify status incidents"
require_in_file "$GENERAL_QML" "Notify quota warnings"

require_in_file "$README_MD" "Display mode"
require_in_file "$README_MD" "incident badge"
require_in_file "$README_MD" "quota warning markers"
require_in_file "$README_MD" "Plasma notifications"
require_in_file "$README_MD" "cost drill-down"

require_in_file "$README_MD" "## Upgrade"
require_in_file "$README_MD" "yay -S codexbar-cli"
require_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -u ."
require_in_file "$README_MD" "systemctl --user restart plasma-plasmashell.service"
require_in_file "$README_MD" "codexbar usage --provider codex --all-accounts --format json --json-only"

reject_in_file "$MAIN_QML" "console.log(\"CodexBar"
reject_in_file "$PROVIDERS_QML" "console.log(\"CodexBar"

echo "KDE plasmoid feature parity checks passed."
