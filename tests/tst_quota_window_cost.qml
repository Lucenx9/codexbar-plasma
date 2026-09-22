import QtQuick
import QtTest
import "../contents/ui/QuotaWindowCost.js" as QuotaWindowCost
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/PrivacyPresentation.js" as Privacy

// The suite runs with TZ=America/Los_Angeles, so local midnights and the
// November daylight-saving change below are deterministic.
TestCase {
    name: "QuotaWindowCost"

    readonly property int weekMinutes: 7 * 24 * 60

    function local(year, month, day, hour, minute) {
        return new Date(year, month - 1, day, hour || 0, minute || 0).getTime();
    }

    // Consecutive calendar days from `first`, with cost = position + 1 and
    // tokens = 100 * cost, so every window total is easy to derive by hand.
    function history(year, month, firstDay, count) {
        var rows = [];
        for (var i = 0; i < count; i++) {
            var date = new Date(year, month - 1, firstDay + i);
            var label = date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
                + "-" + String(date.getDate()).padStart(2, "0");
            rows.push({label: label, cost: i + 1, tokens: (i + 1) * 100});
        }
        return rows;
    }

    function test_midnightResetSplitsExactWeeksAndDropsTruncatedOnes() {
        // History 09-09 .. 09-22; the week resets at local midnight on 09-24.
        var result = QuotaWindowCost.windows(history(2026, 9, 9, 14), local(2026, 9, 24),
            weekMinutes, local(2026, 9, 22, 12));
        compare(result.length, 2);
        compare(result[0].current, true);
        compare(result[0].startMs, local(2026, 9, 17));
        compare(result[0].dayCount, 6);                  // 09-17 .. 09-22 so far
        compare(result[0].cost, 9 + 10 + 11 + 12 + 13 + 14);
        compare(result[0].tokens, (9 + 10 + 11 + 12 + 13 + 14) * 100);
        compare(result[0].startEstimated, false);
        compare(result[0].endEstimated, false);
        compare(result[1].current, false);
        compare(result[1].dayCount, 7);                  // 09-10 .. 09-16
        compare(result[1].cost, 2 + 3 + 4 + 5 + 6 + 7 + 8);
        // The week starting 09-03 predates the scanned 09-09 and is dropped,
        // not shown as a complete week with its first six days missing.
    }

    function test_midDayResetMarksBothBoundariesEstimated() {
        var result = QuotaWindowCost.windows(history(2026, 9, 9, 14), local(2026, 9, 24, 12, 22),
            weekMinutes, local(2026, 9, 22, 12));
        compare(result.length, 2);
        // A day belongs to the window holding its midnight: 09-17 started
        // before the 12:22 boundary, so the current week begins on 09-18.
        compare(result[0].cost, 10 + 11 + 12 + 13 + 14);
        compare(result[0].startEstimated, true);
        compare(result[0].endEstimated, true);
        compare(result[1].cost, 3 + 4 + 5 + 6 + 7 + 8 + 9);
    }

    function test_freshResetWithoutAFullDayKeepsEarlierWeeks() {
        // Reset at 22:56 tonight: the new window has no midnight yet, so today
        // still counts toward the week that just ended.
        var result = QuotaWindowCost.windows(history(2026, 9, 9, 14), local(2026, 9, 29, 22, 56),
            weekMinutes, local(2026, 9, 22, 23, 30));
        compare(result.length, 2);
        compare(result[0].current, false);
        compare(result[0].dayCount, 7);                  // 09-16 .. 09-22
        compare(result[0].cost, 8 + 9 + 10 + 11 + 12 + 13 + 14);
        compare(result[1].cost, 1 + 2 + 3 + 4 + 5 + 6 + 7);
    }

    function test_unknownDaysStayDistinctFromMeasuredZero() {
        var rows = history(2026, 9, 16, 7);
        rows[1].cost = null;
        rows[2].cost = 0;
        var partial = QuotaWindowCost.windows(rows, local(2026, 9, 23), weekMinutes, local(2026, 9, 22, 12));
        compare(partial.length, 1);
        compare(partial[0].cost, 1 + 0 + 4 + 5 + 6 + 7);
        compare(partial[0].costPartial, true);
        compare(partial[0].tokensPartial, false);

        for (var i = 0; i < rows.length; i++)
            rows[i].cost = null;
        var unknown = QuotaWindowCost.windows(rows, local(2026, 9, 23), weekMinutes, local(2026, 9, 22, 12));
        compare(unknown[0].cost, null);
        compare(unknown[0].costPartial, false);
        verify(unknown[0].tokens > 0);
    }

    function test_mixedIncompleteDayKeepsWeeklyTotalsPartialThroughPrivacy() {
        var source = history(2026, 9, 16, 7).map(function(row) {
            return { date: row.label, totalCost: row.cost, totalTokens: row.tokens }
        })
        source[2].incompleteRequestCount = 1
        var daily = Normalizer.normalizeCostDaily(source, "USD", 7, "2026-09-22T12:00:00Z")
        compare(daily[2].incompleteRequests, 1)
        var privateCost = Privacy.cost({provider: "codex", historyDays: 7, daily: daily}, true)
        compare(privateCost.daily[2].incompleteRequests, 1)
        var result = QuotaWindowCost.windows(privateCost.daily, local(2026, 9, 23),
            weekMinutes, local(2026, 9, 22, 12))
        compare(result.length, 1)
        compare(result[0].cost, 28)
        compare(result[0].tokens, 2800)
        compare(result[0].costPartial, true)
        compare(result[0].tokensPartial, true)
    }

    function test_missingDateMakesTheWeekPartialNotComplete() {
        // The normalizer can leave a hole when the CLI sent a malformed day.
        var rows = history(2026, 9, 16, 7);
        rows.splice(3, 1);                               // drop 09-19
        var result = QuotaWindowCost.windows(rows, local(2026, 9, 23), weekMinutes, local(2026, 9, 22, 12));
        compare(result[0].cost, 1 + 2 + 3 + 5 + 6 + 7);
        compare(result[0].costPartial, true);
        compare(result[0].tokensPartial, true);
    }

    function test_staleHistoryMakesTrailingDaysPartial() {
        // The last successful cost scan ended on 09-20, but the quota row and
        // clock have advanced to 09-22. The missing 21st and 22nd are unknown.
        var rows = history(2026, 9, 16, 5);
        var result = QuotaWindowCost.windows(rows, local(2026, 9, 23), weekMinutes,
            local(2026, 9, 22, 12));
        compare(result.length, 1);
        compare(result[0].cost, 1 + 2 + 3 + 4 + 5);
        compare(result[0].costPartial, true);
        compare(result[0].tokensPartial, true);

        // Even a completed earlier week is partial when its last two dates
        // were never scanned; a newer usage row cannot fill that gap.
        var older = QuotaWindowCost.windows(history(2026, 9, 9, 5),
            local(2026, 9, 23), weekMinutes, local(2026, 9, 22, 12));
        compare(older.length, 1);
        compare(older[0].current, false);
        compare(older[0].costPartial, true);
    }

    function test_futureHistoryDayDoesNotEnterCurrentWeek() {
        var rows = history(2026, 9, 16, 8); // includes tomorrow, 09-23
        var result = QuotaWindowCost.windows(rows, local(2026, 9, 24), weekMinutes,
            local(2026, 9, 22, 12));
        compare(result.length, 1);
        compare(result[0].dayCount, 6);
        compare(result[0].cost, 2 + 3 + 4 + 5 + 6 + 7);
    }

    function test_duplicateDateRefusesTheSplit() {
        var rows = history(2026, 9, 16, 7);
        rows.push({label: rows[2].label, cost: 99, tokens: 9900});
        compare(QuotaWindowCost.windows(rows, local(2026, 9, 23), weekMinutes, local(2026, 9, 22, 12)).length, 0);
    }

    function test_overflowingSumIsUnknownNotInfinite() {
        var rows = history(2026, 9, 16, 7);
        rows[0].cost = Number.MAX_VALUE;
        rows[1].cost = Number.MAX_VALUE;
        var result = QuotaWindowCost.windows(rows, local(2026, 9, 23), weekMinutes, local(2026, 9, 22, 12));
        compare(result[0].cost, null);
        compare(result[0].costPartial, false);
        verify(isFinite(result[0].tokens));
    }

    function test_fixedDurationCrossesDaylightSavingWithoutDrift() {
        // Fall back on 2026-11-01: 168 hours before a midnight reset on 11-05
        // lands at 01:00 local, so the start is estimated and the end is not.
        var result = QuotaWindowCost.windows(history(2026, 10, 20, 17), local(2026, 11, 5),
            weekMinutes, local(2026, 11, 4, 12));
        compare(result[0].endEstimated, false);
        compare(result[0].startEstimated, true);
        // 10-29 began at local midnight, an hour before the 01:00 start, so it
        // belongs to the previous window: the week is 10-30 .. 11-04 so far.
        compare(result[0].dayCount, 6);
        compare(result[0].startMs, local(2026, 10, 29, 1));
    }

    function test_limitIsBoundedAndHonoured() {
        var rows = history(2026, 7, 1, 90);
        var now = local(2026, 9, 28, 12);
        compare(QuotaWindowCost.windows(rows, local(2026, 9, 30), weekMinutes, now, 1).length, 1);
        compare(QuotaWindowCost.windows(rows, local(2026, 9, 30), weekMinutes, now, 50).length,
            QuotaWindowCost.maximumWindows);
    }

    function test_refusesInputsThatCannotSupportAnHonestSplit_data() {
        var rows = history(2026, 9, 9, 14);
        var now = local(2026, 9, 22, 12);
        var reset = local(2026, 9, 24);
        return [
            { tag: "stale-reset", daily: rows, reset: now - 1, minutes: weekMinutes },
            { tag: "reset-now", daily: rows, reset: now, minutes: weekMinutes },
            { tag: "reset-beyond-one-window", daily: rows, reset: now + 7 * 86400000 + 1, minutes: weekMinutes },
            { tag: "no-history", daily: [], reset: reset, minutes: weekMinutes },
            { tag: "not-array", daily: {length: 1}, reset: reset, minutes: weekMinutes },
            { tag: "sub-day-window", daily: rows, reset: reset, minutes: 300 },
            { tag: "fractional-window", daily: rows, reset: reset, minutes: 10080.5 },
            { tag: "huge-window", daily: rows, reset: reset, minutes: 367 * 24 * 60 },
            { tag: "nan-reset", daily: rows, reset: NaN, minutes: weekMinutes },
            { tag: "string-minutes", daily: rows, reset: reset, minutes: "10080" },
            { tag: "rolled-over-date", daily: [{label: "2026-02-30", cost: 1, tokens: 1}], reset: reset, minutes: weekMinutes },
            { tag: "non-date-label", daily: [{label: "Today", cost: 1, tokens: 1}], reset: reset, minutes: weekMinutes }
        ];
    }

    function test_refusesInputsThatCannotSupportAnHonestSplit(data) {
        compare(QuotaWindowCost.windows(data.daily, data.reset, data.minutes, local(2026, 9, 22, 12)).length, 0);
    }
}
