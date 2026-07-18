#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="${ROOT_DIR}/scripts/update-widget.sh"
MAKEFILE="${ROOT_DIR}/Makefile"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected updater fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected updater fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

if [[ ! -x "$UPDATER" ]]; then
  echo "scripts/update-widget.sh must exist and be executable" >&2
  exit 1
fi

require_in_file "$UPDATER" "REPO_OWNER=\"Lucenx9\""
require_in_file "$UPDATER" "REPO_NAME=\"codexbar-plasma\""
require_in_file "$UPDATER" "ASSET_NAME=\"codexbar-plasma.plasmoid\""
require_in_file "$UPDATER" "CURL_CONNECT_TIMEOUT_SECONDS=10"
require_in_file "$UPDATER" "CURL_METADATA_MAX_TIME_SECONDS=30"
require_in_file "$UPDATER" "CURL_ASSET_MAX_TIME_SECONDS=300"
require_in_file "$UPDATER" "--connect-timeout \"\$CURL_CONNECT_TIMEOUT_SECONDS\""
require_in_file "$UPDATER" "--max-time \"\$CURL_METADATA_MAX_TIME_SECONDS\""
require_in_file "$UPDATER" "--max-time \"\$CURL_ASSET_MAX_TIME_SECONDS\""
require_in_file "$UPDATER" "https://api.github.com/repos/\${REPO_OWNER}/\${REPO_NAME}/releases/latest"
require_in_file "$UPDATER" "browser_download_url"
require_in_file "$UPDATER" "kpackagetool6 -t Plasma/Applet -u"
require_in_file "$UPDATER" "--check"
require_in_file "$UPDATER" "--install"
require_in_file "$UPDATER" "mktemp -d"
require_in_file "$UPDATER" "trap cleanup EXIT"
require_in_file "$UPDATER" "jq -r"
require_in_file "$UPDATER" "curl --fail --location --show-error --silent"
require_in_file "$UPDATER" "version_gt()"
require_in_file "$UPDATER" "emit_status"
require_in_file "$UPDATER" "restart Plasma to apply the update"
reject_in_file "$UPDATER" "schedule_plasmashell_restart"
reject_in_file "$UPDATER" "systemd-run --user"
reject_in_file "$UPDATER" "systemctl --user restart plasma-plasmashell.service"
reject_in_file "$UPDATER" "| sh"
reject_in_file "$UPDATER" "| bash"
reject_in_file "$UPDATER" "eval "
require_in_file "$MAKEFILE" "scripts/update-widget.sh --install"
require_in_file "$MAKEFILE" "docs/codexbar-plasma-overview.png"
require_in_file "$MAKEFILE" "docs/codexbar-plasma-codex.png"
require_in_file "$MAKEFILE" "python3 -m zipfile -c dist/codexbar-plasma.plasmoid"
require_in_file "$MAKEFILE" "missing required command: cmake, zip, or python3"
reject_in_file "$MAKEFILE" "cmake -E tar cf dist/codexbar-plasma.plasmoid --format=zip metadata.json contents docs scripts/update-widget.sh"
require_in_file "$MAIN_QML" "function missingUpdateScriptJson()"
require_in_file "$MAIN_QML" "Widget updater script is missing from the installed package."
require_in_file "$MAIN_QML" "if [ -x \" + shellQuote(scriptPath) + \" ]; then \""
require_in_file "$MAIN_QML" "printf '%s\\\\n' \" + shellQuote(missingUpdateScriptJson())"
require_in_file "$MAIN_QML" "return \"sh -c \" + shellQuote(updateCommand)"
require_in_file "$MAIN_QML" "setWidgetUpdateState(i18n(\"Checking for widget updates...\"), \"\", false)"
require_in_file "$MAIN_QML" "notifyInstalledUpdate(version)"
require_in_file "$MAIN_QML" "Restart Plasma to apply the new widget version."
require_in_file "$MAIN_QML" "function handleUpdateCommandTimeout()"
require_in_file "$MAIN_QML" "id: updateCommandTimeoutTimer"
require_in_file "$MAIN_QML" "updateCommandTimeoutTimer.restart()"
require_in_file "$MAIN_QML" "updateCommandTimeoutTimer.stop()"
require_in_file "$MAIN_QML" "Widget update check timed out."
# The notified version must persist so the same update is not re-announced on
# every plasmashell restart.
require_in_file "$MAIN_QML" "Plasmoid.configuration.lastNotifiedUpdateVersion = memoKey"
require_in_file "${ROOT_DIR}/contents/config/main.xml" "name=\"lastNotifiedUpdateVersion\""
reject_in_file "$MAIN_QML" "return \"sh \" + shellQuote(updateScriptPath())"
reject_in_file "$MAIN_QML" "return shellQuote(updateScriptPath()) + (installMode ? \" --install\" : \" --check\")"

update_script_sample="${ROOT_DIR}/scripts/update-widget.sh"
missing_json_sample='{"status":"error","message":"Widget updater script is missing from the installed package."}'
compound_sample="if [ -x '${update_script_sample}' ]; then '${update_script_sample}' --check; else printf '%s\n' '${missing_json_sample}'; fi"
nonce_wrapped_sample="CODEXBAR_PLASMA_RUN=1 sh -c $(printf '%q' "${compound_sample}")"
if ! /bin/sh -n -c "${nonce_wrapped_sample}"; then
  echo "nonce-wrapped updater command must be valid /bin/sh syntax" >&2
  exit 1
fi

echo "Widget updater checks passed."
