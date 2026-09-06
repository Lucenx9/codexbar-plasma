"""Exercise the actual hover-only MouseArea declarations with Qt's runtime."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
Item {
    id: scene
    width: 200
    height: 200
    MouseArea {
        id: receiver
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        property int clickCount: 0
        onClicked: receiver.clickCount++
    }
    TestCase {
        name: "HoverOnlyMouseAreas"
        when: windowShown
        function test_hoverAndClicks_data() { return SOURCE_ROWS; }
        function test_hoverAndClicks(row) {
            receiver.clickCount = 0;
            var overlay = Qt.createQmlObject("import QtQuick\\nMouseArea {" + row.body + "}", scene);
            try {
                compare(overlay.acceptedButtons, 0);
                verify(overlay.hoverEnabled);
                mouseMove(scene, 20, 20);
                tryCompare(overlay, "containsMouse", true);
                var buttons = [Qt.LeftButton, Qt.RightButton, Qt.MiddleButton];
                for (var index = 0; index < buttons.length; index++) {
                    mouseClick(scene, 20, 20, buttons[index]);
                    compare(receiver.clickCount, index + 1);
                    verify(!overlay.pressed);
                }
            } finally {
                overlay.destroy();
                wait(0);
            }
        }
    }
}
'''


class HoverMouseAreaTests(unittest.TestCase):
    def test_hover_areas_load_and_pass_clicks_through(self):
        applet = Surface("applet", ROOT)
        rows = [{"tag": object_id, "body": applet.id_block(object_id)}
                for object_id in ("compactStatusMouse", "heatmapMouse")]
        with tempfile.TemporaryDirectory(prefix="codexbar-hover-test-") as temporary:
            fixture = Path(temporary) / "tst_hover.qml"
            fixture.write_text(QML.replace("SOURCE_ROWS", json.dumps(rows)), encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
