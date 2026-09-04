import QtQuick
import QtTest
import "../contents/ui/ChartScale.js" as ChartScale

TestCase {
    name: "ChartScale"

    function test_signedBarsStartAtZeroAndExtendInTheirOwnDirection() {
        var domain = ChartScale.domain([
            {
                value: -3
            },
            {
                value: 9
            }
        ])
        var negative = ChartScale.barGeometry(103, -3, domain)
        var positive = ChartScale.barGeometry(103, 9, domain)

        compare(negative.baseline, 77)
        compare(negative.height, 25)
        compare(negative.negative, true)
        compare(positive.baseline, 77)
        compare(positive.height, 75)
        compare(positive.negative, false)
    }

    function test_nonnegativeChartsKeepTheirExistingScale() {
        var domain = ChartScale.domain([
            {
                value: 0
            },
            {
                value: 3
            },
            {
                value: 9
            }
        ])
        compare(domain.minimum, 0)
        compare(ChartScale.fraction(0, domain), 0)
        compare(ChartScale.fraction(9, domain), 1)
        compare(ChartScale.barGeometry(103, 9, domain).baseline, 102)
        compare(ChartScale.barGeometry(103, 9, domain).height, 100)
        compare(ChartScale.barGeometry(103, 0, domain).height, 1)
        compare(ChartScale.barGeometry(103, 0.01, domain).height, 2)
    }

    function test_negativeOnlyChartsKeepZeroAtTheTop() {
        var domain = ChartScale.domain([
            {
                value: -3
            },
            {
                value: -9
            }
        ])
        compare(domain.minimum, -9)
        compare(domain.maximum, 0)
        compare(ChartScale.fraction(-9, domain), 0)
        compare(ChartScale.fraction(0, domain), 1)
        compare(ChartScale.barGeometry(103, -9, domain).baseline, 2)
        compare(ChartScale.barGeometry(103, -9, domain).height, 100)
    }

    function test_finiteSignedExtremesDoNotOverflowTheScale() {
        var domain = ChartScale.domain([
            {
                value: -Number.MAX_VALUE
            },
            {
                value: Number.MAX_VALUE
            }
        ])
        compare(ChartScale.fraction(-Number.MAX_VALUE, domain), 0)
        compare(ChartScale.fraction(0, domain), 0.5)
        compare(ChartScale.fraction(Number.MAX_VALUE, domain), 1)
        compare(ChartScale.barGeometry(103, -Number.MAX_VALUE, domain).height, 50)
    }

    function test_emptyAndZeroChartsHaveFiniteGeometry() {
        var domain = ChartScale.domain([])
        compare(domain.minimum, 0)
        compare(domain.maximum, 0)
        compare(ChartScale.fraction(0, domain), 0)
        compare(ChartScale.barGeometry(0, 0, domain).height, 0)
        compare(ChartScale.barGeometry(0, 0, domain).baseline, 0)
        compare(ChartScale.pointValue({
            value: NaN
        }), 0)
        compare(ChartScale.pointValue({
            value: Infinity
        }), 0)
        compare(ChartScale.pointValue(null), 0)
    }
}
