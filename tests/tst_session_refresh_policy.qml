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
            lastFinishedAtMs: -1,
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

    function test_failedAttemptCooldownEndsAtTheAttemptBoundary() {
        var current = observation({ lastFinishedAtMs: 900000 })
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.keepAction)
        compare(SessionRefreshPolicy.nextCheckDelay(current), 200000)
        current.nowMs = 1199999
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.keepAction)
        compare(SessionRefreshPolicy.nextCheckDelay(current), 1)
        current.nowMs = 1200000
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.startAction)
    }

    function test_retryCooldownPreservesStaleSnapshotAndManualRetry() {
        var current = observation({
            loadedCommandSource: "codexbar sessions --json-v2",
            lastCompletedAtMs: 500000,
            lastFinishedAtMs: 900000
        })
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.keepAction)
        compare(SessionRefreshPolicy.nextCheckDelay(current), 200000)
        compare(current.lastCompletedAtMs, 500000)
        current.force = true
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.startAction)
        current.loading = true
        compare(SessionRefreshPolicy.refreshAction(current), SessionRefreshPolicy.keepAction)
    }

    function test_invalidAttemptDoesNotPreventRetry_data() {
        return [
            {tag: "missing", value: undefined},
            {tag: "null", value: null},
            {tag: "string", value: "900000"},
            {tag: "negative", value: -1},
            {tag: "nan", value: NaN},
            {tag: "infinite", value: Infinity},
            {tag: "clock-rollback", value: 1000001}
        ]
    }

    function test_invalidAttemptDoesNotPreventRetry(data) {
        compare(SessionRefreshPolicy.refreshAction(observation({lastFinishedAtMs: data.value})),
            SessionRefreshPolicy.startAction)
    }

    function test_lastActivityAtMsAcceptsMissingOrInvalidCommandSource_data() {
        return [
            {tag: "missing-command", current: {loadedCommandSource: "codexbar sessions --json-v2", lastCompletedAtMs: 900000}},
            {tag: "null-command", current: {loadedCommandSource: "codexbar sessions --json-v2", commandSource: null, lastCompletedAtMs: 900000}},
            {tag: "non-string-command", current: {loadedCommandSource: "codexbar sessions --json-v2", commandSource: 42, lastCompletedAtMs: 900000}},
            {tag: "null-current", current: null},
            {tag: "undefined-current", current: undefined},
            {tag: "primitive-current", current: "invalid"}
        ]
    }

    function test_lastActivityAtMsAcceptsMissingOrInvalidCommandSource(data) {
        compare(SessionRefreshPolicy.lastActivityAtMs(data.current), -1)
    }
}
