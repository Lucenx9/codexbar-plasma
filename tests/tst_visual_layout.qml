import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/UsageDetails.js" as UsageDetails

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
        property bool minimalPanel: false
        property bool quotaWarning: false
        property bool loading: false
        property bool expanded: false
        property string openedProvider: ""
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.85
        property var sessions: []
        property bool sessionsLoading: false
        property string sessionsLastUpdatedText: ""
        property string sessionsErrorText: "Loading sessions timed out. Try again."
        property string selectedAccount: ""
        property string selectedProviderID: "codex"
        property int providerToggleCount: 0
        property bool providerEnabled: false
        function isPending() {
            return false;
        }
        function visualEnabled() {
            return providerEnabled;
        }
        function setEnabled(providerID, enabled) {
            providerToggleCount++;
            providerEnabled = enabled;
        }
        property var accountItems: [
            {
                provider: "codex",
                account: "engineering-with-an-unusually-long-account-name@example.com",
                subtitle: "Workspace with a long display name for the example team"
            },
            {
                provider: "codex",
                account: "demo@example.com",
                subtitle: ""
            }
        ]
        function accountOptionsForProvider() {
            return accountItems;
        }
        function accountLoadingForProvider() {
            return false;
        }
        function accountErrorForProvider() {
            return "";
        }
        function selectedAccountForProvider() {
            return selectedAccount;
        }
        function accountLabel(item) {
            return item.account;
        }
        function accountSubtitle(item) {
            return item.subtitle;
        }
        function accountIsSelected(item) {
            return item.account === selectedAccount;
        }
        function selectAccount(providerID, label) {
            selectedAccount = label;
        }
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
        function panelDisplayRow(item, mode) {
            return item;
        }
        function displayPercent(row) {
            return row.value;
        }
        function quotaMeterColor(item, accent) {
            return quotaWarning ? Qt.rgba(1, 0.5, 0, 1) : accent;
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

    function init() {
        applet.minimalPanel = false;
        applet.quotaWarning = false;
        applet.verticalFormFactor = false;
    }

    function test_minimalPanelAppearance_data() {
        return [
            {tag: "small", extent: 32},
            {tag: "normal", extent: 44},
            {tag: "large", extent: 60}
        ];
    }

    function test_minimalPanelAppearance(data) {
        var panel = createControl("CompactRepresentation", {applet: applet, height: data.extent});
        if (!panel)
            return;
        wait(0);
        var standardBarHeight = panel.meterBarHeight;
        var standardIconSize = panel.meterIconSize;
        var icon = findItem(panel, item => item.objectName === "panelProviderIcon");
        var track = findItem(panel, item => item.objectName === "panelMeterTrack");
        var fill = findItem(panel, item => item.objectName === "panelMeterFill");
        verify(icon !== null && track !== null && fill !== null);
        var brandColor = icon.color.toString();
        applet.minimalPanel = true;
        tryCompare(panel, "minimalStyle", true);
        verify(panel.meterBarHeight <= standardBarHeight);
        verify(panel.meterIconSize <= 22);
        verify(panel.meterWidth >= 36);
        verify(icon.isMask);
        verify(icon.color.toString() !== brandColor);
        tryVerify(() => track.width <= panel.meterWidth);
        // Presentation must still defer to the same semantic warning color.
        applet.quotaWarning = true;
        tryCompare(fill, "color", Qt.rgba(1, 0.5, 0, 1));
        verify(icon.color.toString() !== fill.color.toString());
        applet.minimalPanel = false;
        tryCompare(panel, "meterBarHeight", standardBarHeight);
        compare(panel.meterIconSize, standardIconSize);
        compare(icon.color.toString(), brandColor);
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

    function test_longAccountButtonsFitAndKeepFullAccessibleNames_data() {
        return [
            {
                tag: "narrow",
                width: 240
            },
            {
                tag: "popup",
                width: 540
            }
        ];
    }

    function test_longAccountButtonsFitAndKeepFullAccessibleNames(data) {
        applet.selectedAccount = "";
        var view = createControl("ProviderAccountsPanel", {
            applet: applet,
            providerData: {
                provider: "codex"
            },
            width: data.width
        });
        if (!view)
            return;
        wait(0);
        var button = findItem(view, function (item) {
            return item.checkable && item.Accessible.name.indexOf("engineering-") === 0;
        });
        verify(button !== null);
        verify(button.width > 0);
        verify(button.mapToItem(view, button.width, 0).x <= view.width);
        var fullLabel = applet.accountItems[0].account + " · " + applet.accountItems[0].subtitle;
        compare(button.Accessible.name, fullLabel);
        verify(button.plainText.length < fullLabel.length);
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.selectedAccount, applet.accountItems[0].account);
        compare(button.checked, true);
        applet.selectedAccount = applet.accountItems[1].account;
        tryCompare(button, "checked", false);
        testCase.forceActiveFocus();
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

    function test_providerRowKeyboardSelectionDoesNotToggleEnablement() {
        applet.selectedProviderID = "codex";
        applet.providerToggleCount = 0;
        applet.providerEnabled = false;
        var row = createControl("ProviderConfigRow", {
            configPage: applet,
            modelData: {
                provider: "gemini",
                displayName: "Gemini",
                enabled: false,
                defaultEnabled: false
            },
            width: 300
        });
        if (!row)
            return;
        verify(row.activeFocusOnTab);
        compare(row.Accessible.name, "Gemini");
        row.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.selectedProviderID, "gemini");
        compare(applet.providerToggleCount, 0);
        var toggle = row.nextItemInFocusChain(true);
        verify(toggle !== row);
        toggle.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.providerToggleCount, 1);
        compare(applet.providerEnabled, true);
    }

    function test_providerMetersSupportKeyboardAndPointer_data() {
        return [{tag: "standard", minimal: false}, {tag: "minimal", minimal: true}];
    }

    function test_minimalVerticalPanelKeepsIdentityAndIncident() {
        applet.minimalPanel = true;
        applet.verticalFormFactor = true;
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel)
            return;
        wait(0);
        compare(panel.width, panel.compactExtent);
        verify(panel.showPrimaryIdentity);
        var dot = findItem(panel, item => item.visible && item.color !== undefined
            && item.color.toString() === "#ff8000");
        verify(dot !== null);
        compare(dot.width, dot.height);
        var meter = findItem(panel, item => item.activeFocusOnTab && typeof item.activate === "function");
        verify(meter === null || !meter.visible);
    }

    function test_providerMetersSupportKeyboardAndPointer(data) {
        applet.minimalPanel = data.minimal;
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
        tryVerify(function () {
            return value.width > 0 && value.mapToItem(chart, value.width, 0).x <= chart.width && plot.width <= chart.width;
        });
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

    function test_providerDetailValuesStayWithinPopup_data() {
        return [
            { tag: "primary-narrow", field: "value", width: 240 },
            { tag: "primary-popup", field: "value", width: 540 },
            { tag: "secondary-narrow", field: "secondaryValue", width: 240 },
            { tag: "secondary-popup", field: "secondaryValue", width: 540 },
            { tag: "unit-narrow", field: "unit", width: 240 },
            { tag: "unit-popup", field: "unit", width: 540 },
            { tag: "short-values", field: "", width: 540 }
        ];
    }

    function test_providerDetailValuesStayWithinPopup(data) {
        var longValue = "LongModelName".repeat(10).slice(0, 120);
        var rawSection = {
            title: "Details",
            rows: [{ label: "Model", value: "42", secondaryValue: "Included" }],
            chart: { kind: "line", title: "Daily usage", unit: "tokens", points: [] }
        };
        if (data.field === "unit")
            rawSection.chart.unit = longValue;
        else if (data.field.length > 0)
            rawSection.rows[0][data.field] = longValue;
        var section = UsageDetails.normalizeSections([rawSection])[0];
        var view = createControl("ProviderDetailSection", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: section,
            width: data.width
        });
        if (!view)
            return;
        wait(0);
        var expectedTexts = [section.rows[0].label, section.rows[0].value,
            section.rows[0].secondaryValue, section.chart.title, section.chart.unit];
        for (var i = 0; i < expectedTexts.length; i++) {
            var expectedText = expectedTexts[i];
            var label = findItem(view, function (item) {
                return item.visible && item.text === expectedText;
            });
            verify(label !== null, "Missing detail text: " + expectedText);
            verify(label.width > 0, "Detail text has no available width");
            verify(label.mapToItem(view, 0, 0).x >= 0);
            verify(label.mapToItem(view, label.width, 0).x <= view.width + 1,
                "Detail text overflows the popup: " + expectedText);
            if (expectedText !== longValue)
                verify(label.width + 1 >= label.implicitWidth,
                    "A long value hides its short label");
        }
    }
}
