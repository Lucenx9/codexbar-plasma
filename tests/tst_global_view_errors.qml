import QtQuick
import QtTest

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

    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    QtObject {
        id: applet
        property bool privacyMode: false
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.8
        property real nestedSurfaceRadius: 4
        property bool costLoading: false
        property string costErrorText: ""
        property int costHistoryDays: 30
        property string costHistoryPeriod: ""
        property string costHistoryMetric: "cost"
        property bool costHistoryShowsTokens: false
        property var costs: []
        property var sessions: []
        readonly property var presentedSessions: sessions
        property bool sessionsLoading: false
        property string sessionsErrorText: ""
        property string sessionsLastUpdatedText: "Updated just now"
        property bool sessionHostsVary: false
        property int refreshes: 0

        function spendDailyPoints() {
            return [];
        }
        function spendProviderCosts() {
            return costs;
        }
        function presentedSpendProviderCosts(items) {
            return items;
        }
        function spendCurrency() {
            return "USD";
        }
        function spendTotalLine() {
            return "Synthetic local history";
        }
        function spendHistoryStillBuilding() {
            return false;
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
        applet.costs = [];
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
                    windowValueLine: "$2.00"
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
            return item.contentItem && item.contentItem.contentY !== undefined;
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
                windowValueLine: "$2.00"
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
