#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_PATH="${ROOT_DIR}/dist/codexbar-plasma.plasmoid"

command -v kpackagetool6 >/dev/null 2>&1 || {
  echo "missing required command: kpackagetool6" >&2
  exit 127
}
command -v systemctl >/dev/null 2>&1 || {
  echo "missing required command: systemctl" >&2
  exit 127
}

make -C "$ROOT_DIR" package
kpackagetool6 -t Plasma/Applet -u "$PACKAGE_PATH" || kpackagetool6 -t Plasma/Applet -i "$PACKAGE_PATH"
systemctl --user restart plasma-plasmashell.service
