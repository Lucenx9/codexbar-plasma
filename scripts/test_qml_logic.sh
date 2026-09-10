#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QMLTESTRUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

if [[ ! -x "$QMLTESTRUNNER" ]]; then
  echo "qmltestrunner not found: $QMLTESTRUNNER" >&2
  exit 1
fi

TEST_OUTPUT="$(mktemp)"
trap 'rm -f "$TEST_OUTPUT"' EXIT

run_qml_tests() {
  "$QMLTESTRUNNER" "$@" | tee "$TEST_OUTPUT"
  if [[ "${QML_TEST_REQUIRE_NO_SKIPS:-0}" == 1 ]] && grep -q '^SKIP[[:space:]]' "$TEST_OUTPUT"; then
    echo "QML tests were skipped; the CI environment must provide the KDE QML modules." >&2
    exit 1
  fi
}

TZ=America/Los_Angeles QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  run_qml_tests -input "$ROOT_DIR/tests"

# Plasma KCMs use the desktop controls style, whose native buttons do not have
# a QML content item and whose scrollbars reserve layout space. Exercise both
# paths as well as the default test style.
QT_PATHS_TOOL="${QT_PATHS_TOOL:-$(dirname "$QMLTESTRUNNER")/qtpaths}"
if [[ -x "$QT_PATHS_TOOL" ]] \
    && [[ -f "$("$QT_PATHS_TOOL" --query QT_INSTALL_QML)/org/kde/desktop/qmldir" ]]; then
  QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    run_qml_tests -input "$ROOT_DIR/tests/tst_plain_text_controls.qml" \
    PlainTextControls::test_buttonUsesActiveStyleLabelPath
  QT_QUICK_CONTROLS_STYLE=org.kde.desktop QT_QPA_PLATFORMTHEME=kde \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    run_qml_tests -input "$ROOT_DIR/tests/tst_panel_settings_geometry.qml"
  QT_QUICK_CONTROLS_STYLE=org.kde.desktop QT_QPA_PLATFORMTHEME=kde \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    run_qml_tests -input "$ROOT_DIR/tests/tst_popup_notifications_geometry.qml"
else
  if [[ "${QML_TEST_REQUIRE_NO_SKIPS:-0}" == 1 ]]; then
    echo "org.kde.desktop is required for the desktop-style checks." >&2
    exit 1
  fi
  echo "org.kde.desktop is unavailable; desktop-style checks skipped."
fi
