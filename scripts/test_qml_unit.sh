#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v qmltestrunner >/dev/null 2>&1; then
    QMLTESTRUNNER="qmltestrunner"
elif command -v qmltestrunner6 >/dev/null 2>&1; then
    QMLTESTRUNNER="qmltestrunner6"
elif [ -x /usr/lib/qt6/bin/qmltestrunner ]; then
    QMLTESTRUNNER="/usr/lib/qt6/bin/qmltestrunner"
else
    echo "Warning: qmltestrunner not found, skipping QML unit tests."
    exit 0
fi

cd "$ROOT_DIR"
fail=0
for test_file in tests/tst_*.qml; do
    if [ -f "$test_file" ]; then
        echo "Running $test_file..."
        if ! QT_QPA_PLATFORM=offscreen "$QMLTESTRUNNER" -input "$test_file"; then
            fail=1
        fi
    fi
done

if [ "$fail" -eq 1 ]; then
    echo "QML unit tests failed."
    exit 1
fi

echo "QML unit tests passed."
