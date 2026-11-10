import QtQuick
import QtTest
import "../contents/ui/MonthlyAllowance.js" as Allowance
import "../contents/ui/PrivacyPresentation.js" as Privacy

TestCase {
    name: "MonthlyAllowance"

    function row() {
        return {hasPercent: true, usedPercent: 60, leftPercent: 40, windowMinutes: 43200,
            resetsAt: new Date(2026, 10, 20, 12).toISOString()};
    }

    function test_remainingQuotaIsDividedByLocalCalendarDays() {
        var value = row();
        var before = JSON.stringify(value);
        compare(Allowance.dailyPercent(value, new Date(2026, 10, 10, 12).getTime()), {percent: 4, days: 10});
        compare(Allowance.dailyPercent(value, new Date(2026, 10, 19, 23, 59).getTime()), {percent: 40, days: 1});
        compare(Allowance.dailyPercent(value, new Date(2026, 10, 20, 11).getTime()), {percent: 40, days: 1});
        compare(JSON.stringify(value), before);
        value.usedPercent = 100;
        compare(Allowance.dailyPercent(value, new Date(2026, 10, 10, 12).getTime()).percent, 0);
    }

    function test_dstAndPrivacyKeepCalendarDayMeaning() {
        var value = row();
        value.resetsAt = new Date(2026, 2, 9, 0, 30).toISOString();
        var now = new Date(2026, 2, 7, 23, 30).getTime();
        compare(Allowance.dailyPercent(value, now), {percent: 20, days: 2});
        value.dataConfidence = "percentOnly";
        compare(Allowance.dailyPercent(Privacy.quota(value, true, "Usage"), now), {percent: 20, days: 2});
    }

    function test_ineligibleInputs_data() {
        return [
            {tag: "weekly", patch: {windowMinutes: 10080}},
            {tag: "unknown-length", patch: {windowMinutes: 0}},
            {tag: "length-string", patch: {windowMinutes: "43200"}},
            {tag: "unknown-percentage", patch: {hasPercent: false}},
            {tag: "missing-reset", patch: {resetsAt: ""}},
            {tag: "prose-reset", patch: {resetsAt: "Resets monthly"}},
            {tag: "past-reset", patch: {resetsAt: "2026-11-09T00:00:00Z"}},
            {tag: "distant-reset", patch: {resetsAt: "2027-11-20T00:00:00Z"}},
            {tag: "estimated", patch: {dataConfidence: "estimated"}},
            {tag: "unknown-confidence", patch: {dataConfidence: "unknown"}},
            {tag: "invalid-percent", patch: {usedPercent: NaN}},
            {tag: "negative-percent", patch: {usedPercent: -1}},
            {tag: "unbounded-percent", patch: {usedPercent: 101}}
        ];
    }

    function test_ineligibleInputs(data) {
        compare(Allowance.dailyPercent(Object.assign(row(), data.patch), new Date(2026, 10, 10).getTime()), null);
        compare(Allowance.dailyPercent(null, Date.now()), null);
        compare(Allowance.dailyPercent(row(), NaN), null);
    }
}
