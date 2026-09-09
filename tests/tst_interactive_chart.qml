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
