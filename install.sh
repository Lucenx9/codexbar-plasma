#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kpackagetool6 -t Plasma/Applet -u "$ROOT_DIR" || kpackagetool6 -t Plasma/Applet -i "$ROOT_DIR"
systemctl --user restart plasma-plasmashell.service
