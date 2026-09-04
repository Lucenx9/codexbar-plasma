import QtQuick
import QtTest

TestCase {
    name: "InteractiveChart"
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
}
