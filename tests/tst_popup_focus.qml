import QtQuick
import QtQuick.Window
import QtTest
import "../contents/ui/PopupHiddenRows.js" as PopupHiddenRows
import "../contents/ui/PopupHiddenSections.js" as PopupHiddenSections
import "../contents/ui/UsageDetails.js" as UsageDetails

TestCase {
    id: testCase

    name: "PopupFocus"
    when: windowShown
    width: 620
    height: 760
    visible: true

    property var componentHolders: []

    function i18n(text) {
        var result = String(text);
        for (var i = 1; i < arguments.length; i++)
            result = result.replace("%" + i, String(arguments[i]));
        return result;
    }

    function i18nc(context, text) {
        var result = String(text);
        for (var i = 2; i < arguments.length; i++)
            result = result.replace("%" + (i - 1), String(arguments[i]));
        return result;
    }

    function i18np(singular, plural, count) {
        var result = count === 1 ? String(singular) : String(plural);
        for (var i = 2; i < arguments.length; i++)
            result = result.replace("%" + (i - 1), String(arguments[i]));
        return result;
    }

    function i18ncp(context, singular, plural, count) {
        var result = count === 1 ? String(singular) : String(plural);
        for (var i = 3; i < arguments.length; i++)
            result = result.replace("%" + (i - 2), String(arguments[i]));
        return result;
    }

    QtObject {
        id: applet

        property var providers: []
        readonly property var presentedProviders: providers
        property string selectedProviderID: "codex"
        property string selectedAccountKey: ""
        property bool selectionInitialized: true
        readonly property int selectedProviderIndex: 0
        readonly property var selectedProviderData: providers.length > 0 ? providers[0] : null
        readonly property var presentedProviderData: selectedProviderData
        readonly property bool overviewAvailable: false
        readonly property bool overviewSelected: false
        readonly property bool spendAvailable: false
        readonly property bool spendSelected: false
        readonly property bool sessionsAvailable: false
        readonly property bool sessionsSelected: false
        readonly property bool globalViewSelected: false
        readonly property bool globalNavigationAvailable: false
        readonly property bool providerUsageFeedbackVisible: true
        readonly property var overviewProviderItems: []
        readonly property var presentedOverviewProviders: []

        property bool loading: false
        property bool commandPathFailed: false
        property string commandPath: "codexbar"
        property bool cliSetupBusy: false
        property string cliSetupStatus: ""
        property string errorText: ""
        property string lastUpdatedText: "Updated 12:00"
        property bool showPopupTabLabels: true
        property bool showPopupPace: true
        property bool showMonthlyDailyAllowance: false
        property bool showPopupCredits: false
        property bool showPopupProviderDetails: true
        property bool costUsageEnabled: false
        property bool costLoading: false
        property string costErrorText: ""
        property int costHistoryDays: 30
        property string costHistoryPeriod: ""
        property string costHistoryMetric: "cost"
        readonly property bool costHistoryShowsTokens: false
        property var costNumberFormat: ({group: ",", decimal: "."})
        property bool identifiedTokensEnabled: false
        property bool aiInsightsEnabled: false
        property bool aiInsightsConfigured: false
        property bool aiInsightsBusy: false
        property var aiInsightsCache: null
        property string aiInsightsCacheState: "none"
        property string aiInsightsErrorReason: ""
        property var aiInsightsSnapshot: ({sufficient: false})
        property bool privacyMode: false
        property var sessions: []
        readonly property var presentedSessions: sessions
        property bool sessionsLoading: false
        property string sessionsErrorText: ""
        property string sessionsLastUpdatedText: ""
        property bool sessionHostsVary: false
        property var statusComponents: ({loading: false, failed: false, components: [], groups: []})
        property var statusComponentGroups: ({})
        property double panelClockMs: 0
        property real meterTrackHeight: 6
        property real compactMeterTrackHeight: 5
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.85
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 4
        property real quotaWarningPercent: 70
        property real quotaCriticalPercent: 90

        property string hiddenUsageRowsConfig: ""
        readonly property var popupHiddenUsageRows: PopupHiddenRows.parse(hiddenUsageRowsConfig)
        property string hiddenDetailSectionsConfig: ""
        readonly property var popupHiddenDetailSections: PopupHiddenSections.parse(hiddenDetailSectionsConfig)

        function withAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha); }
        function providerColor() { return Qt.rgba(0.2, 0.6, 0.7, 1); }
        function providerReadableColor() { return providerColor(); }
        function readableAccentColor(color) { return color; }
        function providerIconSource() { return "view-statistics"; }
        function providerIconIsMask() { return true; }
        function providerDisplayTitle(id) { return id; }
        function providerCountText(count) { return count + " providers"; }
        function providerIndex() { return 0; }
        function switcherPercent() { return 50; }
        function switcherDescription() { return ""; }
        function providerUsageTimestamp() { return "Updated 12:00"; }
        function providerPlaceholderText() { return ""; }
        function statusBadgeText() { return ""; }
        function statusBadgeColor() { return "red"; }
        function quotaMeterColor() { return providerColor(); }
        function quotaWarningMarkers() { return []; }
        function displayPercent(row) { return row.leftPercent; }
        function usagePercentText(row) { return Math.round(row.leftPercent) + "% left"; }
        function usagePaceText() { return ""; }
        function usageDailyAllowanceText() { return ""; }
        function resetTextForRow(row) { return row.reset ? "Resets " + row.reset : ""; }
        function usageConfidenceText() { return ""; }
        function paceMarkerPercent() { return -1; }
        function usageErrorText(text) { return text; }
        function usageRecoveryHint() { return ""; }
        function usageErrorKind() { return ""; }
        function formatNumber(value) { return String(value); }
        function subscriptionDateText() { return ""; }
        function codexCreditLimitUsageRow() { return null; }
        function accountLoadingForProvider() { return false; }
        function accountAvailabilityForProvider() { return ""; }
        function accountNoticeForProvider() { return ""; }
        function accountOptionsForProvider() { return []; }
        function accountErrorForProvider() { return ""; }
        function selectedAccountForProvider() { return selectedAccountKey; }
        function accountDisplayLabel(item) { return item ? item.label : ""; }
        function accountSubtitle() { return ""; }
        function accountIsSelected() { return false; }
        function accountKey() { return ""; }
        function accountLabel() { return ""; }
        function selectAccount(provider, key) { selectedAccountKey = key; }
        function loadAccounts() {}
        function selectGlobalView() {}
        function refreshNow() {}
        function retryUsage() {}
        function prepareCli() {}
        function performAction() {}
        function actionRows() { return [{title: "Open dashboard", icon: "globe", action: "dashboard", enabled: true}]; }
        function statusComponentsExpanded() { return false; }
        function toggleStatusComponentGroup() {}
        function spendProviderCosts() { return []; }
        function presentedSpendProviderCosts() { return []; }
        function spendCurrency() { return "USD"; }
        function spendTotalLine() { return ""; }
        function amountString(v) { return "$" + Number(v || 0).toFixed(2); }
        function usageCountText(v) { return String(v || 0); }
        function qualifiedCostValue(v) { return v; }
        function privateErrorText(t) { return t; }
        function elapsedText() { return "just now"; }
        function aiInsightsErrorText(r) { return r; }
        function providerCostForProvider() { return null; }
        function tokenCostHint() { return ""; }

        function popupUsageRows(item) {
            return item ? PopupHiddenRows.visibleRows(item.rows, popupHiddenUsageRows, item.provider) : [];
        }
        function hiddenPopupUsageRows(item) {
            return item ? PopupHiddenRows.hiddenRows(item.rows, popupHiddenUsageRows, item.provider) : [];
        }
        function popupUsageRowHideable(row) {
            return PopupHiddenRows.rowKey(row).length > 0
                && popupHiddenUsageRows.length < PopupHiddenRows.maximumEntries;
        }
        function hidePopupUsageRow(providerID, row) {
            var key = PopupHiddenRows.rowKey(row);
            if (key.length > 0)
                hiddenUsageRowsConfig = PopupHiddenRows.serialize(
                    PopupHiddenRows.hidden(popupHiddenUsageRows, providerID, key));
        }
        function restorePopupUsageRow(providerID, row) {
            var key = PopupHiddenRows.rowKey(row);
            if (key.length > 0)
                hiddenUsageRowsConfig = PopupHiddenRows.serialize(
                    PopupHiddenRows.restored(popupHiddenUsageRows, providerID, key));
        }

        function popupDetailSections(item) {
            return item ? PopupHiddenSections.visibleSections(item.providerDetails, popupHiddenDetailSections, item.provider) : [];
        }
        function hiddenPopupDetailSections(item) {
            return item ? PopupHiddenSections.hiddenSections(item.providerDetails, popupHiddenDetailSections, item.provider) : [];
        }
        function popupDetailSectionHideable(section) {
            return PopupHiddenSections.sectionKey(section).length > 0
                && popupHiddenDetailSections.length < PopupHiddenSections.maximumEntries;
        }
        function hidePopupDetailSection(providerID, section) {
            hiddenDetailSectionsConfig = PopupHiddenSections.serialize(
                PopupHiddenSections.hidden(popupHiddenDetailSections, providerID, PopupHiddenSections.sectionKey(section)));
        }
        function restorePopupDetailSection(providerID, section) {
            hiddenDetailSectionsConfig = PopupHiddenSections.serialize(
                PopupHiddenSections.restored(popupHiddenDetailSections, providerID, PopupHiddenSections.sectionKey(section)));
        }
    }

    function createPopup() {
        var holder;
        try {
            holder = Qt.createQmlObject(
                'import QtQuick; import "../contents/ui/components" as Components; '
                + 'QtObject { property Component control: Component { Components.FullRepresentation {} } }',
                testCase, Qt.resolvedUrl("PopupFocusTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("Popup focus tests need the optional KDE QML modules");
                return null;
            }
            throw error;
        }
        componentHolders.push(holder);
        var popup = createTemporaryObject(holder.control, testCase, {
            applet: applet,
            width: 540,
            height: 700
        });
        verify(popup !== null);
        return popup;
    }

    function makeProvider() {
        return {
            provider: "codex",
            title: "Codex",
            account: "demo@example.com",
            planText: "Pro",
            error: "",
            hasIncident: false,
            statusKnown: true,
            statusSeverity: "none",
            status: "",
            lastGoodAtMs: 1,
            credits: null,
            codexCreditLimit: null,
            resetCredits: null,
            providerCost: null,
            tokenCost: null,
            usageDashboard: null,
            subscriptionDates: [],
            rows: [
                {lane: "primary", label: "Session", hasPercent: true, leftPercent: 60, reset: "in 2h", pace: "", summaryText: ""},
                {lane: "secondary", label: "Weekly", hasPercent: true, leftPercent: 40, reset: "in 3d", pace: "", summaryText: ""},
                {lane: "extra", windowId: "burst", label: "Burst", hasPercent: true, leftPercent: 80, reset: "", pace: "", summaryText: ""}
            ],
            providerDetails: UsageDetails.normalizeSections([
                {title: "Budgets", rows: [{label: "Daily", value: "25%"}]},
                {title: "Limits", rows: [{label: "RPM", value: "100"}]}
            ])
        };
    }

    function findAllByObjectName(item, name, out) {
        if (!item)
            return out;
        if (item.objectName === name)
            out.push(item);
        var children = item.children || [];
        for (var i = 0; i < children.length; i++)
            findAllByObjectName(children[i], name, out);
        return out;
    }

    function findByObjectName(item, name) {
        var list = findAllByObjectName(item, name, []);
        return list.length > 0 ? list[0] : null;
    }

    function visibleButtons(root, name) {
        return findAllByObjectName(root, name, []).filter(function(item) {
            return item.visible;
        });
    }

    function init() {
        applet.selectedAccountKey = "";
        applet.hiddenUsageRowsConfig = "";
        applet.hiddenDetailSectionsConfig = "";
        applet.providers = [makeProvider()];
    }

    function cleanupTestCase() {
        for (var i = 0; i < componentHolders.length; i++)
            componentHolders[i].destroy();
    }

    function test_clearingDefaultOverrideWithNoAccountsKeepsFocusVisible() {
        applet.selectedAccountKey = "work";
        var popup = createPopup();
        if (!popup) return;
        var clear = findByObjectName(popup, "clearAccountOverrideButton");
        var actions = findByObjectName(popup, "providerActionsToggle");
        verify(clear.visible && actions.visible);
        clear.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.selectedAccountKey, "");
        verify(!clear.visible);
        verify(!findByObjectName(popup, "reloadAccountsButton").visible);
        verify(actions.activeFocus && actions.visualFocus);
    }

    function test_hidingAndRestoringUsageRowsPreservesKeyboardFocus() {
        var popup = createPopup();
        if (!popup)
            return;
        waitForRendering(popup);

        var hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 3);

        // Hide middle row ("Weekly") via keyboard -> focus advances to next row ("Burst"), not back to "Session".
        hideButtons[1].forceActiveFocus(Qt.TabFocusReason);
        verify(hideButtons[1].activeFocus && hideButtons[1].visualFocus);
        keyClick(Qt.Key_Space);
        wait(0);
        hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 2);
        compare(hideButtons[1].Accessible.name, "Hide the Burst row");
        verify(hideButtons[1].activeFocus, "Focus was lost after hiding the middle usage row");
        verify(hideButtons[1].visualFocus, "Keyboard focus indicator was lost after hiding the middle usage row");

        // Hide last row ("Burst") via keyboard -> focus moves to previous remaining row ("Session").
        keyClick(Qt.Key_Space);
        wait(0);
        hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 1);
        compare(hideButtons[0].Accessible.name, "Hide the Session row");
        verify(hideButtons[0].activeFocus, "Focus was lost after hiding the last usage row");
        verify(hideButtons[0].visualFocus);

        // Hide final remaining row ("Session") -> focus moves to "Hidden usage rows" disclosure.
        keyClick(Qt.Key_Space);
        wait(0);
        compare(visibleButtons(popup, "hideUsageRowButton").length, 0);
        var hiddenToggle = findByObjectName(popup, "hiddenUsageRowsToggle");
        verify(hiddenToggle !== null && hiddenToggle.visible);
        verify(hiddenToggle.activeFocus, "Focus was lost after hiding the final usage row");
        verify(hiddenToggle.visualFocus);

        // Expand hidden rows and restore them one by one via keyboard.
        keyClick(Qt.Key_Space);
        wait(0);
        var restoreButtons = visibleButtons(popup, "restorePopupUsageRowButton");
        compare(restoreButtons.length, 3);

        restoreButtons[0].forceActiveFocus(Qt.TabFocusReason);
        verify(restoreButtons[0].activeFocus && restoreButtons[0].visualFocus);
        keyClick(Qt.Key_Space);
        wait(0);
        restoreButtons = visibleButtons(popup, "restorePopupUsageRowButton");
        compare(restoreButtons.length, 2);
        compare(restoreButtons[0].Accessible.name, "Restore Weekly");
        verify(restoreButtons[0].activeFocus, "Focus was lost after restoring a hidden usage row");
        verify(restoreButtons[0].visualFocus);

        // Restore second hidden row ("Weekly") -> focus moves to final hidden row ("Burst").
        keyClick(Qt.Key_Space);
        wait(0);
        restoreButtons = visibleButtons(popup, "restorePopupUsageRowButton");
        compare(restoreButtons.length, 1);
        compare(restoreButtons[0].Accessible.name, "Restore Burst");
        verify(restoreButtons[0].activeFocus, "Focus was lost after restoring the second hidden usage row");
        verify(restoreButtons[0].visualFocus);

        // Restore final hidden row ("Burst") -> hidden section disappears, focus moves to restored row's hide button.
        keyClick(Qt.Key_Space);
        wait(0);
        compare(hiddenToggle.visible, false);
        hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 3);
        compare(hideButtons[2].Accessible.name, "Hide the Burst row");
        verify(hideButtons[2].activeFocus, "Focus was lost after restoring the final hidden usage row");
        verify(hideButtons[2].visualFocus);
    }

    function test_pointerHideAndRestoreUsageRowDoesNotForceKeyboardFocus() {
        var popup = createPopup();
        if (!popup)
            return;
        waitForRendering(popup);

        var hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 3);
        testCase.forceActiveFocus(Qt.OtherFocusReason);
        mouseClick(hideButtons[0], hideButtons[0].width / 2, hideButtons[0].height / 2);
        wait(0);
        hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 2);
        verify(!hideButtons[0].visualFocus);

        var hiddenToggle = findByObjectName(popup, "hiddenUsageRowsToggle");
        mouseClick(hiddenToggle, hiddenToggle.width / 2, hiddenToggle.height / 2);
        wait(0);
        var restoreButtons = visibleButtons(popup, "restorePopupUsageRowButton");
        compare(restoreButtons.length, 1);
        mouseClick(restoreButtons[0], restoreButtons[0].width / 2, restoreButtons[0].height / 2);
        wait(0);
        hideButtons = visibleButtons(popup, "hideUsageRowButton");
        compare(hideButtons.length, 3);
        for (var i = 0; i < hideButtons.length; i++)
            verify(!hideButtons[i].visualFocus);
    }

    function test_hidingAndRestoringDetailSectionsPreservesKeyboardFocus() {
        var popup = createPopup();
        if (!popup)
            return;
        waitForRendering(popup);

        var hideButtons = visibleButtons(popup, "hideDetailSectionButton");
        compare(hideButtons.length, 2);

        // Hide first section ("Budgets") via keyboard -> focus moves to next section ("Limits").
        hideButtons[0].forceActiveFocus(Qt.TabFocusReason);
        verify(hideButtons[0].activeFocus && hideButtons[0].visualFocus);
        keyClick(Qt.Key_Space);
        wait(0);
        hideButtons = visibleButtons(popup, "hideDetailSectionButton");
        compare(hideButtons.length, 1);
        compare(hideButtons[0].Accessible.name, "Hide the Limits section");
        verify(hideButtons[0].activeFocus, "Focus was lost after hiding the first detail section");
        verify(hideButtons[0].visualFocus, "Keyboard focus indicator was lost after hiding the first detail section");

        // Hide final section ("Limits") -> focus moves to "Hidden detail sections" disclosure.
        keyClick(Qt.Key_Space);
        wait(0);
        compare(visibleButtons(popup, "hideDetailSectionButton").length, 0);
        var hiddenToggle = findByObjectName(popup, "hiddenDetailSectionsToggle");
        verify(hiddenToggle !== null && hiddenToggle.visible);
        verify(hiddenToggle.activeFocus, "Focus was lost after hiding the final detail section");
        verify(hiddenToggle.visualFocus);

        // Expand hidden detail sections and restore both via keyboard.
        keyClick(Qt.Key_Space);
        wait(0);
        var restoreButtons = visibleButtons(popup, "restoreDetailSectionButton");
        compare(restoreButtons.length, 2);

        restoreButtons[0].forceActiveFocus(Qt.TabFocusReason);
        verify(restoreButtons[0].activeFocus && restoreButtons[0].visualFocus);
        keyClick(Qt.Key_Space);
        wait(0);
        restoreButtons = visibleButtons(popup, "restoreDetailSectionButton");
        compare(restoreButtons.length, 1);
        compare(restoreButtons[0].Accessible.name, "Restore Limits");
        verify(restoreButtons[0].activeFocus, "Focus was lost after restoring a hidden detail section");
        verify(restoreButtons[0].visualFocus);

        // Restore final hidden detail section ("Limits") -> focus moves to restored section's hide button.
        keyClick(Qt.Key_Space);
        wait(0);
        compare(hiddenToggle.visible, false);
        hideButtons = visibleButtons(popup, "hideDetailSectionButton");
        compare(hideButtons.length, 2);
        compare(hideButtons[1].Accessible.name, "Hide the Limits section");
        verify(hideButtons[1].activeFocus, "Focus was lost after restoring the final hidden detail section");
        verify(hideButtons[1].visualFocus);
    }

    function test_restoringFinalDetailRevealsFocusedAction() {
        var sections = [];
        for (var i = 0; i < 8; i++) {
            sections.push({title: "Detail " + i, rows: [{label: "Reading", value: "42"}]});
        }
        var provider = makeProvider();
        provider.providerDetails = UsageDetails.normalizeSections(sections);
        applet.providers = [provider];
        applet.hidePopupDetailSection("codex", provider.providerDetails[0]);

        var popup = createPopup();
        if (!popup) return;
        popup.height = 360;
        findByObjectName(popup, "hiddenDetailSectionsToggle").clicked();
        var flick = findByObjectName(popup, "providerScroll").contentItem;
        var restore = findByObjectName(popup, "restoreDetailSectionButton");
        tryVerify(function() { return flick.contentHeight > flick.height * 2; });
        flick.contentY = flick.originY + flick.contentHeight - flick.height;
        function insideViewport(item) {
            var top = item.mapToItem(flick, 0, 0).y;
            return top >= -1 && top + item.height <= flick.height + 1;
        }
        tryVerify(function() { return insideViewport(restore); });
        restore.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        var first = visibleButtons(popup, "hideDetailSectionButton")[0];
        compare(first.Accessible.name, "Hide the Detail 0 section");
        verify(first.activeFocus);
        tryVerify(function() { return insideViewport(first); }, 1000);
    }

    function test_pointerHideAndRestoreDetailSectionDoesNotForceKeyboardFocus() {
        var popup = createPopup();
        if (!popup)
            return;
        waitForRendering(popup);

        var hideButtons = visibleButtons(popup, "hideDetailSectionButton");
        compare(hideButtons.length, 2);
        testCase.forceActiveFocus(Qt.OtherFocusReason);
        mouseClick(hideButtons[0], hideButtons[0].width / 2, hideButtons[0].height / 2);
        wait(0);
        hideButtons = visibleButtons(popup, "hideDetailSectionButton");
        compare(hideButtons.length, 1);
        verify(!hideButtons[0].visualFocus);

        var hiddenToggle = findByObjectName(popup, "hiddenDetailSectionsToggle");
        mouseClick(hiddenToggle, hiddenToggle.width / 2, hiddenToggle.height / 2);
        wait(0);
        var restoreButtons = visibleButtons(popup, "restoreDetailSectionButton");
        compare(restoreButtons.length, 1);
        mouseClick(restoreButtons[0], restoreButtons[0].width / 2, restoreButtons[0].height / 2);
        wait(0);
        hideButtons = visibleButtons(popup, "hideDetailSectionButton");
        compare(hideButtons.length, 2);
        for (var i = 0; i < hideButtons.length; i++)
            verify(!hideButtons[i].visualFocus);
    }
}
