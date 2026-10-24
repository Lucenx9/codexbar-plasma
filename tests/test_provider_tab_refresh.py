"""Exercise the production provider tabs while usage snapshots and rosters change."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from ui_regression_support import Surface, root


QML = '''import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "COMPONENTS_URL"

TestCase {
    id: fullRoot
    name: "ProviderTabRefresh"
    when: windowShown
    width: 620
    height: 180
    visible: true
    property alias applet: applet

    function i18n(text) { return text; }
    function closeAiInsights() {}

    QtObject {
        id: applet
        property var presentedProviders: []
        property string selectedProviderID: "codex"
        property bool selectionInitialized: true
        property bool showPopupTabLabels: true
        property real roundedSurfaceRadius: 8
        readonly property int selectedProviderIndex: presentedProviders.findIndex(function(item) {
            return item.provider === applet.selectedProviderID;
        })

        function switcherPercent(item) { return item.used === undefined ? -1 : item.used; }
        function providerReadableColor() { return Qt.rgba(0.1, 0.5, 0.7, 1); }
        function providerIconSource() { return "view-statistics"; }
        function providerIconIsMask() { return true; }
        function switcherDescription(item) { return item.title; }
        function withAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha); }
    }

    Item {
        id: providerTabsFlickable
        height: 64
        function claimSelectedTab() {}
        function ensureVisible() {}
        function navigateFromTab() { return false; }
    }

    RowLayout {
        width: parent.width
        Repeater { PRODUCTION_REPEATER }
    }

    function provider(id, title, used) {
        return {provider: id, title: title, used: used, error: ""};
    }

    function init() {
        failOnWarning(/^(?!Failed to find a Kirigami platform plugin for style "Fusion"$).*/);
        applet.presentedProviders = [provider("codex", "Codex", 10), provider("claude", "Claude", 20)];
        applet.selectedProviderID = "codex";
    }

    function test_changedUsagePreservesKeyboardFocusAndUpdatesTheTab() {
        var tab = providerTabRepeater.itemAt(0);
        var focus = tab.nextItemInFocusChain(true);
        focus.forceActiveFocus(Qt.TabFocusReason);
        verify(focus.activeFocus && focus.visualFocus);

        applet.presentedProviders = [provider("codex", "Codex updated", 75), provider("claude", "Claude", 25)];
        compare(providerTabRepeater.itemAt(0), tab);
        verify(focus.activeFocus && focus.visualFocus);
        compare(tab.meter, 75);
        compare(focus.Accessible.name, "Codex updated");
        keyClick(Qt.Key_Space);
        compare(applet.selectedProviderID, "codex");
    }

    function test_rosterChangesUpdateTheProviderActivatedByEachTab() {
        applet.presentedProviders = [provider("claude", "Claude", 30), provider("codex", "Codex", 40)];
        compare(providerTabRepeater.count, 2);
        var focus = providerTabRepeater.itemAt(0).nextItemInFocusChain(true);
        focus.forceActiveFocus(Qt.TabFocusReason);
        compare(focus.Accessible.name, "Claude");
        keyClick(Qt.Key_Return);
        compare(applet.selectedProviderID, "claude");

        applet.presentedProviders = [provider("gemini", "Gemini", 50)];
        compare(providerTabRepeater.count, 1);
        focus = providerTabRepeater.itemAt(0).nextItemInFocusChain(true);
        focus.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.selectedProviderID, "gemini");

        applet.presentedProviders = [];
        compare(providerTabRepeater.count, 0);
        compare(providerTabRepeater.itemAt(0), null);
        wait(0);
    }
}
'''


class ProviderTabRefreshTests(unittest.TestCase):
    def test_production_tabs_keep_focus_during_usage_refresh(self):
        applet = Surface("applet", root)
        qml = QML.replace("COMPONENTS_URL", (root / "contents/ui/components").as_uri())
        qml = qml.replace("PRODUCTION_REPEATER", applet.id_block("providerTabRepeater"))
        with tempfile.TemporaryDirectory(prefix="codexbar-provider-tabs-") as temporary:
            fixture = Path(temporary) / "tst_provider_tab_refresh.qml"
            fixture.write_text(qml, encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
