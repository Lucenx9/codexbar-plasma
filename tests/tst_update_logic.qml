import QtQuick
import QtTest
import "../contents/ui/UpdateLogic.js" as UpdateLogic

TestCase {
    name: "UpdateLogic"

    readonly property double nowMs: Date.UTC(2026, 6, 31, 12, 0, 0)

    function test_disabledChecksStayDisabledWhenForced() {
        compare(UpdateLogic.updateCheckDue(false, "", 12, nowMs, true), false)
    }

    function test_missingTimestampIsDue() {
        compare(UpdateLogic.updateCheckDue(true, "", 12, nowMs, false), true)
    }

    function test_recentTimestampIsNotDue() {
        var recent = new Date(nowMs - 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, recent, 12, nowMs, false), false)
    }

    function test_forcedCheckIgnoresRecentTimestamp() {
        var recent = new Date(nowMs - 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, recent, 12, nowMs, true), true)
    }

    function test_staleTimestampIsDue() {
        var stale = new Date(nowMs - 13 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, stale, 12, nowMs, false), true)
    }

    function test_nextDelayUsesRemainingInterval() {
        var recent = new Date(nowMs - 11 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.nextUpdateCheckDelay(true, recent, 12, nowMs, 60000), 60 * 60 * 1000)
    }

    function test_nextDelayRunsSoonWhenAlreadyDueOrMissing() {
        var stale = new Date(nowMs - 13 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.nextUpdateCheckDelay(true, stale, 12, nowMs, 60000), 60000)
        compare(UpdateLogic.nextUpdateCheckDelay(true, "", 12, nowMs, 60000), 60000)
    }

    function test_nextDelayDoesNotExceedConfiguredIntervalAfterClockSkew() {
        var future = new Date(nowMs + 24 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.nextUpdateCheckDelay(true, future, 12, nowMs, 60000), 12 * 60 * 60 * 1000)
    }

    function test_nextDelayIsZeroWhenChecksAreDisabled() {
        compare(UpdateLogic.nextUpdateCheckDelay(false, "", 12, nowMs, 60000), 0)
    }
}
