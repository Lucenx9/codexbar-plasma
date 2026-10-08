import QtQuick
import QtTest
import "../contents/ui/PanelDisplay.js" as PanelDisplay

TestCase {
    name: "PanelDisplay"

    function usageRow(overrides) {
        var row = {
            hasPercent: false,
            usedPercent: 0,
            leftPercent: 0,
            pacePercent: -1,
            paceOnTop: true,
            paceEtaSeconds: 0,
            resetsAt: "",
            resetDescription: "",
            reset: ""
        };
        for (var key in overrides) {
            row[key] = overrides[key];
        }
        return row;
    }

    function test_candidatePreference_data() {
        return [
            {tag: "generic", key: "codex", exhausted: false, order: "primary,secondary,tertiary,extra"},
            {tag: "unknown", key: "future-provider", exhausted: true, order: "primary,secondary,tertiary,extra"},
            {tag: "factory", key: "factory", exhausted: false, order: "secondary,primary,extra,tertiary"},
            {tag: "factory-exhausted", key: "factory", exhausted: true, order: "secondary,primary,extra,tertiary"},
            {tag: "perplexity-healthy", key: "perplexity", exhausted: false, order: "primary,secondary,tertiary,extra"},
            {tag: "perplexity-exhausted", key: "perplexity", exhausted: true, order: "secondary,tertiary,primary,extra"}
        ];
    }
    function test_candidatePreference(data) {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: data.exhausted ? 100 : 40,
            leftPercent: data.exhausted ? 0 : 60});
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 100, leftPercent: 0});
        var tertiary = usageRow({lane: "tertiary"});
        var extra = usageRow({lane: "extra"});
        var input = [extra, tertiary, null, secondary, primary, secondary];
        var before = JSON.stringify(input);
        var result = PanelDisplay.candidateRows(input, data.key, null, "Translated plan");
        compare(result.map(function(row) { return row.lane; }).join(","), data.order);
        compare(result.length, 4);
        compare(result[result.indexOf(extra)], extra);
        compare(JSON.stringify(input), before);
        verify(result !== input);
    }
    function test_missingLanesAndReferenceDeduplication() {
        compare(PanelDisplay.candidateRows(null, "factory", null, "Plan"), []);
        compare(PanelDisplay.candidateRows(undefined, "cursor", {percentUsed: 0}, "Plan"), []);
        compare(PanelDisplay.candidateRows([], "cursor", {percentUsed: 0}, "Plan"), []);
        var first = usageRow({lane: "secondary"});
        var second = usageRow({lane: "secondary"});
        var result = PanelDisplay.candidateRows([null, first, first, second], "factory", null, "Plan");
        compare(result.length, 2);
        compare(result[0], first);
        compare(result[1], second);
        var primary = usageRow({lane: "primary", hasPercent: false, leftPercent: 0});
        compare(PanelDisplay.candidateRows([primary, first], "perplexity", null, "Plan")[0], primary);
        compare(PanelDisplay.candidateRows([primary], "cursor", {percentUsed: 30}, "Plan"), [primary]);
    }
    function test_cursorFallback_data() {
        return [
            {tag: "zero", value: 0, expected: 0},
            {tag: "fraction", value: 32.5, expected: 32.5},
            {tag: "over-limit", value: 130, expected: 100},
            {tag: "numeric-string", value: "42", expected: 42},
            {tag: "null-compatibility", value: null, expected: 0},
            {tag: "boolean-compatibility", value: true, expected: 1},
            {tag: "infinity-compatibility", value: Infinity, expected: 100}
        ];
    }
    function test_cursorFallback(data) {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: 100, leftPercent: 0});
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 20, leftPercent: 80});
        var input = [primary, secondary];
        var cost = {percentUsed: data.value};
        var before = JSON.stringify({rows: input, cost: cost});
        var result = PanelDisplay.candidateRows(input, "cursor", cost, "Translated plan");
        compare(result.length, 3);
        compare(result[0], {lane: "providerCost", label: "Translated plan", hasPercent: true,
            usedPercent: data.expected, leftPercent: 100 - data.expected, pacePercent: -1,
            paceOnTop: true, reset: "", pace: ""});
        verify(result[1] === primary);
        verify(result[2] === secondary);
        compare(PanelDisplay.rowForMode(result, "percent"), result[0]);
        compare(PanelDisplay.meterRows(result), [primary, secondary]);
        compare(PanelDisplay.rowForMode(result, "percent", "primary"), primary);
        compare(JSON.stringify({rows: input, cost: cost}), before);
        var again = PanelDisplay.candidateRows(input, "cursor", cost, "Translated plan");
        verify(again[0] !== result[0]);
    }
    function test_cursorWithoutEligibleCost_data() {
        return [
            {tag: "missing", cost: null},
            {tag: "missing-value", cost: {}},
            {tag: "negative", cost: {percentUsed: -1}},
            {tag: "nan", cost: {percentUsed: NaN}},
            {tag: "invalid-string", cost: {percentUsed: "invalid"}}
        ];
    }
    function test_cursorWithoutEligibleCost(data) {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: 100, leftPercent: 0});
        compare(PanelDisplay.candidateRows([primary], "cursor", data.cost, "Plan"), [primary]);
        primary.leftPercent = 1;
        compare(PanelDisplay.candidateRows([primary], "cursor", {percentUsed: 50}, "Plan"), [primary]);
    }
    function test_firstPrimaryControlsExhaustionAndDuplicatesKeepIdentity() {
        var first = usageRow({lane: "primary", hasPercent: true, leftPercent: 40, usedPercent: 60});
        var second = usageRow({lane: "primary", hasPercent: true, leftPercent: 0, usedPercent: 100});
        var secondary = usageRow({lane: "secondary"});
        var extra = usageRow({lane: "extra"});
        var input = [extra, first, second, secondary];
        var result = PanelDisplay.candidateRows(input, "perplexity", null, "Plan");
        verify(result[0] === first);
        verify(result[1] === secondary);
        verify(result[2] === extra);
        verify(result[3] === second);
        first.leftPercent = 0;
        result = PanelDisplay.candidateRows(input, "perplexity", null, "Plan");
        verify(result[0] === secondary);
        verify(result[1] === first);
        verify(result[3] === second);
        compare(input.length, 4);
    }
    function test_cursorMissingPrimaryDoesNotInventIncludedPlan() {
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 100, leftPercent: 0});
        var result = PanelDisplay.candidateRows([secondary], "cursor", {percentUsed: 20}, "Plan");
        compare(result.length, 1);
        verify(result[0] === secondary);
    }
    function test_cursorPercentageAndPaceSelectIndependentCandidates() {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: 100,
            leftPercent: 0, pacePercent: 50});
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 40, leftPercent: 60});
        var result = PanelDisplay.candidateRows([primary, secondary], "cursor", {percentUsed: 32}, "Plan");
        verify(PanelDisplay.rowForMode(result, "percent") === result[0]);
        verify(PanelDisplay.rowForMode(result, "both") === primary);
        verify(PanelDisplay.rowForMode(result, "pace") === primary);
        compare(PanelDisplay.meterRows(result), [primary, secondary]);
    }

    function test_candidatesRetainNonPercentageCapabilities() {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: 100, leftPercent: 0});
        var secondary = usageRow({lane: "secondary", pacePercent: 60, resetsAt: "2026-10-08T12:00:00Z",
            paceOnTop: false, paceEtaSeconds: 3600});
        var result = PanelDisplay.candidateRows([primary, secondary], "perplexity", null, "Plan");
        compare(PanelDisplay.rowForMode(result, "percent"), primary);
        compare(PanelDisplay.rowForMode(result, "pace"), secondary);
        compare(PanelDisplay.rowForMode(result, "resetTime"), secondary);
        compare(PanelDisplay.rowForMode(result, "runOut"), secondary);
    }

    function test_safeModeFallsBackToPercent() {
        compare(PanelDisplay.safeMode("pace"), "pace");
        compare(PanelDisplay.safeMode("unknown"), "percent");
        compare(PanelDisplay.safeMode(null), "percent");
    }

    function test_explicitLaneOverridesAutomaticPreferenceWithoutFallback() {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: 20, leftPercent: 80});
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 90, leftPercent: 10});
        var rows = [primary, secondary];
        compare(PanelDisplay.rowForMode(rows, "percent"), primary);
        compare(PanelDisplay.rowForMode(rows, "percent", "secondary"), secondary);
        compare(PanelDisplay.rowForMode(rows, "percent", "tertiary"), null);
        compare(rows.length, 2);
    }

    function test_directLaneKeepsModeCapabilitiesAndUnknownLanesAreHarmless() {
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 90, leftPercent: 10, pacePercent: 50});
        var tertiary = usageRow({lane: "tertiary", pacePercent: 40, resetsAt: "2026-09-05T13:00:00Z"});
        var rows = [secondary, tertiary];
        compare(PanelDisplay.rowForMode(rows, "both", "tertiary"), tertiary);
        compare(PanelDisplay.rowForMode(rows, "resetTime", "tertiary"), tertiary);
        compare(PanelDisplay.rowForMode(rows, "percent", "tertiary"), null);
        compare(PanelDisplay.rowForMode(rows, "runOut", "secondary"), null);
        compare(PanelDisplay.rowForMode(rows, "both", "unknown"), secondary);
        compare(PanelDisplay.safeLane({toString: function() { return "primary"; }}), "auto");
        compare(PanelDisplay.rowForMode(null, "percent", "primary"), null);
    }

    function test_eachModeSelectsARowWithTheDataItNeeds() {
        var percent = usageRow({
            hasPercent: true,
            usedPercent: 25,
            leftPercent: 75
        });
        var pace = usageRow({
            pacePercent: 30
        });
        var reset = usageRow({
            resetsAt: "2026-09-04T12:00:00Z"
        });
        var runOut = usageRow({
            paceOnTop: false,
            paceEtaSeconds: 3600
        });
        var rows = [percent, pace, reset, runOut];

        compare(PanelDisplay.rowForMode(rows, "percent"), percent);
        compare(PanelDisplay.rowForMode(rows, "pace"), pace);
        compare(PanelDisplay.rowForMode(rows, "resetTime"), reset);
        compare(PanelDisplay.rowForMode(rows, "runOut"), runOut);
    }

    function test_bothCanFallBackToPaceWithoutAPercentage() {
        var pace = usageRow({
            pacePercent: 40
        });
        compare(PanelDisplay.rowForMode([pace], "both"), pace);
    }

    function test_bothPrefersACompleteRowOverAnEarlierPartialRow() {
        var partial = usageRow({
            hasPercent: true,
            usedPercent: 25,
            leftPercent: 75
        });
        var complete = usageRow({
            hasPercent: true,
            usedPercent: 30,
            leftPercent: 70,
            pacePercent: 40
        });

        compare(PanelDisplay.rowForMode([partial, complete], "both"), complete);
    }

    function test_resetAcceptsDescriptionsButRejectsStructuredText() {
        var description = usageRow({
            resetDescription: "Tomorrow"
        });
        compare(PanelDisplay.rowForMode([description], "resetTime"), description);
        compare(PanelDisplay.rowForMode([usageRow({
                resetDescription: {
                    text: "Tomorrow"
                }
            })], "resetTime"), null);
    }

    function test_runOutNeedsTheExplicitForecastAndPositiveEta() {
        compare(PanelDisplay.rowForMode([usageRow({
                paceOnTop: true,
                paceEtaSeconds: 60
            }), usageRow({
                paceOnTop: false,
                paceEtaSeconds: 0
            })], "runOut"), null);
    }

    function test_remainingSecondsUsesTheObservationTime() {
        compare(PanelDisplay.remainingSeconds(3600, 100000, 160000), 3540);
        compare(PanelDisplay.remainingSeconds(30, 100000, 160000), 0);
        compare(PanelDisplay.remainingSeconds(30, 160000, 100000), 30);
        compare(PanelDisplay.remainingSeconds("30", 100000, 110000), 0);
    }
    function test_meterRowsKeepLaneOrderAndIgnoreAutomaticTextPreference() {
        var primary = usageRow({lane: "primary", hasPercent: true, usedPercent: 0, leftPercent: 100});
        var secondary = usageRow({lane: "secondary", hasPercent: true, usedPercent: 99, leftPercent: 1});
        var tertiary = usageRow({lane: "tertiary", hasPercent: true, usedPercent: 50, leftPercent: 50});
        var rows = [tertiary, secondary, primary];
        compare(PanelDisplay.meterRows(rows, "auto"), [primary, secondary]);
        compare(PanelDisplay.meterRows(rows, "secondary"), [secondary]);
        compare(PanelDisplay.meterRows(rows, "tertiary"), [tertiary]);
        compare(PanelDisplay.meterRows([tertiary]), [tertiary]);
        compare(PanelDisplay.meterRows([secondary]), [secondary]);
        compare(PanelDisplay.meterRows([primary]), [primary]);
        compare(rows, [tertiary, secondary, primary]);
    }

    function test_meterRowsDoNotInventMissingQuotasOrDuplicateLanes() {
        var zero = usageRow({lane: "secondary", hasPercent: true, usedPercent: 0, leftPercent: 100});
        var invalid = usageRow({lane: "primary", hasPercent: true, usedPercent: NaN, leftPercent: 50});
        compare(PanelDisplay.meterRows([null, invalid, zero, zero]), [zero]);
        compare(PanelDisplay.meterRows([zero], "primary"), []);
        compare(PanelDisplay.meterRows([invalid]), []);
        compare(PanelDisplay.meterRows(null), []);
        compare(PanelDisplay.meterRows({primary: zero}), []);
        compare(PanelDisplay.meterRows([usageRow({lane: "primary", hasPercent: true, usedPercent: "50", leftPercent: 50})]), []);
    }

}
