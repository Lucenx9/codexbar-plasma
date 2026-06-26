#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="${ROOT_DIR}/scripts/update-widget.sh"
MAKEFILE="${ROOT_DIR}/Makefile"

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
require_in_file "$UPDATER" "https://api.github.com/repos/\${REPO_OWNER}/\${REPO_NAME}/releases/latest"
require_in_file "$UPDATER" "browser_download_url"
require_in_file "$UPDATER" "kpackagetool6 -t Plasma/Applet -u"
require_in_file "$UPDATER" "systemctl --user restart plasma-plasmashell.service"
require_in_file "$UPDATER" "--check"
require_in_file "$UPDATER" "--install"
require_in_file "$UPDATER" "mktemp -d"
require_in_file "$UPDATER" "trap cleanup EXIT"
require_in_file "$UPDATER" "jq -r"
require_in_file "$UPDATER" "curl --fail --location --show-error --silent"
require_in_file "$UPDATER" "version_gt()"
require_in_file "$UPDATER" "emit_status"
reject_in_file "$UPDATER" "| sh"
reject_in_file "$UPDATER" "| bash"
reject_in_file "$UPDATER" "eval "
require_in_file "$MAKEFILE" "scripts/update-widget.sh --install"

echo "Widget updater checks passed."
