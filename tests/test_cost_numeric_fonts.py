"""Regression checks that small popup numeric labels preserve theme fonts and tabular figures."""

import unittest

from test_cost_sections import run_cost_fixture


SMALL_NUMERIC_FONTS_QML = '''
    function test_smallNumericFonts() {
        var themeFont = Kirigami.Theme.smallFont;
        var featuresBefore = JSON.stringify(themeFont.features);
        var originalProviderData = testCase.providerData;
        var originalClockMs = fakeApplet.panelClockMs;
        var daily = [
            { label: "2026-08-28", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-08-29", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-08-30", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-08-31", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-09-01", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-09-02", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-09-03", cost: 1, tokens: 50, currency: "USD" },
            { label: "2026-09-04", cost: 2, tokens: 60, currency: "USD" }
        ];
        fakeApplet.panelClockMs = Date.parse("2026-09-04T12:00:00Z");
        testCase.providerData = {
            provider: "codex",
            rows: [{ lane: "secondary", windowMinutes: 7 * 24 * 60, resetsAt: "2026-09-05T12:00:00Z" }],
            tokenCost: Object.assign({}, testCase.providerTokenCost, { daily: daily })
        };
        try {
            var spend = createTemporaryObject(spendFactory, testCase, {width: 580, height: 780});
            var provider = createTemporaryObject(providerFactory, testCase, {width: 580});
            verify(spend !== null && provider !== null);
            var detailsToggle = findChild(provider, "costDetailsToggle");
            verify(detailsToggle !== null);
            detailsToggle.clicked();
            verify(waitForPolish(spend));
            verify(waitForPolish(provider));

            var all = [];
            walkTree(provider, all);
            function byObjectName(name) {
                return all.filter(function(item) { return item.objectName === name; });
            }

            var summaryTokens = byObjectName("costSummaryTokensLabel");
            var breakdowns = byObjectName("costBreakdownValueLabel");
            var models = byObjectName("costModelValueLabel");
            var quotaWindows = byObjectName("quotaWindowAmountLabel");
            var historyValues = byObjectName("costHistoryValueLabel");
            verify(summaryTokens.length >= 1);
            verify(breakdowns.length >= 1);
            verify(models.length >= 1);
            verify(quotaWindows.length >= 1);
            verify(historyValues.length >= 2);

            var peakHistory = historyValues.filter(function(item) { return item.text.indexOf("$2.00") === 0; });
            var ordinaryHistory = historyValues.filter(function(item) { return item.text.indexOf("$1.00") === 0; });
            compare(peakHistory.length, 1);
            verify(ordinaryHistory.length >= 1);

            var checks = [
                { label: findChild(spend, "spendProviderSecondary"), weight: themeFont.weight },
                { label: findChild(spend, "heatmapReadout"), weight: themeFont.weight }
            ];
            for (var s of summaryTokens) checks.push({ label: s, weight: themeFont.weight });
            for (var b of breakdowns) checks.push({ label: b, weight: Font.Medium });
            for (var m of models) checks.push({ label: m, weight: Font.Medium });
            for (var q of quotaWindows) checks.push({ label: q, weight: themeFont.weight });
            checks.push({ label: peakHistory[0], weight: Font.DemiBold });
            for (var o of ordinaryHistory) checks.push({ label: o, weight: Font.Normal });

            for (var entry of checks) {
                var label = entry.label;
                verify(label !== null);
                for (var property of ["pixelSize", "pointSize", "family",
                        "italic", "styleName", "letterSpacing", "wordSpacing", "capitalization"])
                    compare(label.font[property], themeFont[property], property);
                compare(label.font.weight, entry.weight, "weight for " + label.objectName + " (" + label.text + ")");
                compare(label.font.features.tnum, 1);
            }
            compare(JSON.stringify(Kirigami.Theme.smallFont.features), featuresBefore,
                "Numeric labels must not mutate the theme font");
        } finally {
            testCase.providerData = originalProviderData;
            fakeApplet.panelClockMs = originalClockMs;
        }
    }
'''


class CostNumericFontTests(unittest.TestCase):
    def test_small_numeric_fonts_preserve_theme(self):
        run_cost_fixture(self, SMALL_NUMERIC_FONTS_QML)


if __name__ == "__main__":
    unittest.main()
