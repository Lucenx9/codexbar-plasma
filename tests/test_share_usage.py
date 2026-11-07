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
import "CONTRAST_URL" as ThemeContrast
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
    function test_darkProviderIndicatorsRemainVisibleInBothThemes() {
        var window = createWindow();
        var card = findChild(window, "shareUsageCard");
        for (var background of ["#232629", "#eff0f1"]) {
            card.color = background;
            for (var brand of ["#1b1b1b", "#202020"]) {
                var segment = findChild(card, "shareProviderSegment");
                var indicator = findChild(card, "shareProviderIndicator");
                verify(segment !== null && indicator !== null);
                segment.modelData = {color: brand, share: 1};
                indicator.parent.modelData = {color: brand, title: "Provider", detail: "100 tokens · USD 2", badge: "100%"};
                verify(ThemeContrast.contrastRatio(segment.color, card.color) >= 3);
                verify(ThemeContrast.contrastRatio(indicator.color,
                    ThemeContrast.interpolateColor(card.color, card.ink, 0.04)) >= 3);
                if (background === "#eff0f1") {
                    compare(segment.color, brand);
                    compare(indicator.color, brand);
                }
            }
        }
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
    function test_footerLayout_data() {
        return [
            {tag: "wide", width: 936, large: false, rtl: false},
            {tag: "narrow", width: 420, large: false, rtl: false},
            {tag: "narrow-rtl", width: 420, large: false, rtl: true},
            {tag: "large-long-labels", width: 420, large: true, rtl: false}
        ];
    }
    function test_footerLayout(data) {
        var window = createWindow();
        window.width = data.width;
        window.footer.LayoutMirroring.enabled = data.rtl;
        window.footer.LayoutMirroring.childrenInherit = true;
        var image = findChild(window, "shareCopyImageButton");
        var statistics = findChild(window, "shareCopyStatisticsButton");
        var save = findChild(window, "shareSaveImageButton");
        var close = findChild(window, "shareCloseButton");
        var group = findChild(window, "shareExportActions");
        var feedback = findChild(window, "shareFeedbackLabel");
        verify(image !== null && statistics !== null && save !== null && close !== null);
        verify(group !== null && feedback !== null);
        verify(image.highlighted);
        verify(!statistics.highlighted && !save.highlighted && !close.highlighted);
        if (data.large) {
            image.text = "Copy the complete usage image to the clipboard";
            statistics.text = "Copy the complete aggregate usage statistics";
            save.text = "Save the complete usage image as a PNG file";
            for (var button of [image, statistics, save, close])
                button.font = Qt.font({family: button.font.family, pixelSize: 28});
        }
        wait(50);
        for (var button of [image, statistics, save, close]) {
            var point = button.mapToItem(window.footer, 0, 0);
            verify(point.x >= -0.5 && point.y >= -0.5);
            verify(point.x + button.width <= window.footer.width + 0.5,
                "Export action exceeds footer width");
            verify(point.y + button.height <= window.footer.height + 0.5);
        }
        if (!data.large) {
            var groupEdge = group.mapToItem(window.footer, data.rtl ? 0 : group.width, 0).x;
            var closeEdge = close.mapToItem(window.footer, data.rtl ? close.width : 0, 0).x;
            verify(data.rtl ? closeEdge < groupEdge : groupEdge < closeEdge,
                "Close must be separate from the export actions");
        }
        var footerHeight = window.footer.height;
        var viewportHeight = window.contentItem.height;
        verify(feedback.Accessible.ignored);
        window.feedback = "Copied";
        wait(50);
        fuzzyCompare(window.footer.height, footerHeight, 0.5);
        fuzzyCompare(window.contentItem.height, viewportHeight, 0.5);
        verify(!feedback.Accessible.ignored);
        window.feedback = "";
        wait(50);
        fuzzyCompare(window.footer.height, footerHeight, 0.5);
        window.feedback = Array(15).join("A long export failure with recovery guidance. ");
        wait(50);
        verify(feedback.lineCount > 1, "Long feedback must wrap");
        window.close();
    }
    function test_footerKeyboardOrderAndCopy() {
        var window = createWindow();
        window.requestActivate();
        var image = findChild(window, "shareCopyImageButton");
        var statistics = findChild(window, "shareCopyStatisticsButton");
        var save = findChild(window, "shareSaveImageButton");
        var close = findChild(window, "shareCloseButton");
        image.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Tab);
        tryCompare(statistics, "activeFocus", true);
        keyClick(Qt.Key_Space);
        compare(clipboard.content, window.statisticsText);
        compare(window.feedback, "Copied");
        keyClick(Qt.Key_Tab);
        tryCompare(save, "activeFocus", true);
        keyClick(Qt.Key_Tab);
        tryCompare(close, "activeFocus", true);
        keyClick(Qt.Key_Space);
        tryCompare(window, "visible", false);
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
            source = source.replace("CONTRAST_URL", (ROOT / "contents/ui/ThemeContrast.js").as_uri())
            source = source.replace("OUTPUT_URL", image.as_uri())
            source = source.replace("MISSING_URL", (work / "missing/image.png").as_uri())
            (work / "tst_export.qml").write_text(source)
            env = dict(os.environ,
                       QT_QPA_PLATFORM="offscreen",
                       QT_QUICK_BACKEND="software",
                       # Without a platform theme, Kirigami selects the embedded
                       # breeze-internal icon theme; Neon KF 6.31/Plasma 6.8 warns it is missing.
                       QT_QPA_PLATFORMTHEME="kde",
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
