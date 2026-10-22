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
