import QtQuick
import QtTest
import "../contents/ui/PopupRefreshPolicy.js" as PopupRefreshPolicy

TestCase {
    name: "PopupRefreshPolicy"

    function observation(overrides) {
        var result = {
            enabled: true,
            visible: true,
            loading: false,
            scheduled: false,
            commandSource: "codexbar usage --format json --json-only",
            lastAttemptAtMs: -1,
            lastCompletedAtMs: -1,
            nowMs: 1000000,
            refreshIntervalSeconds: 300
        };
        for (var key in overrides) {
            result[key] = overrides[key];
        }
        return result;
    }

    function test_firstOpeningLoadsMissingData() {
        verify(PopupRefreshPolicy.shouldRefresh(observation({})));
    }

    function test_noUnrequestedOrDuplicateRefresh_data() {
        return [
            {
                tag: "disabled",
                change: {
                    enabled: false
                }
            },
            {
                tag: "closed",
                change: {
                    visible: false
                }
            },
            {
                tag: "running",
                change: {
                    loading: true
                }
            },
            {
                tag: "queued",
                change: {
                    scheduled: true
                }
            },
            {
                tag: "no command",
                change: {
                    commandSource: "  "
                }
            },
            {
                tag: "invalid command",
                change: {
                    commandSource: {}
                }
            },
            {
                tag: "invalid clock",
                change: {
                    nowMs: NaN
                }
            }
        ];
    }

    function test_noUnrequestedOrDuplicateRefresh(data) {
        verify(!PopupRefreshPolicy.shouldRefresh(observation(data.change)));
    }

    function test_staleBoundaryUsesLastCompletion() {
        verify(!PopupRefreshPolicy.shouldRefresh(observation({
            lastCompletedAtMs: 700001
        })));
        verify(PopupRefreshPolicy.shouldRefresh(observation({
            lastCompletedAtMs: 700000
        })));
    }

    function test_failedAttemptsHaveTheSameCooldown() {
        verify(!PopupRefreshPolicy.shouldRefresh(observation({
            lastCompletedAtMs: 1,
            lastAttemptAtMs: 900000
        })));
        verify(PopupRefreshPolicy.shouldRefresh(observation({
            lastCompletedAtMs: 1,
            lastAttemptAtMs: 700000
        })));
    }

    function test_completionExtendsFreshnessBeyondAttempt() {
        verify(!PopupRefreshPolicy.shouldRefresh(observation({
            lastAttemptAtMs: 650000,
            lastCompletedAtMs: 800000
        })));
    }

    function test_clockRollbackDoesNotBlockFutureRefresh() {
        verify(PopupRefreshPolicy.shouldRefresh(observation({
            lastAttemptAtMs: 1000001
        })));
    }

    function test_manualOnlyUsesFiveMinuteFreshness() {
        verify(!PopupRefreshPolicy.shouldRefresh(observation({
            refreshIntervalSeconds: 0,
            lastCompletedAtMs: 700001
        })));
        verify(PopupRefreshPolicy.shouldRefresh(observation({
            refreshIntervalSeconds: 0,
            lastCompletedAtMs: 700000
        })));
    }

    function test_intervalChangeReevaluatesAge() {
        verify(PopupRefreshPolicy.shouldRefresh(observation({
            refreshIntervalSeconds: 60,
            lastCompletedAtMs: 900000
        })));
        verify(!PopupRefreshPolicy.shouldRefresh(observation({
            refreshIntervalSeconds: 900,
            lastCompletedAtMs: 900000
        })));
    }

    function test_invalidObservationsStayIdle() {
        for (var value of [null, undefined, [], 1, "true",
            {}
        ]) {
            verify(!PopupRefreshPolicy.shouldRefresh(value));
        }
    }

    function test_invalidTimestampsAreTreatedAsMissing() {
        for (var value of [null, undefined, "999999", NaN, Infinity, -1]) {
            verify(PopupRefreshPolicy.shouldRefresh(observation({
                lastAttemptAtMs: value,
                lastCompletedAtMs: value
            })));
        }
    }

    function test_intervalsAreBounded() {
        compare(PopupRefreshPolicy.staleAfterMs(120), 120000);
        compare(PopupRefreshPolicy.staleAfterMs(0.1), 1000);
        compare(PopupRefreshPolicy.staleAfterMs(1e50), 3600000);
        for (var value of [0, -1, null, "60", NaN, Infinity]) {
            compare(PopupRefreshPolicy.staleAfterMs(value), 300000);
        }
    }
}
