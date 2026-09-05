import QtQuick
import QtTest
import "../contents/ui/PanelRules.js" as PanelRules

TestCase {
    name: "PanelRules"

    function test_storedRulesAreBoundedAndUnknownFieldsAreDiscarded() {
        var rules = PanelRules.normalizedRules(JSON.stringify({
            text: {
                condition: "usageAtLeast",
                usedPercent: 140,
                resetMinutes: -4,
                extra: "ignored"
            },
            meters: {
                condition: "unknown",
                usedPercent: "20"
            },
            other: {
                condition: "resetWithin"
            }
        }));
        compare(rules.text.condition, "usageAtLeast");
        compare(rules.text.usedPercent, 100);
        compare(rules.text.resetMinutes, 1);
        compare(rules.meters.condition, "always");
        compare(rules.meters.usedPercent, 80);
        verify(rules.other === undefined);
        verify(rules.text.extra === undefined);
    }

    function test_visibilityUsesKnownUsageAndFutureResetTimes() {
        var now = Date.parse("2026-09-05T12:00:00Z");
        var row = {
            hasPercent: true,
            usedPercent: 80,
            resetsAt: "2026-09-05T13:00:00Z"
        };
        verify(PanelRules.matches({
            condition: "usageAtLeast",
            usedPercent: 80
        }, row, now));
        verify(!PanelRules.matches({
            condition: "usageAtLeast",
            usedPercent: 81
        }, row, now));
        verify(PanelRules.matches({
            condition: "resetWithin",
            resetMinutes: 60
        }, row, now));
        verify(!PanelRules.matches({
            condition: "resetWithin",
            resetMinutes: 59
        }, row, now));
        verify(!PanelRules.matches({
            condition: "resetWithin"
        }, row, now + 3600000));
        verify(!PanelRules.matches({
            condition: "usageAtLeast"
        }, null, now));
        verify(PanelRules.matches({
            condition: "always"
        }, null, now));
    }

    function test_editKeepsTheOtherRuleAndInactiveThresholds() {
        var stored = '{"text":{"condition":"usageAtLeast","usedPercent":92},"meters":{"condition":"resetWithin","resetMinutes":15}}';
        var next = PanelRules.updatedRules(stored, "text", {
            condition: "resetWithin",
            resetMinutes: 30
        });
        var rules = PanelRules.normalizedRules(next);
        compare(rules.text.condition, "resetWithin");
        compare(rules.text.usedPercent, 92);
        compare(rules.text.resetMinutes, 30);
        compare(rules.meters.condition, "resetWithin");
        compare(rules.meters.resetMinutes, 15);
        compare(PanelRules.updatedRules(next, "__proto__", {
            condition: "runOut"
        }), next);
    }

    function test_malformedOrOversizedConfigurationKeepsElementsVisible() {
        var inputs = [null,
            {},
            "{", "[]", "null", '"text"', " ".repeat(2049), '{"text":null,"meters":[]}', '{"__proto__":{"text":{"condition":"runOut"}}}'];
        for (var i = 0; i < inputs.length; i++) {
            var rules = PanelRules.normalizedRules(inputs[i]);
            verify(PanelRules.matches(rules.text, null, 0));
            verify(PanelRules.matches(rules.meters, null, 0));
        }
        var rules = PanelRules.normalizedRules('{"text":{"resetMinutes":999999,"usedPercent":-10}}');
        compare(rules.text.resetMinutes, 10080);
        compare(rules.text.usedPercent, 0);
    }

    function test_unknownUsageCannotSatisfyEvenAZeroThreshold() {
        var rule = {
            condition: "usageAtLeast",
            usedPercent: 0
        };
        var rows = [null, [],
            {},
            {
                hasPercent: false,
                usedPercent: 100
            },
            {
                hasPercent: true,
                usedPercent: "100"
            },
            {
                hasPercent: true,
                usedPercent: Infinity
            },
            {
                hasPercent: true,
                usedPercent: NaN
            }
        ];
        for (var i = 0; i < rows.length; i++)
            verify(!PanelRules.matches(rule, rows[i], 0));
        verify(PanelRules.matches(rule, {
            hasPercent: true,
            usedPercent: 0
        }, 0));
    }

    function test_resetRulesUseTheClockAndNeverParseDescriptions() {
        var rule = {
            condition: "resetWithin",
            resetMinutes: 30
        };
        var now = Date.parse("2026-09-05T12:00:00Z");
        var row = {
            resetsAt: "2026-09-05T13:00:00Z"
        };
        verify(!PanelRules.matches(rule, row, now));
        verify(PanelRules.matches(rule, row, now + 1800000));
        verify(!PanelRules.matches(rule, row, now + 3600001));
        verify(!PanelRules.matches(rule, row, NaN));
        verify(!PanelRules.matches(rule, {
            resetDescription: "in 5 minutes"
        }, now));
        verify(!PanelRules.matches(rule, {
            resetsAt: "invalid"
        }, now));
        verify(!PanelRules.matches(rule, {
            resetsAt: {}
        }, now));
    }

    function test_forecastConditionRequiresTheCliPrediction() {
        var rule = {
            condition: "runOut"
        };
        verify(PanelRules.matches(rule, {
            paceOnTop: false,
            paceEtaSeconds: 1800
        }, 0));
        verify(!PanelRules.matches(rule, {
            paceOnTop: true,
            paceEtaSeconds: 1800
        }, 0));
        verify(!PanelRules.matches(rule, {
            paceOnTop: false,
            paceEtaSeconds: 0
        }, 0));
        verify(!PanelRules.matches(rule, {
            paceOnTop: false,
            paceEtaSeconds: "1800"
        }, 0));
        verify(!PanelRules.matches(rule, {
            hasPercent: true,
            usedPercent: 100
        }, 0));
    }
}
