#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
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
require_in_file "$MAIN_QML" "function normalizeCostDaily(items, currency)"
require_in_file "$MAIN_QML" "Canvas {"
require_in_file "$MAIN_QML" "id: costSparkline"
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

require_in_file "$README_MD" "Display mode"

require_in_file "$README_MD" "## Upgrade"
require_in_file "$README_MD" "yay -S codexbar-cli"
require_in_file "$README_MD" "kpackagetool6 -t Plasma/Applet -u ."
require_in_file "$README_MD" "systemctl --user restart plasma-plasmashell.service"
require_in_file "$README_MD" "codexbar usage --provider codex --all-accounts --format json --json-only"

reject_in_file "$MAIN_QML" "console.log(\"CodexBar"
reject_in_file "$PROVIDERS_QML" "console.log(\"CodexBar"

echo "KDE plasmoid feature parity checks passed."
