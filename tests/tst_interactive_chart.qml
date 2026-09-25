import QtQuick
import QtTest

TestCase {
    name: "InteractiveChart"
    when: windowShown
    width: 340
    height: 240
    visible: true
    property var componentHolders: []

    function cleanupTestCase() {
        for (var i = 0; i < componentHolders.length; i++) {
            componentHolders[i].destroy()
        }
    }

    function createChart(properties) {
        var component
        try {
            var holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; ' + 'QtObject { property Component chartComponent: Component {' + ' Components.InteractiveChart { function i18n(text) { return text } } } }', this, Qt.resolvedUrl("InteractiveChartTest.qml"))
            component = holder.chartComponent
            componentHolders.push(holder)
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("InteractiveChart needs the optional KDE QML modules")
                return null
            }
            throw error
        }
        var chart = createTemporaryObject(component, this, properties)
        verify(chart !== null)
        return chart
    }

    function test_firstInspectionKeepsPlotGeometry_data() {
        return [{tag: "hover", keyboard: false}, {tag: "keyboard", keyboard: true}]
    }

    function test_firstInspectionKeepsPlotGeometry(data) {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300,
            points: [{label: "First", value: 0}],
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        var plot = chart.nextItemInFocusChain(true)
        verify(typeof plot.requestPaint === "function")
        verify(waitForRendering(chart))
        var initialY = plot.y
        var initialHeight = chart.implicitHeight
        compare(chart.readoutIndex, -1)
        if (data.keyboard) {
            plot.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Home)
        } else {
            mouseMove(plot, plot.width / 2, plot.height / 2)
        }
        compare(chart.readoutIndex, 0)
        verify(waitForRendering(chart))
        compare(plot.y, initialY)
        compare(chart.implicitHeight, initialHeight)
        mouseMove(this, 330, 230)
        chart.selectedIndex = -1
        verify(waitForRendering(chart))
        compare(plot.y, initialY)
        chart.points = []
        verify(waitForRendering(chart))
        compare(plot.y, initialY)
    }

    // CLI calendar keys read as local dates in the system locale. The key is a
    // calendar day, not an instant, so a zone west of UTC must not show the
    // previous day. Other labels stay as the CLI wrote them.
    function test_calendarKeysUseTheLocaleShortDate() {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300,
            points: [{label: "2026-08-25", value: 1}],
            accent: "blue"
        })
        if (!chart)
            return
        var expected = new Date(2026, 7, 25).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
        compare(chart.pointLabel({label: "2026-08-25"}), expected)
        verify(expected.indexOf("25") >= 0)
        compare(chart.pointLabel({label: "Week 34"}), "Week 34")
        compare(chart.pointLabel({label: "2026-02-30"}), "2026-02-30")
        compare(chart.pointLabel({label: "2026-08-25T10:00:00Z"}), "2026-08-25T10:00:00Z")
        compare(chart.pointLabel(null), "")
    }

    function test_readoutPreservesNegativeDetailValues() {
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7
            },
            points: [
                {
                    label: "Adjustment",
                    value: -3
                }
            ],
            accent: "blue",
            valueSuffix: "credits"
        })
        if (!chart)
            return
        verify(chart !== null)
        compare(chart.pointDisplayValue(chart.points[0]), "-3 credits")
    }

    function test_signedPointsHaveSeparatePositionsAroundZero() {
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7
            },
            points: [
                {
                    value: -3
                },
                {
                    value: 0
                },
                {
                    value: 9
                }
            ],
            accent: "blue"
        })
        if (!chart)
            return
        compare(chart.chartFraction(-3), 0)
        compare(chart.chartFraction(0), 0.25)
        compare(chart.chartFraction(9), 1)
    }

    function test_missingPointsClearSelectionAndRecover_data() {
        return [{ tag: "null", value: null }, { tag: "undefined", value: undefined }]
    }

    function test_missingPointsClearSelectionAndRecover(data) {
        var chart = createChart({
            applet: { secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" } },
            width: 300,
            points: [{ label: "Before", value: 0 }],
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        compare(chart.pointCount, 1)
        chart.selectedIndex = 0
        chart.hoveredIndex = 0
        var plot = chart.nextItemInFocusChain(true)
        verify(typeof plot.requestPaint === "function")
        plot.forceActiveFocus(Qt.TabFocusReason)
        chart.points = data.value
        compare(chart.selectedIndex, -1)
        compare(chart.hoveredIndex, -1)
        compare(chart.hasActivePoint, false)
        compare(chart.indexAt(10), -1)
        for (var key of [Qt.Key_Left, Qt.Key_Right, Qt.Key_Home, Qt.Key_End]) {
            keyClick(key)
            compare(chart.selectedIndex, -1)
        }
        waitForRendering(plot)
        chart.points = [{ label: "After", value: 0 }]
        keyClick(Qt.Key_Home)
        compare(chart.selectedIndex, 0)
        compare(chart.hasActivePoint, true)
        compare(chart.pointLabel(chart.points[chart.activeIndex]), "After")
        waitForRendering(plot)
    }

    // A line chart plots through the applet's line geometry, not the bar
    // path: usage detail sections feed kind "line" from the CLI payload.
    function test_lineKindPlotsThroughLineGeometry() {
        var calls = { line: 0, bar: 0 };
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7,
                canvasColor: function() { return "#000000"; },
                chartLineX: function(width, count, index, inset) { calls.line++; return index * 10; },
                chartLineY: function(height, fraction, inset) { return height * (1 - fraction); },
                chartBarGeometry: function() { calls.bar++; return { offset: 0, step: 10, barWidth: 8 }; },
                buildChartBarGradient: function() { return "#000000"; },
                paintRoundedTopBar: function() {}
            },
            width: 300,
            points: [{ label: "First", value: 1 }, { label: "Last", value: 2 }],
            accent: "blue",
            kind: "line"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        verify(waitForRendering(chart))
        // One render pass is not guaranteed to have painted the canvas when the
        // runner shares a process with the rest of the suite, so wait for the
        // line geometry to actually be asked for rather than assuming it was.
        tryVerify(function() { return calls.line > 0 })
        compare(calls.bar, 0)
    }

    // The plot stays in the tab chain so keyboard inspection needs no mouse.
    function test_plotIsReachableByTab() {
        var chart = createChart({
            applet: { secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" } },
            width: 300,
            points: [{ label: "First", value: 0 }],
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        var plot = chart.nextItemInFocusChain(true)
        verify(typeof plot.requestPaint === "function")
        verify(waitForRendering(chart))
        verify(!plot.activeFocus)
        chart.forceActiveFocus()
        verify(chart.activeFocus)
        keyClick(Qt.Key_Tab)
        verify(plot.activeFocus)
    }

    function test_keyboardSelectionOverridesStationaryPointer_data() {
        return [
            { tag: "left", key: Qt.Key_Left, hovered: 2, selected: 0 },
            { tag: "right", key: Qt.Key_Right, hovered: 0, selected: 2 },
            { tag: "home", key: Qt.Key_Home, hovered: 2, selected: 0 },
            { tag: "end", key: Qt.Key_End, hovered: 0, selected: 2 }
        ]
    }

    function test_keyboardSelectionOverridesStationaryPointer(data) {
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7,
                canvasColor: function() { return "#000000" }
            },
            width: 300,
            points: [
                { label: "First", value: 0 },
                { label: "Middle", value: 0 },
                { label: "Last", value: 0 }
            ],
            accent: "blue",
            selectedIndex: 1
        })
        if (!chart)
            return
        var plot = chart.nextItemInFocusChain(true)
        verify(typeof plot.requestPaint === "function")
        mouseMove(plot, (data.hovered + 0.5) * plot.width / 3, plot.height / 2)
        compare(chart.activeIndex, data.hovered)
        plot.forceActiveFocus(Qt.TabFocusReason)
        keyClick(data.key)
        compare(chart.selectedIndex, data.selected)
        compare(chart.activeIndex, data.selected)
        mouseMove(plot, plot.width / 2, plot.height / 2)
        compare(chart.activeIndex, 1)
        mouseMove(this, 330, 230)
        tryCompare(chart, "hoveredIndex", -1)
        compare(chart.activeIndex, data.selected)
    }
}
