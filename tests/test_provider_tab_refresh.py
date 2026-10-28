"""Exercise the production provider tabs, overview rows, and action rows while snapshots change."""

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
import "COMPONENTS_URL" as Components

TestCase {
    id: fullRoot
    name: "ProviderTabRefresh"
    when: windowShown
    width: 620
    height: 360
    visible: true
    property alias applet: applet

    function i18n(text) { return text; }
    function closeAiInsights() {}

    QtObject {
        id: applet
        property var presentedProviders: []
        property var presentedOverviewProviders: []
        property var presentedProviderData: null
        property var selectedProviderData: null
        property var statusComponents: ({loading: false, failed: false, rows: []})
        property var statusComponentGroups: []
        property string selectedProviderID: "codex"
        property bool selectionInitialized: true
        property bool showPopupTabLabels: true
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 6
        property real secondaryTextOpacity: 0.72
        property real valueTextOpacity: 0.88
        property real compactMeterTrackHeight: 6
        property string lastPerformedAction: ""
        readonly property int selectedProviderIndex: presentedProviders.findIndex(function(item) {
            return item.provider === applet.selectedProviderID;
        })

        function switcherPercent(item) { return item.used === undefined ? -1 : item.used; }
        function providerReadableColor() { return Qt.rgba(0.1, 0.5, 0.7, 1); }
        function providerIconSource() { return "view-statistics"; }
        function providerIconIsMask() { return true; }
        function switcherDescription(item) { return item.title; }
        function withAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha); }
        function overviewMeterRows(item) { return item && item.rows ? item.rows : []; }
        function lastGoodUsageText() { return ""; }
        function quotaDescription(row) { return (row.label || "") + " " + String(row.usedPercent || 0) + "%"; }
        function resetTextForRow() { return ""; }
        function usagePercentText(row) { return String(row.usedPercent || 0) + "%"; }
        function displayPercent(row) { return row.usedPercent || 0; }
        function quotaMeterColor(row, accent) { return accent; }
        function providerIndex(item) {
            return presentedProviders.findIndex(function(candidate) {
                return candidate.provider === (item ? item.provider : "");
            });
        }
        function statusComponentsExpanded() { return false; }
        function toggleStatusComponentGroup() {}
        function actionRows(item) { return item && item.actions ? item.actions : []; }
        function performAction(action) { lastPerformedAction = typeof action === "string" ? action : (action.action || ""); }
    }

    ColumnLayout {
        width: parent.width

        Components.PopupTabStrip {
            id: providerTabsBar
            surfaceRadius: 8
            Layout.fillWidth: true
            Repeater { PRODUCTION_REPEATER }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Repeater { PRODUCTION_OVERVIEW_REPEATER }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Repeater { PRODUCTION_ACTION_REPEATER }
        }
    }

    function provider(id, title, used) {
        return {
            provider: id,
            title: title,
            used: used,
            error: "",
            rows: [{label: "Session", hasPercent: true, usedPercent: used, leftPercent: 100 - used}]
        };
    }

    function actionsFor(refreshEnabled, refreshTitle) {
        return [
            {title: "Usage Dashboard", icon: "view-statistics", action: "dashboard", enabled: true},
            {title: refreshTitle || "Refresh", icon: "view-refresh", action: "refresh", enabled: refreshEnabled, separatorBefore: true}
        ];
    }

    function init() {
        failOnWarning(/^(?!Failed to find a Kirigami platform plugin for style "Fusion"$).*/);
        applet.presentedProviders = [provider("codex", "Codex", 10), provider("claude", "Claude", 20)];
        applet.presentedOverviewProviders = applet.presentedProviders;
        var selected = {provider: "codex", title: "Codex", actions: actionsFor(true, "Refresh")};
        applet.presentedProviderData = selected;
        applet.selectedProviderData = selected;
        applet.selectedProviderID = "codex";
        applet.lastPerformedAction = "";
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

    function test_changedOverviewSnapshotPreservesKeyboardFocusAndUpdatesRow() {
        var row = overviewProviderRepeater.itemAt(1);
        var focus = row.nextItemInFocusChain(true);
        focus.forceActiveFocus(Qt.TabFocusReason);
        verify(focus.activeFocus && focus.visualFocus);

        applet.presentedOverviewProviders = [provider("codex", "Codex", 15), provider("claude", "Claude updated", 85)];
        compare(overviewProviderRepeater.itemAt(1), row);
        verify(focus.activeFocus && focus.visualFocus);
        compare(row.providerData.title, "Claude updated");
        keyClick(Qt.Key_Space);
        compare(applet.selectedProviderID, "claude");
    }

    function test_changedActionRowsPreserveKeyboardFocusDuringAccountRefresh() {
        var actionRow = providerActionRows.itemAt(0);
        var delegate = actionRow.nextItemInFocusChain(true);
        delegate.forceActiveFocus(Qt.TabFocusReason);
        verify(delegate.activeFocus);

        var updated = {provider: "codex", title: "Codex", actions: actionsFor(false, "Refreshing\u2026")};
        applet.presentedProviderData = updated;
        applet.selectedProviderData = updated;
        compare(providerActionRows.itemAt(0), actionRow);
        verify(delegate.activeFocus);
        compare(providerActionRows.itemAt(1).modelData.enabled, false);
        compare(providerActionRows.itemAt(1).modelData.title, "Refreshing\u2026");
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
        qml = qml.replace("PRODUCTION_OVERVIEW_REPEATER", applet.id_block("overviewProviderRepeater"))
        qml = qml.replace("PRODUCTION_ACTION_REPEATER", applet.id_block("providerActionRows"))
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
