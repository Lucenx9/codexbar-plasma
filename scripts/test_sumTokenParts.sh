#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export QT_QPA_PLATFORM=offscreen
/usr/lib/qt6/bin/qmltestrunner -input "$ROOT_DIR/tests/tst_sumTokenParts.qml"
