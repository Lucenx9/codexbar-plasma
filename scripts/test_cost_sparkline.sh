#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLTESTRUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

echo "Running Cost Sparkline Summary QML tests..."
QT_QPA_PLATFORM=offscreen "$QMLTESTRUNNER" -input "$ROOT_DIR/tests/test_costSparklineSummary.qml"
echo "Cost Sparkline Summary tests passed."
