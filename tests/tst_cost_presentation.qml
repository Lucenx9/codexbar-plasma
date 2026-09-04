import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation

TestCase {
    name: "CostPresentation"

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
        // Non-numeric input degrades like the money path; null counts as 0,
        // matching the pinned "$0.00" behaviour of the USD branch.
        compare(CostPresentation.amountString(fmt, "abc", "Quota"), "-")
        compare(CostPresentation.amountString(fmt, null, "Quota"), "0")
    }

    function test_nonNumericAmountDegradesToDash() {
        compare(CostPresentation.amountString(fmt, "abc", "USD"), "-")
        compare(CostPresentation.amountString(fmt, "abc", "EUR"), "-")
        compare(CostPresentation.amountString(fmt, undefined, "USD"), "-")
        compare(CostPresentation.amountString(fmt, Number.NaN, "USD"), "-")
        compare(CostPresentation.amountString(fmt, null, "USD"), "$0.00")
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
    }

    function test_peakPointLeavesAnEmptyLabelForTheCallerToWord() {
        compare(CostPresentation.peakPoint([dailyPoint("", 5, 900)], false).label, "")
    }

    function test_averageDailyValueDividesByEveryPlottedDay() {
        var points = [dailyPoint("Mon", 3, 0), dailyPoint("Tue", 0, 0), dailyPoint("Wed", 6, 0)]
        compare(CostPresentation.averageDailyValue(points, false).value, 3)
        compare(CostPresentation.averageDailyValue([], false), null)
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
            { label: "Cache", tokens: "abc" }
        ])
        compare(rows.length, 1)
        compare(rows[0].label, "Total")
        compare(rows[0].value, "1.5K")
    }

    function test_tokenSummaryOmitsTheHalfThatIsMissing() {
        compare(CostPresentation.tokenSummary(fmt, 3, 0, "USD", ""), "$3.00")
        compare(CostPresentation.tokenSummary(fmt, 0, 2000, "USD", ""), "2K")
        compare(CostPresentation.tokenSummary(fmt, 0, 0, "USD", ""), "")
        compare(CostPresentation.tokenSummary(fmt, 3, 2000, "USD", "2K tokens"), "$3.00 · 2K tokens")
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
    }

    function test_chartPointsAndSparklineMaxSurviveNonArrayInputs() {
        compare(CostPresentation.chartPoints(fmt, null, false).length, 0)
        compare(CostPresentation.chartPoints(fmt, "invalid", false).length, 0)
        compare(CostPresentation.sparklineMax(null, false), 0)
        compare(CostPresentation.sparklineMax("invalid", false), 0)
    }

    function test_averageDailyValueAndPeakPointSurviveNonArrayInputs() {
        compare(CostPresentation.averageDailyValue(null, false), null)
        compare(CostPresentation.averageDailyValue("invalid", false), null)
        compare(CostPresentation.peakPoint(null, false), null)
        compare(CostPresentation.peakPoint("invalid", false), null)
    }

    function test_spendTotalsSurviveNonArrayInputs() {
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
        compare(state.key, "information|listPrice|estimated|priced|metered")
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
    }
}
