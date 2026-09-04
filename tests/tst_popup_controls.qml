import QtQuick
import QtTest

TestCase {
    id: testCase

    name: "PopupControls"
    when: windowShown
    width: 620
    height: 300
    visible: true

    property var componentHolders: []
    readonly property var provider: ({
            provider: "codex",
            title: "Codex",
            account: "demo@example.com",
            planText: "Pro",
            hasIncident: false
        })

    QtObject {
        id: applet

        property bool loading: false
        property string lastUpdatedText: "Updated 12:00"
        property real secondaryTextOpacity: 0.7
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 4
        property real compactMeterTrackHeight: 5

        function providerColor() {
            return Qt.rgba(0.2, 0.6, 0.7, 1);
        }
        function providerReadableColor() {
            return providerColor();
        }
        function providerIconSource() {
            return "view-statistics";
        }
        function providerIconIsMask() {
            return true;
        }
        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, alpha);
        }
        function switcherMetricRow() {
            return null;
        }
        function overviewDetailText(item) {
            return item.account || "";
        }
        function percentSuffix() {
            return "left";
        }
        function statusBadgeText() {
            return "";
        }
        function statusBadgeColor() {
            return "red";
        }
        function quotaMeterColor() {
            return providerColor();
        }
        function contrastTextColor() {
            return "white";
        }
    }

    SignalSpy {
        id: actionSpy
    }

    function createControl(type, properties) {
        var holder;
        try {
            holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; ' + 'QtObject { property Component control: Component { Components.' + type + ' { function i18n(text) { return text } } } }', testCase, Qt.resolvedUrl("PopupControlsTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("Popup controls need the optional KDE QML modules");
                return null;
            }
            throw error;
        }
        componentHolders.push(holder);
        var control = createTemporaryObject(holder.control, testCase, properties);
        verify(control !== null);
        return control;
    }

    function cleanup() {
        actionSpy.target = null;
        actionSpy.signalName = "";
        actionSpy.clear();
        applet.lastUpdatedText = "Updated 12:00";
    }

    function cleanupTestCase() {
        for (var i = 0; i < componentHolders.length; i++) {
            componentHolders[i].destroy();
        }
    }

    function findText(item, text) {
        if (item.text === text)
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findText(children[i], text);
            if (found)
                return found;
        }
        return null;
    }

    function test_refreshKeepsSizeAndCannotRepeatWhileBusy() {
        var control = createControl("RefreshButton", {
            label: "Refresh"
        });
        if (!control)
            return;
        actionSpy.target = control;
        actionSpy.signalName = "requested";
        var idleWidth = control.width;
        var idleHeight = control.height;
        verify(idleWidth > 0 && idleHeight > 0);
        mouseClick(control, idleWidth / 2, idleHeight / 2);
        compare(actionSpy.count, 1);
        control.busy = true;
        compare(control.width, idleWidth);
        compare(control.height, idleHeight);
        mouseClick(control, idleWidth / 2, idleHeight / 2);
        compare(actionSpy.count, 1);
        control.busy = false;
        mouseClick(control, idleWidth / 2, idleHeight / 2);
        compare(actionSpy.count, 2);
    }

    function test_overviewShowsKeyboardFocusOnlyForKeyboardNavigation() {
        var row = createControl("OverviewProviderRow", {
            applet: applet,
            modelData: provider,
            width: 540
        });
        if (!row)
            return;
        actionSpy.target = row;
        actionSpy.signalName = "selected";
        row.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
        tryCompare(row, "keyboardFocusVisible", true);
        keyClick(Qt.Key_Space);
        compare(actionSpy.count, 1);
        compare(actionSpy.signalArguments[0][0].provider, "codex");
        mouseClick(row, row.width / 2, row.height / 2);
        compare(actionSpy.count, 2);
        tryCompare(row, "keyboardFocusVisible", false);
    }

    function test_refreshSupportsKeyboardActivation() {
        var control = createControl("RefreshButton", {
            label: "Refresh"
        });
        if (!control)
            return;
        actionSpy.signalName = "requested";
        actionSpy.target = control;
        var button = control.nextItemInFocusChain(true);
        button.forceActiveFocus(Qt.TabFocusReason);
        control.requested.connect(function () {
            control.busy = true;
        });
        keyClick(Qt.Key_Space);
        compare(actionSpy.count, 1);
        verify(control.busy);
        verify(button.visible);
        verify(button.enabled);
        verify(button.activeFocus);
        verify(button.visualFocus);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Return);
        mouseClick(control, control.width / 2, control.height / 2);
        compare(actionSpy.count, 1);
        control.busy = false;
        verify(button.activeFocus);
        keyClick(Qt.Key_Space);
        compare(actionSpy.count, 2);
        // Completion must not steal focus if the user has moved elsewhere.
        testCase.forceActiveFocus(Qt.TabFocusReason);
        control.busy = false;
        verify(!button.activeFocus);
    }

    function test_overviewPointerSelectionMovesKeyboardFocusToTheClickedRow() {
        var first = createControl("OverviewProviderRow", {
            applet: applet, modelData: provider, width: 260
        });
        var second = createControl("OverviewProviderRow", {
            applet: applet, modelData: {provider: "claude", title: "Claude"},
            x: 280, width: 260
        });
        if (!first || !second)
            return;
        var firstFocus = first.nextItemInFocusChain(true);
        var secondFocus = second.nextItemInFocusChain(true);
        firstFocus.forceActiveFocus(Qt.TabFocusReason);
        verify(first.keyboardFocusVisible);
        actionSpy.target = second;
        actionSpy.signalName = "selected";
        mouseClick(second, second.width / 2, second.height / 2);
        verify(!firstFocus.activeFocus);
        verify(secondFocus.activeFocus);
        verify(!first.keyboardFocusVisible && !second.keyboardFocusVisible);
        keyClick(Qt.Key_Space);
        compare(actionSpy.count, 2);
        compare(actionSpy.signalArguments[1][0].provider, "claude");
    }

    function test_headerTimestampRequiresAnObservedUpdate() {
        var header = createControl("ProviderHeader", {
            applet: applet, providerData: provider, width: 540
        });
        if (!header)
            return;
        var timestamp = findText(header, applet.lastUpdatedText);
        verify(timestamp !== null);
        applet.lastUpdatedText = "";
        tryCompare(timestamp, "visible", false);
        applet.lastUpdatedText = "Updated 12:05";
        tryCompare(timestamp, "visible", true);
        compare(timestamp.text, "Updated 12:05");
    }

    function test_headerIdentityAppearsAfterDataAndPopupBecomeVisible() {
        var header = createControl("ProviderHeader", {
            applet: applet,
            providerData: null,
            width: 540,
            visible: false
        });
        if (!header)
            return;
        header.providerData = provider;
        header.visible = true;
        var account = findText(header, provider.account);
        var plan = findText(header, provider.planText);
        verify(account !== null && plan !== null);
        tryCompare(account, "visible", true);
        tryCompare(plan, "visible", true);
        header.visible = false;
        header.visible = true;
        compare(account.visible, true);
        compare(plan.visible, true);
    }
}
