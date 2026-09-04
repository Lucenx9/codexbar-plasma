import QtQuick
import QtTest
import "../contents/ui/CommandLedger.js" as CommandLedger

TestCase {
    name: "CommandLedger"

    function entry(kind, providerID, deadlineMs) {
        return { kind: kind, providerID: providerID, deadlineMs: deadlineMs }
    }

    function test_runNonceMakesEveryStartADistinctSource() {
        compare(CommandLedger.withRunNonce("codexbar usage", 1),
                "CODEXBAR_PLASMA_RUN=1 codexbar usage")
        verify(CommandLedger.withRunNonce("codexbar usage", 1)
               !== CommandLedger.withRunNonce("codexbar usage", 2))
    }

    function test_runNonceRefusesAnEmptyCommand() {
        compare(CommandLedger.withRunNonce("", 3), "")
        compare(CommandLedger.withRunNonce(null, 3), "")
        compare(CommandLedger.withRunNonce(undefined, 3), "")
    }

    function test_descriptorCoercesKindAndProvider() {
        var made = CommandLedger.descriptor(undefined, undefined, 1000, 500, 9000)
        compare(made.kind, "")
        compare(made.providerID, "")
        compare(made.deadlineMs, 1500)
    }

    // A command registered without a usable timeout would sit in the ledger for
    // ever, so the fallback has to apply.
    function test_descriptorFallsBackToTheCallerTimeout() {
        compare(CommandLedger.descriptor("usage", "codex", 1000, 0, 9000).deadlineMs, 10000)
        compare(CommandLedger.descriptor("usage", "codex", 1000, -5, 9000).deadlineMs, 10000)
        compare(CommandLedger.descriptor("usage", "codex", 1000, "abc", 9000).deadlineMs, 10000)
        compare(CommandLedger.descriptor("usage", "codex", 1000, undefined, 9000).deadlineMs, 10000)
    }

    function test_descriptorUsesAnExplicitTimeoutWhenItIsUsable() {
        compare(CommandLedger.descriptor("sessions", "", 1000, 250, 9000).deadlineMs, 1250)
    }

    // Even when both the timeout and the caller fallback are unusable, the
    // descriptor must stay finite: a NaN deadline disables the timeout timer
    // (hasDeadlines) while expired() skips it for ever, leaking the entry.
    function test_descriptorNeverMintsAnImmortalDeadline() {
        var bothBad = CommandLedger.descriptor("usage", "codex", 1000, 0, 0)
        verify(isFinite(bothBad.deadlineMs))
        verify(bothBad.deadlineMs > 0)
        var commands = CommandLedger.opened(({}), "a", bothBad)
        verify(CommandLedger.hasDeadlines(commands))
        compare(CommandLedger.expired(commands, bothBad.deadlineMs).length, 1)

        var badClock = CommandLedger.descriptor("usage", "codex", Number.NaN, "abc", undefined)
        verify(isFinite(badClock.deadlineMs))
        verify(badClock.deadlineMs > 0)

        var overflow = CommandLedger.descriptor(
            "usage", "codex", Number.MAX_VALUE, Number.MAX_VALUE, 1)
        verify(isFinite(overflow.deadlineMs))
        commands = CommandLedger.opened(({}), "overflow", overflow)
        compare(CommandLedger.expired(commands, Number.MAX_VALUE).length, 1)
    }

    // QML bindings on command maps only re-evaluate when the property is
    // reassigned, so neither opening nor closing may edit a map in place.
    function test_openedAndClosedReturnNewMapsWithoutMutating() {
        var original = ({})
        var withOne = CommandLedger.opened(original, "a", entry("usage", "", 10))
        compare(CommandLedger.find(original, "a"), null)
        compare(CommandLedger.find(withOne, "a").kind, "usage")

        var withoutOne = CommandLedger.closed(withOne, "a")
        compare(CommandLedger.find(withOne, "a").kind, "usage")
        compare(CommandLedger.find(withoutOne, "a"), null)
    }

    function test_openedRecordsAnEntryEvenWithoutADescriptor() {
        var commands = CommandLedger.opened(({}), "a", null)
        compare(CommandLedger.find(commands, "a").kind, "")
        compare(CommandLedger.hasDeadlines(commands), false)
    }

    function test_openedRefusesAnEmptySourceName() {
        compare(CommandLedger.find(CommandLedger.opened(({}), "", entry("usage", "", 10)), ""), null)
    }

    function test_openedRejectsPrototypePollutingSourceNames() {
        var polluted = CommandLedger.opened(({}), "__proto__", entry("usage", "", 10))
        compare(CommandLedger.find(polluted, "__proto__"), null)
        compare(CommandLedger.find(CommandLedger.opened(({}), "constructor", entry("usage", "", 10)),
                                   "constructor"), null)
    }

    // The rule the whole module exists for: a reply from a run that has already
    // been retired must not be routed, because a newer run owns the result.
    function test_aRetiredRunIsNoLongerRoutable() {
        var first = CommandLedger.withRunNonce("codexbar usage", 1)
        var second = CommandLedger.withRunNonce("codexbar usage", 2)

        var commands = CommandLedger.opened(({}), first, entry("usage", "", 10))
        // A refresh retires the older run before starting the newer one.
        commands = CommandLedger.closed(commands, first)
        commands = CommandLedger.opened(commands, second, entry("usage", "", 20))

        compare(CommandLedger.find(commands, first), null)
        compare(CommandLedger.find(commands, second).kind, "usage")
    }

    function test_findIsNullForAnUnknownSource() {
        var commands = CommandLedger.opened(({}), "a", entry("usage", "", 10))
        compare(CommandLedger.find(commands, "b"), null)
        compare(CommandLedger.find(commands, ""), null)
        compare(CommandLedger.find(({}), "a"), null)
    }

    function test_findIgnoresInheritedProperties() {
        var commands = CommandLedger.opened(({}), "a", entry("usage", "", 10))
        compare(CommandLedger.find(commands, "toString"), null)
        compare(CommandLedger.find(commands, "hasOwnProperty"), null)
    }

    function test_sourcesOfKindFindsEveryLiveCommandOfThatKind() {
        var commands = CommandLedger.opened(({}), "a", entry("providerFallback", "codex", 10))
        commands = CommandLedger.opened(commands, "b", entry("providerFallback", "claude", 10))
        commands = CommandLedger.opened(commands, "c", entry("cost", "", 10))

        compare(CommandLedger.sourcesOfKind(commands, "providerFallback").length, 2)
        compare(CommandLedger.sourcesOfKind(commands, "cost").length, 1)
        compare(CommandLedger.sourcesOfKind(commands, "sessions").length, 0)
    }

    // costLoading and sessionsLoading read this, so it has to follow the ledger
    // rather than a separate flag that can drift out of step.
    function test_hasKindTracksWhatIsActuallyRunning() {
        var commands = CommandLedger.opened(({}), "a", entry("cost", "", 10))
        compare(CommandLedger.hasKind(commands, "cost"), true)
        compare(CommandLedger.hasKind(CommandLedger.closed(commands, "a"), "cost"), false)
        compare(CommandLedger.hasKind(({}), "cost"), false)
    }

    function test_hasAnyKindCanIgnoreIndependentCostWork() {
        var refreshKinds = ["usage", "providerConfig", "sessions", "providerFallback"]
        var commands = CommandLedger.opened(({}), "cost", entry("cost", "", 10))
        compare(CommandLedger.hasAnyKind(commands, refreshKinds), false)

        commands = CommandLedger.opened(commands, "usage", entry("usage", "", 10))
        compare(CommandLedger.hasAnyKind(commands, refreshKinds), true)
    }

    // A descriptor may deliberately opt out of the shared timeout clock.
    function test_hasDeadlinesIgnoresCommandsWaitedOnWithoutAClock() {
        compare(CommandLedger.hasDeadlines(({})), false)
        compare(CommandLedger.hasDeadlines(
            CommandLedger.opened(({}), "a", entry("clockless", "", 0))), false)
        compare(CommandLedger.hasDeadlines(
            CommandLedger.opened(({}), "a", entry("usage", "", 10))), true)
    }

    function test_expiredReturnsOnlyCommandsPastTheirDeadline() {
        var commands = CommandLedger.opened(({}), "due", entry("usage", "", 100))
        commands = CommandLedger.opened(commands, "later", entry("cost", "", 500))

        var overdue = CommandLedger.expired(commands, 200)
        compare(overdue.length, 1)
        compare(overdue[0].sourceName, "due")
        compare(overdue[0].descriptor.kind, "usage")
    }

    function test_expiredTreatsTheDeadlineAsInclusive() {
        var commands = CommandLedger.opened(({}), "a", entry("usage", "", 100))
        compare(CommandLedger.expired(commands, 99).length, 0)
        compare(CommandLedger.expired(commands, 100).length, 1)
    }

    function test_expiredSkipsAbsentAndUnusableDeadlines() {
        var commands = CommandLedger.opened(({}), "clockless", entry("clockless", "", 0))
        commands = CommandLedger.opened(commands, "broken", entry("usage", "", "abc"))
        compare(CommandLedger.expired(commands, 9999999).length, 0)
    }

    function test_expiredIsEmptyForAnEmptyLedger() {
        compare(CommandLedger.expired(({}), 1000).length, 0)
    }

    // The kinds main.qml routes on. A typo in one of them would silently send a
    // reply down the default branch and lose it.
    function test_everyRoutedKindSurvivesARoundTrip() {
        var kinds = ["usage", "cost", "sessions", "providerConfig", "account", "providerFallback"]
        var commands = ({})
        for (var i = 0; i < kinds.length; i++) {
            commands = CommandLedger.opened(commands, "src-" + i, entry(kinds[i], "", 10))
        }
        for (var j = 0; j < kinds.length; j++) {
            compare(CommandLedger.find(commands, "src-" + j).kind, kinds[j])
        }
    }

    // The cost descriptor carries the range it asked for, so a reply is parsed
    // against the window that was requested rather than the current setting.
    function test_extraDescriptorFieldsSurviveTheLedger() {
        var costEntry = CommandLedger.descriptor("cost", "", 1000, 500, 9000)
        costEntry.costHistoryDays = 7
        var commands = CommandLedger.opened(({}), "a", costEntry)
        compare(CommandLedger.find(commands, "a").costHistoryDays, 7)
    }
}
