import QtQuick
import QtTest
import "../contents/ui/NotificationPlanner.js" as NotificationPlanner

TestCase {
    name: "NotificationPlanner"

    function plannerOptions(mode) {
        return {
            mode: mode,
            statusEnabled: true,
            quotaEnabled: true,
            paceEnabled: true,
            resetEnabled: true,
            resetArmThreshold: 80,
            resetFloor: 5
        }
    }

    function observation(severity, incidentKey, rows, scopeID, pending, errorPresent) {
        return {
            providerID: "codex",
            scopeID: scopeID || "codex/account-a",
            pending: pending === true,
            errorPresent: errorPresent === true,
            statusActive: String(severity || "").length > 0,
            statusSeverity: severity || "",
            statusIncidentKey: incidentKey || "",
            rows: rows || []
        }
    }

    function usageRow(level, usedPercent, paceActive, label, lane, resetsAt, hasPercent) {
        return {
            quotaLevel: level || "",
            hasPercent: hasPercent !== false,
            usedPercent: usedPercent,
            paceActive: paceActive === true,
            label: label || "Weekly",
            lane: lane || "secondary",
            resetsAt: resetsAt || "2026-08-24T00:00:00Z"
        }
    }

    function transition(mode, observations, memo) {
        return NotificationPlanner.transition(
            observations,
            memo || ({}),
            plannerOptions(mode))
    }

    function intentKinds(result) {
        var kinds = []
        for (var i = 0; i < result.intents.length; i++) {
            kinds.push(result.intents[i].kind)
        }
        return kinds.join(",")
    }

    function test_errorOnlyObservationRemainsPending() {
        compare(NotificationPlanner.observationPending(false, true, false, 0), true)
    }

    function test_observationPendingKeepsPartialHealthySignalsAndExplicitRefreshState() {
        compare(NotificationPlanner.observationPending(false, true, true, 0), false)
        compare(NotificationPlanner.observationPending(false, true, false, 1), false)
        compare(NotificationPlanner.observationPending(false, false, false, 0), false)
        compare(NotificationPlanner.observationPending(true, false, false, 0), true)
    }
    function test_errorPassWithIncidentKeepsThresholdBaselines() {
        var primedRows = [
            usageRow("minor", 85, false, "Weekly", "secondary"),
            usageRow("", 60, true, "Daily", "primary")
        ]
        var primed = transition(
            "prime",
            [observation("minor", "incident-1", primedRows)])
        compare(primed.intents.length, 0)

        // The usage refresh fails while the status incident continues. The
        // error carries no usage evidence, so it must not read as a quiet
        // recovery: quota, pace, and reset baselines all survive.
        var errored = transition(
            "observe",
            [observation("minor", "incident-1", [], "codex/account-a", false, true)],
            primed.nextMemo)
        compare(errored.intents.length, 0)

        var recovered = transition(
            "observe",
            [observation("minor", "incident-1", primedRows)],
            errored.nextMemo)
        compare(recovered.intents.length, 0)

        // The armed reset survives the outage and still fires once usage
        // collapses.
        var collapsed = transition(
            "observe",
            [observation("minor", "incident-1", [usageRow("", 3, false, "Weekly", "secondary"), usageRow("", 60, false, "Daily", "primary")])],
            recovered.nextMemo)
        compare(collapsed.intents.length, 1)
        compare(collapsed.intents[0].kind, "reset")
        compare(collapsed.intents[0].rowIndex, 0)

        // Escalation after recovery still announces: the baseline was kept,
        // not merely suppressed.
        var escalated = transition(
            "observe",
            [observation("minor", "incident-1", [usageRow("major", 96, false, "Weekly", "secondary"), usageRow("", 60, false, "Daily", "primary")])],
            collapsed.nextMemo)
        compare(escalated.intents.length, 1)
        compare(escalated.intents[0].kind, "quota")
        compare(escalated.intents[0].severity, "major")
    }

    function test_erroredFirstObservationLeavesTheScopeUnprimed() {
        var errored = transition(
            "observe",
            [observation("minor", "incident-1", [], "codex/account-a", false, true)])
        compare(errored.intents.length, 0)

        // The first healthy pass establishes the baseline silently instead of
        // announcing a level that was never observed before.
        var recovered = transition(
            "observe",
            [observation("minor", "incident-1", [usageRow("minor", 85, false)])],
            errored.nextMemo)
        compare(recovered.intents.length, 0)
    }

    function test_erroredFirstPrimePassLeavesTheScopeUnprimed() {
        var primed = transition(
            "prime",
            [observation("minor", "incident-1", [], "codex/account-a", false, true)])
        compare(primed.intents.length, 0)

        // The first healthy pass after the outage establishes the baseline
        // silently instead of announcing a level that was never observed.
        var recovered = transition(
            "observe",
            [observation("minor", "incident-1", [usageRow("minor", 85, false)])],
            primed.nextMemo)
        compare(recovered.intents.length, 0)
    }

    function test_statusBaselinePrimesSilentlyThenNewIncidentNotifies() {
        var primed = transition("prime", [observation("", "")])
        compare(primed.intents.length, 0)

        var changed = transition("observe", [observation("major", "incident-1")], primed.nextMemo)
        compare(changed.intents.length, 1)
        compare(changed.intents[0].kind, "status")
        compare(changed.intents[0].observationIndex, 0)
        compare(changed.intents[0].severity, "major")
    }

    function test_quotaBaselineIsQuietAndOnlyEscalationNotifies() {
        var primed = transition("prime", [observation("", "", [usageRow("minor", 85, false)])])
        compare(primed.intents.length, 0)

        var unchanged = transition(
            "observe",
            [observation("", "", [usageRow("minor", 86, false)])],
            primed.nextMemo)
        compare(unchanged.intents.length, 0)

        var escalated = transition(
            "observe",
            [observation("", "", [usageRow("major", 96, false)])],
            unchanged.nextMemo)
        compare(escalated.intents.length, 1)
        compare(escalated.intents[0].kind, "quota")
        compare(escalated.intents[0].rowIndex, 0)
        compare(escalated.intents[0].severity, "major")

        var improved = transition(
            "observe",
            [observation("", "", [usageRow("minor", 90, false)])],
            escalated.nextMemo)
        compare(improved.intents.length, 0)
    }

    function test_paceWarningPrimesStaysQuietAndReannouncesAfterRecovery() {
        var activeRow = usageRow("", 60, true)
        var primed = transition("prime", [observation("", "", [activeRow])])
        compare(primed.intents.length, 0)

        var unchanged = transition("observe", [observation("", "", [activeRow])], primed.nextMemo)
        compare(unchanged.intents.length, 0)

        var recovered = transition(
            "observe",
            [observation("", "", [usageRow("", 60, false)])],
            unchanged.nextMemo)
        compare(recovered.intents.length, 0)

        var regressed = transition("observe", [observation("", "", [activeRow])], recovered.nextMemo)
        compare(regressed.intents.length, 1)
        compare(regressed.intents[0].kind, "pace")
        compare(regressed.intents[0].rowIndex, 0)
    }

    function test_limitResetNeedsAnArmedHighUsageBaselineAndFiresOnce() {
        var primed = transition(
            "prime",
            [observation("", "", [usageRow("minor", 85, false)])])
        compare(primed.intents.length, 0)

        var descending = transition(
            "observe",
            [observation("", "", [usageRow("", 60, false)])],
            primed.nextMemo)
        compare(descending.intents.length, 0)

        var reset = transition(
            "observe",
            [observation("", "", [usageRow("", 5, false)])],
            descending.nextMemo)
        compare(reset.intents.length, 1)
        compare(reset.intents[0].kind, "reset")
        compare(reset.intents[0].rowIndex, 0)

        var stillLow = transition(
            "observe",
            [observation("", "", [usageRow("", 2, false)])],
            reset.nextMemo)
        compare(stillLow.intents.length, 0)
    }

    function test_pendingRefreshCarriesThePreviousStatusAndSuppressesCachedChanges() {
        var primed = transition(
            "prime",
            [observation("minor", "incident-1", [usageRow("minor", 85, false)])])
        var cached = transition(
            "observe",
            [observation(
                "major",
                "incident-1",
                [usageRow("major", 96, true)],
                "codex/account-a",
                true)],
            primed.nextMemo)
        compare(cached.intents.length, 0)

        var fresh = transition(
            "observe",
            [observation("major", "incident-1", [usageRow("major", 96, true)])],
            cached.nextMemo)
        compare(intentKinds(fresh), "status,quota,pace")
    }

    function test_newAccountScopePrimesSilentlyWithoutDiscardingTheOldScope() {
        var accountA = transition(
            "prime",
            [observation("", "", [usageRow("minor", 85, false)], "codex/account-a")])
        var accountB = transition(
            "observe",
            [observation("", "", [usageRow("major", 96, true)], "codex/account-b")],
            accountA.nextMemo)
        compare(accountB.intents.length, 0)

        var backToA = transition(
            "observe",
            [observation("", "", [usageRow("major", 96, false)], "codex/account-a")],
            accountB.nextMemo)
        compare(backToA.intents.length, 1)
        compare(backToA.intents[0].kind, "quota")
    }

    function test_resetDropsThresholdStateButPreservesStatusBaseline() {
        var primed = transition(
            "prime", [observation(
                "minor", "incident-1", [usageRow("minor", 85, false)])])
        var reset = transition("reset", [], primed.nextMemo)
        compare(reset.intents.length, 0)

        // Status survives and therefore escalates. Quota, pace, and reset
        // state do not: the same observation silently establishes their new
        // baseline instead of treating a settings change as a transition.
        var fresh = transition(
            "observe",
            [observation("major", "incident-1", [usageRow("major", 5, true)])],
            reset.nextMemo)
        compare(intentKinds(fresh), "status")
    }

    function test_quotaBaselineSurvivesUnrelatedRowInsertion() {
        var weekly = usageRow("minor", 85, false, "Weekly", "secondary")
        var primed = transition("prime", [observation("", "", [weekly])])

        // The CLI starts reporting a new window ahead of the existing one.
        var inserted = transition(
            "observe",
            [observation("", "", [usageRow("", 40, false, "Daily", "primary"), weekly])],
            primed.nextMemo)
        compare(inserted.intents.length, 0)

        // Escalation still tracks the same row across the shifted index.
        var escalated = transition(
            "observe",
            [observation("", "", [usageRow("", 96, false, "Daily", "primary"), usageRow("major", 96, false, "Weekly", "secondary")])],
            inserted.nextMemo)
        compare(escalated.intents.length, 1)
        compare(escalated.intents[0].kind, "quota")
        compare(escalated.intents[0].rowIndex, 1)
        compare(escalated.intents[0].severity, "major")
    }

    function test_paceStateFollowsRowsThroughAReorder() {
        var first = usageRow("", 60, true, "Weekly", "secondary")
        var second = usageRow("", 70, true, "Daily", "primary", "2026-08-25T00:00:00Z")
        var primed = transition("prime", [observation("", "", [first, second])])
        compare(primed.intents.length, 0)

        var swapped = transition(
            "observe",
            [observation("", "", [second, first])],
            primed.nextMemo)
        compare(swapped.intents.length, 0)
    }

    function test_armedResetStateSurvivesARowShift() {
        var armed = usageRow("", 85, false, "Weekly", "secondary")
        var primed = transition(
            "prime",
            [observation("", "", [usageRow("", 40, false, "Daily", "primary"), armed])])
        compare(primed.intents.length, 0)

        // The armed row moves to index 0 while its usage also falls back under
        // the arming threshold: the armed baseline must survive both changes,
        // otherwise the promised single reset notice can never fire.
        var shiftedAndCooled = transition(
            "observe",
            [observation("", "", [usageRow("", 30, false, "Weekly", "secondary"), usageRow("", 40, false, "Daily", "primary")])],
            primed.nextMemo)
        compare(shiftedAndCooled.intents.length, 0)

        var reset = transition(
            "observe",
            [observation("", "", [usageRow("", 5, false, "Weekly", "secondary"), usageRow("", 40, false, "Daily", "primary")])],
            shiftedAndCooled.nextMemo)
        compare(reset.intents.length, 1)
        compare(reset.intents[0].kind, "reset")
        compare(reset.intents[0].rowIndex, 0)
    }

    function test_duplicateLabelsStayDistinctAcrossAPass() {
        var firstWindow = usageRow("minor", 30, false, "5 hours", "primary")
        var secondWindow = usageRow("major", 96, false, "5 hours", "primary")
        var primed = transition(
            "prime",
            [observation("", "", [firstWindow, secondWindow])])
        compare(primed.intents.length, 0)

        var unchanged = transition(
            "observe",
            [observation("", "", [firstWindow, secondWindow])],
            primed.nextMemo)
        compare(unchanged.intents.length, 0)
    }

    function test_intentsKeepStatusQuotaPaceResetOrdering() {
        var initialRows = [
            usageRow("minor", 85, false, "Weekly", "secondary"),
            usageRow("", 85, false, "Daily", "primary")
        ]
        var primed = transition("prime", [observation("", "", initialRows)])
        var changedRows = [
            usageRow("major", 96, true, "Weekly", "secondary"),
            usageRow("", 5, false, "Daily", "primary")
        ]
        var changed = transition(
            "observe",
            [observation("major", "incident-1", changedRows)],
            primed.nextMemo)
        compare(intentKinds(changed), "status,quota,pace,reset")
    }

    function test_transitionReturnsANewMemoWithoutMutatingThePreviousOne() {
        var primed = transition(
            "prime",
            [observation("minor", "incident-1", [usageRow("minor", 85, true)])])
        var before = JSON.stringify(primed.nextMemo)
        var changed = transition(
            "observe",
            [observation("major", "incident-1", [usageRow("major", 96, false)])],
            primed.nextMemo)
        compare(JSON.stringify(primed.nextMemo), before)
        verify(changed.nextMemo !== primed.nextMemo)
    }

    function test_armedResetSurvivesAnUnknownPercentagePass() {
        var armed = usageRow("", 85, false, "Weekly", "secondary")
        var primed = transition("prime", [observation("", "", [armed])])
        compare(primed.intents.length, 0)

        // The same window reports back without a usable percentage. The arm
        // must survive the degraded pass, otherwise the promised single reset
        // notice can never fire.
        var degraded = transition(
            "observe",
            [observation("", "", [usageRow("", 0, false, "Weekly", "secondary", "", false)])],
            primed.nextMemo)
        compare(degraded.intents.length, 0)

        var reset = transition(
            "observe",
            [observation("", "", [usageRow("", 3, false, "Weekly", "secondary")])],
            degraded.nextMemo)
        compare(reset.intents.length, 1)
        compare(reset.intents[0].kind, "reset")
        compare(reset.intents[0].rowIndex, 0)
    }

    function test_unknownPercentagePassKeepsTheQuotaBaseline() {
        var primed = transition(
            "prime",
            [observation("", "", [usageRow("minor", 85, false, "Weekly", "secondary")])])

        var degraded = transition(
            "observe",
            [observation("", "", [usageRow("", 0, false, "Weekly", "secondary", "", false)])],
            primed.nextMemo)
        compare(degraded.intents.length, 0)

        // Recovery at the unchanged level stays quiet; a later real
        // escalation still announces.
        var recovered = transition(
            "observe",
            [observation("", "", [usageRow("minor", 85, false, "Weekly", "secondary")])],
            degraded.nextMemo)
        compare(recovered.intents.length, 0)

        var escalated = transition(
            "observe",
            [observation("", "", [usageRow("major", 96, false, "Weekly", "secondary")])],
            recovered.nextMemo)
        compare(escalated.intents.length, 1)
        compare(escalated.intents[0].kind, "quota")
        compare(escalated.intents[0].severity, "major")
    }

    function test_unknownPercentagePassKeepsThePaceBaseline() {
        var primed = transition(
            "prime",
            [observation("", "", [usageRow("", 60, true, "Daily", "primary")])])

        // The window reports back without a usable percentage and without
        // pace data: the active pace baseline must survive the degraded pass.
        var degraded = transition(
            "observe",
            [observation("", "", [usageRow("", 0, false, "Daily", "primary", "", false)])],
            primed.nextMemo)
        compare(degraded.intents.length, 0)

        var recovered = transition(
            "observe",
            [observation("", "", [usageRow("", 60, true, "Daily", "primary")])],
            degraded.nextMemo)
        compare(recovered.intents.length, 0)

        // A genuine recovery stays quiet, and pace returning afterwards
        // still announces.
        var quiet = transition(
            "observe",
            [observation("", "", [usageRow("", 60, false, "Daily", "primary")])],
            recovered.nextMemo)
        compare(quiet.intents.length, 0)

        var regressed = transition(
            "observe",
            [observation("", "", [usageRow("", 60, true, "Daily", "primary")])],
            quiet.nextMemo)
        compare(regressed.intents.length, 1)
        compare(regressed.intents[0].kind, "pace")
    }

    function test_transitionBoundsStaleMemoWithoutDroppingTheCurrentScope() {
        var limit = NotificationPlanner.maximumMemoEntries
        verify(limit > 0)
        var previous = ({})
        for (var i = 0; i < limit + 32; i++) {
            previous["scope:stale-" + i] = "1"
        }

        var currentScope = "codex/current-account"
        var result = transition(
            "observe", [observation("", "", [], currentScope)], previous)
        verify(Object.keys(result.nextMemo).length <= limit)
        compare(result.nextMemo["scope:" + currentScope], "1")
    }

    function test_transitionRejectsUnsafeKeysWhenCopyingTheOpaqueMemo() {
        var hostile = JSON.parse(
            '{"__proto__":{"polluted":true},"constructor":1,"prototype":2,"keep":"yes"}')
        var result = transition("observe", [], hostile)
        compare(result.nextMemo.keep, "yes")
        verify(!Object.prototype.hasOwnProperty.call(result.nextMemo, "__proto__"))
        verify(!Object.prototype.hasOwnProperty.call(result.nextMemo, "constructor"))
        verify(!Object.prototype.hasOwnProperty.call(result.nextMemo, "prototype"))
    }
}
