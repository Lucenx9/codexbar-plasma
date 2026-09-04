import QtQuick
import QtTest
import "../contents/ui/SessionRefreshPolicy.js" as SessionRefreshPolicy

TestCase {
    name: "SessionRefreshPolicy"

    function observation(overrides) {
        var result = {
            commandSource: "codexbar sessions --json-v2",
            loadedCommandSource: "",
            loading: false,
            visible: true,
            force: false,
            lastCompletedAtMs: -1,
            nowMs: 1000000,
            staleAfterMs: 300000
        }
        var values = overrides || ({})
        for (var key in values) {
            if (Object.prototype.hasOwnProperty.call(values, key)) {
                result[key] = values[key]
            }
        }
        return result
    }

    function test_firstVisibleEntryStarts() {
        compare(SessionRefreshPolicy.refreshAction(observation()),
                SessionRefreshPolicy.startAction)
    }

    function test_hiddenOrUnselectedViewStaysIdle() {
        compare(SessionRefreshPolicy.refreshAction(observation({ visible: false })),
                SessionRefreshPolicy.keepAction)
    }

    function test_manualRefreshStartsWhileThePopupIsHidden() {
        compare(SessionRefreshPolicy.refreshAction(observation({
            force: true,
            visible: false
        })), SessionRefreshPolicy.startAction)
    }

    function test_activeLoadIsNotRestarted() {
        compare(SessionRefreshPolicy.refreshAction(observation({
            force: true,
            loading: true
        })), SessionRefreshPolicy.keepAction)
    }

    function test_visibleIntentReportsAMissingCommand() {
        compare(SessionRefreshPolicy.refreshAction(observation({ commandSource: "" })),
                SessionRefreshPolicy.missingCommandAction)
    }

    function test_freshCompletedSnapshotStaysIdle() {
        compare(SessionRefreshPolicy.refreshAction(observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 900000
        })), SessionRefreshPolicy.keepAction)
    }

    function test_staleCompletedSnapshotStartsAtTheBoundary() {
        compare(SessionRefreshPolicy.refreshAction(observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 700000
        })), SessionRefreshPolicy.startAction)
    }

    function test_commandChangeMakesACompletedSnapshotStale() {
        compare(SessionRefreshPolicy.refreshAction(observation({
            commandSource: "/new/codexbar sessions --json-v2",
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 999999
        })), SessionRefreshPolicy.startAction)
    }

    function test_failedAttemptDoesNotMakeOldDataFresh() {
        compare(SessionRefreshPolicy.refreshAction(observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: -1
        })), SessionRefreshPolicy.startAction)
    }

    function test_refreshIntervalFallsBackWhenAutomaticUsageRefreshIsDisabled() {
        compare(SessionRefreshPolicy.staleAfterMs(0), 300000)
        compare(SessionRefreshPolicy.staleAfterMs(120), 120000)
        compare(SessionRefreshPolicy.staleAfterMs("120"), 300000)
    }

    function test_nextCheckIsScheduledFromSnapshotCompletion() {
        compare(SessionRefreshPolicy.nextCheckDelay(observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 900000
        })), 200000)
        compare(SessionRefreshPolicy.nextCheckDelay(observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 700001
        })), 1)
    }

    function test_nextCheckStopsWhenInactiveAndRetriesMissingSnapshotsLater() {
        compare(SessionRefreshPolicy.nextCheckDelay(observation({
            visible: false
        })), 0)
        compare(SessionRefreshPolicy.nextCheckDelay(observation({
            loading: true
        })), 0)
        compare(SessionRefreshPolicy.nextCheckDelay(observation({
            commandSource: ""
        })), 0)
        compare(SessionRefreshPolicy.nextCheckDelay(observation()), 300000)
    }

    function test_intervalChangeReevaluatesTheExistingSnapshot() {
        var current = observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 900000
        })
        compare(SessionRefreshPolicy.nextCheckDelay(current), 200000)

        current.staleAfterMs = SessionRefreshPolicy.staleAfterMs(60)
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.startAction)

        current.staleAfterMs = SessionRefreshPolicy.staleAfterMs(600)
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.keepAction)
        compare(SessionRefreshPolicy.nextCheckDelay(current), 500000)

        current.visible = false
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.keepAction)
        compare(SessionRefreshPolicy.nextCheckDelay(current), 0)
    }
}
