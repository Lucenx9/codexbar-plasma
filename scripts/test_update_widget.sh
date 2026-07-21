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

python3 - "$UPDATER" "$MAIN_QML" <<'PY'
import re
import sys
from pathlib import Path

updater_text = Path(sys.argv[1]).read_text()
main_qml_text = Path(sys.argv[2]).read_text()


def integer_constant(text, name):
    match = re.search(rf"(?:readonly property int )?{name}(?::|=)\s*(\d+)", text)
    if not match:
        raise AssertionError(f"missing integer timeout constant: {name}")
    return int(match.group(1))


metadata_seconds = integer_constant(updater_text, "CURL_METADATA_MAX_TIME_SECONDS")
asset_seconds = integer_constant(updater_text, "CURL_ASSET_MAX_TIME_SECONDS")
install_seconds = integer_constant(updater_text, "KPACKAGE_INSTALL_MAX_TIME_SECONDS")
kill_after_seconds = integer_constant(updater_text, "KPACKAGE_INSTALL_KILL_AFTER_SECONDS")
outer_seconds = integer_constant(main_qml_text, "widgetAutoUpdateTimeoutMs") / 1000
minimum_seconds = metadata_seconds + asset_seconds + install_seconds + kill_after_seconds
required_outer_seconds = minimum_seconds + 30
if outer_seconds < required_outer_seconds:
    raise AssertionError(
        "widgetAutoUpdateTimeoutMs must cover all sequential updater phases plus 30s headroom: "
        f"{outer_seconds:g}s < {required_outer_seconds}s"
    )
install_timeout = re.search(
    r'(?m)^[ \t]*timeout[ \t]+--kill-after="\$\{KPACKAGE_INSTALL_KILL_AFTER_SECONDS\}s"[ \t]*\\\n'
    r'[ \t]*"\$\{KPACKAGE_INSTALL_MAX_TIME_SECONDS\}s"[ \t]*\\\n'
    r'[ \t]*kpackagetool6\b',
    updater_text,
)
if not install_timeout:
    raise AssertionError("kpackagetool6 installation must have a hard timeout with a force-kill grace")
install_timer = re.search(
    r'updateCommandTimeoutTimer\.interval\s*=\s*autoUpdateEnabled\s*\?\s*widgetAutoUpdateTimeoutMs\s*:\s*widgetUpdateCheckTimeoutMs',
    main_qml_text,
)
if not install_timer:
    raise AssertionError("automatic installs must select widgetAutoUpdateTimeoutMs")
PY
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
require_in_file "$MAIN_QML" "Widget update operation timed out."
reject_in_file "$MAIN_QML" "Widget update check timed out."
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
