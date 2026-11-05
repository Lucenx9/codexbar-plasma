import QtQuick
import QtTest
import "../contents/ui/HeatmapNavigation.js" as Navigation

TestCase {
    name: "HeatmapNavigation"

    function days() {
        var cells = [];
        for (var i = 0; i < 21; i++)
            cells.push(i < 2 || i === 9 || i > 18 ? null : {label: "day-" + i});
        return cells;
    }

    function test_movementSkipsMissingDaysAndStaysSpatial() {
        var cells = days();
        compare(Navigation.nextDay(cells, "", "first", false), "day-2");
        compare(Navigation.nextDay(cells, "", "last", false), "day-18");
        compare(Navigation.nextDay(cells, "day-2", "right", false), "day-16");
        compare(Navigation.nextDay(cells, "day-16", "left", false), "day-2");
        compare(Navigation.nextDay(cells, "day-8", "down", false), "day-10");
        compare(Navigation.nextDay(cells, "day-10", "up", false), "day-8");
        compare(Navigation.nextDay(cells, "day-6", "down", false), "day-6");
        compare(Navigation.nextDay(cells, "day-7", "up", false), "day-7");
        compare(Navigation.nextDay(cells, "day-18", "right", false), "day-18");
        compare(Navigation.nextDay(cells, "day-18", "down", false), "day-18");
    }

    function test_mirroredColumns() {
        compare(Navigation.nextDay(days(), "day-2", "left", true), "day-16");
        compare(Navigation.nextDay(days(), "day-16", "right", true), "day-2");
        compare(Navigation.nextDay(days(), "day-8", "down", true), "day-10");
    }

    function test_dateIdentitySurvivesPaddingAndValueChanges() {
        var cells = days();
        compare(Navigation.indexForDay(cells, "day-10"), 10);
        cells.unshift(null);
        cells[11] = {label: "day-10", displayValue: "$99"};
        compare(Navigation.indexForDay(cells, "day-10"), 11);
        cells[11] = null;
        compare(Navigation.indexForDay(cells, "day-10"), -1);
    }

    function test_invalidAndEmptyInputs() {
        for (var cells of [null, {}, "days", [], [null, false, {}, {label: 5}], new Array(379)]) {
            compare(Navigation.nextDay(cells, "", "first", false), "");
            compare(Navigation.nextDay(cells, "", "last", false), "");
            compare(Navigation.indexForDay(cells, "day-2"), -1);
        }
        compare(Navigation.nextDay(days(), "day-2", "invalid", false), "day-2");
        for (var index of [-1, 1.5, Infinity, NaN, "2", 1000])
            compare(Navigation.dayAt(days(), index), "");
        compare(Navigation.indexForDay(days(), null), -1);
        compare(Navigation.nextDay([{label: "x".repeat(257)}], "", "first", false), "");
    }
}
