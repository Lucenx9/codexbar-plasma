import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    name: "UsageWindowText"

    readonly property double nowMs: Date.UTC(2026, 8, 13, 12)

    Components.TimeLabels {
        id: dates
        locale: Qt.locale("C")
    }
    Components.UsageWindowText {
        id: subject
        dateLabels: dates
    }

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, String(arguments[i]));
        return text;
    }
    function i18np(one, many, count) {
        return i18n(count === 1 ? one : many, count);
    }
    function i18nc(context, text) {
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), String(arguments[i]));
        return text;
    }

    function test_pacePartsPreserveOrderAndInputs() {
        var parts = [
            {
                kind: "onTrack"
            },
            {
                kind: "deficit",
                percent: 13
            },
            {
                kind: "reserve",
                percent: 3
            },
            {
                kind: "expected",
                percent: 40
            },
            {
                kind: "lasts"
            },
            {
                kind: "runsOut",
                seconds: 3600
            },
            {
                kind: "runsOut",
                seconds: 0
            },
            {
                kind: "fallback",
                text: "Legacy <forecast>"
            },
            {
                kind: "future"
            }
        ];
        var before = JSON.stringify(parts);
        compare(subject.paceSummaryPartsText(parts), "On pace | 13% in deficit | 3% in reserve | Expected 40% used | Lasts until reset | Runs out in 1 hour | Runs out now | Legacy <forecast>");
        compare(JSON.stringify(parts), before);
        compare(subject.paceSummaryPartsText([]), "");
    }
    function test_resetMetadataKeepsTimestampPrecedenceAndInputs() {
        var window = {
            resetsAt: nowMs + 3600000,
            resetDescription: "Old <description>"
        };
        compare(subject.resetText(window, nowMs, false), "1h");
        compare(subject.resetText(window, nowMs + 60000, false), "59 min");
        compare(window.resetDescription, "Old <description>");
        compare(window.resetsAt, nowMs + 3600000);
    }
    function test_resetFallbacks_data() {
        return [
            {
                tag: "empty",
                window: {},
                expected: ""
            },
            {
                tag: "missing",
                window: null,
                expected: ""
            },
            {
                tag: "invalid-date",
                window: {
                    resetsAt: "invalid",
                    resetDescription: "Legacy <reset>"
                },
                expected: "invalid"
            },
            {
                tag: "invalid-description",
                window: {
                    resetDescription: {}
                },
                expected: ""
            },
            {
                tag: "elapsed",
                window: {
                    resetsAt: nowMs - 1
                },
                expected: "now"
            }
        ];
    }
    function test_resetFallbacks(data) {
        compare(subject.resetText(data.window, nowMs, false), data.expected);
    }
    function test_labelCompatibility() {
        compare(subject.resetLabel("Resets2h30m"), "Resets 2h 30m");
        compare(subject.resetLabel("Resets unknown future text"), "unknown future text");
        compare(subject.resetLabel(""), "");
    }
    function test_absoluteResetUsesTheSuppliedRegionalFormatter() {
        var timestamp = new Date(2026, 8, 14, 14, 30).getTime();
        compare(subject.resetText({
            resetsAt: timestamp
        }, nowMs, true), dates.weekdayTime(timestamp));
        timestamp = new Date(2026, 9, 3, 14, 30).getTime();
        compare(subject.resetText({
            resetsAt: timestamp
        }, nowMs, true), dates.monthDayTime(timestamp));
    }
}
