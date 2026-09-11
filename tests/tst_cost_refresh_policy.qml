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

    function test_bucketDayGroupsOneLocalDay() {
        var now = new Date()
        var evening = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 55, 0, 0).getTime()
        var night = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 0, 0).getTime()
        var morning = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 5, 0, 0).getTime()
        var nextMorning = evening + 10 * 60 * 1000
        compare(CostRefreshPolicy.bucketDayForMs(evening), CostRefreshPolicy.bucketDayForMs(night))
        verify(CostRefreshPolicy.bucketDayForMs(evening).length > 0)
        verify(CostRefreshPolicy.bucketDayForMs(morning).length > 0)
        verify(CostRefreshPolicy.bucketDayForMs(evening) !== CostRefreshPolicy.bucketDayForMs(nextMorning))
        compare(CostRefreshPolicy.bucketDayForMs(-1), "")
        compare(CostRefreshPolicy.bucketDayForMs(NaN), "")
    }

    function test_newBucketDayNeedsTwoValidDays() {
        var now = new Date()
        var evening = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 55, 0, 0).getTime()
        var nextMorning = evening + 10 * 60 * 1000
        verify(CostRefreshPolicy.isNewBucketDay(evening, nextMorning))
        verify(!CostRefreshPolicy.isNewBucketDay(evening, evening + 2 * 60 * 1000))
        verify(!CostRefreshPolicy.isNewBucketDay(-1, nextMorning))
        verify(!CostRefreshPolicy.isNewBucketDay(evening, NaN))
        verify(!CostRefreshPolicy.isNewBucketDay(nextMorning, evening))
    }

    function test_dayChangeRefreshesEvenWithinTheHour() {
        var now = new Date()
        var evening = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 55, 0, 0).getTime()
        var nextMorning = evening + 10 * 60 * 1000
        compare(CostRefreshPolicy.refreshAction(true, false, false, evening, nextMorning), "start")
    }

    function test_dayChangeNeverReplacesAnActiveScan() {
        var now = new Date()
        var evening = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 55, 0, 0).getTime()
        var nextMorning = evening + 10 * 60 * 1000
        compare(CostRefreshPolicy.refreshAction(true, true, false, evening, nextMorning), "keep")
        compare(CostRefreshPolicy.refreshAction(false, true, true, evening, nextMorning), "clear")
    }
}
