#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLTESTRUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

if [[ ! -x "$QMLTESTRUNNER" ]]; then
  echo "qmltestrunner not found: $QMLTESTRUNNER" >&2
  exit 1
fi

QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  "$QMLTESTRUNNER" -input "$ROOT_DIR/tests"
