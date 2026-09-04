import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation

TestCase {
    id: testCase
    name: "VisualLayout"
    when: windowShown
    width: 620
    height: 240
    visible: true
    property var holders: []

    QtObject {
        id: applet
        property bool verticalFormFactor: false
        property bool loading: false
        property bool expanded: false
        property string openedProvider: ""
        property real secondaryTextOpacity: 0.7
        property var sessions: []
        property bool sessionsLoading: false
        property string sessionsLastUpdatedText: ""
        property string sessionsErrorText: "Loading sessions timed out. Try again."
        function refreshSessions() {
        }
        function panelElementOrder() {
            return ["identity", "status", "text", "meters"];
        }
        function compactText() {
            return "A long provider name with 57% remaining";
        }
        function compactProviders() {
            return [
                {
                    provider: "codex",
                    title: "Codex",
                    value: 57
                },
                {
                    provider: "claude",
                    title: "Claude",
                    value: 0
                }
            ];
        }
        function selectedCompactProvider() {
            return {
                provider: "codex"
            };
        }
        function primaryIncidentProvider() {
            return {
                hasIncident: true,
                statusSeverity: "minor",
                title: "Codex",
                status: "Degraded"
            };
        }
        function providerIconSource() {
            return "view-statistics";
        }
        function providerIconIsMask() {
            return true;
        }
        function providerReadableColor() {
            return Qt.rgba(0.2, 0.6, 0.7, 1);
        }
        function statusBadgeColor() {
            return Qt.rgba(1, 0.5, 0, 1);
        }
        function switcherPercent(item) {
            return item.value;
        }
        function switcherMetricRow(item) {
            return item;
        }
        function quotaMeterColor(item, accent) {
            return accent;
        }
        function withAlpha(c, a) {
            return Qt.rgba(c.r, c.g, c.b, a);
        }
        function openProviderFromPanel(id) {
            openedProvider = id;
        }
        function canvasColor(c, a) {
            return Qt.rgba(c.r, c.g, c.b, a).toString();
        }
        function chartLineX(w, n, i, inset) {
            return CostPresentation.chartLineX(w, n, i, inset);
        }
        function chartLineIndexAt(w, n, x, inset) {
            return CostPresentation.chartLineIndexAt(w, n, x, inset);
        }
        function chartLineY(h, v, inset) {
            return CostPresentation.chartLineY(h, v, inset);
        }
        function chartBarGeometry(w, n) {
            return CostPresentation.chartBarGeometry(w, n);
        }
        function paintRoundedTopBar(ctx, x, y, w, h, r) {
            CostPresentation.paintRoundedTopBar(ctx, x, y, w, h, r);
        }
        function buildChartBarGradient(ctx, c, y, a, b) {
            var gradient = ctx.createLinearGradient(0, 0, 0, Math.max(1, y));
            gradient.addColorStop(0, canvasColor(c, a));
            gradient.addColorStop(1, canvasColor(c, b));
            return gradient;
        }
    }

    function createControl(type, properties) {
        var holder;
        try {
            holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component control: Component { Components.' + type + ' { function i18n(text) { return text } function i18np(one, many, count) { return count === 1 ? one : many } } } }', testCase, Qt.resolvedUrl("VisualLayoutTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("Visual layout checks need the optional KDE QML modules");
                return null;
            }
            throw error;
        }
        holders.push(holder);
        return createTemporaryObject(holder.control, testCase, properties);
    }

    function cleanupTestCase() {
        for (var i = 0; i < holders.length; i++)
            holders[i].destroy();
    }

    function findItem(item, predicate) {
        if (predicate(item))
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findItem(children[i], predicate);
            if (found)
                return found;
        }
        return null;
    }

    function test_sessionFeedbackKeepsHeadingAtTop_data() {
        return [
            {
                tag: "error",
                loading: false,
                errorText: "Loading sessions timed out. Try again."
            },
            {
                tag: "empty",
                loading: false,
                errorText: ""
            },
            {
                tag: "loading",
                loading: true,
                errorText: ""
            }
        ];
    }

    function test_sessionFeedbackKeepsHeadingAtTop(data) {
        applet.sessionsErrorText = data.errorText;
        applet.sessionsLoading = data.loading;
        var view = createControl("SessionsView", {
            applet: applet,
            width: 540,
            height: 300
        });
        if (!view)
            return;
        wait(0);
        var heading = findItem(view, function (item) {
            return item.text === "Sessions";
        });
        verify(heading !== null);
        verify(heading.mapToItem(view, 0, 0).y < 40);
        if (data.errorText.length > 0) {
            var error = findItem(view, function (item) {
                return item.visible && item.plainText === applet.sessionsErrorText;
            });
            verify(error !== null);
            verify(error.mapToItem(view, 0, 0).y < 100);
        } else if (!data.loading) {
            var placeholder = findItem(view, function (item) {
                return item.visible && item.plainText === "No local agent sessions found.";
            });
            verify(placeholder !== null);
            compare(placeholder.height, placeholder.implicitHeight);
        }
    }

    function test_statusDotStaysSquare_data() {
        return [
            {
                tag: "24px",
                extent: 24
            },
            {
                tag: "32px",
                extent: 32
            },
            {
                tag: "48px",
                extent: 48
            }
        ];
    }

    function test_statusDotStaysSquare(data) {
        var panel = createControl("CompactRepresentation", {
            applet: applet,
            height: data.extent
        });
        if (!panel)
            return;
        wait(0);
        var dot = findItem(panel, function (item) {
            return item.visible && item.color !== undefined && item.color.toString() === "#ff8000";
        });
        verify(dot !== null);
        verify(dot.width > 0);
        compare(dot.width, dot.height);
        var center = dot.mapToItem(panel, dot.width / 2, dot.height / 2);
        verify(Math.abs(center.y - panel.height / 2) < 1);
    }

    function test_providerMetersSupportKeyboardAndPointer() {
        applet.openedProvider = "";
        applet.expanded = false;
        var panel = createControl("CompactRepresentation", {
            applet: applet,
            height: 32
        });
        if (!panel)
            return;
        wait(0);
        var meter = findItem(panel, function (item) {
            return item.activeFocusOnTab && typeof item.activate === "function";
        });
        verify(meter !== null);
        meter.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.openedProvider, "codex");
        applet.openedProvider = "";
        mouseClick(meter, meter.width / 2, meter.height / 2);
        compare(applet.openedProvider, "codex");
        compare(applet.expanded, false);
    }

    function test_longChartReadoutFitsAndKeysInspectPoints() {
        var chart = createControl("InteractiveChart", {
            applet: applet,
            width: 240,
            accent: "blue",
            points: [
                {
                    label: "First",
                    value: -1
                },
                {
                    label: "Final point with a long display label",
                    value: 1e300,
                    displayValue: "An unusually long value that must not push the chart beyond its assigned width"
                }
            ]
        });
        if (!chart)
            return;
        var plot = findItem(chart, function (item) {
            return typeof item.requestPaint === "function";
        });
        verify(plot !== null);
        plot.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_End);
        compare(chart.selectedIndex, 1);
        wait(0);
        var value = findItem(chart, function (item) {
            return item.text === chart.points[1].displayValue;
        });
        verify(value !== null);
        verify(value.width > 0);
        verify(value.mapToItem(chart, value.width, 0).x <= chart.width);
        verify(plot.width <= chart.width);
        keyClick(Qt.Key_Left);
        compare(chart.selectedIndex, 0);
        mouseMove(plot, plot.width - 1, plot.height / 2);
        compare(chart.hoveredIndex, 1);
        mouseMove(testCase, 600, 220);
        tryCompare(chart, "hoveredIndex", -1);
        chart.points = [];
        tryCompare(chart, "selectedIndex", -1);
        keyClick(Qt.Key_End);
        compare(chart.selectedIndex, -1);
    }
}
