"""Exercise the production provider tabs, overview rows, and action rows while snapshots change."""

import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

from ui_regression_support import Surface, root


QML = '''import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQuick.Templates as Templates
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
        id: providerScroll
        PRODUCTION_SELECTION_KEY
    }

    QtObject {
        id: applet
        property var presentedProviders: []
        property var presentedOverviewProviders: []
        property var presentedProviderData: null
        property var selectedProviderData: null
        property var statusComponents: ({loading: false, failed: false, rows: []})
        property var statusComponentGroups: []
        property string selectedProviderID: "codex"
        property string selectedAccount: ""
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
        function selectedAccountForProvider() { return selectedAccount; }
        function accountKey(item) { return item ? item.account || "" : ""; }
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
            ColumnLayout { PRODUCTION_ACTION_SECTION }
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
        applet.selectedAccount = "";
        applet.showPopupTabLabels = true;
        providerTabsBar.implicitHeight = Kirigami.Units.gridUnit * 2.35;
        applet.lastPerformedAction = "";
        providerActionsToggle.expanded = true;
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

    function test_actionsDisclosureOpensWithKeyboardAndClosesOnSelectionChange() {
        providerActionsToggle.expanded = false;
        providerActionsToggle.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(providerActionsToggle.expanded, true);
        verify(providerActionRows.itemAt(0).visible);
        applet.selectedProviderData = {provider: "codex", actions: actionsFor(false, "Refreshing")};
        compare(providerActionsToggle.expanded, true);
        applet.selectedProviderData = {provider: "claude", actions: actionsFor(true, "Refresh")};
        applet.selectedProviderID = "claude";
        compare(providerActionsToggle.expanded, false);
        verify(!providerActionRows.itemAt(0).visible);
    }

    function test_quotaGaugeKeepsSmallValuesProportional() {
        for (var used of [-1, 0, 1, 12, 25, 43, 100]) {
            applet.presentedProviders = [provider("codex", "Codex", used), provider("claude", "Claude", used)];
            for (var index = 0; index < providerTabRepeater.count; index++) {
                var tab = providerTabRepeater.itemAt(index);
                var gauge = findChild(tab, "providerTabQuotaGauge");
                var fill = findChild(tab, "providerTabQuotaFill");
                verify(waitForPolish(gauge));
                compare(gauge.visible, used >= 0);
                if (used < 0)
                    continue;
                compare(fill.height, used === 0 ? 0 : Math.max(1, Math.round(gauge.height * used / 100)));
                verify(gauge.width >= 5 && gauge.width <= 7);
            }
        }
    }

    function test_iconOnlyTabsKeepIconsCenteredWithAndWithoutQuota() {
        applet.showPopupTabLabels = false;
        for (var used of [-1, 0, 43, 100]) {
            applet.presentedProviders = [provider("codex", "Codex", used)];
            var tab = providerTabRepeater.itemAt(0);
            var icon = findChild(tab, "providerTabIcon");
            tryVerify(function() { return tab.width > 0; });
            verify(waitForPolish(tab));
            fuzzyCompare(icon.mapToItem(tab, icon.width / 2, 0).x, tab.width / 2, 0.5);
        }
    }

    function test_iconOnlyGaugeStaysBesideIconInsideShortStrips() {
        applet.showPopupTabLabels = false;
        applet.presentedProviders = [provider("codex", "Codex", 43), provider("claude", "Claude", 0)];
        // A small font shrinks the strip; the icon keeps its theme size.
        for (var stripHeight of [Kirigami.Units.gridUnit * 2.35, Kirigami.Units.iconSizes.small + 6]) {
            providerTabsBar.implicitHeight = stripHeight;
            tryVerify(function() { return Math.abs(providerTabsBar.height - stripHeight) <= 1; });
            for (var index = 0; index < providerTabRepeater.count; index++) {
                var tab = providerTabRepeater.itemAt(index);
                var icon = findChild(tab, "providerTabIcon");
                var gauge = findChild(tab, "providerTabQuotaGauge");
                // Wait until the resized strip has laid the tab out again.
                tryVerify(function() {
                    return Math.abs(icon.mapToItem(tab, icon.width / 2, 0).x - tab.width / 2) <= 0.5
                        && tab.height === providerTabsBar.tabHeight;
                });
                var iconRight = icon.mapToItem(tab, icon.width, 0).x;
                var gaugeLeft = gauge.mapToItem(tab, 0, 0).x;
                verify(gaugeLeft >= iconRight + 1, "gauge overlaps icon at strip height " + stripHeight);
                verify(gaugeLeft + gauge.width <= tab.width, "gauge leaves tab at strip height " + stripHeight);
            }
        }
    }

    function test_accountChangesCloseActionsAndPreserveVisibleFocus_data() {
        return [
            {tag: "selected-account-focused-action", identity: false, actionFocus: true},
            {tag: "account-identity-focused-action", identity: true, actionFocus: true},
            {tag: "selected-account-focused-tab", identity: false, actionFocus: false},
            {tag: "account-identity-focused-tab", identity: true, actionFocus: false}
        ];
    }

    function test_accountChangesCloseActionsAndPreserveVisibleFocus(data) {
        var focused = data.actionFocus ? findChild(providerActionRows.itemAt(0), "providerActionButton")
            : providerTabRepeater.itemAt(0).nextItemInFocusChain(true);
        focused.forceActiveFocus(Qt.TabFocusReason);
        verify(focused.activeFocus);
        if (data.identity)
            applet.selectedProviderData = {provider: "codex", account: "second-account", actions: actionsFor(true, "Refresh")};
        else
            applet.selectedAccount = "second-account";
        compare(applet.selectedProviderID, "codex");
        compare(providerActionsToggle.expanded, false);
        if (data.actionFocus) {
            verify(providerActionsToggle.activeFocus && providerActionsToggle.visible);
            verify(providerActionsToggle.visualFocus);
        } else {
            verify(focused.activeFocus && focused.visible);
        }
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
        qml = qml.replace("PRODUCTION_ACTION_SECTION", applet.id_block("providerActionsSection"))
        selection_key = re.search(r"readonly property string selectionKey: JSON\.stringify\(\[[\s\S]*?\]\)",
                                  applet.id_block("providerScroll"))
        self.assertIsNotNone(selection_key)
        qml = qml.replace("PRODUCTION_SELECTION_KEY", selection_key.group())
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
