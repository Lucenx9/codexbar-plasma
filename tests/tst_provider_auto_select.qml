import QtQuick
import QtTest
import "../contents/ui/ProviderAutoSelect.js" as ProviderAutoSelect

TestCase {
    name: "ProviderAutoSelect"

    function quotaProvider(providerID, usedPercent) {
        return {
            provider: providerID,
            rows: [{ hasPercent: true, usedPercent: usedPercent }]
        };
    }

    function test_usedPercentTakesTheBusiestQuotaRow() {
        compare(ProviderAutoSelect.usedPercent({
            rows: [
                { hasPercent: true, usedPercent: 12 },
                { hasPercent: true, usedPercent: 74 },
                { hasPercent: true, usedPercent: 31 }
            ]
        }), 74);
    }

    function test_usedPercentIgnoresRowsWithoutAPercentage() {
        compare(ProviderAutoSelect.usedPercent({
            rows: [
                { hasPercent: false, usedPercent: 99 },
                { usedPercent: 98 },
                null
            ]
        }), -1);
        compare(ProviderAutoSelect.usedPercent({ rows: [] }), -1);
        compare(ProviderAutoSelect.usedPercent({}), -1);
        compare(ProviderAutoSelect.usedPercent(null), -1);
        compare(ProviderAutoSelect.usedPercent(undefined), -1);
    }

    function test_usedPercentRejectsUnusableNumbersAndClampsTheRange() {
        // The CLI owns these values: a malformed one must not become a score
        // that outranks every healthy provider.
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: "not a number" }]
        }), -1);
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: Infinity }]
        }), -1);
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: 3200 }]
        }), 100);
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: -40 }]
        }), 0);
        // A numeric string is still a usable percentage.
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: "55" }]
        }), 55);
    }

    function test_providerCostCompetesWithQuotaRows() {
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: 20 }],
            providerCost: { percentUsed: 88 }
        }), 88);
        compare(ProviderAutoSelect.usedPercent({
            rows: [{ hasPercent: true, usedPercent: 60 }],
            providerCost: { percentUsed: 5 }
        }), 60);
        // An unmeasured cost budget reports a negative percentage.
        compare(ProviderAutoSelect.usedPercent({
            providerCost: { percentUsed: -1 }
        }), -1);
        compare(ProviderAutoSelect.usedPercent({
            providerCost: { percentUsed: 42 }
        }), 42);
    }

    function test_severityOnlyBreaksTiesBetweenEqualConsumption() {
        var quiet = quotaProvider("codex", 50);
        var critical = { provider: "claude", statusSeverity: "critical", rows: [{ hasPercent: true, usedPercent: 50 }] };
        verify(ProviderAutoSelect.score(critical) > ProviderAutoSelect.score(quiet));
        // One point of severity can never overtake one point of usage.
        verify(ProviderAutoSelect.score(quotaProvider("gemini", 51)) > ProviderAutoSelect.score(critical));
        compare(ProviderAutoSelect.bestIndex([quiet, critical]), 1);
        compare(ProviderAutoSelect.bestIndex([quotaProvider("gemini", 51), critical]), 0);
    }

    function test_providersWithoutAnyPercentageRankBySeverityAlone() {
        var unknown = { provider: "cursor" };
        var maintenance = { provider: "claude", statusSeverity: "maintenance" };
        var outage = { provider: "codex", statusSeverity: "major" };
        compare(ProviderAutoSelect.score(unknown), 0);
        verify(ProviderAutoSelect.score(outage) > ProviderAutoSelect.score(maintenance));
        compare(ProviderAutoSelect.bestIndex([unknown, maintenance, outage]), 2);
        // Severity still outranks an idle provider: an incident is the reason
        // the popup was opened, an unused quota is not.
        compare(ProviderAutoSelect.bestIndex([quotaProvider("gemini", 0), outage]), 1);
    }

    function test_anErrorOnlyProviderNeverWins() {
        var broken = { provider: "codex", error: "codexbar exited with status 1", statusSeverity: "critical",
            credits: null, codexCreditLimit: null };
        compare(ProviderAutoSelect.score(broken), -1);
        compare(ProviderAutoSelect.bestIndex([broken, quotaProvider("claude", 1)]), 1);
        // A provider that still carries a quota row stays rankable even with
        // an error attached to its refresh.
        var degraded = { provider: "gemini", error: "status unavailable", rows: [{ hasPercent: true, usedPercent: 90 }] };
        compare(ProviderAutoSelect.bestIndex([quotaProvider("claude", 1), degraded]), 1);
    }

    function test_aFullyBrokenRosterStillSelectsItsFirstProvider() {
        // Nothing is rankable, but the popup and the panel still have to show a
        // provider. The first one surfaces its error instead of leaving the
        // surfaces blank, which is what a no-selection answer would produce.
        var broken = [
            { provider: "codex", error: "codexbar exited with status 1", credits: null, codexCreditLimit: null },
            { provider: "claude", error: "connection refused", credits: null, codexCreditLimit: null }
        ];
        compare(ProviderAutoSelect.score(broken[0]), -1);
        compare(ProviderAutoSelect.score(broken[1]), -1);
        compare(ProviderAutoSelect.bestIndex(broken), 0);
    }

    function test_theFirstProviderKeepsATie() {
        compare(ProviderAutoSelect.bestIndex([
            quotaProvider("codex", 40),
            quotaProvider("claude", 40),
            quotaProvider("gemini", 40)
        ]), 0);
        compare(ProviderAutoSelect.bestIndex([{ provider: "codex" }, { provider: "claude" }]), 0);
    }

    function test_missingRostersAndEntriesResolveToTheFirstSlot() {
        compare(ProviderAutoSelect.bestIndex([]), 0);
        compare(ProviderAutoSelect.bestIndex(null), 0);
        compare(ProviderAutoSelect.bestIndex(undefined), 0);
        compare(ProviderAutoSelect.bestIndex("codex,claude"), 0);
        compare(ProviderAutoSelect.bestIndex([null, undefined]), 0);
        compare(ProviderAutoSelect.bestIndex([null, quotaProvider("claude", 3)]), 1);
        compare(ProviderAutoSelect.score(null), -1);
    }
}
