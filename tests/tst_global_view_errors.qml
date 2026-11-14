import QtQuick
import QtTest
import "../contents/ui/ProviderOrder.js" as ProviderOrder
import "../contents/ui/CostCurrency.mjs" as CostCurrency

TestCase {
    id: testCase
    name: "GlobalViewErrors"
    when: windowShown
    visible: true
    width: 540
    height: 504

    property var holders: []
    readonly property string longError: Array(17).join("Synthetic local scan failed. ")

    function i18n(text, value, second) {
        var result = value === undefined ? text : text.replace("%1", value);
        return second === undefined ? result : result.replace("%2", second);
    }

    function i18nc(context, text) {
        return text;
    }

    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    function i18ncp(context, singular, plural, count) {
        return i18np(singular, plural, count);
    }

    QtObject {
        id: applet
        property bool aiInsightsEnabled: false
        property bool aiInsightsConfigured: false
        property bool aiInsightsBusy: false
        property var aiInsightsCache: null
        property string aiInsightsCacheState: "none"
        property string aiInsightsErrorReason: ""
        property var aiInsightsSnapshot: ({sufficient: false})
        property var presentedProviders: []
        property var costNumberFormat: ({group: ",", decimal: "."})
        property double panelClockMs: 0
        function aiInsightsErrorText(reason) { return reason; }
        property bool privacyMode: false
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.8
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 4
        property bool costLoading: false
        property string costErrorText: ""
        property int costHistoryDays: 30
        property string costHistoryPeriod: ""
        property string costHistoryMetric: "cost"
        readonly property bool costHistoryShowsTokens: costHistoryMetric === "tokens"
        property var dailyPoints: []
        property var costs: []
        property string providerOrderRaw: ""
        property var sessions: []
        readonly property var presentedSessions: sessions
        property bool sessionsLoading: false
        property string sessionsErrorText: ""
        property string sessionsLastUpdatedText: "Updated just now"
        property bool sessionHostsVary: false
        property int refreshes: 0

        function spendProviderCosts() {
            var items = costs.length > 0 ? costs : dailyPoints.length > 0 ? [{provider: "codex"}] : [];
            return items.map(function(item) {
                return Object.assign({}, item, {daily: item.daily || dailyPoints.map(function(point) {
                    return {label: point.label, cost: point.value, tokens: point.value, currency: "USD"};
                })});
            });
        }
        function presentedSpendProviderCosts(items) {
            return ProviderOrder.orderedItems(items, providerOrderRaw);
        }
        function spendCurrency(items) {
            return CostCurrency.spendCurrency(items);
        }
        function spendTotalLine() {
            return "Synthetic local history";
        }
        function amountString(value) {
            return "$" + value.toFixed(2);
        }
        function usageCountText(value) {
            return value + " tokens";
        }
        function qualifiedCostValue(value) {
            return value;
        }
        function privateErrorText(text) {
            return privacyMode ? "Private scan failure" : text;
        }
        function providerDisplayTitle() {
            return "Codex";
        }
        function providerReadableColor() {
            return "blue";
        }
        function readableAccentColor(color) {
            return color;
        }
        function providerIconSource() {
            return "system-run-symbolic";
        }
        function providerIconIsMask() {
            return true;
        }
        function elapsedText() {
            return "just now";
        }
        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, alpha);
        }
        function canvasColor(color) {
            return String(color);
        }
        function refreshCost() {
            refreshes++;
        }
        function refreshSessions() {
            refreshes++;
        }
    }

    function createView(type) {
        var holder;
        try {
            holder = Qt.createQmlObject('import QtQuick; import org.kde.kirigami as Kirigami; ' + 'import "../contents/ui/components" as Components; ' + 'QtObject { property Component subject: Component { Components.' + type + ' { } } }', testCase, Qt.resolvedUrl("GlobalViewErrorsTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.[^"]+" is not installed/.test(String(error))) {
                skip("Global popup views need the optional KDE QML modules");
                return null;
            }
            throw error;
        }
        holders.push(holder);
        failOnWarning(/.*/);
        var view = createTemporaryObject(holders[holders.length - 1].subject, testCase, {
            applet: applet,
            width: width,
            height: height
        });
        verify(view !== null);
        var message = findItem(view, function (item) {
            return typeof item.plainText === "string" && item.plainText.indexOf(longError) >= 0;
        });
        if (message) {
            var label = findItem(message, function (item) {
                return item.font !== undefined && item.text === message.text;
            });
            verify(label !== null);
            label.font = Qt.font({
                pointSize: 24
            });
        }
        waitForRendering(view);
        return view;
    }

    function cleanup() {
        applet.dailyPoints = [];
        applet.costHistoryDays = 30;
        applet.costHistoryPeriod = "";
        applet.costHistoryMetric = "cost";
        applet.costs = [];
        applet.providerOrderRaw = "";
        applet.sessions = [];
        applet.costErrorText = "";
        applet.sessionsErrorText = "";
        applet.costLoading = false;
        applet.sessionsLoading = false;
        applet.privacyMode = false;
        applet.refreshes = 0;
    }

    function cleanupTestCase() {
        for (var holder of holders)
            holder.destroy();
    }

    function findItem(item, predicate) {
        if (predicate(item))
            return item;
        for (var child of item.children || []) {
            var found = findItem(child, predicate);
            if (found)
                return found;
        }
        return null;
    }

    function test_providerModelsExpandWithoutFilteringAndKeepFocus() {
        var rows = Array.from({length: 5}, function(_, index) {
            return {label: "Model " + index, cost: 5 - index, tokens: index + 1, currency: "USD"};
        });
        applet.costs = [{provider: "codex", models: rows, totals: {cost: 15, tokens: 15, currency: "USD"}}];
        var view = createView("SpendView");
        if (!view) return;
        var section = findChild(view, "analysisModels");
        verify(!section.expanded);
        var card = findChild(view, "analysisProviderToggle-codex");
        card.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(section.expanded);
        compare(view.selectedProvider, "");
        verify(card.activeFocus);
        verify(waitForPolish(view));
        compare(section.models.rows.length, 5);
        var more = findChild(section, "analysisModelsShowMore");
        verify(more.visible);
        compare(findItem(section, function(item) { return item.text === "Model 4"; }), null);
        more.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(section.showAll);
        verify(more.activeFocus);
        verify(findItem(section, function(item) { return item.text === "Model 4"; }) !== null);
        keyClick(Qt.Key_Space);
        verify(!section.showAll);
        verify(more.activeFocus);
        compare(findItem(section, function(item) { return item.text === "Model 4"; }), null);
        section.selectedDay = "2026-11-13";
        verify(!more.visible);
        verify(card.activeFocus);
        keyClick(Qt.Key_Space);
        verify(!section.visible);
        compare(view.selectedProvider, "");
    }

    function test_openProviderModelsFollowDayAndRefresh() {
        var daily = {label: "2026-11-13", cost: 2, tokens: 20, currency: "USD",
            models: [{label: "Day model", cost: 2, tokens: 20, currency: "USD"}]};
        var cost = {provider: "codex", currency: "USD", totals: daily, daily: [daily],
            models: [{label: "Period model", cost: 4, tokens: 40, currency: "USD"}]};
        applet.costs = [cost, {provider: "claude", totals: daily}];
        var view = createView("SpendView");
        if (!view) return;
        findChild(view, "analysisProviderToggle-codex").clicked();
        verify(findChild(view, "analysisProviderToggle-codex").checked);
        verify(!findChild(view, "analysisProviderToggle-claude").checked);
        compare(findChild(view, "analysisModels").models.rows[0].label, "Period model");
        findChild(view, "analysisHistoryChart").selectedIndex = 0;
        verify(findChild(view, "analysisProviderToggle-codex").checked);
        compare(findChild(view, "analysisModels").models.rows[0].label, "Day model");
        applet.costs = [Object.assign({}, cost, {daily: [Object.assign({}, daily, {models: []})]})];
        verify(findChild(view, "analysisProviderToggle-codex").checked);
        compare(findChild(view, "analysisModels").models.rows.length, 0);
        compare(view.selectedProvider, "");
    }

    function test_longErrorKeepsBodyReachable_data() {
        return [
            {
                tag: "spend-retained",
                type: "SpendView",
                retained: true
            },
            {
                tag: "spend-empty",
                type: "SpendView",
                retained: false
            },
            {
                tag: "sessions-retained",
                type: "SessionsView",
                retained: true
            },
            {
                tag: "sessions-empty",
                type: "SessionsView",
                retained: false
            }
        ];
    }

    function test_longErrorKeepsBodyReachable(data) {
        if (data.type === "SpendView") {
            applet.costErrorText = longError;
            applet.costs = data.retained ? [
                {
                    provider: "codex",
                    totals: {cost: 2, tokens: 100, currency: "USD"},
                    valueMode: "plain"
                }
            ] : [];
        } else {
            applet.sessionsErrorText = longError;
            applet.sessions = data.retained ? [
                {
                    provider: "codex",
                    projectName: "Synthetic project",
                    sessionName: "",
                    state: "active",
                    host: "",
                    source: "cli",
                    dialect: "",
                    activityMs: 1
                }
            ] : [];
        }
        var view = createView(data.type);
        if (!view)
            return;
        var scroll = findItem(view, function (item) {
            return item.objectName === (data.type === "SpendView" ? "spendHistoryScroll" : "sessionsBodyScroll");
        });
        verify(scroll !== null, "The body must remain scrollable without retained data");
        tryVerify(function () {
            return scroll.visible && scroll.height > 100;
        }, 1000, "Long errors must leave a usable body viewport; height=" + scroll.height);
        var position = scroll.mapToItem(view, 0, 0);
        verify(position.y >= 0 && position.y + scroll.height <= view.height + 1, "The body must fit inside the popup");
        var error = findItem(view, function (item) {
            return typeof item.plainText === "string" && item.plainText.indexOf(longError) >= 0;
        });
        verify(error !== null);
        tryVerify(function () {
            return scroll.contentItem.contentHeight > scroll.height;
        });
        var header = findItem(view, function (item) {
            return item.label === "Refresh sessions" || item.label === "Refresh local history";
        });
        verify(header !== null);
        var headerPosition = header.mapToItem(view, 0, 0);
        scroll.contentItem.contentY = scroll.contentItem.contentHeight - scroll.height;
        waitForRendering(view);
        compare(header.mapToItem(view, 0, 0).y, headerPosition.y);
        var refreshButton = findItem(header, function (item) {
            return typeof item.clicked === "function";
        });
        verify(refreshButton !== null);
        refreshButton.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.refreshes, 1);
        if (data.retained) {
            var text = data.type === "SpendView" ? "$2.00" : "Synthetic project";
            var row = findItem(view, function (item) {
                return item.text === text;
            });
            verify(row !== null);
            var rowPosition = row.mapToItem(scroll, 0, 0);
            verify(rowPosition.y >= 0 && rowPosition.y + row.height <= scroll.height + 1, "Retained data must be reachable by scrolling past the error");
        }
        applet.privacyMode = true;
        tryVerify(function () {
            return error.plainText.indexOf("Private scan failure") >= 0;
        });
        verify(error.plainText.indexOf(longError) < 0);
    }

    function test_emptyAndLoadingStates_data() {
        return [
            {
                tag: "spend",
                type: "SpendView",
                emptyText: "No local token or cost history"
            },
            {
                tag: "sessions",
                type: "SessionsView",
                emptyText: "No local agent sessions found"
            }
        ];
    }

    function test_emptyAndLoadingStates(data) {
        var view = createView(data.type);
        if (!view)
            return;
        var placeholder = findItem(view, function (item) {
            return item.plainText === data.emptyText;
        });
        verify(placeholder !== null);
        tryVerify(function () {
            return placeholder.visible && placeholder.height > 0;
        });
        var position = placeholder.mapToItem(view, 0, 0);
        verify(position.y > 0 && position.y + placeholder.height <= view.height + 1);
        if (data.type === "SpendView")
            applet.costLoading = true;
        else
            applet.sessionsLoading = true;
        tryCompare(placeholder, "visible", false);
        var spinner = findItem(view, function (item) {
            return item.running === true && item.visible && item.implicitHeight > 0;
        });
        verify(spinner !== null);
        tryVerify(function () {
            var point = spinner.mapToItem(view, 0, 0);
            return point.y > 0 && point.y + spinner.height <= view.height + 1;
        });
        if (data.type === "SpendView")
            applet.costLoading = false;
        else
            applet.sessionsLoading = false;
        tryCompare(placeholder, "visible", true);
    }

    function test_shortSessionStartsAtTop() {
        applet.sessions = [
            {
                provider: "codex",
                projectName: "Synthetic project",
                sessionName: "",
                state: "active",
                host: "",
                source: "cli",
                dialect: "",
                activityMs: 1
            }
        ];
        var view = createView("SessionsView");
        if (!view)
            return;
        var scroll = findChild(view, "sessionsBodyScroll");
        var card = findItem(view, function (item) {
            return item.activeSession !== undefined;
        });
        verify(scroll !== null && card !== null);
        tryCompare(card, "y", 0);
        verify(card.height < 100, "A short session must retain its content height");
    }

    function test_shortSpendKeepsContentHeight() {
        applet.costs = [
            {
                provider: "codex",
                totals: {cost: 2, tokens: 100, currency: "USD"},
                valueMode: "plain"
            }
        ];
        var view = createView("SpendView");
        if (!view)
            return;
        var scroll = findChild(view, "spendHistoryScroll");
        verify(scroll !== null);
        tryVerify(function () {
            return scroll.contentItem.contentHeight < scroll.availableHeight;
        }, 1000, "Short spend content must stay at its natural height");
        var value = findItem(view, function (item) {
            return item.text === "$2.00";
        });
        verify(value !== null);
        verify(value.mapToItem(scroll, 0, 0).y < scroll.availableHeight / 2, "Short provider totals must stay near the top of the body");
    }

    function test_selectionKeepsGeometryAndReturnsVisibleFocus() {
        applet.dailyPoints = [day("2026-10-16", 2), day("2026-10-17", 3)];
        var view = createView("SpendView");
        if (!view) return;
        var chart = findChild(view, "analysisHistoryChart");
        var y = chart.mapToItem(view, 0, 0).y;
        chart.focusPlot(Qt.TabFocusReason);
        keyClick(Qt.Key_End);
        verify(waitForPolish(view));
        compare(chart.mapToItem(view, 0, 0).y, y);
        var reset = findChild(view, "analysisAllDaysButton");
        reset.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(chart.selectedIndex, -1);
        verify(!reset.activeFocus);
        keyClick(Qt.Key_Home);
        compare(chart.selectedIndex, 0);
        keyClick(Qt.Key_Escape);
        compare(chart.selectedIndex, -1);
    }

    function test_assistantAndKeyboardUseOneScrollViewport() {
        applet.dailyPoints = [day("2026-10-16", 2), day("2026-10-17", 3)];
        var view = createView("SpendView");
        if (!view) return;
        var scroll = findChild(view, "spendHistoryScroll");
        var toggle = findChild(view, "analysisAssistantToggle");
        var height = scroll.height;
        toggle.forceActiveFocus(Qt.TabFocusReason);
        tryVerify(function() {
            var pos = toggle.mapToItem(scroll, 0, 0);
            return pos.y >= 0 && pos.y + toggle.height <= scroll.height + 1;
        });
        keyClick(Qt.Key_Space);
        verify(waitForPolish(view));
        compare(scroll.height, height);
        var assistant = findChild(view, "analysisAssistant");
        verify(assistant.answerExpanded);
        tryVerify(function() {
            var top = assistant.mapToItem(scroll, 0, 0).y;
            return top >= -1 && top + Math.min(assistant.height, scroll.height) <= scroll.height + 1;
        }, 1000, "Opening the assistant reveals its content after layout, not only its toggle: "
            + JSON.stringify({top: assistant.mapToItem(scroll, 0, 0).y, height: assistant.height,
                viewport: scroll.height, available: scroll.availableHeight, content: scroll.contentItem.contentHeight,
                offset: scroll.contentItem.contentY}));
    }

    function test_providerFilterRetainsVisibleFocusAfterRowRebuild() {
        applet.costs = [{provider: "codex", totals: {cost: 2, tokens: 10, currency: "USD"}},
            {provider: "claude", totals: {cost: 3, tokens: 20, currency: "USD"}}];
        var view = createView("SpendView");
        if (!view) return;
        var filter = findChild(view, "analysisProviderFilter");
        filter.forceActiveFocus(Qt.TabFocusReason);
        filter.activated(2);
        compare(view.selectedProvider, "claude");
        verify(findChild(view, "analysisProviderFilter").activeFocus);
        applet.costs = [applet.costs[0]];
        var empty = findItem(view, function(item) { return item.plainText === "No history for this provider"; });
        verify(empty !== null && empty.visible);
        empty.helpfulAction.trigger();
        compare(view.selectedProvider, "");
        verify(findChild(view, "analysisProviderFilter").activeFocus);
    }

    function test_providerFilterSurvivesRangeReplacement() {
        var codex = {provider: "codex", totals: {cost: 2, tokens: 100, currency: "USD"}, valueMode: "plain"};
        var claude = {provider: "claude", totals: {cost: 3, tokens: 200, currency: "USD"}, valueMode: "plain"};
        applet.costs = [codex, claude];
        var view = createView("SpendView");
        if (!view)
            return;
        var filter = findChild(view, "analysisProviderFilter");
        filter.activated(2);
        compare(view.selectedProvider, "claude");
        applet.costHistoryDays = 7;
        applet.costs = [];
        compare(view.selectedProvider, "claude");
        compare(filter.currentValue, "claude");
        compare(view.providerCosts.length, 0);
        applet.costs = [codex, claude];
        compare(view.providerCosts.length, 1);
        compare(view.providerCosts[0].provider, "claude");
        applet.costHistoryPeriod = "month-to-date";
        applet.costs = [codex];
        compare(filter.currentValue, "claude");
        compare(view.providerCosts.length, 0);
        filter.activated(0);
        compare(view.selectedProvider, "");
        compare(view.providerCosts.length, 1);
        compare(applet.refreshes, 0);
    }

    function test_providerPickKeepsComboInSyncWithDisclosureAndReset() {
        applet.costs = [{provider: "codex", totals: {cost: 2, tokens: 10, currency: "USD"}},
            {provider: "claude", totals: {cost: 3, tokens: 20, currency: "USD"}}];
        var view = createView("SpendView");
        if (!view) return;
        var filter = findChild(view, "analysisProviderFilter");
        filter.incrementCurrentIndex();
        filter.activated(filter.currentIndex);
        compare(view.selectedProvider, "codex");
        var card = findItem(view, function(item) { return item.modelData && item.modelData.provider === "codex" && item.checked !== undefined; });
        card.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(view.selectedProvider, "codex");
        compare(filter.currentIndex, 1);
        applet.costs = [applet.costs[1]];
        var empty = findItem(view, function(item) { return item.plainText === "No history for this provider"; });
        empty.helpfulAction.trigger();
        compare(view.selectedProvider, "");
        compare(filter.currentIndex, 0);
    }

    function test_providerFilterKeepsWidthAcrossAnalysisModes() {
        applet.costs = [{provider: "codex", totals: {cost: 2, tokens: 10, currency: "USD"}}];
        var view = createView("SpendView");
        if (!view) return;
        var filter = findChild(view, "analysisProviderFilter");
        var expand = findChild(view, "analysisExpandButton");
        view.width = 612;
        verify(waitForPolish(view));
        filter.activated(1);
        var compactWidth = filter.width;
        compare(filter.popup.width, compactWidth);
        expand.clicked();
        view.width = 900;
        verify(waitForPolish(view));
        compare(filter.width, compactWidth);
        compare(filter.popup.width, compactWidth);
        compare(view.selectedProvider, "codex");
        expand.clicked();
        view.width = 612;
        verify(waitForPolish(view));
        compare(filter.width, compactWidth);
        compare(filter.popup.width, compactWidth);
        view.width = 320;
        verify(waitForPolish(view));
        verify(filter.width <= view.width);
        compare(filter.popup.width, filter.width);
        compare(view.selectedProvider, "codex");
    }

    function test_providerOrderDoesNotChangeChartCurrency() {
        function cost(provider, currency, amount, tokens) {
            var day = {label: "2026-11-13", cost: amount, tokens: tokens, currency: currency};
            return {provider: provider, currency: currency, totals: day, daily: [day]};
        }
        applet.costs = [cost("claude", "USD", 3, 100), cost("codex", "EUR", 90, 200),
            cost("gemini", "USD", 7, 300)];
        applet.providerOrderRaw = "codex,gemini,claude";
        var view = createView("SpendView");
        if (!view) return;
        var chart = findItem(view, function(item) { return item.lineSeries !== undefined; });
        compare(view.spendCurrency, "USD");
        compare(view.dailyPoints[0].value, 10);
        compare(chart.lineSeries.map(function(series) { return series.provider; }), ["gemini", "claude"]);
        compare(chart.lineSeries.map(function(series) { return series.points[0].value; }), [7, 3]);
        verify(chart.axisLabels[0].indexOf("$") === 0);
        applet.providerOrderRaw = "claude,codex,gemini";
        compare(chart.lineSeries.map(function(series) { return series.provider; }), ["claude", "gemini"]);
        compare(view.dailyPoints[0].value, 10);
        applet.providerOrderRaw = "codex,gemini,claude";
        applet.costHistoryMetric = "tokens";
        compare(view.dailyPoints[0].value, 600);
        compare(chart.lineSeries.map(function(series) { return series.provider; }), ["codex", "gemini", "claude"]);
        compare(chart.lineSeries.map(function(series) { return series.points[0].value; }), [200, 300, 100]);
    }

    function spendChart(points) {
        applet.dailyPoints = points;
        var view = createView("SpendView");
        if (!view)
            return null;
        var chart = findItem(view, function (item) {
            return item.selectedIndex !== undefined && item.plotHeight !== undefined;
        });
        verify(chart !== null);
        return chart;
    }

    function day(label, value) {
        return { label: label, value: value, displayValue: "$" + value };
    }

    function test_spendSelectionFollowsDateAfterRefresh_data() {
        return [
            { tag: "same-days", points: [day("2026-10-16", 2), day("2026-10-17", 9)] },
            { tag: "older-day-arrives", points: [day("2026-10-15", 1), day("2026-10-16", 2), day("2026-10-17", 9)] },
            { tag: "older-day-expires", points: [day("2026-10-17", 9)] },
            { tag: "selected-day-disappears", points: [day("2026-10-16", 2), day("2026-10-18", 4)], missing: true },
            { tag: "selected-day-duplicated", points: [day("2026-10-16", 2), day("2026-10-17", 3), day("2026-10-17", 4)], missing: true },
            { tag: "empty-history", points: [], missing: true }
        ];
    }

    function test_spendSelectionFollowsDateAfterRefresh(data) {
        var chart = spendChart([day("2026-10-16", 2), day("2026-10-17", 3)]);
        if (!chart)
            return;
        chart.selectedIndex = 1;
        chart.hoveredIndex = 0;
        applet.dailyPoints = data.points;
        if (data.missing) {
            compare(chart.selectedIndex, -1);
        } else {
            verify(chart.selectedIndex >= 0);
            compare(chart.points[chart.selectedIndex].label, "2026-10-17");
            compare(chart.pointDisplayValue(chart.points[chart.selectedIndex]), "$9.00");
        }
        compare(chart.hoveredIndex, -1);
        compare(applet.refreshes, 0);
    }

    function test_spendContextChangeClearsSelection_data() {
        return [
            { tag: "metric", property: "costHistoryMetric", value: "tokens" },
            { tag: "days", property: "costHistoryDays", value: 7 },
            { tag: "period", property: "costHistoryPeriod", value: "month-to-date" }
        ];
    }

    function test_spendContextChangeClearsSelection(data) {
        var chart = spendChart([day("2026-10-16", 2), day("2026-10-17", 3)]);
        if (!chart)
            return;
        chart.selectedIndex = 1;
        chart.hoveredIndex = 0;
        applet[data.property] = data.value;
        compare(chart.selectedIndex, -1);
        compare(chart.hoveredIndex, -1);
        applet.dailyPoints = [day("2026-10-16", 2), day("2026-10-17", 9)];
        compare(chart.selectedIndex, -1);
        compare(applet.refreshes, 0);
    }

    function test_shortErrorStartsAtTop_data() {
        return [
            {
                tag: "spend",
                type: "SpendView"
            },
            {
                tag: "sessions",
                type: "SessionsView"
            }
        ];
    }

    function test_shortErrorStartsAtTop(data) {
        if (data.type === "SpendView")
            applet.costErrorText = "Synthetic short failure";
        else
            applet.sessionsErrorText = "Synthetic short failure";
        var view = createView(data.type);
        if (!view)
            return;
        var message = findItem(view, function (item) {
            return typeof item.plainText === "string" && item.plainText.indexOf("Synthetic short failure") >= 0;
        });
        verify(message !== null);
        tryCompare(message, "y", 0);
    }
}
