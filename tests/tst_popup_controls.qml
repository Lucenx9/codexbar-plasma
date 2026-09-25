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
        property string providerUpdatedText: "Provider updated 11:55"
        property real secondaryTextOpacity: 0.7
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 4
        property real compactMeterTrackHeight: 5

        function providerColor() {
            return Qt.rgba(0.2, 0.6, 0.7, 1);
        }
        function providerUsageTimestamp(item) {
            return item && item.lastGoodAtMs > 0 ? providerUpdatedText : "";
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
        function switcherMetricRow(item) {
            return item.testRow || null;
        }
        function displayPercent(row) {
            return row.leftPercent;
        }
        function usageResetText(row) {
            return row.reset || "";
        }
        function resetLabel(value) {
            return "Resets " + value;
        }
        function overviewDetailText(item) {
            return item.account || "";
        }
        function percentSuffix() {
            return "left";
        }
        function statusBadgeText() {
            return "Issue";
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
        property bool accountsLoading: false
        property var accountOptions: []
        function accountLoadingForProvider() {
            return accountsLoading;
        }
        function accountOptionsForProvider() {
            return accountOptions;
        }
        function accountErrorForProvider() {
            return "";
        }
        function selectedAccountForProvider() {
            return "";
        }
        function accountDisplayLabel(item) {
            return item.label;
        }
        function accountSubtitle(item) {
            return item.subtitle || "";
        }
        function accountIsSelected(item) {
            return !!item.selected;
        }
        function accountKey(item) {
            return item.key;
        }
        function selectAccount() {
        }
        function loadAccounts() {
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
        applet.providerUpdatedText = "Provider updated 11:55";
        applet.accountsLoading = false;
        applet.accountOptions = [];
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

    // The meter and reset are only visual; the row's accessible description
    // must carry them beside the detail line, and drop what is absent.
    function test_overviewDescribesItsQuotaToAssistiveTools() {
        var measured = Object.assign({}, provider, {
            testRow: {hasPercent: true, leftPercent: 42.4, reset: "in 2h"}
        });
        var row = createControl("OverviewProviderRow", {
            applet: applet, modelData: measured, width: 540
        });
        if (!row)
            return;
        var focus = row.nextItemInFocusChain(true);
        compare(focus.Accessible.name, "Codex");
        verify(row.percentText.length > 0);
        compare(focus.Accessible.description,
            row.percentText + ". demo@example.com. Resets in 2h");
        row.modelData = {provider: "claude", title: "Claude", account: ""};
        compare(focus.Accessible.description, "");
        row.modelData = provider;
        compare(focus.Accessible.description, "demo@example.com");
    }

    function findToolTip(item) {
        var data = item.data || [];
        for (var i = 0; i < data.length; i++) {
            if (data[i] && data[i].plainText !== undefined && data[i].delay !== undefined)
                return data[i];
        }
        return null;
    }

    // Elided title or detail text must stay readable on hover, and a row whose
    // text fits must not grow a redundant tooltip.
    function test_overviewRevealsTruncatedTextOnHover() {
        var longAccount = "a-very-long-account-name-that-cannot-fit@example.com";
        var row = createControl("OverviewProviderRow", {
            applet: applet,
            modelData: Object.assign({}, provider, {account: longAccount}),
            width: 180
        });
        if (!row)
            return;
        var tip = findToolTip(row);
        verify(tip !== null);
        tryVerify(function () { return row.textTruncated; });
        compare(tip.plainText, "Codex\n" + longAccount);
        mouseMove(row, row.width / 2, row.height / 2);
        tryCompare(tip, "visible", true);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(tip, "visible", false);
        row.width = 600;
        tryVerify(function () { return !row.textTruncated; });
        mouseMove(row, row.width / 2, row.height / 2);
        wait(tip.delay + 100);
        verify(!tip.visible);
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
        var measured = Object.assign({}, provider, {lastGoodAtMs: 1});
        var header = createControl("ProviderHeader", {
            applet: applet, providerData: measured, width: 540
        });
        if (!header)
            return;
        var timestamp = findText(header, applet.providerUpdatedText);
        verify(timestamp !== null);
        applet.lastUpdatedText = "Another provider updated 12:05";
        compare(timestamp.text, "Provider updated 11:55");
        header.providerData = provider;
        tryCompare(timestamp, "visible", false);
        header.providerData = measured;
        applet.providerUpdatedText = "Last known usage, 8 minutes ago";
        tryCompare(timestamp, "visible", true);
        compare(timestamp.text, "Last known usage, 8 minutes ago");
    }

    function test_headerMetadataSharesABaseline() {
        var header = createControl("ProviderHeader", {
            applet: applet, providerData: provider, width: 540
        });
        if (!header)
            return;
        var account = findText(header, provider.account);
        var plan = findText(header, provider.planText);
        account.font.pixelSize = 30;
        plan.font.pixelSize = 18;
        tryVerify(function () {
            return Math.abs(account.mapToItem(header, 0, account.baselineOffset).y
                - plan.mapToItem(header, 0, plan.baselineOffset).y) < 1;
        });
    }

    function test_headerPlanStaysBesideElidedAccount_data() {
        return [
            {tag: "narrow", width: 240},
            {tag: "popup", width: 540}
        ];
    }

    function test_headerPlanStaysBesideElidedAccount(data) {
        var longAccount = "engineering-with-an-unusually-long-account-name@example.com";
        var header = createControl("ProviderHeader", {
            applet: applet,
            providerData: {
                provider: "codex",
                title: "Codex",
                account: longAccount,
                planText: "Pro",
                hasIncident: false
            },
            width: data.width
        });
        if (!header)
            return;
        var account = findText(header, longAccount);
        var plan = findText(header, "Pro");
        verify(account !== null && plan !== null);
        tryVerify(function () {
            return account.width > 0 && plan.width > 0;
        });
        // The account never claims more width than its own text, so the plan
        // cannot drift away from the email it qualifies.
        verify(account.width <= account.implicitWidth + 1);
        var separator = findText(header, "·");
        verify(separator !== null && separator.visible);
        verify(separator.x - (account.x + account.width) <= 8);
        verify(plan.x - (separator.x + separator.width) <= 8);
        // On a narrow popup the account yields first and both stay inside.
        if (data.width < 300) {
            verify(account.width < account.implicitWidth);
        }
        verify(account.mapToItem(header, account.width, 0).x <= header.width + 1);
        verify(plan.mapToItem(header, plan.width, 0).x <= header.width + 1);
    }

    function test_incidentBadgeYieldsToTheStatusBanner() {
        var header = createControl("ProviderHeader", {
            applet: applet, width: 540,
            providerData: {provider: "codex", title: "Codex", account: "", planText: "",
                hasIncident: true, statusSeverity: "minor", status: "Partial outage"}
        });
        if (!header)
            return;
        var label = findText(header, "Issue");
        verify(label !== null);
        // Production status text names the severity even without a CLI
        // description, so an incident always reaches the banner instead.
        verify(!label.parent.visible, "an incident with banner text already has its banner");
        header.providerData = {provider: "codex", title: "Codex", account: "", planText: "",
            hasIncident: true, statusSeverity: "minor", status: ""};
        tryVerify(function () { return label.parent.visible; });
    }

    function test_incidentBadgeGrowsWithItsText() {
        var header = createControl("ProviderHeader", {
            applet: applet, width: 540,
            providerData: {provider: "codex", title: "Codex", account: "", planText: "",
                hasIncident: true, statusSeverity: "minor"}
        });
        if (!header)
            return;
        var label = findText(header, "Issue");
        verify(label !== null && label.visible);
        label.font.pixelSize = 40;
        tryVerify(function () {
            return label.parent.height > label.implicitHeight
                && label.y > 0 && label.y + label.height < label.parent.height;
        });
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

    function findAccountButton(item) {
        if (item.fullLabel !== undefined)
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findAccountButton(children[i]);
            if (found)
                return found;
        }
        return null;
    }

    function findByObjectName(item, name) {
        if (item.objectName === name)
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findByObjectName(children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    // A truncated account label must stay readable on hover, and a label
    // that fits must not grow a redundant tooltip.
    function test_accountsRevealTruncatedLabelOnHover() {
        applet.accountOptions = [{
            key: "work",
            label: "engineering-with-an-unusually-long-account-name@example.com",
            subtitle: "Production",
            provider: "codex"
        }];
        var panel = createControl("ProviderAccountsPanel", {
            applet: applet, providerData: {provider: "codex"}, width: 220
        });
        if (!panel)
            return;
        var button = findAccountButton(panel);
        verify(button !== null);
        tryVerify(function () { return button.textTruncated; });
        var tip = findToolTip(button);
        verify(tip !== null);
        compare(tip.plainText, button.fullLabel);
        // Park the virtual mouse away first, flushing the move: back-to-back
        // moves compress into one, which cannot be relied on to enter the
        // button from an unknown start position.
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        wait(300);
        mouseMove(button, button.width / 2, button.height / 2);
        tryCompare(tip, "visible", true);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(tip, "visible", false);
        panel.width = 640;
        tryVerify(function () { return !button.textTruncated; });
        mouseMove(button, button.width / 2, button.height / 2);
        wait(tip.delay + 100);
        verify(!tip.visible);
    }

    // The loading indicator holds its place while idle so the reload action
    // does not jump when a scan starts or finishes.
    function test_accountsHoldTheReloadActionPlaceWhileLoading() {
        applet.accountOptions = [{key: "work", label: "Work", provider: "codex"}];
        var panel = createControl("ProviderAccountsPanel", {
            applet: applet, providerData: {provider: "codex"}, width: 400
        });
        if (!panel)
            return;
        var indicator = findByObjectName(panel, "accountsBusyIndicator");
        var reload = findByObjectName(panel, "reloadAccountsButton");
        verify(indicator !== null && reload !== null);
        tryVerify(function () { return indicator.width > 0 && reload.width > 0; });
        verify(indicator.visible);
        var idleX = reload.mapToItem(panel, 0, 0).x;
        applet.accountsLoading = true;
        tryVerify(function () { return indicator.running; });
        verify(Math.abs(reload.mapToItem(panel, 0, 0).x - idleX) < 1);
        applet.accountsLoading = false;
        tryVerify(function () { return !indicator.running; });
        verify(Math.abs(reload.mapToItem(panel, 0, 0).x - idleX) < 1);
        verify(indicator.visible);
    }
}
