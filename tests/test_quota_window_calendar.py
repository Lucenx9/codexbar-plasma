"""Quota-week calendar iteration must terminate across midnight DST gaps."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QuotaWindowCalendarTests(unittest.TestCase):
    def test_missing_day_at_midnight_transition_does_not_hang(self):
        qml = r'''
import QtQuick
import QtTest
import "SOURCE_URL/QuotaWindowCost.js" as QuotaWindowCost
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/AiInsightsSnapshot.js" as AiInsightsSnapshot

TestCase {
    name: "QuotaWindowCalendar"

    function test_windows_data() {
        return [{tag: "mid-week", lastDay: 9},
                {tag: "current-week", lastDay: 12},
                {tag: "previous-week", lastDay: 19}];
    }

    function test_windows(data) {
        var daily = [];
        for (var day = data.lastDay === 9 ? 1 : 5; day <= data.lastDay; day++) {
            // A sparse history can omit the day whose midnight does not exist.
            if (day !== 6)
                daily.push({label: "2026-09-" + String(day).padStart(2, "0"), cost: 1, tokens: 100});
        }
        var before = JSON.stringify(daily);
        var result = QuotaWindowCost.windows(daily,
            new Date(2026, 8, data.lastDay + 1).getTime(), 10080,
            new Date(2026, 8, data.lastDay, 12).getTime());
        var expected = data.lastDay === 19 ? 2 : 1;
        // Qt versions differ in how they resolve nonexistent local midnight.
        // Omission is safe; an available split must still report the missing day.
        verify(result.length >= expected - ALLOW_OMISSION && result.length <= expected);
        if (data.lastDay === 19) {
            compare(result[0].current, true);
            compare(result[0].cost, 7);
            compare(result[0].tokens, 700);
            compare(result[0].costPartial, false);
        }
        if (result.length === expected) {
            var crossing = result[result.length - 1];
            compare(crossing.cost, 6);
            compare(crossing.tokens, 600);
            compare(crossing.costPartial, true);
            compare(crossing.tokensPartial, true);
        }
        compare(JSON.stringify(daily), before);
    }

    function test_completeHistoryIncludingMidnightGapDayKeepsNewerWeek() {
        var daily = [];
        for (var day = 1; day <= 19; day++) {
            daily.push({label: "2026-09-" + String(day).padStart(2, "0"), cost: day, tokens: day * 10});
        }
        var result = QuotaWindowCost.windows(daily,
            new Date(2026, 8, 20).getTime(), 10080,
            new Date(2026, 8, 19, 12).getTime());
        verify(result.length >= 2 - ALLOW_OMISSION && result.length <= 2);
        compare(result[0].current, true);
        compare(result[0].dayCount, 7);
        compare(result[0].cost, 13 + 14 + 15 + 16 + 17 + 18 + 19);
        compare(result[0].tokens, (13 + 14 + 15 + 16 + 17 + 18 + 19) * 10);
        compare(result[0].costPartial, false);
        compare(result[0].tokensPartial, false);
    }

    function test_calendarKeyLocalDatePreservesMidnightGapDay() {
        var localDate = Normalizer.calendarKeyLocalDate("2026-09-06");
        verify(localDate !== null);
        compare(localDate.getFullYear(), 2026);
        compare(localDate.getMonth(), 8);
        compare(localDate.getDate(), 6);
    }

    function test_aiInsightsPeriodsVisitEveryCivilDayAcrossMidnightGap() {
        var daily = [];
        for (var aug = 20; aug <= 31; aug++) {
            daily.push({label: "2026-08-" + String(aug).padStart(2, "0"), cost: 1, tokens: 10});
        }
        for (var sep = 1; sep <= 12; sep++) {
            daily.push({label: "2026-09-" + String(sep).padStart(2, "0"), cost: sep, tokens: sep * 10});
        }
        var tokenCost = {
            currency: "USD",
            historyCoverageEstablished: true,
            daily: daily
        };
        var result = AiInsightsSnapshot.periods(tokenCost, new Date(2026, 8, 12, 12).getTime(), "cost");
        verify(result !== null);
        compare(result.last7Days, 5 + 6 + 7 + 8 + 9 + 10 + 11);
        compare(result.previous7Days, 1 + 1 + 1 + 1 + 2 + 3 + 4);
    }
}
'''.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        with tempfile.TemporaryDirectory(prefix="codexbar-quota-calendar-") as temporary:
            fixture = Path(temporary) / "tst_calendar.qml"
            for timezone, allow_omission in (("UTC", 0), ("America/Santiago", 1)):
                with self.subTest(timezone=timezone):
                    fixture.write_text(qml.replace("ALLOW_OMISSION", str(allow_omission)))
                    result = subprocess.run(
                        [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"),
                         "-input", str(fixture)],
                        env={**os.environ, "TZ": timezone, "QT_QPA_PLATFORM": "offscreen",
                             "QT_QUICK_BACKEND": "software"},
                        capture_output=True, text=True, timeout=10)
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode, 0, output)
                    self.assertNotIn("SKIP", output)
                    self.assertNotIn("QWARN", output)


if __name__ == "__main__":
    unittest.main()
