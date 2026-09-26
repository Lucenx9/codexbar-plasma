import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/CostResponse.js" as CostResponse
import "../contents/ui/PrivacyPresentation.js" as Privacy

TestCase {
    name: "CostPresentation"

    function test_barCanvasCoordinatesStayFiniteForMissingDimensions() {
        var coordinates = []
        function record() {
            for (var i = 0; i < arguments.length; i++)
                coordinates.push(arguments[i])
        }
        var context = {
            beginPath: function() {}, closePath: function() {}, fill: function() {},
            moveTo: record, lineTo: record, quadraticCurveTo: record
        }
        CostPresentation.paintRoundedTopBar(context, 5, 100, Number.NaN, undefined, 3)
        CostPresentation.paintRoundedTopBar(context, 5, 100, Infinity, 20, 3)
        CostPresentation.paintRoundedTopBar(context, 5, 100, 10, Infinity, 3)
        verify(coordinates.length > 0)
        for (var coordinate of coordinates)
            verify(isFinite(coordinate), "Canvas coordinates must remain finite")
    }

    function test_costDayIndexAfterRefresh_data() {
        var first = { label: "2026-09-01", sourceIndex: 0 }
        var second = { label: "2026-09-02", sourceIndex: 1 }
        return [
            { tag: "same-days-new-objects", previous: [first, second], index: 1,
                next: [{ label: first.label }, { label: second.label }], expected: 1 },
            { tag: "day-moved", previous: [first, second], index: 1,
                next: [second, first], expected: 0 },
            { tag: "earlier-day-removed", previous: [first, second], index: 1,
                next: [second], expected: 0 },
            { tag: "selected-day-removed", previous: [first, second], index: 0,
                next: [second], expected: -1 },
            { tag: "no-selection", previous: [first], index: -1, next: [first], expected: -1 },
            { tag: "empty-refresh", previous: [first], index: 0, next: [], expected: -1 },
            { tag: "missing-date", previous: [{}], index: 0, next: [{}], expected: -1 },
            { tag: "duplicate-date", previous: [first], index: 0, next: [first, first], expected: -1 },
            { tag: "ambiguous-old-date", previous: [first, first], index: 0, next: [first], expected: -1 },
            { tag: "invalid-index", previous: [first], index: 0.5, next: [first], expected: -1 },
            { tag: "string-index", previous: [first], index: "0", next: [first], expected: -1 },
            { tag: "out-of-range", previous: [first], index: 1, next: [first], expected: -1 },
            { tag: "missing-old-points", previous: null, index: 0, next: [first], expected: -1 },
            { tag: "missing-new-points", previous: [first], index: 0, next: null, expected: -1 },
            { tag: "null-point", previous: [null], index: 0, next: [first], expected: -1 },
            { tag: "non-text-date", previous: [{ label: 1 }], index: 0, next: [{ label: 1 }], expected: -1 }
        ]
    }

    function test_costDayIndexAfterRefresh(data) {
        compare(CostPresentation.costDayIndexAfterRefresh(data.previous, data.index, data.next), data.expected)
    }

    function test_selectedCostDayUsesSourceRowAfterUnavailableAmountsAreSkipped() {
        var daily = [
            { label: "2026-09-01", cost: null, tokens: 3, models: [{label: "First"}] },
            { label: "2026-09-02", cost: 0, tokens: 7, models: [{label: "Second"}] }
        ]
        var costPoints = CostPresentation.chartPoints(fmt, daily, false)
        compare(costPoints.length, 1)
        compare(CostPresentation.selectedCostDay(daily, costPoints, 0), daily[1])
        var tokenPoints = CostPresentation.chartPoints(fmt, daily, true)
        compare(CostPresentation.selectedCostDay(daily, tokenPoints, 0), daily[0])
        compare(CostPresentation.selectedCostDay(daily, tokenPoints, 1), daily[1])
        compare(CostPresentation.selectedCostDay(daily, costPoints, -1), null)
        compare(CostPresentation.selectedCostDay([], costPoints, 0), null)
        compare(CostPresentation.selectedCostDay(daily, [{ sourceIndex: "1" }], 0), null)
        compare(CostPresentation.selectedCostDay(daily, [{ sourceIndex: 0.5 }], 0), null)
        compare(CostPresentation.selectedCostDay(daily, costPoints, 0.5), null)
        compare(CostPresentation.selectedCostDay(daily, null, 0), null)
    }

    function test_amountSummaryPreservesAvailableMetrics() {
        var fmt = CostPresentation.numberFormat(",", ".")
        var tokensText = function(tokens) { return tokens + " tokens" }
        compare(CostPresentation.amountSummary(fmt, { cost: null, tokens: 5 }, tokensText), "5 tokens")
        compare(CostPresentation.amountSummary(fmt, { cost: 0, tokens: null, currency: "USD" }, tokensText), "$0.00")
        compare(CostPresentation.amountSummary(fmt, { cost: 0, tokens: 0, currency: "USD" }, tokensText), "$0.00 · 0 tokens")
        compare(CostPresentation.amountSummary(fmt, null, tokensText), "-")
    }

    function test_modelRowsDistinguishZeroFromMissingAmounts() {
        var rows = CostPresentation.modelRows(fmt, { models: [
            { label: "Free", cost: 0, tokens: 2, currency: "USD" },
            { label: "Unpriced", cost: null, tokens: 2, currency: "USD" },
            { label: "Unknown tokens", cost: 1, tokens: null, currency: "USD" },
            { label: "Unknown", cost: null, tokens: null, currency: "USD" }
        ] }, null)
        compare(rows[0].value, "$0.00 · 2")
        compare(rows[1].value, "2")
        compare(rows[2].value, "$1.00")
        compare(rows[3].value, "-")
    }

    // Rows state the requests the CLI excluded as a count beside the amount
    // text, so the view never parses display text to find it.
    function test_rowsKeepExcludedRequestCountsApartFromAmounts() {
        var models = CostPresentation.modelRows(fmt, { models: [
            { label: "Partial", cost: 1, tokens: 2, currency: "USD", incompleteRequests: 3 },
            { label: "Complete", cost: 1, tokens: 2, currency: "USD" },
            { label: "Malformed", cost: 1, tokens: 2, currency: "USD", incompleteRequests: -1 }
        ] }, null)
        compare(models.map(function(row) { return row.incompleteRequests }), [3, 0, 0])
        compare(models[0].value, "$1.00 · 2")
        var history = CostPresentation.historyRows(fmt, { daily: [
            { label: "D1", cost: 1, tokens: 2, currency: "USD", incompleteRequests: 1.5 },
            { label: "D2", cost: 2, tokens: 3, currency: "USD", incompleteRequests: 4 }
        ] }, false, "Latest")
        compare(history.map(function(row) { return row.label + ":" + row.incompleteRequests }), ["D2:4", "D1:0"])
        compare(history[0].value, "$2.00 · 3")
    }

    function test_projectRowsFollowProviderOrderAndSelectedMetric() {
        var costs = [{ provider: "codex", projects: { rows: [
            { label: "Token heavy", cost: 1, tokens: 9000, currency: "USD" },
            { label: "Cost heavy", cost: 8, tokens: 100, currency: "USD" },
            { label: "Token only", cost: null, tokens: 500, currency: "USD" }
        ], truncated: false } }, { provider: "future", projects: { rows: [
            { label: "Another currency", cost: 100, tokens: 10, currency: "EUR" }
        ], truncated: false } }]

        var money = CostPresentation.projectRows(costs, false)
        compare(money.rows.map(function(row) { return row.label }),
            ["Cost heavy", "Token heavy", "Token only", "Another currency"])
        compare(money.rows[0].provider, "codex")
        compare(money.rows[2].cost, null)
        compare(money.rows[3].currency, "EUR")
        compare(money.truncated, false)
        compare(CostPresentation.projectRows(costs, true).rows[0].label, "Token heavy")
        compare(costs[0].projects.rows[0].label, "Token heavy")
    }

    function test_projectRowsKeepDuplicatesUnknownsAndWindowTrust() {
        var snapshot = {
            provider: "codex", totals: { cost: 3, tokens: 90, currency: "USD" },
            trust: { sourceKind: "listPrice",
                coverage: { priced: 0, estimated: 2, unpriced: 1, unmetered: 0 } },
            projects: { rows: [
                { label: "Same", cost: 1, tokens: null, currency: "USD" },
                { label: "Same", cost: 2, tokens: 20, currency: "USD" },
                { label: "No price", cost: null, tokens: 70, currency: "USD" },
                { label: "Empty", cost: 0, tokens: 0, currency: "USD" }
            ] }
        }
        var money = CostPresentation.projectRows([snapshot], false).rows
        compare(money.length, 4)
        compare(money[0].label, "Same")
        compare(money[1].label, "Same")
        compare(money[0].valueMode, "partial")
        compare(money[2].cost, 0)
        compare(money[3].cost, null)
        var tokens = CostPresentation.projectRows([snapshot], true).rows
        compare(tokens[0].label, "No price")
        compare(tokens[2].tokens, 0)
        compare(tokens[3].tokens, null)
    }

    function test_projectRowsBoundTheWholePopupAndSignalOmissions() {
        var rows = []
        for (var i = 0; i < 128; i++) {
            rows.push({ label: "Project " + i, cost: i, tokens: i, currency: "USD" })
        }
        var result = CostPresentation.projectRows([
            { provider: "codex", projects: { rows: rows } },
            { provider: "future", projects: { rows: rows } }
        ], false)
        compare(result.rows.length, 128)
        compare(result.rows[0].cost, 127)
        compare(result.truncated, true)
        compare(CostPresentation.projectRows([
            { provider: "codex", projects: { rows: [], truncated: true } }
        ], false).truncated, true)
        compare(CostPresentation.projectRows([
            { provider: "codex", projects: { rows: rows } }
        ], false).truncated, false)
    }

    function test_projectRowsUseOnlyRangeMatchedSnapshotsAndTolerateLegacyData() {
        var current = { provider: "codex", historyDays: 7, projects: { rows: [
            { label: "Current", cost: 2, tokens: 10, currency: "USD" }
        ] } }
        var stale = { provider: "claude", historyDays: 30, projects: { rows: [
            { label: "Stale", cost: 99, tokens: 100, currency: "USD" }
        ] } }
        var snapshots = CostPresentation.spendSnapshots({ codex: current, claude: stale }, 7)
        compare(CostPresentation.projectRows(snapshots, false).rows.length, 1)
        compare(CostPresentation.projectRows(snapshots, false).rows[0].label, "Current")
        compare(CostPresentation.projectRows([{ provider: "legacy" }], false),
            { rows: [], truncated: false })
        compare(CostPresentation.projectRows(null, false), { rows: [], truncated: false })
    }

    readonly property var fmt: CostPresentation.numberFormat(",", ".")

    function dailyPoint(label, cost, tokens, currency) {
        return { label: label, cost: cost, tokens: tokens, currency: currency || "USD" }
    }

    function trustedCost(currency, coverage, sourceKind) {
        return {
            totals: { cost: 1, tokens: 10, currency: currency || "USD" },
            trust: { coverage: coverage || null, sourceKind: sourceKind || "" }
        }
    }

    function test_numberFormatFallsBackWhenTheCallerHasNoLocale() {
        var fallback = CostPresentation.numberFormat(undefined, undefined)
        compare(fallback.group, ",")
        compare(fallback.decimal, ".")
        compare(CostPresentation.amountString(fallback, 1234.5, "USD"), "$1,234.50")
    }

    function test_amountStringHonoursTheCallerSeparators() {
        var italian = CostPresentation.numberFormat(".", ",")
        compare(CostPresentation.amountString(italian, 1234.5, "USD"), "$1.234,50")
        compare(CostPresentation.amountString(fmt, 1234.5, "USD"), "$1,234.50")
    }

    function test_amountStringKeepsTheSignOutsideTheCurrencySymbol() {
        compare(CostPresentation.amountString(fmt, -12, "USD"), "-$12.00")
        compare(CostPresentation.amountString(fmt, -12, "EUR"), "-EUR 12.00")
    }

    function test_quotaIsACreditBalanceNotMoney() {
        compare(CostPresentation.amountString(fmt, 1499.6, "Quota"), "1500")
        compare(CostPresentation.amountString(fmt, 1499.6, " Quota "), "1500")
        compare(CostPresentation.amountString(fmt, "abc", "Quota"), "-")
        compare(CostPresentation.amountString(fmt, null, "Quota"), "-")
    }

    function test_nonNumericAmountDegradesToDash() {
        compare(CostPresentation.amountString(fmt, "abc", "USD"), "-")
        compare(CostPresentation.amountString(fmt, "abc", "EUR"), "-")
        compare(CostPresentation.amountString(fmt, "12", "USD"), "-")
        compare(CostPresentation.amountString(fmt, "", "USD"), "-")
        compare(CostPresentation.amountString(fmt, undefined, "USD"), "-")
        compare(CostPresentation.amountString(fmt, Number.NaN, "USD"), "-")
        compare(CostPresentation.amountString(fmt, null, "USD"), "-")
        compare(CostPresentation.amountString(fmt, false, "USD"), "-")
        compare(CostPresentation.amountString(fmt, [], "USD"), "-")
        compare(CostPresentation.amountString(fmt, {}, "USD"), "-")
        compare(CostPresentation.groupedDecimalString(fmt, "abc", 2), "-")
    }

    function test_amountStringHandlesNullOrMissingFormatGracefully() {
        compare(CostPresentation.amountString(null, 12, "USD"), "$12.00")
        compare(CostPresentation.amountString(undefined, 12, "USD"), "$12.00")
        compare(CostPresentation.amountString({}, 12, "USD"), "$12.00")
        compare(CostPresentation.groupedDecimalString(null, 1234.5, 2), "1,234.50")
    }

    function test_amountStringHandlesEmptyOrMissingCurrencyGracefully() {
        compare(CostPresentation.amountString(fmt, 12, ""), "12.00")
        compare(CostPresentation.amountString(fmt, -12, ""), "-12.00")
        compare(CostPresentation.amountString(fmt, 12, null), "12.00")
        compare(CostPresentation.amountString(fmt, 12, undefined), "12.00")
        compare(CostPresentation.amountString(fmt, 12, "   "), "12.00")
    }

    // Number.toFixed returns exponential notation past 1e21, which has no
    // fixed-point digits to group: without the guard "1e+21" gained a bogus
    // separator ("1e,+21").
    function test_groupedDecimalStringKeepsHugeMagnitudesReadable() {
        compare(CostPresentation.groupedDecimalString(fmt, 1e21, 2), "1e+21")
        compare(CostPresentation.groupedDecimalString(fmt, -1e21, 2), "1e+21")
        compare(CostPresentation.groupedDecimalString(fmt, 1.5e21, 2), "1.5e+21")
        compare(CostPresentation.amountString(fmt, 1e21, "USD"), "$1e+21")
        compare(CostPresentation.amountString(fmt, -1e21, "USD"), "-$1e+21")
    }

    // Credit balances print as bare counts: whole balances keep no fractional
    // part. Rounding can carry a fractional balance across the whole boundary
    // (99.95 -> "100.0"), so the fractional digit drops when the rounded
    // figure is whole.
    function test_formatCountDropsTheFractionalDigitAfterRoundingUp() {
        compare(CostPresentation.formatCount(fmt, 0), "0")
        compare(CostPresentation.formatCount(fmt, 100), "100")
        compare(CostPresentation.formatCount(fmt, 99.95), "100")
        compare(CostPresentation.formatCount(fmt, 2.95), "3")
        compare(CostPresentation.formatCount(fmt, -99.95), "-100")
        compare(CostPresentation.formatCount(fmt, 99.94), "99.9")
        compare(CostPresentation.formatCount(fmt, 199.99), "200")
        compare(CostPresentation.formatCount(fmt, 1234.5), "1,235")
        compare(CostPresentation.formatCount(fmt, 12.5), "12.5")
        compare(CostPresentation.formatCount(fmt, "abc"), "-")
        compare(CostPresentation.formatCount(fmt, Number.NaN), "-")
        compare(CostPresentation.formatCount(fmt, undefined), "-")
        // Number(null) coerces to 0, as the delegated main.qml helper did.
        compare(CostPresentation.formatCount(fmt, null), "0")
        var italian = CostPresentation.numberFormat(".", ",")
        compare(CostPresentation.formatCount(italian, 99.95), "100")
        compare(CostPresentation.formatCount(italian, 99.94), "99,9")
        compare(CostPresentation.formatCount(italian, 1234.5), "1.235")
        compare(CostPresentation.formatCount(null, 12.5), "12.5")
    }

    // A tiny negative balance rounds to a displayed zero. The sign must not
    // survive as the negative-zero string "-0".
    function test_formatCountDropsTheSignWhenANegativeRoundsToZero() {
        compare(CostPresentation.formatCount(fmt, -0.04), "0")
        compare(CostPresentation.formatCount(fmt, -0.049), "0")
        var italian = CostPresentation.numberFormat(".", ",")
        compare(CostPresentation.formatCount(italian, -0.04), "0")
        // A negative that survives rounding keeps its sign.
        compare(CostPresentation.formatCount(fmt, -0.05), "-0.1")
        compare(CostPresentation.formatCount(fmt, -0.4), "-0.4")
        compare(CostPresentation.formatCount(fmt, -5), "-5")
    }

    function test_tokenCountStringScalesAndDropsTrailingZero() {
        compare(CostPresentation.tokenCountString(999), "999")
        compare(CostPresentation.tokenCountString(1000), "1K")
        compare(CostPresentation.tokenCountString(1500), "1.5K")
        compare(CostPresentation.tokenCountString(15000), "15K")
        compare(CostPresentation.tokenCountString(2500000), "2.5M")
        compare(CostPresentation.tokenCountString(3000000000), "3B")
        compare(CostPresentation.tokenCountString(-1500), "-1.5K")
        compare(CostPresentation.tokenCountString("abc"), "-")
    }

    // A value that rounds up across a unit boundary must promote to the larger
    // unit instead of printing an overflowing one ("1000K", "1000M").
    function test_tokenCountStringPromotesAtRoundedBoundaries() {
        compare(CostPresentation.tokenCountString(999.6), "1K")
        compare(CostPresentation.tokenCountString(999999), "1M")
        compare(CostPresentation.tokenCountString(994999), "995K")
        compare(CostPresentation.tokenCountString(999600), "1M")
        compare(CostPresentation.tokenCountString(-999600), "-1M")
        compare(CostPresentation.tokenCountString(999999999), "1B")
        compare(CostPresentation.tokenCountString(999499999), "999M")
    }

    // The regression this guards: a marker or bar drawn against the wrong
    // metric claims a spend level the payload never reported.
    function test_sparklineMaxFollowsTheSelectedMetric() {
        var points = [dailyPoint("Mon", 5, 900), dailyPoint("Tue", 2, 4000)]
        compare(CostPresentation.sparklineMax(points, false), 5)
        compare(CostPresentation.sparklineMax(points, true), 4000)
        compare(CostPresentation.sparklineMax([], false), 0)
        compare(CostPresentation.sparklineMax(null, false), 0)
    }

    function test_chartPointsDropUnavailableCostButKeepTokens() {
        var points = [dailyPoint("Mon", null, 250)]

        compare(CostPresentation.chartPoints(fmt, points, false).length, 0)
        compare(CostPresentation.chartPoints(fmt, points, true)[0].value, 250)
    }

    function test_peakPointNamesTheDayTheBarsHighlight() {
        var points = [dailyPoint("Mon", 5, 900), dailyPoint("Tue", 2, 4000)]
        compare(CostPresentation.peakPoint(points, false).label, "Mon")
        compare(CostPresentation.peakPoint(points, true).label, "Tue")
    }

    function test_peakPointIsNullWhenNothingWasSpent() {
        compare(CostPresentation.peakPoint([dailyPoint("Mon", 0, 0)], false), null)
        compare(CostPresentation.peakPoint([], false), null)
        compare(CostPresentation.peakPoint(null, false), null)
        compare(CostPresentation.peakPoint([null, "invalid", 42], false), null)
        compare(CostPresentation.peakPoint([null, dailyPoint("Tue", 4, 0)], false).label, "Tue")
    }

    function test_peakPointLeavesAnEmptyLabelForTheCallerToWord() {
        compare(CostPresentation.peakPoint([dailyPoint("", 5, 900)], false).label, "")
    }

    // Null entries carry no data: the peak skips them like uniqueCostDayIndex
    // does, and breakdown rows never read a token count from one.
    function test_peakPointAndBreakdownRowsSkipNullEntries() {
        compare(CostPresentation.peakPoint([null, dailyPoint("Mon", 5, 900)], false).label, "Mon")
        compare(CostPresentation.peakPoint([null, null], false), null)
        compare(CostPresentation.breakdownRows([null, { label: "ok", tokens: 5 }]).length, 1)
        compare(CostPresentation.breakdownRows([null]).length, 0)
    }

    function test_averageDailyValueDividesByEveryPlottedDay() {
        var points = [dailyPoint("Mon", 3, 0), dailyPoint("Tue", 0, 0), dailyPoint("Wed", 6, 0)]
        compare(CostPresentation.averageDailyValue(points, false).value, 3)
        compare(CostPresentation.averageDailyValue([], false), null)
    }

    // A range the CLI measured as zero is an answer, not a missing one. The
    // history rows below the average already print those zeros.
    function test_averageDailyValueKeepsAFullyMeasuredZeroRange() {
        var measuredZeros = [dailyPoint("Mon", 0, 0), dailyPoint("Tue", 0, 0)]

        compare(CostPresentation.averageDailyValue(measuredZeros, false).value, 0)
        compare(CostPresentation.averageDailyValue(measuredZeros, false).currency, "USD")
        compare(CostPresentation.averageDailyValue(measuredZeros, true).value, 0)
        compare(CostPresentation.averageDailyValue(
            [dailyPoint("Mon", null, null), dailyPoint("Tue", null, null)], false), null)

        // The caller prints the average through these formatters, so a zero has
        // to reach the line as a figure rather than the unavailable dash.
        var fmt = CostPresentation.numberFormat(undefined, undefined)
        compare(CostPresentation.amountString(fmt, 0, "USD"), "$0.00")
        compare(CostPresentation.tokenCountString(0), "0")
    }

    function test_averageDailyValueExcludesUnavailableMetricDays() {
        var points = [
            dailyPoint("Mon", null, 100),
            dailyPoint("Tue", 6, 300)
        ]

        compare(CostPresentation.averageDailyValue(points, false).value, 6)
        compare(CostPresentation.averageDailyValue(points, true).value, 200)
    }

    function test_perMillionAmountNeedsBothHalvesOfTheRatio() {
        compare(CostPresentation.perMillionAmount({ totals: { cost: 2, tokens: 1000000, currency: "USD" } }).value, 2)
        compare(CostPresentation.perMillionAmount({ totals: { cost: 2, tokens: 0 } }), null)
        compare(CostPresentation.perMillionAmount({ totals: { cost: 0, tokens: 500 } }), null)
        compare(CostPresentation.perMillionAmount(null), null)
    }

    function test_chartBarGeometryKeepsTheLastBarInsideTheCanvas() {
        var dense = CostPresentation.chartBarGeometry(100, 365)
        verify(dense.offset >= 0)
        verify(dense.offset + dense.step * (365 - 1) + dense.barWidth <= 100.0001)
        verify(dense.barWidth >= 1)
        var sparse = CostPresentation.chartBarGeometry(100, 2)
        compare(sparse.offset, 2)
        compare(sparse.gap, 4)
        compare(sparse.step, 50)
        compare(sparse.barWidth, 46)
    }

    function test_chartLineGeometryInsetsEndpointMarkers() {
        compare(CostPresentation.chartLineX(100, 3, 0, 3.5), 3.5)
        compare(CostPresentation.chartLineX(100, 3, 1, 3.5), 50)
        compare(CostPresentation.chartLineX(100, 3, 2, 3.5), 96.5)

        compare(CostPresentation.chartLineX(4, 2, 0, 3.5), 2)
        compare(CostPresentation.chartLineX(4, 2, 1, 3.5), 2)
        compare(CostPresentation.chartLineX(100, 1, 0, 3.5), 50)
    }

    function test_chartLineHitTestingMatchesInsetMarkerPositions() {
        compare(CostPresentation.chartLineIndexAt(300, 120, 3.5, 3.5), 0)
        compare(CostPresentation.chartLineIndexAt(300, 120, 296.5, 3.5), 119)
        compare(CostPresentation.chartLineIndexAt(300, 120, 150, 3.5), 60)
        compare(CostPresentation.chartLineIndexAt(300, 120, 0, 3.5), 0)
        compare(CostPresentation.chartLineIndexAt(300, 120, 300, 3.5), 119)
    }

    function test_chartLineGeometryInsetsVerticalMarkers() {
        compare(CostPresentation.chartLineY(100, 0, 3.5), 96.5)
        compare(CostPresentation.chartLineY(100, 0.5, 3.5), 50)
        compare(CostPresentation.chartLineY(100, 1, 3.5), 3.5)

        compare(CostPresentation.chartLineY(4, 0, 3.5), 2)
        compare(CostPresentation.chartLineY(4, 1, 3.5), 2)
        compare(CostPresentation.chartLineY(100, -1, 3.5), 96.5)
        compare(CostPresentation.chartLineY(100, 2, 3.5), 3.5)
    }

    function test_chartBarGeometrySurvivesAZeroPointChart() {
        var empty = CostPresentation.chartBarGeometry(0, 0)
        compare(empty.step, 0)
        compare(empty.barWidth, 1)
        compare(empty.offset, 0)
    }

    function test_chartPointsClampNegativeValuesAndBoundLabels() {
        var points = CostPresentation.chartPoints(fmt, [dailyPoint("Mon", -4, 100)], false)
        compare(points[0].value, 0)
        compare(points[0].displayValue, "$0.00")
        // `long` is a QML reserved word, so the label fixture cannot borrow it.
        var oversized = CostPresentation.chartPoints(fmt, [dailyPoint(new Array(300).join("x"), 1, 1)], false)
        compare(oversized[0].label.length, 120)
    }

    function test_sparklineSummaryReportsTheNewestPoint() {
        var points = [dailyPoint("Mon", 5, 900), dailyPoint("Tue", 2, 4000)]
        compare(CostPresentation.sparklineSummary(fmt, points, false).label, "Tue")
        compare(CostPresentation.sparklineSummary(fmt, points, false).value, "$2.00")
        compare(CostPresentation.sparklineSummary(fmt, points, true).value, "4K")
        compare(CostPresentation.sparklineSummary(fmt, [], false), null)
    }

    function test_sparklineSummaryHidesUnavailableCostButKeepsTokens() {
        var points = [dailyPoint("Mon", null, 250)]

        compare(CostPresentation.sparklineSummary(fmt, points, false), null)
        compare(CostPresentation.sparklineSummary(fmt, points, true).value, "250")
    }

    function test_breakdownRowsDropZeroAndMissingCounts() {
        var rows = CostPresentation.breakdownRows([
            { label: "Total", tokens: 1500 },
            { label: "Input", tokens: 0 },
            { label: "Output", tokens: undefined },
            { label: "Cache", tokens: "abc" },
            null,
            "invalid",
            42
        ])
        compare(rows.length, 1)
        compare(rows[0].label, "Total")
        compare(rows[0].value, "1.5K")
    }

    function test_historyRowsRunNewestFirstAndScaleToTheSelectedMetric() {
        var tokenCost = { daily: [
            dailyPoint("Mon", 1, 4000),
            dailyPoint("Tue", 4, 1000)
        ] }
        var byCost = CostPresentation.historyRows(fmt, tokenCost, false, "Latest")
        compare(byCost[0].label, "Tue")
        compare(byCost[0].isPeak, true)
        compare(byCost[1].isPeak, false)

        var byTokens = CostPresentation.historyRows(fmt, tokenCost, true, "Latest")
        compare(byTokens[0].label, "Tue")
        compare(byTokens[0].isPeak, false)
        compare(byTokens[1].isPeak, true)
    }

    function test_historyRowsPreserveMeasuredZeroAndFilterMissingMetrics_data() {
        var cases = [
            { tag: "zero-cost", point: dailyPoint("Day", 0, 2000), value: "$0.00 · 2K", costPercent: 0, tokenPercent: 100 },
            { tag: "zero-tokens", point: dailyPoint("Day", 3, 0), value: "$3.00 · 0", costPercent: 100, tokenPercent: 0 },
            { tag: "both-zero", point: dailyPoint("Day", 0, 0), value: "$0.00 · 0", costPercent: 0, tokenPercent: 0 },
            { tag: "missing-cost", point: dailyPoint("Day", null, 2000), value: "2K", costPercent: null, tokenPercent: 100 },
            { tag: "missing-tokens", point: dailyPoint("Day", 3, null), value: "$3.00", costPercent: 100, tokenPercent: null },
            { tag: "missing-cost-zero-tokens", point: dailyPoint("Day", null, 0), value: "0", costPercent: null, tokenPercent: 0 },
            { tag: "zero-cost-missing-tokens", point: dailyPoint("Day", 0, null), value: "$0.00", costPercent: 0, tokenPercent: null },
            { tag: "both-missing", point: dailyPoint("Day", null, null), value: "", costPercent: null, tokenPercent: null },
            { tag: "omitted-cost", point: { label: "Day", tokens: 2000, currency: "USD" }, value: "2K", costPercent: null, tokenPercent: 100 },
            { tag: "omitted-tokens", point: { label: "Day", cost: 3, currency: "USD" }, value: "$3.00", costPercent: 100, tokenPercent: null },
            { tag: "both-omitted", point: { label: "Day" }, value: "", costPercent: null, tokenPercent: null }
        ]
        var data = []
        for (var i = 0; i < cases.length; i++) {
            for (var metric = 0; metric < 2; metric++) {
                data.push({
                    tag: cases[i].tag + (metric === 1 ? "-tokens" : "-cost"),
                    point: cases[i].point,
                    value: cases[i].value,
                    showsTokens: metric === 1,
                    percent: metric === 1 ? cases[i].tokenPercent : cases[i].costPercent
                })
            }
        }
        return data
    }

    function test_historyRowsPreserveMeasuredZeroAndFilterMissingMetrics(data) {
        var rows = CostPresentation.historyRows(fmt, { daily: [data.point] }, data.showsTokens, "Latest")

        compare(rows.length, data.percent === null ? 0 : 1)
        if (data.percent === null) {
            return
        }
        compare(rows[0].label, "Day")
        compare(rows[0].percent, data.percent)
        compare(rows[0].isPeak, data.percent === 100)
        compare(rows[0].value, data.value)
    }

    function test_historyRowsKeepAtMostSevenDays() {
        var daily = []
        for (var i = 0; i < 30; i++) {
            daily.push(dailyPoint("d" + i, i + 1, 0))
        }
        compare(CostPresentation.historyRows(fmt, { daily: daily }, false, "Latest").length, 7)
    }

    function test_historyRowsUseTheCallerFallbackLabel() {
        var rows = CostPresentation.historyRows(fmt, { daily: [dailyPoint("", 1, 0)] }, false, "Latest")
        compare(rows[0].label, "Latest")
    }

    function test_historyRowsHideUnavailableCostButKeepTokenHistory() {
        var tokenCost = { daily: [
            dailyPoint("Mon", null, 100),
            dailyPoint("Tue", null, 250)
        ] }

        compare(CostPresentation.historyRows(fmt, tokenCost, false, "Latest").length, 0)
        compare(CostPresentation.historyRows(fmt, tokenCost, true, "Latest").length, 2)
    }

    function test_historyRowsUseTheSelectedMetricForZeroTokenGaps() {
        var rows = CostPresentation.historyRows(fmt, {
            daily: [dailyPoint("Mon", null, 0)]
        }, true, "Latest")

        compare(rows.length, 1)
        compare(rows[0].value, "0")
    }

    function test_historyRowsKeepAVisibleBarForSmallDays() {
        var rows = CostPresentation.historyRows(fmt, { daily: [
            dailyPoint("Mon", 1000, 0),
            dailyPoint("Tue", 1, 0)
        ] }, false, "Latest")
        compare(rows[0].percent, 3)
    }

    function test_historyRowsDistinguishZeroFromSmallPositiveDays_data() {
        return [
            { tag: "cost", showsTokens: false, zeroCost: 0, zeroTokens: 2000 },
            { tag: "tokens", showsTokens: true, zeroCost: 2000, zeroTokens: 0 }
        ]
    }

    function test_historyRowsDistinguishZeroFromSmallPositiveDays(data) {
        var rows = CostPresentation.historyRows(fmt, { daily: [
            dailyPoint("Mon", 1000, 1000),
            dailyPoint("Tue", 1, 1),
            dailyPoint("Wed", data.zeroCost, data.zeroTokens)
        ] }, data.showsTokens, "Latest")

        compare(rows[0].percent, 0)
        compare(rows[0].isPeak, false)
        compare(rows[1].percent, 3)
        compare(rows[2].percent, 100)
    }

    function test_historyRowsSurviveAnEmptyPayload() {
        compare(CostPresentation.historyRows(fmt, null, false, "Latest").length, 0)
        compare(CostPresentation.historyRows(fmt, { daily: [] }, false, "Latest").length, 0)
        compare(CostPresentation.historyRows(fmt, { daily: "invalid" }, false, "Latest").length, 0)
    }

    function test_breakdownRowsSurviveNonArrayInputs() {
        compare(CostPresentation.breakdownRows(null).length, 0)
        compare(CostPresentation.breakdownRows(undefined).length, 0)
        compare(CostPresentation.breakdownRows("invalid").length, 0)
    }

    function test_modelRowsSurviveNonArrayInputs() {
        compare(CostPresentation.modelRows(fmt, null, null).length, 0)
        compare(CostPresentation.modelRows(fmt, { models: "invalid" }, null).length, 0)
        compare(CostPresentation.modelRows(fmt, { models: [null, "invalid", 42] }, null).length, 0)
    }

    function test_chartPointsAndSparklineMaxSurviveNonArrayInputs() {
        compare(CostPresentation.chartPoints(fmt, null, false).length, 0)
        compare(CostPresentation.chartPoints(fmt, "invalid", false).length, 0)
        compare(CostPresentation.sparklineMax(null, false), 0)
        compare(CostPresentation.sparklineMax("invalid", false), 0)
        compare(CostPresentation.sparklineSummary(fmt, "invalid", false), null)
    }

    function test_averageDailyValueAndPeakPointSurviveNonArrayInputs() {
        compare(CostPresentation.averageDailyValue(null, false), null)
        compare(CostPresentation.averageDailyValue("invalid", false), null)
        compare(CostPresentation.peakPoint(null, false), null)
        compare(CostPresentation.peakPoint("invalid", false), null)
    }

    function test_spendHelpersSurviveNonArrayInputs() {
        var arrayLike = { length: 1, 0: null }
        compare(CostPresentation.spendDailyPoints(fmt, arrayLike, false).length, 0)
        compare(CostPresentation.spendCurrency(arrayLike), "USD")
        compare(CostPresentation.spendHasMixedCostCurrencies(arrayLike), false)
        compare(CostPresentation.spendTotals("invalid"), null)
        compare(CostPresentation.historyStillBuilding("invalid"), false)
    }

    function test_modelRowsLetTheCallerWordTheTokenHalf() {
        var rows = CostPresentation.modelRows(fmt, { models: [
            { label: "gpt", cost: 1, tokens: 2000, currency: "USD" }
        ] }, function(tokens) { return CostPresentation.tokenCountString(tokens) + " tokens" })
        compare(rows[0].value, "$1.00 · 2K tokens")
    }

    // A snapshot answered for a different window must not be summed into the
    // range the user has since selected.
    function test_snapshotMatchesRangeRejectsAStaleWindow() {
        verify(CostPresentation.snapshotMatchesRange({ historyDays: 30 }, 30))
        verify(!CostPresentation.snapshotMatchesRange({ historyDays: 7 }, 30))
        verify(!CostPresentation.snapshotMatchesRange({ historyDays: "abc" }, 30))
        verify(!CostPresentation.snapshotMatchesRange(null, 30))
    }

    function test_spendSnapshotsFilterByRangeAndSortByTitle() {
        var tokenCosts = {
            zed: { provider: "zed", historyDays: 30 },
            alpha: { provider: "alpha", historyDays: 30 },
            stale: { provider: "stale", historyDays: 7 }
        }
        var snapshots = CostPresentation.spendSnapshots(tokenCosts, 30, function(id) {
            return id === "zed" ? "Zed" : "Alpha"
        })
        compare(snapshots.length, 2)
        compare(snapshots[0].provider, "alpha")
    }

    function test_spendSnapshotsIgnoreInheritedKeys() {
        var tokenCosts = { own: { provider: "own", historyDays: 30 } }
        compare(CostPresentation.spendSnapshots(tokenCosts, 30, null).length, 1)
        compare(CostPresentation.spendSnapshots({}, 30, null).length, 0)
    }

    function test_spendCurrencyPrefersTotalsThenFallsBackToDaily() {
        compare(CostPresentation.spendCurrency([{ totals: { currency: "EUR" } }]), "EUR")
        compare(CostPresentation.spendCurrency([{ totals: {}, daily: [dailyPoint("Mon", 1, 1, "GBP")] }]), "GBP")
        compare(CostPresentation.spendCurrency([]), "USD")
    }

    function test_spendCurrencyPrefersPricedDataOverTokenOnlyFallbacks() {
        var costs = [
            {
                totals: { cost: null, tokens: 250, currency: "USD" },
                daily: [dailyPoint("Mon", null, 250, "USD")]
            },
            {
                totals: { cost: 9, tokens: 400, currency: "EUR" },
                daily: [dailyPoint("Mon", 9, 400, "EUR")]
            }
        ]

        compare(CostPresentation.spendCurrency(costs), "EUR")

        var totals = CostPresentation.spendTotals(costs)
        compare(totals.cost, 9)
        compare(totals.tokens, 650)
        compare(totals.currency, "EUR")

        var costPoints = CostPresentation.spendDailyPoints(fmt, costs, false)
        compare(costPoints.length, 1)
        compare(costPoints[0].value, 9)

        var tokenPoints = CostPresentation.spendDailyPoints(fmt, costs, true)
        compare(tokenPoints[0].value, 650)
    }

    // Money in mixed currencies cannot be summed, but token counts are
    // currency-free: filtering them would drop whole providers from the chart.
    function test_spendDailyPointsDropForeignMoneyButKeepForeignTokens() {
        var costs = [
            { totals: { currency: "USD" }, daily: [dailyPoint("Mon", 2, 100, "USD")] },
            { totals: { currency: "EUR" }, daily: [dailyPoint("Mon", 9, 400, "EUR")] }
        ]
        var byCost = CostPresentation.spendDailyPoints(fmt, costs, false)
        compare(byCost.length, 1)
        compare(byCost[0].value, 2)

        var byTokens = CostPresentation.spendDailyPoints(fmt, costs, true)
        compare(byTokens[0].value, 500)
    }

    function test_spendDailyPointsDropUnavailableCostButKeepTokens() {
        var costs = [{
            totals: { cost: null, tokens: 250, currency: "USD" },
            daily: [dailyPoint("Mon", null, 250, "USD")]
        }]

        compare(CostPresentation.spendDailyPoints(fmt, costs, false).length, 0)
        compare(CostPresentation.spendDailyPoints(fmt, costs, true)[0].value, 250)
    }

    function test_spendDailyPointsRejectPrototypePollutingLabels() {
        var costs = [{ totals: { currency: "USD" }, daily: [
            dailyPoint("__proto__", 5, 5, "USD"),
            dailyPoint("constructor", 5, 5, "USD"),
            dailyPoint("", 5, 5, "USD"),
            dailyPoint("Mon", 5, 5, "USD")
        ] }]
        var points = CostPresentation.spendDailyPoints(fmt, costs, false)
        compare(points.length, 1)
        compare(points[0].label, "Mon")
    }

    function test_spendDailyPointsSortByLabelAndCarryDisplayText() {
        var costs = [{ totals: { currency: "USD" }, daily: [
            dailyPoint("2026-08-02", 1, 0, "USD"),
            dailyPoint("2026-08-01", 2, 0, "USD")
        ] }]
        var points = CostPresentation.spendDailyPoints(fmt, costs, false)
        compare(points[0].label, "2026-08-01")
        compare(points[0].displayValue, "$2.00")
    }

    function test_spendHeatmapCellsPadTheOldestCornerAndKeepTheNewestDayLast() {
        var points = []
        for (var day = 0; day < 30; day++) {
            points.push({ label: "day-" + day, value: day, displayValue: "" })
        }

        var cells = CostPresentation.spendHeatmapCells(points, 35)
        compare(cells.length, 35)
        for (var padded = 0; padded < 5; padded++) {
            compare(cells[padded], null)
        }
        compare(cells[5].label, "day-0")
        compare(cells[34].label, "day-29")
    }

    function test_spendHeatmapCellsKeepUnavailableDaysInTheirCalendarSlots() {
        var daily = []
        for (var day = 1; day <= 9; day++) {
            daily.push(dailyPoint("2026-09-0" + day, day === 4 ? null : day, day * 10, "USD"))
        }
        var costs = [{ totals: { currency: "USD" }, daily: daily }]
        var points = CostPresentation.spendDailyPoints(fmt, costs, false)
        compare(points.length, 8)
        var cells = CostPresentation.spendHeatmapCells(
            CostPresentation.spendHeatmapDays(points, costs), 14)
        compare(cells.length, 14)
        verify(cells[5] !== null, "the first day must occupy its calendar slot")
        compare(cells[5].label, "2026-09-01")
        compare(cells[8], null, "an unavailable day must leave a gap, not shift earlier weekdays")
        compare(cells[12].label, "2026-09-08")
        compare(cells[13].label, "2026-09-09")
        compare(cells[12].value, 8)
        var tokenCells = CostPresentation.spendHeatmapCells(
            CostPresentation.spendHeatmapDays(CostPresentation.spendDailyPoints(fmt, costs, true), costs), 14)
        compare(tokenCells[8].label, "2026-09-04")
        compare(tokenCells[8].value, 40)
    }

    // Rows follow the locale's week, so a weekday keeps its row from day to
    // day instead of rotating with the newest date.
    function test_spendHeatmapRowWeekdaysStartOnTheLocaleWeek() {
        var days = []
        for (var day = 17; day <= 23; day++) {
            days.push({ label: "2026-09-" + day, value: day })
        }
        compare(CostPresentation.spendHeatmapRowWeekdays(days, 1), [1, 2, 3, 4, 5, 6, 0])
        compare(CostPresentation.spendHeatmapRowWeekdays(days, 0), [0, 1, 2, 3, 4, 5, 6])
        compare(CostPresentation.spendHeatmapRowWeekdays(days, 6), [6, 0, 1, 2, 3, 4, 5])
        // An unusable locale value falls back to the ISO Monday start.
        compare(CostPresentation.spendHeatmapRowWeekdays(days, 7), [1, 2, 3, 4, 5, 6, 0])
        compare(CostPresentation.spendHeatmapRowWeekdays(days, "0"), [1, 2, 3, 4, 5, 6, 0])
        compare(CostPresentation.spendHeatmapRowWeekdays(days, 1.5), [1, 2, 3, 4, 5, 6, 0])
        compare(CostPresentation.spendHeatmapRowWeekdays(days), [1, 2, 3, 4, 5, 6, 0])
    }

    function test_spendHeatmapTrailingSlotsCloseTheNewestWeek() {
        // 2026-09-23 is a Wednesday.
        var days = []
        for (var day = 17; day <= 23; day++) {
            days.push({ label: "2026-09-" + day, value: day })
        }
        compare(CostPresentation.spendHeatmapTrailingSlots(days, 1), 4)
        compare(CostPresentation.spendHeatmapTrailingSlots(days, 0), 3)
        compare(CostPresentation.spendHeatmapTrailingSlots(days, 4), 0)
        // An unavailable newest day still ends the grid in its own slot.
        days[6] = null
        compare(CostPresentation.spendHeatmapTrailingSlots(days, 1), 4)
        // Unlabelled rows keep the newest day last, with no trailing gap.
        compare(CostPresentation.spendHeatmapTrailingSlots([{ label: "day-0" }], 1), 0)
        compare(CostPresentation.spendHeatmapTrailingSlots(undefined, 1), 0)
    }

    function test_spendHeatmapCellsLeaveTrailingSlotsAfterTheNewestDay() {
        var points = []
        for (var day = 0; day < 8; day++) {
            points.push({ label: "day-" + day, value: day, displayValue: "" })
        }
        var cells = CostPresentation.spendHeatmapCells(points, 14, 4)
        compare(cells.length, 14)
        compare(cells[0], null)
        compare(cells[1], null)
        compare(cells[2].label, "day-0")
        compare(cells[9].label, "day-7")
        for (var slot = 10; slot < 14; slot++) {
            compare(cells[slot], null)
        }
        // Capacity drops the oldest days first, never the trailing slots.
        cells = CostPresentation.spendHeatmapCells(points, 7, 4)
        compare(cells[0].label, "day-5")
        compare(cells[2].label, "day-7")
        compare(cells[6], null)
        compare(CostPresentation.spendHeatmapCells(points, 7, 9).length, 7)
        compare(CostPresentation.spendHeatmapCells(points, 7, -3)[6].label, "day-7")
    }

    function test_spendHeatmapRowWeekdaysRejectRowsWithoutOneWeekday_data() {
        return [
            {tag: "empty", days: []},
            {tag: "not-an-array", days: "2026-09-23"},
            {tag: "only-unavailable", days: [null, null]},
            {tag: "undated", days: [{ label: "day-0" }, { label: "day-1" }]},
            {tag: "gap-without-slot", days: [{ label: "2026-09-01" }, { label: "2026-09-03" }]},
            {tag: "unordered", days: [{ label: "2026-09-02" }, { label: "2026-09-01" }]},
            {tag: "duplicate", days: [{ label: "2026-09-01" }, { label: "2026-09-01" }]},
            {tag: "invalid-date", days: [{ label: "2026-02-30" }]},
            {tag: "non-object", days: [7]},
            {tag: "missing-label", days: [{ value: 1 }]}
        ]
    }

    function test_spendHeatmapRowWeekdaysRejectRowsWithoutOneWeekday(data) {
        compare(CostPresentation.spendHeatmapRowWeekdays(data.days, 1), [])
    }

    function test_spendHeatmapRowWeekdaysFollowTheCalendarFallback() {
        var daily = []
        for (var day = 1; day <= 9; day++) {
            daily.push(dailyPoint("2026-09-0" + day, day === 9 ? null : day, day * 10, "USD"))
        }
        var costs = [{ totals: { currency: "USD" }, daily: daily }]
        var days = CostPresentation.spendHeatmapDays(
            CostPresentation.spendDailyPoints(fmt, costs, false), costs)
        // 2026-09-09 is a Wednesday; its unavailable slot still ends the grid.
        compare(CostPresentation.spendHeatmapRowWeekdays(days, 1)[0], 1)
        compare(CostPresentation.spendHeatmapTrailingSlots(days, 1), 4)

        var undated = [{ label: "day-0", value: 1 }, { label: "day-1", value: 2 }]
        compare(CostPresentation.spendHeatmapRowWeekdays(
            CostPresentation.spendHeatmapDays(undated, []), 1), [])
    }

    function test_spendHeatmapDaysPreserveCalendarBoundaries_data() {
        return [
            {tag: "weekend", first: "2026-09-04", last: "2026-09-07", span: 4},
            {tag: "leap-day", first: "2024-02-28", last: "2024-03-01", span: 3},
            {tag: "daylight-saving", first: "2026-03-07", last: "2026-03-09", span: 3},
            {tag: "year-boundary", first: "2025-12-31", last: "2026-01-02", span: 3},
            {tag: "adjacent", first: "2026-09-01", last: "2026-09-02", span: 2},
            {tag: "two-weeks", first: "2026-09-01", last: "2026-09-09", span: 9}
        ]
    }

    function test_spendHeatmapDaysKeepUnavailableBoundaryDays_data() {
        return [
            {tag: "cost-first", missing: [1], tokens: false},
            {tag: "cost-last", missing: [9], tokens: false},
            {tag: "cost-both-edges", missing: [1, 2, 8, 9], tokens: false},
            {tag: "tokens-last", missing: [9], tokens: true}
        ]
    }

    function test_spendHeatmapDaysKeepUnavailableBoundaryDays(data) {
        var daily = []
        for (var day = 1; day <= 9; day++) {
            var amount = data.missing.indexOf(day) >= 0 ? null : day === 5 ? 0 : day
            daily.push(dailyPoint("2026-09-0" + day,
                data.tokens ? day : amount, data.tokens ? amount : day * 10, "USD"))
        }
        var costs = [{totals: {currency: "USD"}, daily: daily}]
        var points = CostPresentation.spendDailyPoints(fmt, costs, data.tokens)
        var days = CostPresentation.spendHeatmapDays(points, costs)
        compare(days.length, 9, "metric filtering must preserve the loaded calendar boundaries")
        compare(CostPresentation.spendHeatmapDays([], costs), [])
        compare(days[4].value, 0)
        for (var i = 0; i < data.missing.length; i++) {
            compare(days[data.missing[i] - 1], null)
        }
        var cells = CostPresentation.spendHeatmapCells(days, 14)
        compare(cells[9].label, "2026-09-05")
        compare(cells[13], days[8])
    }

    function test_spendHeatmapDaysPreserveCalendarBoundaries(data) {
        var points = [{label: data.first, value: 0}, {label: data.last, value: 3}]
        var days = CostPresentation.spendHeatmapDays(points)
        compare(days.length, data.span)
        compare(days[0], points[0])
        compare(days[days.length - 1], points[1])
        for (var i = 1; i < days.length - 1; i++) {
            compare(days[i], null)
        }
        compare(points.length, 2)
    }

    function test_spendHeatmapDaysBoundSparseHistoryAndPreserveLegacyLabels() {
        var latest = {label: "2026-09-09", value: 0}
        var days = CostPresentation.spendHeatmapDays([{label: "1970-01-01", value: 2}, latest])
        compare(days.length, CostPresentation.maximumCostHistoryPoints)
        compare(days[0], null)
        compare(days[days.length - 1], latest)
        var cells = CostPresentation.spendHeatmapCells(
            CostPresentation.spendHeatmapDays([{label: "2026-09-01", value: 2}, latest]), 7)
        compare(cells.length, 7)
        compare(cells[0], null)
        compare(cells[6], latest)
        var legacyCases = [
            [{label: "Mon"}, {label: "Wed"}],
            [{label: "2026-02-30"}, latest],
            [latest, latest],
            [latest, {label: "2026-09-01"}],
            [null, latest],
            [{label: {toString: null}}, latest]
        ]
        for (var i = 0; i < legacyCases.length; i++) {
            compare(CostPresentation.spendHeatmapDays(legacyCases[i]), legacyCases[i])
        }
        compare(CostPresentation.spendHeatmapDays(null), [])
    }

    function test_spendHeatmapCellsDropTheOldestDaysBeyondCapacity() {
        var cells = CostPresentation.spendHeatmapCells([
            { label: "a" }, { label: "b" }, { label: "c" }
        ], 2)
        compare(cells.length, 2)
        compare(cells[0].label, "b")
        compare(cells[1].label, "c")
    }

    function test_spendHeatmapCellsSurviveMissingAndNonsenseInput() {
        compare(CostPresentation.spendHeatmapCells(undefined, 7).length, 7)
        compare(CostPresentation.spendHeatmapCells("not an array", 2)[0], null)
        compare(CostPresentation.spendHeatmapCells([{ label: "a" }], 0).length, 0)
        compare(CostPresentation.spendHeatmapCells([{ label: "a" }], -4).length, 0)
        compare(CostPresentation.spendHeatmapCells([{ label: "a" }], NaN).length, 0)
        compare(CostPresentation.spendHeatmapCells([{ label: "a" }], 2.7).length, 2)
    }

    function test_spendTotalsKeepAllCurrencyFreeTokens() {
        var totals = CostPresentation.spendTotals([
            { totals: { cost: 2, tokens: 100, currency: "USD" } },
            { totals: { cost: 9, tokens: 400, currency: "EUR" } }
        ])
        compare(totals.cost, 2)
        compare(totals.tokens, 500)
        compare(totals.currency, "USD")
        verify(totals.hasMixedCostCurrencies)
    }

    function test_spendCurrencyStatusIgnoresTokenOnlyProviders() {
        var totals = CostPresentation.spendTotals([
            { totals: { cost: null, tokens: 100, currency: "USD" } },
            { totals: { cost: 9, tokens: 400, currency: "EUR" } }
        ])

        compare(totals.currency, "EUR")
        verify(!totals.hasMixedCostCurrencies)
    }

    function test_spendCurrencyStatusChecksDailyCostWhenTotalsAreUnavailable() {
        verify(CostPresentation.spendHasMixedCostCurrencies([
            {
                totals: { cost: 2, tokens: 100, currency: "USD" },
                daily: [dailyPoint("Mon", 2, 100, "USD")]
            },
            {
                totals: { cost: null, tokens: 400, currency: "EUR" },
                daily: [dailyPoint("Mon", 9, 400, "EUR")]
            }
        ]))
    }

    function test_spendTotalsPreserveUnavailableCostAndKeepTokens() {
        var totals = CostPresentation.spendTotals([
            { totals: { cost: null, tokens: 250, currency: "USD" } }
        ])

        compare(totals.cost, null)
        compare(totals.tokens, 250)
        compare(totals.currency, "USD")
    }

    function test_spendTotalsKeepUnknownTokensWithoutDroppingCost() {
        var costs = [{ totals: { cost: 3, tokens: null, currency: "USD" } }]
        compare(CostPresentation.spendTotals(costs).tokens, null)
        compare(CostPresentation.spendTotals(costs).cost, 3)
        costs.push({ totals: { cost: 2, tokens: 0, currency: "USD" } })
        compare(CostPresentation.spendTotals(costs).tokens, 0)
        compare(CostPresentation.spendTotals(costs).cost, 5)
        costs[0].totals.tokens = 1e308
        costs[1].totals.tokens = 1e308
        compare(CostPresentation.spendTotals(costs).tokens, null)
    }

    function test_spendTotalsAreNullWithNoSnapshots() {
        compare(CostPresentation.spendTotals([]), null)
        compare(CostPresentation.spendTotals(null), null)
    }

    function test_costTrustSummaryIsQuietForLegacyAndExactUnspecifiedData() {
        compare(CostPresentation.costTrustSummary([]), null)
        compare(CostPresentation.costTrustSummary(null), null)
        compare(CostPresentation.costTrustSummary([{ totals: { currency: "USD" } }]), null)
        compare(CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 3, unpriced: 0, unmetered: 0, estimated: 0
        }, "")]), null)
        compare(CostPresentation.costTrustSummary([{
            totals: { currency: "USD" },
            trust: { coverage: { priced: "3" }, sourceKind: "not-a-semantic-value" }
        }]), null)

        function InheritedTrust() {}
        InheritedTrust.prototype.coverage = {
            priced: 0, unpriced: 1, unmetered: 0, estimated: 0
        }
        InheritedTrust.prototype.sourceKind = "unknown"
        compare(CostPresentation.costTrustSummary([{
            totals: { currency: "USD" },
            trust: new InheritedTrust()
        }]), null)
    }

    function test_costTrustSummaryIgnoresTokenOnlySnapshots() {
        compare(CostPresentation.costTrustSummary([{
            totals: { cost: null, tokens: 250, currency: "USD" },
            trust: { coverage: null, sourceKind: "unknown" }
        }]), null)
    }

    function test_costTrustSummaryIgnoresEmptySnapshots_data() {
        return [
            { tag: "missing history flag" },
            { tag: "established history", historyEstablished: true },
            { tag: "unestablished history", historyEstablished: false }
        ]
    }

    function test_costTrustSummaryIgnoresEmptySnapshots(data) {
        var emptySnapshot = {
            totals: { cost: null, tokens: 0, currency: "USD" },
            daily: [],
            trust: {
                coverage: {
                    priced: 0, unpriced: 0, unmetered: 0, estimated: 0
                },
                sourceKind: "unknown"
            }
        }
        if (data.historyEstablished !== undefined) {
            emptySnapshot.historyCoverageEstablished = data.historyEstablished
        }

        var summary = CostPresentation.costTrustSummary([
            trustedCost("USD", {
                priced: 1, unpriced: 0, unmetered: 0, estimated: 1
            }, "listPrice"),
            emptySnapshot
        ])

        compare(summary.sourceKind, "listPrice")
        compare(summary.valueMode, "estimated")
    }

    function test_costTrustSummaryKeepsTokenOnlyGapsInAMixedTotal() {
        var summary = CostPresentation.costTrustSummary([
            trustedCost("USD", null, "vendor"),
            {
                totals: { cost: null, tokens: 250, currency: "USD" },
                historyCoverageEstablished: false,
                trust: { coverage: null, sourceKind: "unknown" }
            }
        ])

        compare(summary.level, "warning")
        compare(summary.valueMode, "approximate")
        compare(summary.sourceKind, "unknown")
    }

    function test_costTrustSummaryKeepsCurrencyFreeTokenOnlyGaps() {
        var summary = CostPresentation.costTrustSummary([
            {
                totals: { cost: null, tokens: 250, currency: "USD" },
                trust: { coverage: null, sourceKind: "unknown" }
            },
            trustedCost("EUR", null, "vendor")
        ])

        compare(summary.level, "warning")
        compare(summary.valueMode, "approximate")
        compare(summary.sourceKind, "unknown")
    }

    function test_costTrustSummaryMapsEstimateAndSourceToSemanticKeys() {
        var summary = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 0, unmetered: 0, estimated: 1
        }, "listPrice")])

        compare(summary.level, "information")
        compare(summary.valueMode, "estimated")
        compare(summary.sourceKind, "listPrice")
        verify(summary.hasEstimated)
        verify(!summary.hasUnpriced)
        verify(!summary.hasUnmetered)
    }

    function test_costTrustSummaryMakesIncompleteCoverageAWarning() {
        var summary = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 5, unpriced: 2, unmetered: 1, estimated: 0
        }, "vendor")])

        compare(summary.level, "warning")
        compare(summary.valueMode, "partial")
        compare(summary.sourceKind, "vendor")
        verify(summary.hasUnpriced)
        verify(summary.hasUnmetered)
    }

    function test_costTrustSummaryMakesExcludedRequestsPartial() {
        var summary = CostPresentation.costTrustSummary([{
            totals: { cost: 4, tokens: 40, currency: "USD" },
            trust: {
                coverage: { priced: 2, unpriced: 0, unmetered: 0, estimated: 0 },
                sourceKind: "vendor",
                incompleteRequests: 2
            }
        }])

        compare(summary.level, "warning")
        compare(summary.valueMode, "partial")
        compare(summary.incompleteRequests, 2)
        verify(!summary.hasUnpriced)
        verify(!summary.hasUnmetered)
    }

    function test_costTrustSummaryAddsExcludedRequestsAcrossSnapshots() {
        var summary = CostPresentation.costTrustSummary([
            {
                totals: { cost: 1, tokens: 10, currency: "USD" },
                trust: { coverage: null, sourceKind: "vendor", incompleteRequests: 2 }
            },
            {
                totals: { cost: 2, tokens: 20, currency: "USD" },
                trust: { coverage: null, sourceKind: "vendor", incompleteRequests: 3 }
            }
        ])

        compare(summary.incompleteRequests, 5)
        compare(summary.valueMode, "partial")
    }

    function test_costTrustSummaryRejectsUnusableExcludedRequestCounts_data() {
        return [
            { tag: "absent", value: undefined },
            { tag: "null", value: null },
            { tag: "negative", value: -2 },
            { tag: "fractional", value: 0.5 },
            { tag: "text", value: "2" },
            { tag: "nan", value: NaN },
            { tag: "infinite", value: Infinity }
        ]
    }

    function test_costTrustSummaryRejectsUnusableExcludedRequestCounts(data) {
        var summary = CostPresentation.costTrustSummary([{
            totals: { cost: 1, tokens: 10, currency: "USD" },
            trust: { coverage: null, sourceKind: "vendor", incompleteRequests: data.value }
        }])

        compare(summary.incompleteRequests, 0)
        compare(summary.valueMode, "plain")
        compare(summary.level, "information")
    }

    function test_costTrustSummaryBoundsSaturatedExcludedRequestCounts() {
        var summary = CostPresentation.costTrustSummary([
            {
                totals: { cost: 1, tokens: 10, currency: "USD" },
                trust: { coverage: null, sourceKind: "vendor", incompleteRequests: 1000000000 }
            },
            {
                totals: { cost: 2, tokens: 20, currency: "USD" },
                trust: { coverage: null, sourceKind: "vendor", incompleteRequests: 1000000000 }
            }
        ])

        compare(summary.incompleteRequests, 1000000000)
    }

    function test_costTrustSummaryQualifiesATokenOnlyTotalWithExcludedRequests() {
        // The excluded requests are missing from the tokens as well, so the
        // warning must survive a snapshot without a cost amount.
        var summary = CostPresentation.costTrustSummary([{
            totals: { tokens: 10, currency: "USD" },
            trust: { coverage: null, sourceKind: "", incompleteRequests: 4 }
        }])

        compare(summary.level, "warning")
        compare(summary.valueMode, "partial")
        compare(summary.incompleteRequests, 4)
    }

    function test_costTrustSummaryStaysQuietWithoutAnyDisplayedAmount() {
        compare(CostPresentation.costTrustSummary([{
            totals: { tokens: 0, currency: "USD" },
            trust: { coverage: null, sourceKind: "", incompleteRequests: 4 }
        }]), null)
    }

    function test_costTrustNoticeKeyIgnoresTheExcludedRequestMagnitude() {
        var one = CostPresentation.costTrustNoticeKey({
            level: "warning", sourceKind: "vendor", incompleteRequests: 1
        })
        var many = CostPresentation.costTrustNoticeKey({
            level: "warning", sourceKind: "vendor", incompleteRequests: 9
        })
        var none = CostPresentation.costTrustNoticeKey({
            level: "warning", sourceKind: "vendor", incompleteRequests: 0
        })

        compare(one, many)
        verify(one.indexOf("incomplete") !== -1)
        verify(none.indexOf("complete") !== -1)
        verify(none.indexOf("incomplete") === -1)
        compare(CostPresentation.costTrustNoticeKey({ incompleteRequests: 3 }),
            "information||exact|priced|metered|incomplete")
        compare(CostPresentation.costTrustNoticeKey({ incompleteRequests: 0 }), "")
    }

    function test_costTrustSummaryTreatsUnknownAsApproximateAndConservative() {
        var summary = CostPresentation.costTrustSummary([
            trustedCost("USD", null, "listPrice"),
            trustedCost("USD", null, "unknown")
        ])

        compare(summary.level, "warning")
        compare(summary.valueMode, "approximate")
        compare(summary.sourceKind, "unknown")
    }

    function test_costTrustSummaryDoesNotClassifyLegacyCostFromTrustedSubset() {
        var summary = CostPresentation.costTrustSummary([
            trustedCost("USD", null, "vendor"),
            { totals: { cost: 9, tokens: 90, currency: "USD" }, trust: null }
        ])

        compare(summary.level, "warning")
        compare(summary.valueMode, "approximate")
        compare(summary.sourceKind, "unknown")
    }

    function test_costTrustSummaryFoldsKnownSourcesWithoutCallingMixedIncomplete() {
        var summary = CostPresentation.costTrustSummary([
            trustedCost("USD", null, "listPrice"),
            trustedCost("USD", null, "vendor")
        ])

        compare(summary.level, "information")
        compare(summary.valueMode, "estimated")
        compare(summary.sourceKind, "mixed")
        verify(summary.hasEstimated)
        verify(!summary.hasUnpriced)
        verify(!summary.hasUnmetered)
    }

    function test_costTrustSummaryUsesTheSpendTotalCurrencyEligibility() {
        var summary = CostPresentation.costTrustSummary([
            trustedCost("USD", null, "listPrice"),
            trustedCost("EUR", {
                priced: 0, unpriced: 3, unmetered: 0, estimated: 0
            }, "unknown")
        ])

        compare(summary.level, "information")
        compare(summary.valueMode, "estimated")
        compare(summary.sourceKind, "listPrice")
        verify(!summary.hasUnpriced)
    }

    function test_costTrustSummaryDoesNotConfuseScanCoverageWithPricingCoverage() {
        compare(CostPresentation.costTrustSummary([{
            totals: { currency: "USD" },
            historyCoverageEstablished: false
        }]), null)
    }

    function test_costTrustNoticeDismissalSurvivesRefreshUntilMeaningChanges() {
        var estimated = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 0, unmetered: 0, estimated: 1
        }, "listPrice")])
        var initial = CostPresentation.costTrustNoticeTransition(
            estimated, null, false)
        verify(initial.shouldShow)

        var dismissed = CostPresentation.costTrustNoticeTransition(
            estimated, initial, true)
        verify(!dismissed.shouldShow)

        var refreshed = CostPresentation.costTrustNoticeTransition(
            CostPresentation.costTrustSummary([trustedCost("USD", {
                priced: 4, unpriced: 0, unmetered: 0, estimated: 1
            }, "listPrice")]),
            dismissed,
            false)
        verify(!refreshed.shouldShow)

        var partial = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 1, unmetered: 0, estimated: 1
        }, "listPrice")])
        var changed = CostPresentation.costTrustNoticeTransition(
            partial, refreshed, false)
        verify(changed.shouldShow)
        verify(changed.key !== dismissed.key)

        var dismissedPartial = CostPresentation.costTrustNoticeTransition(
            partial, changed, true)
        var returned = CostPresentation.costTrustNoticeTransition(
            estimated, dismissedPartial, false)
        verify(returned.shouldShow)
    }

    function test_costTrustNoticeDismissalSurvivesNoticeRecreationPerScope() {
        var summary = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 1, unmetered: 0, estimated: 1
        }, "listPrice")])
        var initial = CostPresentation.costTrustNoticeStoreTransition(
            summary, ({}), "provider:codex", false)
        verify(initial.state.shouldShow)

        var dismissed = CostPresentation.costTrustNoticeStoreTransition(
            summary, initial.states, "provider:codex", true)
        verify(!dismissed.state.shouldShow)
        verify(dismissed.states !== initial.states)
        verify(!initial.states["provider:codex"].dismissed)

        var temporarilyMissing = CostPresentation.costTrustNoticeStoreTransition(
            null, dismissed.states, "provider:codex", false)
        verify(!temporarilyMissing.state.shouldShow)

        // A new CostTrustNotice instance must recover the dismissal from its
        // persistent owner even if its summary binding was briefly empty.
        var recreated = CostPresentation.costTrustNoticeStoreTransition(
            summary, temporarilyMissing.states, "provider:codex", false)
        verify(!recreated.state.shouldShow)

        // Provider details and aggregate Spend are separate information scopes.
        var aggregate = CostPresentation.costTrustNoticeStoreTransition(
            summary, dismissed.states, "spend", false)
        verify(aggregate.state.shouldShow)
    }

    function test_costTrustNoticeStoreBoundsAndRejectsUnsafeScopes() {
        var summary = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 1, unmetered: 0, estimated: 1
        }, "listPrice")])
        var oversized = ({})
        for (var i = 0; i < 200; i++) {
            oversized["provider:" + i] = { key: "old", dismissed: true }
        }
        var bounded = CostPresentation.costTrustNoticeStoreTransition(
            summary, oversized, "spend", false)
        verify(Object.keys(bounded.states).length <= 128)
        verify(Object.prototype.hasOwnProperty.call(bounded.states, "spend"))

        var unsafe = CostPresentation.costTrustNoticeStoreTransition(
            summary, bounded.states, "__proto__", true)
        verify(!Object.prototype.hasOwnProperty.call(unsafe.states, "__proto__"))
        verify(unsafe.state.dismissed)
    }

    function test_costTrustNoticeTransitionRejectsMalformedSummaries() {
        var invalidSummaries = [null, undefined, [], "estimated", 7, ({})]
        for (var i = 0; i < invalidSummaries.length; i++) {
            var state = CostPresentation.costTrustNoticeTransition(
                invalidSummaries[i],
                { key: "old", dismissed: true, shouldShow: false },
                true)
            compare(state.key, "")
            verify(!state.dismissed)
            verify(!state.shouldShow)
        }
    }

    function test_costTrustNoticeTransitionIgnoresInheritedLevel() {
        function InheritedWarning() {}
        InheritedWarning.prototype.level = "warning"
        var summary = new InheritedWarning()
        summary.sourceKind = "listPrice"
        summary.hasEstimated = true
        summary.hasUnpriced = false
        summary.hasUnmetered = false

        var state = CostPresentation.costTrustNoticeTransition(
            summary, null, false)
        compare(state.key, "information|listPrice|estimated|priced|metered|complete")
        verify(state.shouldShow)
    }

    function test_costTrustNoticeTransitionRejectsMalformedPreviousState() {
        var summary = CostPresentation.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 0, unmetered: 0, estimated: 1
        }, "listPrice")])

        function InheritedDismissal() {}
        InheritedDismissal.prototype.key = "inherited"
        InheritedDismissal.prototype.dismissed = true
        var invalidStates = [
            null,
            undefined,
            [],
            "dismissed",
            { key: 7, dismissed: "yes" },
            new InheritedDismissal()
        ]
        for (var i = 0; i < invalidStates.length; i++) {
            var state = CostPresentation.costTrustNoticeTransition(
                summary, invalidStates[i], false)
            verify(state.key.length > 0)
            verify(state.key.length < 80)
            verify(!state.dismissed)
            verify(state.shouldShow)
        }
    }

    // A missing flag counts as established, so older CLI payloads do not print
    // a permanent "still collecting" note.
    function test_historyStillBuildingOnlyOnAnExplicitFalse() {
        verify(CostPresentation.historyStillBuilding([{ historyCoverageEstablished: false }]))
        verify(!CostPresentation.historyStillBuilding([{ historyCoverageEstablished: true }]))
        verify(!CostPresentation.historyStillBuilding([{}]))
        verify(!CostPresentation.historyStillBuilding([]))
        verify(!CostPresentation.historyStillBuilding([null, "stale", 42]))
    }

    function test_malformedSnapshotsDegradeInsteadOfThrowing() {
        var points = CostPresentation.spendDailyPoints(fmt, [
            null,
            { daily: null, totals: {} },
            { daily: { length: 1000000000000 }, totals: {} },
            { daily: [null, 42, "Mon", { label: "Mon", cost: 2, tokens: 10, currency: "USD" }], totals: {} }
        ], false)
        compare(points.length, 1)
        compare(points[0].label, "Mon")

        var rows = CostPresentation.projectRows([
            null,
            { provider: "codex", projects: null },
            { provider: "codex", projects: { rows: [0, 1, null, { label: "Kept", cost: 3, tokens: 30, currency: "USD" }] } }
        ], false)
        compare(rows.rows.length, 1)
        compare(rows.rows[0].label, "Kept")
        verify(!rows.truncated)

        var totals = CostPresentation.spendTotals([{ totals: { tokens: "100", currency: "USD" } }])
        compare(totals.tokens, null)
        compare(CostPresentation.spendTotals([null, { totals: { cost: 2, tokens: 40, currency: "USD" } }]).tokens, 40)
        verify(!CostPresentation.historyStillBuilding([null]))
        compare(CostPresentation.spendCurrency([null]), "USD")
    }

    // The suite runs with TZ=America/Los_Angeles. The CLI's "today" is the
    // total of the day it scanned, so a scan from 22:00 on 09-23 still
    // describes the 23rd after midnight.
    function test_todayAmountsNeedAScanFromToday() {
        var payload = [{provider: "codex", historyDays: 30, currencyCode: "USD",
            updatedAt: new Date(2026, 8, 23, 22).toISOString(),
            sessionCostUSD: 1.25, sessionTokens: 1200,
            totals: {totalCost: 9, totalTokens: 9000}, daily: []}];
        var cost = CostResponse.response(JSON.stringify(payload), "", 30).costs.codex;
        compare(cost.scanDay, "2026-09-23");

        var sameDay = CostPresentation.todayAmounts(cost, new Date(2026, 8, 23, 23, 30).getTime());
        compare(sameDay.cost, 1.25);
        compare(sameDay.tokens, 1200);

        var nextDay = CostPresentation.todayAmounts(cost, new Date(2026, 8, 24, 0, 30).getTime());
        compare(nextDay.cost, null);
        compare(nextDay.tokens, null);
        compare(nextDay.currency, "USD");
        verify(!CostPresentation.hasMetricValue(nextDay, false));
        verify(!CostPresentation.hasMetricValue(nextDay, true));
        // The retained snapshot itself is untouched.
        compare(cost.today.cost, 1.25);

        // Privacy mode keeps the scan date, so it hides the same stale total.
        var privateCost = Privacy.cost(cost, true);
        compare(privateCost.scanDay, "2026-09-23");
        compare(CostPresentation.todayAmounts(privateCost, new Date(2026, 8, 24, 0, 30).getTime()).cost, null);
        compare(Privacy.cost({scanDay: {}}, true).scanDay, "");

        // Without a scan date or a usable clock there is nothing to compare.
        payload[0].updatedAt = "not a date";
        var undated = CostResponse.response(JSON.stringify(payload), "", 30).costs.codex;
        compare(undated.scanDay, "");
        compare(CostPresentation.todayAmounts(undated, new Date(2026, 8, 24, 0, 30).getTime()).cost, 1.25);
        compare(CostPresentation.todayAmounts(cost, NaN).cost, 1.25);
        compare(CostPresentation.todayAmounts(cost, "2026-09-24").cost, 1.25);
        compare(CostPresentation.todayAmounts(null, 0), null);
        compare(CostPresentation.todayAmounts({scanDay: "2026-09-23"}, 0), null);
    }
}
