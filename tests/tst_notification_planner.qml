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

    function usageRow(level, usedPercent, paceActive, label, lane, resetsAt, hasPercent, paceKnown) {
        return {
            quotaLevel: level || "",
            hasPercent: hasPercent !== false,
            usedPercent: usedPercent,
            paceActive: paceActive === true,
            paceKnown: paceKnown !== false,
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

    function test_firstReadingRespectsEachNotificationToggle_data() {
        var cases = []
        for (var mode of ["prime", "observe"]) {
            for (var mask = 0; mask < 8; mask++) {
                cases.push({tag: mode + "-" + mask, mode: mode,
                    quota: !!(mask & 1), pace: !!(mask & 2), reset: !!(mask & 4)})
            }
        }
        return cases
    }

    function test_initialMeasuredZeroOrKnownForecastEstablishesBaseline_data() {
        return [
            {tag: "zero-prime", mode: "prime", hasPercent: true, paceKnown: false},
            {tag: "zero-observe", mode: "observe", hasPercent: true, paceKnown: false},
            {tag: "forecast-prime", mode: "prime", hasPercent: false, paceKnown: true},
            {tag: "forecast-observe", mode: "observe", hasPercent: false, paceKnown: true}
        ]
    }

    function test_initialMeasuredZeroOrKnownForecastEstablishesBaseline(data) {
        var initial = transition(data.mode, [observation("", "", [
            usageRow("", 0, false, "Weekly", "secondary", "", data.hasPercent, data.paceKnown)
        ])])
        compare(intentKinds(initial), "")
        var increased = transition("observe", [observation("", "", [
            usageRow("minor", 85, true)
        ])], initial.nextMemo)
        compare(intentKinds(increased), "quota,pace")
    }

    function test_firstReadingRespectsEachNotificationToggle(data) {
        var options = plannerOptions(data.mode)
        options.quotaEnabled = data.quota
        options.paceEnabled = data.pace
        options.resetEnabled = data.reset
        var active = observation("", "", [usageRow("minor", 85, true)])
        var initial = NotificationPlanner.transition([active], {}, options)
        compare(intentKinds(initial), "")

        // Enabling a previously disabled signal may announce it. Signals
        // already baselined by the first reading must remain quiet.
        var unchanged = transition("observe", [active], initial.nextMemo)
        var expected = []
        if (!data.quota) expected.push("quota")
        if (!data.pace) expected.push("pace")
        compare(intentKinds(unchanged), expected.join(","))

        // Follow the initial reading independently: a disabled reset must not
        // have armed itself while the other signals were being primed.
        var collapsed = transition("observe",
            [observation("", "", [usageRow("", 3, false)])], initial.nextMemo)
        compare(intentKinds(collapsed), data.reset ? "reset" : "")
    }

    function test_mixedConfidenceReadingPrimesOnlyAuthoritativeRows_data() {
        return [{tag: "prime", mode: "prime"}, {tag: "observe", mode: "observe"}]
    }

    function test_mixedConfidenceReadingPrimesOnlyAuthoritativeRows(data) {
        var trusted = usageRow("minor", 85, true, "Trusted", "primary")
        trusted.dataConfidence = "exact"
        var untrusted = usageRow("major", 99, true, "Estimated", "secondary")
        untrusted.dataConfidence = "estimated"
        var initial = transition(data.mode, [observation("", "", [trusted, untrusted])])
        compare(intentKinds(initial), "")

        var recovered = usageRow("major", 99, true, "Estimated", "secondary")
        recovered.dataConfidence = "exact"
        var fresh = transition("observe", [observation("", "", [trusted, recovered])],
            initial.nextMemo)
        compare(intentKinds(fresh), "quota,pace")
        compare(fresh.intents[0].rowIndex, 1)
        compare(fresh.intents[1].rowIndex, 1)

        var collapsed = transition("observe", [observation("", "", [trusted,
            usageRow("", 3, false, "Estimated", "secondary")])], initial.nextMemo)
        compare(intentKinds(collapsed), "")
    }

    function test_resetArmingMatchesForInitialAndLaterReadings_data() {
        return [
            {tag: "custom-below", threshold: 90, used: 89, hasPercent: true, expected: ""},
            {tag: "custom-equal", threshold: 90, used: 90, hasPercent: true, expected: "reset"},
            {tag: "default-below", threshold: undefined, used: 79, hasPercent: true, expected: ""},
            {tag: "default-equal", threshold: undefined, used: 80, hasPercent: true, expected: "reset"},
            {tag: "invalid-threshold", threshold: NaN, used: 80, hasPercent: true, expected: "reset"},
            {tag: "unknown-percent", threshold: 80, used: 90, hasPercent: false, expected: ""},
            {tag: "invalid-percent", threshold: 80, used: Infinity, hasPercent: true, expected: ""}
        ]
    }

    function test_resetArmingMatchesForInitialAndLaterReadings(data) {
        var options = plannerOptions("prime")
        options.resetArmThreshold = data.threshold
        var high = observation("", "", [usageRow("", data.used, false,
            "Weekly", "secondary", "", data.hasPercent)])
        var low = observation("", "", [usageRow("", 3, false)])
        var initial = NotificationPlanner.transition([high], {}, options)
        options.mode = "observe"
        var collapsed = NotificationPlanner.transition([low], initial.nextMemo, options)
        compare(intentKinds(collapsed), data.expected)

        var healthy = transition("prime", [observation("", "", [usageRow("", 20, false)])])
        var later = NotificationPlanner.transition([high], healthy.nextMemo, options)
        var laterCollapse = NotificationPlanner.transition([low], later.nextMemo, options)
        compare(intentKinds(laterCollapse), data.expected)
    }

    function test_errorWithoutStatusOrUsageRemainsPending() {
        compare(NotificationPlanner.observationPending(false, true, false, 0), true)
    }

    function test_observationPendingKeepsPartialHealthySignalsAndExplicitRefreshState() {
        compare(NotificationPlanner.observationPending(false, true, true, 0), false)
        compare(NotificationPlanner.observationPending(false, true, false, 1), false)
        compare(NotificationPlanner.observationPending(false, false, false, 0), false)
        compare(NotificationPlanner.observationPending(true, false, false, 0), true)
        compare(NotificationPlanner.observationPending(true, true, true, 0), true)
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

    function test_staleUsageKeepsThresholdStateAndProcessesStatus_data() {
        return [{ tag: "rows-omitted", includeRows: false },
                { tag: "stale-rows-present", includeRows: true }]
    }

    function test_staleUsageKeepsThresholdStateAndProcessesStatus(data) {
        var rows = [usageRow("minor", 85, true)]
        var initial = transition("prime", [observation("", "", rows)])
        var stale = observation("major", "incident-1",
            data.includeRows ? [usageRow("major", 99, false)] : [])
        stale.usageStale = true
        var changed = transition("observe", [stale], initial.nextMemo)
        compare(intentKinds(changed), "status")

        var fresh = transition("observe", [observation("major", "incident-1", rows)],
            changed.nextMemo)
        compare(intentKinds(fresh), "")
        var reset = transition("observe", [observation("major", "incident-1",
            [usageRow("", 2, false)])], fresh.nextMemo)
        compare(intentKinds(reset), "reset")
        var escalated = transition("observe", [observation("major", "incident-1",
            [usageRow("major", 96, true)])], reset.nextMemo)
        compare(intentKinds(escalated), "quota,pace")
    }

    function test_firstStaleUsageDoesNotPrimeThresholds_data() {
        return [{ tag: "prime", mode: "prime" },
                { tag: "observe", mode: "observe" }]
    }

    function test_firstStaleUsageDoesNotPrimeThresholds(data) {
        var stale = observation("major", "incident-1", [])
        stale.usageStale = true
        var initial = transition(data.mode, [stale])
        compare(intentKinds(initial), "")
        var fresh = transition("observe", [observation("major", "incident-1",
            [usageRow("minor", 85, true)])], initial.nextMemo)
        compare(intentKinds(fresh), "")
        var escalated = transition("observe", [observation("major", "incident-1",
            [usageRow("major", 96, true)])], fresh.nextMemo)
        compare(intentKinds(escalated), "quota")
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

    function test_disabledStatusPreservesTheIncidentWhileQuotaStillNotifies() {
        var initial = transition("prime", [observation(
            "minor", "incident-1", [usageRow("minor", 85, false)])])
        var disabledOptions = plannerOptions("observe")
        disabledOptions.statusEnabled = false
        var withoutStatus = NotificationPlanner.transition(
            [observation("", "", [usageRow("major", 96, false)])],
            initial.nextMemo,
            disabledOptions)
        compare(intentKinds(withoutStatus), "quota")

        var restored = transition("observe", [observation(
            "minor", "incident-1", [usageRow("major", 96, false)])],
            withoutStatus.nextMemo)
        compare(restored.intents.length, 0)

        var changed = transition("observe", [observation(
            "major", "incident-2", [usageRow("major", 96, false)])],
            restored.nextMemo)
        compare(intentKinds(changed), "status")
    }

    function test_disabledStatusSurvivesResetAndPrime_data() {
        return [
            { tag: "unchanged", before: "minor", beforeID: "incident-1", after: "minor", afterID: "incident-1", expected: "" },
            { tag: "worsened", before: "minor", beforeID: "incident-1", after: "major", afterID: "incident-1", expected: "status" },
            { tag: "replacement", before: "minor", beforeID: "incident-1", after: "minor", afterID: "incident-2", expected: "status" },
            { tag: "new", before: "", beforeID: "", after: "major", afterID: "incident-1", expected: "status" }
        ]
    }

    function test_disabledStatusSurvivesResetAndPrime(data) {
        var initial = transition("prime", [observation(data.before, data.beforeID)])
        var reset = transition("reset", [], initial.nextMemo)
        var disabledOptions = plannerOptions("prime")
        disabledOptions.statusEnabled = false
        var primedWithoutStatus = NotificationPlanner.transition(
            [observation("", "", [usageRow("minor", 85, false)])],
            reset.nextMemo,
            disabledOptions)
        compare(primedWithoutStatus.intents.length, 0)

        var restored = transition("observe", [observation(
            data.after, data.afterID, [usageRow("minor", 85, false)])],
            primedWithoutStatus.nextMemo)
        compare(intentKinds(restored), data.expected)
    }

    function test_unknownStatusKeepsTheLastIncidentUntilAnAuthoritativeReply_data() {
        return [
            { tag: "observe-missing", mode: "observe", explicitUnknown: false },
            { tag: "prime-missing", mode: "prime", explicitUnknown: false },
            { tag: "observe-failed-fetch", mode: "observe", explicitUnknown: true },
            { tag: "prime-failed-fetch", mode: "prime", explicitUnknown: true }
        ]
    }

    function test_unknownStatusKeepsTheLastIncidentUntilAnAuthoritativeReply(data) {
        var initial = transition("prime", [observation(
            "minor", "incident-1", [usageRow("minor", 85, false)])])
        var unknown = observation(data.explicitUnknown ? "unknown" : "", "", [usageRow("major", 96, false)])
        unknown.statusKnown = data.explicitUnknown
        var unavailable = transition(data.mode, [unknown], initial.nextMemo)
        compare(intentKinds(unavailable), data.mode === "observe" ? "quota" : "")

        var restored = transition("observe", [observation(
            "minor", "incident-1", [usageRow("major", 96, false)])],
            unavailable.nextMemo)
        compare(restored.intents.length, 0)

        var healthy = observation("", "", [usageRow("major", 96, false)])
        healthy.statusKnown = true
        var recovered = transition("observe", [healthy], restored.nextMemo)
        compare(recovered.intents.length, 0)
        var recurring = transition("observe", [observation(
            "minor", "incident-1", [usageRow("major", 96, false)])],
            recovered.nextMemo)
        compare(intentKinds(recurring), "status")
    }

    function test_unknownStatusDoesNotInventAHealthyBaseline_data() {
        return test_unknownStatusKeepsTheLastIncidentUntilAnAuthoritativeReply_data()
    }

    function test_unknownStatusDoesNotInventAHealthyBaseline(data) {
        var unknown = observation(data.explicitUnknown ? "unknown" : "", "", [usageRow("minor", 85, false)])
        unknown.statusKnown = data.explicitUnknown
        var initial = transition(data.mode, [unknown])
        var firstStatus = transition("observe", [observation(
            "major", "incident-1", [usageRow("minor", 85, false)])], initial.nextMemo)
        compare(firstStatus.intents.length, 0)
    }

    function test_failedStatusFetchDoesNotBecomeAnIncident() {
        var healthy = observation("", "", [])
        healthy.statusKnown = true
        var unavailable = observation("unknown", "", [])
        unavailable.statusKnown = true
        var state = transition("prime", [healthy])
        for (var i = 0; i < 3; i++) {
            state = transition("observe", [unavailable], state.nextMemo)
            compare(state.intents.length, 0)
            state = transition("observe", [healthy], state.nextMemo)
            compare(state.intents.length, 0)
        }
        state = transition("observe", [unavailable], state.nextMemo)
        var incident = transition("observe", [observation("major", "incident-1", [])], state.nextMemo)
        compare(intentKinds(incident), "status")
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

    function test_paceResetIdentity_data() {
        return [
            {tag: "missing", reset: "", expected: ""},
            {tag: "invalid", reset: "invalid", expected: ""},
            {tag: "impossible-date", reset: "2026-02-30T00:00:00Z", expected: ""},
            {tag: "same-instant", reset: "2026-08-24T02:00:00+02:00", expected: ""},
            {tag: "new-window", reset: "2026-08-31T00:00:00Z", expected: "pace"}
        ]
    }

    function test_paceResetIdentity(data) {
        var active = usageRow("", 60, true)
        var initial = transition("prime", [observation("", "", [active])])
        active.resetsAt = data.reset
        var originalMemo = JSON.stringify(initial.nextMemo)
        var changed = transition("observe", [observation("", "", [active])], initial.nextMemo)
        compare(intentKinds(changed), data.expected)
        compare(JSON.stringify(initial.nextMemo), originalMemo)
        compare(transition("observe", [observation("", "", [active])], changed.nextMemo).intents.length, 0)

        // Unknown metadata cannot erase the known window identity.
        active.resetsAt = ""
        var missing = transition("observe", [observation("", "", [active])], changed.nextMemo)
        compare(missing.intents.length, 0)
        active.resetsAt = "2026-09-07T00:00:00Z"
        var nextWindow = transition("observe", [observation("", "", [active])], missing.nextMemo)
        compare(intentKinds(nextWindow), "pace")
    }

    function test_untrustedResetCannotReplacePaceIdentity() {
        var active = usageRow("", 60, true)
        var initial = transition("prime", [observation("", "", [active])])
        active.dataConfidence = "estimated"
        active.resetsAt = "2026-08-31T00:00:00Z"
        var untrusted = transition("observe", [observation("", "", [active])], initial.nextMemo)
        compare(untrusted.intents.length, 0)
        active.dataConfidence = "exact"
        var measured = transition("observe", [observation("", "", [active])], untrusted.nextMemo)
        compare(intentKinds(measured), "pace")
    }

    function test_newResetWithoutForecastWaitsForMeasuredPace() {
        var active = usageRow("", 60, true)
        var initial = transition("prime", [observation("", "", [active])])
        active.resetsAt = "2026-08-31T00:00:00Z"
        active.paceActive = false
        active.paceKnown = false
        var unknown = transition("observe", [observation("", "", [active])], initial.nextMemo)
        compare(unknown.intents.length, 0)
        active.paceActive = true
        active.paceKnown = true
        var measured = transition("observe", [observation("", "", [active])], unknown.nextMemo)
        compare(intentKinds(measured), "pace")
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

    function test_namedWindowsKeepTheirBaselinesWhenReordered() {
        var nearLimit = usageRow("minor", 85, false, "Daily", "extra")
        nearLimit.windowId = "requests"
        var empty = usageRow("", 0, false, "Daily", "extra")
        empty.windowId = "tokens"
        var initial = transition("prime", [observation("", "", [nearLimit, empty])])

        var reordered = transition("observe", [observation("", "", [empty, nearLimit])], initial.nextMemo)
        compare(intentKinds(reordered), "", "Reordering unchanged named windows must not announce a quota crossing or reset")

        var reset = usageRow("", 0, false, "Daily", "extra")
        reset.windowId = "requests"
        var changed = transition("observe", [observation("", "", [empty, reset])], reordered.nextMemo)
        compare(intentKinds(changed), "reset")
        compare(changed.intents[0].rowIndex, 1)
        compare(transition("observe", [observation("", "", [empty, reset])], changed.nextMemo).intents.length, 0)
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

    function test_intentsKeepOriginalObservationIndexesAndGroupRowsBySignal() {
        var first = observation("", "", [
            usageRow("minor", 85, false, "Weekly"),
            usageRow("minor", 85, false, "Daily"),
            usageRow("minor", 85, false, "Monthly")])
        var second = observation("", "", [usageRow("minor", 85, false)], "claude/account-b")
        second.providerID = "claude"
        var initial = transition("prime", [first, second])
        first.statusActive = true
        first.statusSeverity = "major"
        first.statusIncidentKey = "incident-a"
        first.rows = [
            usageRow("major", 96, true, "Weekly"),
            usageRow("major", 96, true, "Daily"),
            usageRow("", 3, false, "Monthly")]
        second.rows = [usageRow("major", 96, true)]
        var pending = observation("critical", "cached", [], "codex/pending", true)
        var observations = [null, pending, first, null, second]
        var before = JSON.stringify(observations)
        var changed = transition("observe", observations, initial.nextMemo)
        compare(changed.intents, [
            {kind: "status", severity: "major", observationIndex: 2},
            {kind: "quota", severity: "major", rowIndex: 0, observationIndex: 2},
            {kind: "quota", severity: "major", rowIndex: 1, observationIndex: 2},
            {kind: "pace", rowIndex: 0, observationIndex: 2},
            {kind: "pace", rowIndex: 1, observationIndex: 2},
            {kind: "reset", rowIndex: 2, observationIndex: 2},
            {kind: "quota", severity: "major", rowIndex: 0, observationIndex: 4},
            {kind: "pace", rowIndex: 0, observationIndex: 4}
        ])
        compare(JSON.stringify(observations), before)
        compare(transition("observe", observations, changed.nextMemo).intents.length, 0)
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
            [observation("", "", [usageRow("", 0, false, "Daily", "primary", "", false, false)])],
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

    function test_knownPaceRecoveryClearsTheBaselineWhenUsageIsUnknown() {
        var primed = transition(
            "prime",
            [observation("", "", [usageRow("", 60, true, "Daily", "primary")])])

        // Usage availability and pace availability are independent. A valid
        // pace forecast can report recovery while the percentage is unknown.
        var recovered = transition(
            "observe",
            [observation("", "", [usageRow("", 0, false, "Daily", "primary", "", false, true)])],
            primed.nextMemo)
        compare(recovered.intents.length, 0)

        var regressed = transition(
            "observe",
            [observation("", "", [usageRow("", 0, true, "Daily", "primary", "", false, true)])],
            recovered.nextMemo)
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
            "observe", [observation("", "", [usageRow("", 0, false)], currentScope)], previous)
        verify(Object.keys(result.nextMemo).length <= limit)
        compare(result.nextMemo["scope:" + currentScope], "1")
    }

    function test_memoBudgetProtectsOldCurrentBaselinesBeforeRecentStaleScopes() {
        var observations = [observation("major", "incident-a", [usageRow("major", 96, true)])]
        var initial = transition("prime", observations)
        var currentKeys = Object.keys(initial.nextMemo)
        var previous = initial.nextMemo
        var limit = NotificationPlanner.maximumMemoEntries
        for (var i = 0; i < limit + 32; i++) {
            previous["scope:stale-" + i] = "1"
        }
        var before = JSON.stringify(previous)
        var result = transition("observe", observations, previous)
        compare(result.intents.length, 0)
        compare(Object.keys(result.nextMemo).length, limit)
        for (var key of currentKeys) {
            compare(result.nextMemo[key], previous[key])
        }
        verify(!Object.prototype.hasOwnProperty.call(result.nextMemo, "scope:stale-0"))
        compare(result.nextMemo["scope:stale-" + (limit + 31)], "1")
        compare(Object.keys(result.nextMemo).slice(0, currentKeys.length), currentKeys)
        compare(JSON.stringify(previous), before)
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

    function test_missingRowRetainsThresholdState_data() {
        return [{tag: "unchanged", used: 96, level: "major", expected: ""},
            {tag: "reset", used: 0, level: "", expected: "reset"},
            {tag: "recovery", used: 50, level: "", expected: ""}]
    }

    function test_missingRowRetainsThresholdState(data) {
        var daily = usageRow("", 40, false, "Daily", "primary")
        var initial = transition("prime", [observation("", "",
            [daily, usageRow("major", 96, false)])])
        var missing = transition("observe", [observation("", "", [daily])], initial.nextMemo)
        compare(missing.intents.length, 0)
        var returned = transition("observe", [observation("", "",
            [daily, usageRow(data.level, data.used, false)])], missing.nextMemo)
        compare(intentKinds(returned), data.expected)
        var repeated = transition("observe", [observation("", "",
            [daily, usageRow(data.level, data.used, false)])], returned.nextMemo)
        compare(repeated.intents.length, 0)
        if (data.used === 50) {
            var escalated = transition("observe", [observation("", "",
                [daily, usageRow("major", 96, false)])], repeated.nextMemo)
            compare(intentKinds(escalated), "quota")
        }
    }

    function test_missingRowRetainsPaceStateUntilKnownRecovery() {
        var active = usageRow("", 50, true)
        var initial = transition("prime", [observation("", "", [active])])
        var missing = transition("observe", [observation("", "", [])], initial.nextMemo)
        var returned = transition("observe", [observation("", "", [active])], missing.nextMemo)
        compare(returned.intents.length, 0)
        var recovered = transition("observe", [observation("", "",
            [usageRow("", 50, false)])], returned.nextMemo)
        var activeAgain = transition("observe", [observation("", "", [active])], recovered.nextMemo)
        compare(intentKinds(activeAgain), "pace")
    }

}
