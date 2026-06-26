#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Verify if qmltestrunner is available
if ! command -v /usr/lib/qt6/bin/qmltestrunner >/dev/null 2>&1; then
    echo "Skipping qmltestrunner because it is not installed"
    exit 0
fi

export QT_QPA_PLATFORM=offscreen
/usr/lib/qt6/bin/qmltestrunner -input "$ROOT_DIR/tests/tst_scaledTokenCount.qml"
