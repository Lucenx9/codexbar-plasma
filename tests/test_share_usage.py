"""Exercise native clipboard/image export using the actual share window offscreen."""

import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QML = '''import QtQuick
import QtTest
import org.kde.kquickcontrolsaddons as KQuickControlsAddons
import "COMPONENT_URL" as Components
import "SHARE_URL" as ShareUsage
TestCase {
    id: testCase
    name: "ShareUsageWindow"
    when: windowShown
    width: 640
    height: 480
    visible: true
    KQuickControlsAddons.Clipboard { id: clipboard }
    QtObject {
        id: mockApplet
        property bool privacyMode: false
        function providerTitle(value) { return value; }
        function providerDisplayTitle(value) {
            return privacyMode && value === "private_provider" ? "Provider" : providerTitle(value);
        }
        function providerColor(value) { return "#6699ff"; }
        function usageCountText(value) { return value + " tokens"; }
        function amountString(value, currency) { return currency + " " + value; }
    }
    Component {
        id: windowComponent
        Components.ShareUsageWindow {
            applet: mockApplet
            function i18n(text, a) { return a === undefined ? text : text.replace("%1", a); }
            function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }
        }
    }
    function createWindow(provider) {
        var snapshot = ShareUsage.snapshot([{provider: provider || "codex", historyDays: 30,
            totals: {tokens: 100, cost: 2, currency: "USD"},
            models: [{label: "Synthetic model", tokens: 100, cost: 2, currency: "USD"}]}],
            30, "2026-09-22T12:00:00Z", false);
        var window = createTemporaryObject(windowComponent, testCase, {snapshot: snapshot});
        verify(window !== null);
        window.show();
        wait(100);
        return window;
    }
    function init() {
        clipboard.content = "untouched";
        mockApplet.privacyMode = false;
    }
    function test_copyImageAndSavePng() {
        var window = createWindow();
        verify(window.statisticsText.indexOf("github.com/Lucenx9/codexbar-plasma") !== -1);
        window.captureImage(false);
        tryCompare(window, "capturing", false);
        verify(clipboard.formats.some(function(format) { return format.indexOf("image") !== -1; }));
        compare(window.feedback, "Image copied");
        verify(window.saveImage("OUTPUT_URL"));
        tryCompare(window, "capturing", false);
        compare(window.feedback, "Image saved");
        verify(!window.saveImage("https://example.com/image.png"));
        compare(window.feedback, "Choose a local PNG file.");
        verify(window.saveImage("MISSING_URL"));
        tryCompare(window, "capturing", false);
        compare(window.feedback, "Could not save the image. Choose another location.");
        window.close();
    }
    function test_saveWhileCapturingFailsWithFeedback() {
        var window = createWindow();
        window.captureImage(false);
        verify(window.capturing);
        verify(!window.saveImage("OUTPUT_URL"));
        compare(window.feedback, "Could not create the image. Try again.");
        tryCompare(window, "capturing", false);
        window.close();
    }
    function test_copyStatisticsAction() {
        var window = createWindow();
        var button = findChild(window, "shareCopyStatisticsButton");
        verify(button !== null);
        mouseClick(button);
        compare(clipboard.content, window.statisticsText);
        compare(window.feedback, "Copied");
        window.close();
    }
    function test_closeRetiresCapture() {
        var window = createWindow();
        window.captureImage(false);
        window.close();
        wait(100);
        compare(window.capturing, false);
        compare(clipboard.content, "untouched");
    }
    function test_privacyChangeClosesSnapshot() {
        var window = createWindow();
        mockApplet.privacyMode = true;
        tryCompare(window, "visible", false);
    }
    function test_privateUnknownProviderStaysMaskedInBothExports() {
        mockApplet.privacyMode = true;
        var window = createWindow("private_provider");
        verify(window.statisticsText.indexOf("private_provider") === -1);
        verify(window.statisticsText.indexOf("Provider") !== -1);
        var card = findChild(window, "shareUsageCard");
        verify(card !== null);
        verify(JSON.stringify(card.presentation).indexOf("private_provider") === -1);
        window.close();
    }
}
'''


class ShareUsageWindowTests(unittest.TestCase):
    def test_native_export(self):
        runner = os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner")
        self.assertTrue(Path(runner).is_file(), f"Missing qmltestrunner: {runner}")
        with tempfile.TemporaryDirectory(prefix="codexbar-share-test-") as directory:
            work = Path(directory)
            image = work / "shared image.png"
            source = QML.replace("COMPONENT_URL", (ROOT / "contents/ui/components").as_uri())
            source = source.replace("SHARE_URL", (ROOT / "contents/ui/ShareUsage.js").as_uri())
            source = source.replace("OUTPUT_URL", image.as_uri())
            source = source.replace("MISSING_URL", (work / "missing/image.png").as_uri())
            (work / "tst_export.qml").write_text(source)
            env = dict(os.environ,
                       QT_QPA_PLATFORM="offscreen",
                       QT_QUICK_BACKEND="software",
                       QT_QUICK_CONTROLS_STYLE=os.environ.get("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop"))
            result = subprocess.run([runner, "-input", str(work)], env=env,
                                    capture_output=True, text=True, timeout=30, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("QWARN", result.stdout)
            self.assertNotIn("ReferenceError", result.stderr)
            data = image.read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            width, height = struct.unpack(">II", data[16:24])
            self.assertGreater(width, 800)
            self.assertGreater(height, 400)

    def test_owner_and_effect_boundaries(self):
        source = (ROOT / "contents/ui/components/ShareUsageWindow.qml").read_text()
        self.assertIn("clipboard.content = result.image", source)
        self.assertIn("fileMode: FileDialog.SaveFile", source)
        self.assertNotIn("DontConfirmOverwrite", source)
        self.assertIn("generation !== window.captureGeneration", source)
        self.assertNotIn("DataSource", source)
        self.assertNotIn("Qt.openUrlExternally", source)
        self.assertIn("transientParent: null", source)
        root = (ROOT / "contents/ui/main.qml").read_text()
        self.assertIn("ShareUsage.snapshot(costs, costHistoryDays", root)
        self.assertIn("var costs = spendProviderCosts()", root)


if __name__ == "__main__":
    unittest.main()
