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

    // QML bindings on activeUsageCommands only re-evaluate when the property is
    // reassigned, so neither opening nor closing may edit the map in place.
    function test_openedAndClosedReturnNewMapsWithoutMutating() {
        var original = ({})
        var withOne = CommandLedger.opened(original, "a", entry("usage", "", 10))
        compare(CommandLedger.kindOf(original, "a"), "")
        compare(CommandLedger.kindOf(withOne, "a"), "usage")

        var withoutOne = CommandLedger.closed(withOne, "a")
        compare(CommandLedger.kindOf(withOne, "a"), "usage")
        compare(CommandLedger.kindOf(withoutOne, "a"), "")
    }

    function test_openedRecordsAnEntryEvenWithoutADescriptor() {
        var commands = CommandLedger.opened(({}), "a", null)
        verify(CommandLedger.find(commands, "a") !== null)
        compare(CommandLedger.kindOf(commands, "a"), "")
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
        compare(CommandLedger.kindOf(commands, first), "")
        compare(CommandLedger.kindOf(commands, second), "usage")
    }

    function test_kindOfIsEmptyForAnUnknownSource() {
        var commands = CommandLedger.opened(({}), "a", entry("usage", "", 10))
        compare(CommandLedger.kindOf(commands, "b"), "")
        compare(CommandLedger.kindOf(commands, ""), "")
        compare(CommandLedger.kindOf(({}), "a"), "")
    }

    function test_kindOfIgnoresInheritedProperties() {
        var commands = CommandLedger.opened(({}), "a", entry("usage", "", 10))
        compare(CommandLedger.kindOf(commands, "toString"), "")
        compare(CommandLedger.kindOf(commands, "hasOwnProperty"), "")
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

    // Account loads are waited on without a clock, so they must not keep the
    // timeout timer running.
    function test_hasDeadlinesIgnoresCommandsWaitedOnWithoutAClock() {
        compare(CommandLedger.hasDeadlines(({})), false)
        compare(CommandLedger.hasDeadlines(
            CommandLedger.opened(({}), "a", entry("account", "codex", 0))), false)
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
        var commands = CommandLedger.opened(({}), "clockless", entry("account", "codex", 0))
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
            compare(CommandLedger.kindOf(commands, "src-" + j), kinds[j])
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
