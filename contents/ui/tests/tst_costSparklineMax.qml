import QtQuick 2.15
import QtTest 1.0
import "../Logic.js" as Logic

TestCase {
    name: "CostSparklineMaxTests"

    function test_costSparklineMax_null() {
        compare(Logic.costSparklineMax(null), 0, "Null points should return 0")
    }

    function test_costSparklineMax_empty() {
        compare(Logic.costSparklineMax([]), 0, "Empty points should return 0")
    }

    function test_costSparklineMax_single() {
        var points = [{cost: 1.5}]
        compare(Logic.costSparklineMax(points), 1.5, "Single point should return its cost")
    }

    function test_costSparklineMax_multiple() {
        var points = [{cost: 1.5}, {cost: 3.2}, {cost: 2.1}]
        compare(Logic.costSparklineMax(points), 3.2, "Multiple points should return max cost")
    }

    function test_costSparklineMax_withStrings() {
        var points = [{cost: "1.5"}, {cost: "3.2"}, {cost: "2.1"}]
        compare(Logic.costSparklineMax(points), 3.2, "String costs should be parsed and max returned")
    }

    function test_costSparklineMax_withInvalidNumbers() {
        var points = [{cost: "invalid"}, {cost: 3.2}, {cost: null}]
        compare(Logic.costSparklineMax(points), 3.2, "Invalid costs should be treated as 0")
    }

    function test_costSparklineMax_allInvalid() {
        var points = [{cost: "invalid"}, {cost: null}]
        compare(Logic.costSparklineMax(points), 0, "All invalid costs should return 0")
    }
}
