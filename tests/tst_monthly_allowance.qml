import QtQuick
import QtTest
import "../contents/ui/MonthlyAllowance.js" as Allowance
import "../contents/ui/PrivacyPresentation.js" as Privacy
import "../contents/ui/ProviderSnapshot.js" as Snapshot

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

    function test_resetValidation_data() {
        return [
            {tag: "impossible-day", reset: "2026-02-30T12:00:00Z", now: "2026-02-20T12:00:00Z", days: 0},
            {tag: "non-leap-year", reset: "2026-02-29T12:00:00Z", now: "2026-02-20T12:00:00Z", days: 0},
            {tag: "short-month", reset: "2026-11-31T12:00:00Z", now: "2026-11-20T12:00:00Z", days: 0},
            {tag: "overflow-hour", reset: "2026-11-30T24:00:00Z", now: "2026-11-20T12:00:00Z", days: 0},
            {tag: "missing-zone", reset: "2026-11-30T12:00:00", now: "2026-11-20T12:00:00Z", days: 0},
            {tag: "prose-date", reset: "November 30, 2026", now: "2026-11-20T12:00:00Z", days: 0},
            {tag: "invalid-offset", reset: "2026-11-30T12:00:00+14:01", now: "2026-11-20T12:00:00Z", days: 0},
            {tag: "valid-february", reset: "2026-02-28T12:00:00Z", now: "2026-02-20T12:00:00Z", days: 8},
            {tag: "leap-year", reset: "2028-02-29T12:00:00Z", now: "2028-02-20T12:00:00Z", days: 9},
            {tag: "explicit-offset", reset: "2026-11-30T14:30:00.123+02:30", now: "2026-11-20T12:00:00Z", days: 10}
        ];
    }

    function test_resetValidation(data) {
        var now = Date.parse(data.now);
        var source = {provider: "bifrost", usage: {primary: {
            usedPercent: 60, windowMinutes: 43200, resetsAt: data.reset
        }}};
        var row = Snapshot.normalize(source, now).rows[0];
        var before = JSON.stringify(row);
        var privateRow = Privacy.quota(row, true, "Usage");
        for (var value of [row, privateRow]) {
            compare(value.usedPercent, 60);
            compare(value.hasPercent, true);
            var result = Allowance.dailyPercent(value, now);
            compare(result, data.days > 0 ? {percent: 40 / data.days, days: data.days} : null);
        }
        compare(JSON.stringify(row), before);
    }
}
