#!/usr/bin/env bash
set -euo pipefail

export QT_QPA_PLATFORM=offscreen

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLTESTRUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

echo "Running QML tests for capitalize function..."

"$QMLTESTRUNNER" -input "$ROOT_DIR/contents/ui/tst_capitalize.qml"

echo "QML capitalize tests passed."
