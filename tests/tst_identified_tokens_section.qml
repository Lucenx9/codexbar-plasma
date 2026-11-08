import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    id: testCase
    name: "IdentifiedTokensSection"
    when: windowShown
    width: 640
    height: 1000
    visible: true

    QtObject {
        id: applet
        property var identifiedTokensSnapshot: null
        property string identifiedTokensErrorKind: ""
        property int identifiedTokensHistoryDays: 7
        property bool identifiedTokensSshAvailable: true
        property bool identifiedTokensLoading: false
        property real roundedSurfaceRadius: 8
        property real secondaryTextOpacity: 0.7
        property int loads: 0
        function usageCountText(value, unit) { return value + " " + unit; }
        function amountString(value) { return "$" + value; }
        function withAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha); }
        function loadIdentifiedTokens() { loads++; }
    }

    Components.IdentifiedTokensSection {
        id: section
        applet: applet
        width: testCase.width
        height: implicitHeight
        function i18n(source) {
            for (var i = 1; i < arguments.length; i++)
                source = source.replace("%" + i, String(arguments[i]));
            return source;
        }
        function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }
    }

    function snapshot(end, days, partial) {
        return {totalTokens: 320, requestCount: 2, apiEstimateUSD: 0.0125,
            startUnixMs: 1793577600000, endUnixMs: end, historyDays: days,
            remoteRequested: true, allSourcesAvailable: false, localAvailable: true,
            remoteAvailable: false, requestsPartial: partial, conflictCount: 0,
            excludedCount: partial ? 1 : 0, unpricedRequestCount: 0};
    }

    function visibleText(item, text) {
        if (item.visible && item.text === text) return true;
        for (var child of item.children)
            if (child.visible && visibleText(child, text)) return true;
        return false;
    }

    function init() {
        applet.identifiedTokensSnapshot = null;
        applet.identifiedTokensHistoryDays = 7;
        applet.loads = 0;
        section.detailsExpanded = false;
    }

    function test_unloadedRangeDoesNotStartCollection() {
        compare(findChild(section, "identifiedTokensRange").text, "7 UTC days");
        verify(!findChild(section, "identifiedDetailsButton").visible);
        applet.identifiedTokensHistoryDays = 1;
        compare(findChild(section, "identifiedTokensRange").text, "1 UTC day");
        compare(applet.loads, 0);
    }

    function test_detailsUseSnapshotAndPreserveWarnings_data() {
        return [{tag: "source", partial: false}, {tag: "source-and-requests", partial: true}];
    }
    function test_detailsUseSnapshotAndPreserveWarnings(data) {
        applet.identifiedTokensSnapshot = snapshot(1794177600000, 3, data.partial);
        var button = findChild(section, "identifiedDetailsButton");
        var details = findChild(section, "identifiedCollectionDetails");
        var window = findChild(section, "identifiedTokensWindow");
        compare(findChild(section, "identifiedTokensRange").text, "3 UTC days");
        verify(!details.visible && !window.visible);
        verify(visibleText(section, "SSH unavailable. Showing local data only."));
        if (data.partial)
            verify(visibleText(section, "Some requests could not be included. This subtotal is partial."));

        mouseClick(button);
        verify(details.visible && window.visible);
        verify(window.text.indexOf("2026-11-08 22:40:00") >= 0);
        verify(visibleText(section, "Sources requested: this computer + SSH"));
        verify(visibleText(section, "Separate from spend totals."));
        verify(visibleText(section, "Check SSH and use the same supported codexbar version on both computers."));
        verify(button.Accessible.checked);
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(!details.visible && !window.visible);
        verify(!button.Accessible.checked && button.activeFocus);
        verify(visibleText(section, "SSH unavailable. Showing local data only."));
        if (data.partial)
            verify(visibleText(section, "Some requests could not be included. This subtotal is partial."));
        compare(applet.loads, 0);
    }

    function test_newSnapshotClosesDetailsWithoutMovingFocus() {
        applet.identifiedTokensSnapshot = snapshot(1794177600000, 3, false);
        var button = findChild(section, "identifiedDetailsButton");
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(findChild(section, "identifiedCollectionDetails").visible);
        applet.identifiedTokensSnapshot = snapshot(1794177660000, 4, false);
        verify(!findChild(section, "identifiedCollectionDetails").visible);
        compare(findChild(section, "identifiedTokensRange").text, "4 UTC days");
        verify(button.activeFocus);
        compare(applet.loads, 0);
    }
}
