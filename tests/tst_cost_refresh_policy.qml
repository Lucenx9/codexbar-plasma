import QtQuick
import QtTest
import "../contents/ui/CostRefreshPolicy.js" as CostRefreshPolicy

TestCase {
    name: "CostRefreshPolicy"

    readonly property double hourMs: 60 * 60 * 1000

    function test_missingCommandClearsEvenForAForcedRefresh() {
        compare(CostRefreshPolicy.refreshAction(false, true, true, 0, hourMs), "clear")
    }

    function test_firstAutomaticRefreshStartsImmediately() {
        compare(CostRefreshPolicy.refreshAction(true, false, false, -1, 0), "start")
    }

    function test_automaticRefreshWaitsForTheHourlyBoundary() {
        compare(CostRefreshPolicy.refreshAction(true, false, false, 0, hourMs - 1), "keep")
        compare(CostRefreshPolicy.refreshAction(true, false, false, 0, hourMs), "start")
    }

    function test_automaticRefreshNeverReplacesAnActiveScan() {
        compare(CostRefreshPolicy.refreshAction(true, true, false, 0, hourMs), "keep")
    }

    function test_forcedRefreshMayReplaceAnActiveScan() {
        compare(CostRefreshPolicy.refreshAction(true, true, true, 0, 1), "start")
    }

    function test_clockRollbackReestablishesTheHourlyBaseline() {
        compare(CostRefreshPolicy.refreshAction(true, false, false, hourMs, 0), "start")
    }

    function test_invalidClockKeepsTheCurrentState() {
        compare(CostRefreshPolicy.refreshAction(true, false, false, 0, NaN), "keep")
    }
}
