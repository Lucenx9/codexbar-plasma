#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLTESTRUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
if ! command -v "$QMLTESTRUNNER" >/dev/null 2>&1; then
  echo "qmltestrunner not found; skipping QML tests"
  exit 0
fi
cd "$ROOT_DIR"
QT_QPA_PLATFORM=minimal "$QMLTESTRUNNER" -input contents/ui/tests
