import QtQuick
import QtTest
import "../contents/ui/CostPresentation.mjs" as CostPresentation
import "../contents/ui/CostAmounts.mjs" as CostAmounts
import "../contents/ui/CostChart.mjs" as CostChart
import "../contents/ui/CostCurrency.mjs" as CostCurrency
import "../contents/ui/CostTrust.mjs" as CostTrust
import "../contents/ui/CostResponse.mjs" as CostResponse
import "../contents/ui/PrivacyPresentation.js" as Privacy
import "../contents/ui/ProviderNormalizer.mjs" as Normalizer

TestCase {
    name: "CostPresentation"

    function projectFixtureRows(count) {
        var rows = []
        for (var i = 0; i < count; i++)
            rows.push({ label: "project-" + i, cost: i, tokens: i * 10, currency: "USD" })
        return rows
    }

    function test_projectRowsShareTheCapAcrossPartiallyFilledProviders() {
        var result = CostPresentation.projectRows([
            { provider: "first", projects: { rows: projectFixtureRows(100) } },
            { provider: "second", projects: { rows: projectFixtureRows(128) } }
        ], false)
        compare(result.rows.length, 128)
        compare(result.truncated, true)
        compare(result.rows[99].provider, "first")
        compare(result.rows[100].provider, "second")
        compare(result.rows[100].cost, 127)
        compare(result.rows[127].cost, 100)
    }

    function test_projectRowsReportSourceInspectionTruncation() {
        var result = CostPresentation.projectRows([
            { provider: "single", projects: { rows: projectFixtureRows(129) } }
        ], false)
        compare(result.rows.length, 128)
        compare(result.truncated, true)
        compare(result.rows[0].cost, 127)
        compare(result.rows[127].cost, 0)
    }

    function test_excludedRequestCountsClampBeforeIndividualRowUse() {
        compare(CostTrust.acceptedIncompleteRequests({ incompleteRequests: 9007199254740991 }), 1000000000)
        compare(CostTrust.acceptedIncompleteRequests({ incompleteRequests: 7 }), 7)
        compare(CostTrust.acceptedIncompleteRequests({ incompleteRequests: 0 }), 0)
    }

    function test_excludedRequestsNeedAPublishedAmountEvenWithDailyEvidence() {
        var item = {
            totals: { cost: null, tokens: 0, currency: "USD" },
            daily: [{ cost: 1, tokens: 4, currency: "USD" }],
            trust: { sourceKind: "vendor", incompleteRequests: 3 }
        }
        compare(CostTrust.costTrustSummary([item]), null)
        item.totals.tokens = 4
        compare(CostTrust.costTrustSummary([item]), {
            level: "warning", valueMode: "partial", sourceKind: "vendor",
            hasEstimated: false, hasUnpriced: false, hasUnmetered: false, incompleteRequests: 3
        })
    }

    function test_mixedProvenanceAloneQualifiesAnAmountAsEstimated() {
        compare(CostTrust.costTrustSummary([{
            totals: { cost: 1, currency: "USD" }, trust: { sourceKind: "mixed" }
        }]), {
            level: "information", valueMode: "estimated", sourceKind: "mixed",
            hasEstimated: true, hasUnpriced: false, hasUnmetered: false, incompleteRequests: 0
        })
    }

    function test_noticeDismissalRequiresLiteralTrue() {
        var summary = { sourceKind: "vendor" }
        var key = "information|vendor|exact|priced|metered|complete"
        for (var truthy of [1, "yes", [], {}]) {
            compare(CostTrust.costTrustNoticeTransition(summary, null, truthy), {
                key: key, dismissed: false, shouldShow: true
            })
        }
        compare(CostTrust.costTrustNoticeTransition(summary, null, true), {
            key: key, dismissed: true, shouldShow: false
        })
    }

    function test_noticeStoreRetainsOnlyValidPreviousState() {
        var invalidStates = [null, {}, { key: "remembered", dismissed: "yes" },
            { key: "remembered" }, { key: 7, dismissed: true }, []]
        for (var invalid of invalidStates) {
            compare(CostTrust.costTrustNoticeStoreTransition(null, { provider: invalid }, "provider", false), {
                states: ({}), state: { key: "", dismissed: false, shouldShow: false }
            })
        }
        compare(CostTrust.costTrustNoticeStoreTransition(null, {
            provider: { key: "remembered", dismissed: true }
        }, "provider", false), {
            states: { provider: { key: "remembered", dismissed: true } },
            state: { key: "", dismissed: false, shouldShow: false }
        })
    }

    function test_roundedBarsClampCornersToTheirBounds_data() {
        return [
            { tag: "ordinary", bounds: { x: 5, baseline: 100, width: 10, height: 10 }, radius: 3,
                expected: [[5, 100], [5, 93], [5, 90, 8, 90], [12, 90], [15, 90, 15, 93], [15, 100]] },
            { tag: "short-and-narrow", bounds: { x: 5, baseline: 100, width: 4, height: 2 }, radius: 99,
                expected: [[5, 100], [5, 100], [5, 98, 7, 98], [7, 98], [9, 98, 9, 100], [9, 100]] }
        ]
    }

    function test_roundedBarsClampCornersToTheirBounds(data) {
        var points = []
        var operations = []
        function record() { points.push(Array.prototype.slice.call(arguments)) }
        var context = {
            beginPath: function() { operations.push("begin") },
            moveTo: record, lineTo: record, quadraticCurveTo: record,
            closePath: function() { operations.push("close") },
            fill: function() { operations.push("fill") }
        }
        CostChart.paintRoundedTopBar(context, data.bounds, data.radius)
        compare(points, data.expected)
        compare(operations, ["begin", "close", "fill"])
    }

    function test_noticeScopesCannotReadEmptyOrUnsafeMapKeys() {
        var key = "information|vendor|exact|priced|metered|complete"
        var states = JSON.parse('{"":{},"__proto__":{},"constructor":{},"prototype":{}}')
        for (var scope in states)
            states[scope] = { key: key, dismissed: true }
        for (var invalid of [null, "", "__proto__", "constructor", "prototype"]) {
            compare(CostTrust.costTrustNoticeStoreTransition({ sourceKind: "vendor" }, states, invalid, false), {
                states: ({}), state: { key: key, dismissed: false, shouldShow: true }
            })
        }
    }

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
        CostChart.paintRoundedTopBar(context, { x: 5, baseline: 100, width: Number.NaN, height: undefined }, 3)
        CostChart.paintRoundedTopBar(context, { x: 5, baseline: 100, width: Infinity, height: 20 }, 3)
        CostChart.paintRoundedTopBar(context, { x: 5, baseline: 100, width: 10, height: Infinity }, 3)
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
        compare(CostChart.costDayIndexAfterRefresh(data.previous, data.index, data.next), data.expected)
    }

    function test_selectedCostDayUsesSourceRowAfterUnavailableAmountsAreSkipped() {
        var daily = [
            { label: "2026-09-01", cost: null, tokens: 3, models: [{label: "First"}] },
            { label: "2026-09-02", cost: 0, tokens: 7, models: [{label: "Second"}] }
        ]
        var costPoints = CostChart.chartPoints(fmt, daily, false)
        compare(costPoints.length, 1)
        compare(CostChart.selectedCostDay(daily, costPoints, 0), daily[1])
        var tokenPoints = CostChart.chartPoints(fmt, daily, true)
        compare(CostChart.selectedCostDay(daily, tokenPoints, 0), daily[0])
        compare(CostChart.selectedCostDay(daily, tokenPoints, 1), daily[1])
        compare(CostChart.selectedCostDay(daily, costPoints, -1), null)
        compare(CostChart.selectedCostDay([], costPoints, 0), null)
        compare(CostChart.selectedCostDay(daily, [{ sourceIndex: "1" }], 0), null)
        compare(CostChart.selectedCostDay(daily, [{ sourceIndex: 0.5 }], 0), null)
        compare(CostChart.selectedCostDay(daily, costPoints, 0.5), null)
        compare(CostChart.selectedCostDay(daily, null, 0), null)
    }

    function test_amountSummaryPreservesAvailableMetrics() {
        var fmt = CostAmounts.numberFormat(",", ".")
        var tokensText = function(tokens) { return tokens + " tokens" }
        compare(CostAmounts.amountSummary(fmt, { cost: null, tokens: 5 }, tokensText), "5 tokens")
        compare(CostAmounts.amountSummary(fmt, { cost: 0, tokens: null, currency: "USD" }, tokensText), "$0.00")
        compare(CostAmounts.amountSummary(fmt, { cost: 0, tokens: 0, currency: "USD" }, tokensText), "$0.00 · 0 tokens")
        compare(CostAmounts.amountSummary(fmt, null, tokensText), "-")
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

    readonly property var fmt: CostAmounts.numberFormat(",", ".")

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
        var fallback = CostAmounts.numberFormat(undefined, undefined)
        compare(fallback.group, ",")
        compare(fallback.decimal, ".")
        compare(CostAmounts.amountString(fallback, 1234.5, "USD"), "$1,234.50")
    }

    function test_amountStringHonoursTheCallerSeparators() {
        var italian = CostAmounts.numberFormat(".", ",")
        compare(CostAmounts.amountString(italian, 1234.5, "USD"), "$1.234,50")
        compare(CostAmounts.amountString(fmt, 1234.5, "USD"), "$1,234.50")
    }

    function test_amountStringKeepsTheSignOutsideTheCurrencySymbol() {
        compare(CostAmounts.amountString(fmt, -12, "USD"), "-$12.00")
        compare(CostAmounts.amountString(fmt, -12, "EUR"), "-EUR 12.00")
    }

    function test_quotaIsACreditBalanceNotMoney() {
        compare(CostAmounts.amountString(fmt, 1499.6, "Quota"), "1500")
        compare(CostAmounts.amountString(fmt, 1499.6, " Quota "), "1500")
        compare(CostAmounts.amountString(fmt, "abc", "Quota"), "-")
        compare(CostAmounts.amountString(fmt, null, "Quota"), "-")
    }

    function test_amountStringDoesNotDisplayNegativeZero() {
        for (var format of [fmt, CostAmounts.numberFormat(".", ","), null]) {
            for (var currency of ["USD", "EUR", ""]) {
                for (var value of [-0, -0.001, -0.0049]) {
                    compare(CostAmounts.amountString(format, value, currency),
                        CostAmounts.amountString(format, 0, currency))
                }
                for (var negative of [-0.005, -0.01, -12.5]) {
                    compare(CostAmounts.amountString(format, negative, currency),
                        "-" + CostAmounts.amountString(format, -negative, currency))
                }
            }
        }
    }

    function test_nonNumericAmountDegradesToDash() {
        compare(CostAmounts.amountString(fmt, "abc", "USD"), "-")
        compare(CostAmounts.amountString(fmt, "abc", "EUR"), "-")
        compare(CostAmounts.amountString(fmt, "12", "USD"), "-")
        compare(CostAmounts.amountString(fmt, "", "USD"), "-")
        compare(CostAmounts.amountString(fmt, undefined, "USD"), "-")
        compare(CostAmounts.amountString(fmt, Number.NaN, "USD"), "-")
        compare(CostAmounts.amountString(fmt, null, "USD"), "-")
        compare(CostAmounts.amountString(fmt, false, "USD"), "-")
        compare(CostAmounts.amountString(fmt, [], "USD"), "-")
        compare(CostAmounts.amountString(fmt, {}, "USD"), "-")
        compare(CostAmounts.groupedDecimalString(fmt, "abc", 2), "-")
    }

    function test_amountStringHandlesNullOrMissingFormatGracefully() {
        compare(CostAmounts.amountString(null, 12, "USD"), "$12.00")
        compare(CostAmounts.amountString(undefined, 12, "USD"), "$12.00")
        compare(CostAmounts.amountString({}, 12, "USD"), "$12.00")
        compare(CostAmounts.groupedDecimalString(null, 1234.5, 2), "1,234.50")
    }

    function test_amountStringHandlesEmptyOrMissingCurrencyGracefully() {
        compare(CostAmounts.amountString(fmt, 12, ""), "12.00")
        compare(CostAmounts.amountString(fmt, -12, ""), "-12.00")
        compare(CostAmounts.amountString(fmt, 12, null), "12.00")
        compare(CostAmounts.amountString(fmt, 12, undefined), "12.00")
        compare(CostAmounts.amountString(fmt, 12, "   "), "12.00")
    }

    // Number.toFixed returns exponential notation past 1e21, which has no
    // fixed-point digits to group: without the guard "1e+21" gained a bogus
    // separator ("1e,+21").
    function test_groupedDecimalStringKeepsHugeMagnitudesReadable() {
        compare(CostAmounts.groupedDecimalString(fmt, 1e21, 2), "1e+21")
        compare(CostAmounts.groupedDecimalString(fmt, -1e21, 2), "1e+21")
        compare(CostAmounts.groupedDecimalString(fmt, 1.5e21, 2), "1.5e+21")
        compare(CostAmounts.amountString(fmt, 1e21, "USD"), "$1e+21")
        compare(CostAmounts.amountString(fmt, -1e21, "USD"), "-$1e+21")
    }

    // Credit balances print as bare counts: whole balances keep no fractional
    // part. Rounding can carry a fractional balance across the whole boundary
    // (99.95 -> "100.0"), so the fractional digit drops when the rounded
    // figure is whole.
    function test_formatCountDropsTheFractionalDigitAfterRoundingUp() {
        compare(CostAmounts.formatCount(fmt, 0), "0")
        compare(CostAmounts.formatCount(fmt, 100), "100")
        compare(CostAmounts.formatCount(fmt, 99.95), "100")
        compare(CostAmounts.formatCount(fmt, 2.95), "3")
        compare(CostAmounts.formatCount(fmt, -99.95), "-100")
        compare(CostAmounts.formatCount(fmt, 99.94), "99.9")
        compare(CostAmounts.formatCount(fmt, 199.99), "200")
        compare(CostAmounts.formatCount(fmt, 1234.5), "1,235")
        compare(CostAmounts.formatCount(fmt, 12.5), "12.5")
        compare(CostAmounts.formatCount(fmt, "abc"), "-")
        compare(CostAmounts.formatCount(fmt, Number.NaN), "-")
        compare(CostAmounts.formatCount(fmt, undefined), "-")
        // Number(null) coerces to 0, as the delegated main.qml helper did.
        compare(CostAmounts.formatCount(fmt, null), "0")
        var italian = CostAmounts.numberFormat(".", ",")
        compare(CostAmounts.formatCount(italian, 99.95), "100")
        compare(CostAmounts.formatCount(italian, 99.94), "99,9")
        compare(CostAmounts.formatCount(italian, 1234.5), "1.235")
        compare(CostAmounts.formatCount(null, 12.5), "12.5")
    }

    // A tiny negative balance rounds to a displayed zero. The sign must not
    // survive as the negative-zero string "-0".
    function test_formatCountDropsTheSignWhenANegativeRoundsToZero() {
        compare(CostAmounts.formatCount(fmt, -0.04), "0")
        compare(CostAmounts.formatCount(fmt, -0.049), "0")
        var italian = CostAmounts.numberFormat(".", ",")
        compare(CostAmounts.formatCount(italian, -0.04), "0")
        // A negative that survives rounding keeps its sign.
        compare(CostAmounts.formatCount(fmt, -0.05), "-0.1")
        compare(CostAmounts.formatCount(fmt, -0.4), "-0.4")
        compare(CostAmounts.formatCount(fmt, -5), "-5")
    }

    function test_tokenCountStringScalesAndDropsTrailingZero() {
        compare(CostAmounts.tokenCountString(999), "999")
        compare(CostAmounts.tokenCountString(1000), "1K")
        compare(CostAmounts.tokenCountString(1500), "1.5K")
        compare(CostAmounts.tokenCountString(15000), "15K")
        compare(CostAmounts.tokenCountString(2500000), "2.5M")
        compare(CostAmounts.tokenCountString(3000000000), "3B")
        compare(CostAmounts.tokenCountString(-1500), "-1.5K")
        compare(CostAmounts.tokenCountString("abc"), "-")
    }

    function test_tokenCountStringUsesTheCallerDecimalMark() {
        var comma = CostAmounts.numberFormat(".", ",")
        compare(CostAmounts.tokenCountString(1500, comma), "1,5K")
        compare(CostAmounts.tokenCountString(-2500000, comma), "-2,5M")
        compare(CostAmounts.tokenCountString(4294967297, comma), "4,3B")
        compare(CostAmounts.tokenCountString(1000, comma), "1K")
        compare(CostAmounts.tokenCountString(15000, comma), "15K")
        compare(CostAmounts.tokenCountString(999, comma), "999")
        compare(CostAmounts.tokenCountString(1500, ({})), "1.5K")
        compare(CostAmounts.metricText(comma, 1500, "USD", true), "1,5K")
        compare(CostPresentation.breakdownRows([{ label: "Input", tokens: 1500 }], comma)[0].value, "1,5K")
        compare(CostAmounts.amountSummary(comma, { cost: 1.5, tokens: 1500, currency: "USD" }), "$1,50 · 1,5K")
    }

    // A value that rounds up across a unit boundary must promote to the larger
    // unit instead of printing an overflowing one ("1000K", "1000M").
    function test_tokenCountStringPromotesAtRoundedBoundaries() {
        compare(CostAmounts.tokenCountString(999.6), "1K")
        compare(CostAmounts.tokenCountString(999999), "1M")
        compare(CostAmounts.tokenCountString(994999), "995K")
        compare(CostAmounts.tokenCountString(999600), "1M")
        compare(CostAmounts.tokenCountString(-999600), "-1M")
        compare(CostAmounts.tokenCountString(999999999), "1B")
        compare(CostAmounts.tokenCountString(999499999), "999M")
    }

    // The regression this guards: a marker or bar drawn against the wrong
    // metric claims a spend level the payload never reported.
    function test_sparklineMaxFollowsTheSelectedMetric() {
        var points = [dailyPoint("Mon", 5, 900), dailyPoint("Tue", 2, 4000)]
        compare(CostAmounts.sparklineMax(points, false), 5)
        compare(CostAmounts.sparklineMax(points, true), 4000)
        compare(CostAmounts.sparklineMax([], false), 0)
        compare(CostAmounts.sparklineMax(null, false), 0)
    }

    function test_chartPointsDropUnavailableCostButKeepTokens() {
        var points = [dailyPoint("Mon", null, 250)]

        compare(CostChart.chartPoints(fmt, points, false).length, 0)
        compare(CostChart.chartPoints(fmt, points, true)[0].value, 250)
    }

    function test_peakPointNamesTheDayTheBarsHighlight() {
        var points = [dailyPoint("Mon", 5, 900), dailyPoint("Tue", 2, 4000)]
        compare(CostAmounts.peakPoint(points, false).label, "Mon")
        compare(CostAmounts.peakPoint(points, true).label, "Tue")
    }

    function test_recentHistoryPointsKeepTheNewestSevenDays() {
        var daily = []
        for (var i = 0; i < 9; i++) {
            daily.push(dailyPoint("D" + i, i, i))
        }
        compare(CostPresentation.recentHistoryPoints(daily).map(function(point) { return point.label }),
            ["D2", "D3", "D4", "D5", "D6", "D7", "D8"])
        compare(daily.length, 9)
        compare(CostPresentation.recentHistoryPoints(daily.slice(0, 2)).length, 2)
        compare(CostPresentation.recentHistoryPoints(null), [])
        compare(CostPresentation.recentHistoryPoints({ length: 9 }), [])
    }

    function test_peakPointIsNullWhenNothingWasSpent() {
        compare(CostAmounts.peakPoint([dailyPoint("Mon", 0, 0)], false), null)
        compare(CostAmounts.peakPoint([], false), null)
        compare(CostAmounts.peakPoint(null, false), null)
        compare(CostAmounts.peakPoint([null, "invalid", 42], false), null)
        compare(CostAmounts.peakPoint([null, dailyPoint("Tue", 4, 0)], false).label, "Tue")
    }

    function test_peakPointLeavesAnEmptyLabelForTheCallerToWord() {
        compare(CostAmounts.peakPoint([dailyPoint("", 5, 900)], false).label, "")
    }

    // Null entries carry no data: the peak skips them like uniqueCostDayIndex
    // does, and breakdown rows never read a token count from one.
    function test_peakPointAndBreakdownRowsSkipNullEntries() {
        compare(CostAmounts.peakPoint([null, dailyPoint("Mon", 5, 900)], false).label, "Mon")
        compare(CostAmounts.peakPoint([null, null], false), null)
        compare(CostPresentation.breakdownRows([null, { label: "ok", tokens: 5 }]).length, 1)
        compare(CostPresentation.breakdownRows([null]).length, 0)
    }

    function test_averageDailyValueDividesByEveryPlottedDay() {
        var points = [dailyPoint("Mon", 3, 0), dailyPoint("Tue", 0, 0), dailyPoint("Wed", 6, 0)]
        compare(CostAmounts.averageDailyValue(points, false).value, 3)
        compare(CostAmounts.averageDailyValue([], false), null)
    }

    function test_averageDailyValuePreservesHalfTokenRounding() {
        var points = [803, 136, 8, 19].map(function(tokens) {
            return {tokens: tokens}
        })
        for (var order = 0; order < 2; order++) {
            var average = CostAmounts.averageDailyValue(points, true)
            compare(CostAmounts.tokenCountString(average.value), "242")
            verify(average.value === 241.5)
            points.reverse()
        }
    }

    function test_averageDailyValueAvoidsIntermediateOverflow() {
        for (var showsTokens of [false, true]) {
            var points = [
                {cost: Number.MAX_VALUE, tokens: Number.MAX_VALUE, currency: "EUR"},
                {cost: Number.MAX_VALUE, tokens: Number.MAX_VALUE, currency: "EUR"}
            ]
            var average = CostAmounts.averageDailyValue(points, showsTokens)
            compare(average.value, Number.MAX_VALUE)
            compare(average.currency, "EUR")
            points.push({cost: null, tokens: null})
            points.push({cost: 0, tokens: 0, currency: "EUR"})
            average = CostAmounts.averageDailyValue(points, showsTokens)
            verify(isFinite(average.value))
            verify(Math.abs(average.value / Number.MAX_VALUE - 2 / 3) < 1e-15)
        }
    }

    // A range the CLI measured as zero is an answer, not a missing one. The
    // history rows below the average already print those zeros.
    function test_averageDailyValueKeepsAFullyMeasuredZeroRange() {
        var measuredZeros = [dailyPoint("Mon", 0, 0), dailyPoint("Tue", 0, 0)]

        compare(CostAmounts.averageDailyValue(measuredZeros, false).value, 0)
        compare(CostAmounts.averageDailyValue(measuredZeros, false).currency, "USD")
        compare(CostAmounts.averageDailyValue(measuredZeros, true).value, 0)
        compare(CostAmounts.averageDailyValue(
            [dailyPoint("Mon", null, null), dailyPoint("Tue", null, null)], false), null)

        // The caller prints the average through these formatters, so a zero has
        // to reach the line as a figure rather than the unavailable dash.
        var fmt = CostAmounts.numberFormat(undefined, undefined)
        compare(CostAmounts.amountString(fmt, 0, "USD"), "$0.00")
        compare(CostAmounts.tokenCountString(0), "0")
    }

    function test_averageDailyValueExcludesUnavailableMetricDays() {
        var points = [
            dailyPoint("Mon", null, 100),
            dailyPoint("Tue", 6, 300)
        ]

        compare(CostAmounts.averageDailyValue(points, false).value, 6)
        compare(CostAmounts.averageDailyValue(points, true).value, 200)
    }

    function test_perMillionAmountNeedsBothHalvesOfTheRatio() {
        compare(CostAmounts.perMillionAmount({ totals: { cost: 2, tokens: 1000000, currency: "USD" } }).value, 2)
        compare(CostAmounts.perMillionAmount({ totals: { cost: 2, tokens: 0 } }), null)
        compare(CostAmounts.perMillionAmount({ totals: { cost: 0, tokens: 500 } }), null)
        compare(CostAmounts.perMillionAmount(null), null)
    }

    function test_perMillionAmountKeepsRepresentableRatios_data() {
        return [
            {tag: "ordinary", cost: 2, tokens: 1000000, expected: 2},
            {tag: "large equal totals", cost: 1e308, tokens: 1e308, expected: 1000000},
            {tag: "maximum equal totals", cost: Number.MAX_VALUE, tokens: Number.MAX_VALUE, expected: 1000000},
            {tag: "maximum rate", cost: Number.MAX_VALUE, tokens: 1000000, expected: Number.MAX_VALUE},
            {tag: "smallest rate", cost: Number.MIN_VALUE, tokens: 1000000, expected: Number.MIN_VALUE}
        ]
    }

    function test_perMillionAmountKeepsRepresentableRatios(data) {
        var result = CostAmounts.perMillionAmount({totals: {
            cost: data.cost, tokens: data.tokens, currency: "EUR"
        }})
        verify(result !== null)
        verify(isFinite(result.value))
        verify(Math.abs(result.value / data.expected - 1) < 1e-14)
        compare(result.currency, "EUR")
    }

    function test_perMillionAmountOmitsUnrepresentableRatios() {
        compare(CostAmounts.perMillionAmount({totals: {
            cost: Number.MAX_VALUE, tokens: 1, currency: "USD"
        }}), null)
    }

    function test_chartBarGeometryKeepsTheLastBarInsideTheCanvas() {
        var dense = CostChart.chartBarGeometry(100, 365)
        verify(dense.offset >= 0)
        verify(dense.offset + dense.step * (365 - 1) + dense.barWidth <= 100.0001)
        verify(dense.barWidth >= 1)
        var sparse = CostChart.chartBarGeometry(100, 2)
        compare(sparse.offset, 2)
        compare(sparse.gap, 4)
        compare(sparse.step, 50)
        compare(sparse.barWidth, 46)
    }

    function test_chartPreviewKeepsTheInspectedDayClear_data() {
        return [
            {tag: "left edge", width: 300, anchor: 3.5, wanted: 120, x: 15.5, size: 120},
            {tag: "middle", width: 300, anchor: 150, wanted: 120, x: 162, size: 120},
            {tag: "flip left", width: 300, anchor: 210, wanted: 120, x: 78, size: 120},
            {tag: "right edge", width: 300, anchor: 296.5, wanted: 120, x: 164.5, size: 120},
            {tag: "long content", width: 200, anchor: 120, wanted: 400, x: 0, size: 108},
            {tag: "long content right", width: 200, anchor: 80, wanted: 400, x: 92, size: 108},
            {tag: "empty plot", width: 0, anchor: 0, wanted: 120, x: 0, size: 0}
        ]
    }

    function test_chartPreviewKeepsTheInspectedDayClear(data) {
        var result = CostChart.chartPreviewGeometry(data.width, data.anchor, data.wanted, 12)
        compare(result.x, data.x)
        compare(result.width, data.size)
        verify(result.x >= 0 && result.x + result.width <= data.width)
        if (data.width > 0)
            verify(result.x >= data.anchor + 12 || result.x + result.width <= data.anchor - 12)
    }

    function test_chartLineGeometryInsetsEndpointMarkers() {
        compare(CostChart.chartLineX(100, 3, 0, 3.5), 3.5)
        compare(CostChart.chartLineX(100, 3, 1, 3.5), 50)
        compare(CostChart.chartLineX(100, 3, 2, 3.5), 96.5)

        compare(CostChart.chartLineX(4, 2, 0, 3.5), 2)
        compare(CostChart.chartLineX(4, 2, 1, 3.5), 2)
        compare(CostChart.chartLineX(100, 1, 0, 3.5), 50)
    }

    function test_chartLineHitTestingMatchesInsetMarkerPositions() {
        compare(CostChart.chartLineIndexAt(300, 120, 3.5, 3.5), 0)
        compare(CostChart.chartLineIndexAt(300, 120, 296.5, 3.5), 119)
        compare(CostChart.chartLineIndexAt(300, 120, 150, 3.5), 60)
        compare(CostChart.chartLineIndexAt(300, 120, 0, 3.5), 0)
        compare(CostChart.chartLineIndexAt(300, 120, 300, 3.5), 119)
    }

    function test_chartLineGeometryInsetsVerticalMarkers() {
        compare(CostChart.chartLineY(100, 0, 3.5), 96.5)
        compare(CostChart.chartLineY(100, 0.5, 3.5), 50)
        compare(CostChart.chartLineY(100, 1, 3.5), 3.5)

        compare(CostChart.chartLineY(4, 0, 3.5), 2)
        compare(CostChart.chartLineY(4, 1, 3.5), 2)
        compare(CostChart.chartLineY(100, -1, 3.5), 96.5)
        compare(CostChart.chartLineY(100, 2, 3.5), 3.5)
    }

    function test_chartBarGeometrySurvivesAZeroPointChart() {
        var empty = CostChart.chartBarGeometry(0, 0)
        compare(empty.step, 0)
        compare(empty.barWidth, 1)
        compare(empty.offset, 0)
    }

    function test_chartPointsClampNegativeValuesAndBoundLabels() {
        var points = CostChart.chartPoints(fmt, [dailyPoint("Mon", -4, 100)], false)
        compare(points[0].value, 0)
        compare(points[0].displayValue, "$0.00")
        // `long` is a QML reserved word, so the label fixture cannot borrow it.
        var oversized = CostChart.chartPoints(fmt, [dailyPoint(new Array(300).join("x"), 1, 1)], false)
        compare(oversized[0].label.length, 120)
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

    function test_historyRowsScaleLargeFiniteAmounts_data() {
        return [{ tag: "cost", showsTokens: false }, { tag: "tokens", showsTokens: true }]
    }

    function test_historyRowsScaleLargeFiniteAmounts(data) {
        var daily = Normalizer.normalizeCostDaily([
            { date: "2026-10-19", totalCost: 1e308, totalTokens: 1e308 },
            { date: "2026-10-20", totalCost: 5e307, totalTokens: 5e307 }
        ], "USD", { days: 2, updatedAt: "2026-10-20T12:00:00Z" })
        compare(CostAmounts.metricValue(daily[1], data.showsTokens), 5e307)
        compare(CostAmounts.sparklineMax(daily, data.showsTokens), 1e308)
        var rows = CostPresentation.historyRows(fmt, { daily: daily }, data.showsTokens, "Latest")
        compare(rows.length, 2)
        compare(rows[0].percent, 50)
        compare(rows[1].percent, 100)
        compare(rows[0].isPeak, false)
        compare(rows[1].isPeak, true)
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

    // Qt 6.8 re-notifies a var binding that re-evaluates to the same object, so
    // a shallow provider copy must not rebuild the points the chart reconciles.
    function test_memoizedChartPointsKeepIdentityForSameInputs() {
        var memo = ({})
        var daily = [dailyPoint("Mon", 1, 1500), dailyPoint("Tue", 2, 200)]
        var first = CostChart.memoizedChartPoints(memo, fmt, daily, false)
        compare(first.length, 2)
        verify(CostChart.memoizedChartPoints(memo, fmt, daily, false) === first)
        var copy = daily.slice()
        var rebuilt = CostChart.memoizedChartPoints(memo, fmt, copy, false)
        verify(rebuilt !== first)
        var tokenPoints = CostChart.memoizedChartPoints(memo, fmt, copy, true)
        verify(tokenPoints !== rebuilt)
        compare(tokenPoints[0].displayValue, "1.5K")
        var otherFormat = CostAmounts.numberFormat(".", ",")
        var localizedPoints = CostChart.memoizedChartPoints(memo, otherFormat, copy, true)
        verify(localizedPoints !== tokenPoints)
        compare(localizedPoints[0].displayValue, "1,5K")
        compare(CostChart.memoizedChartPoints(memo, fmt, null, false).length, 0)
        compare(CostChart.memoizedChartPoints(null, fmt, daily, false).length, 2)
    }

    function test_chartPointsAndSparklineMaxSurviveNonArrayInputs() {
        compare(CostChart.chartPoints(fmt, null, false).length, 0)
        compare(CostChart.chartPoints(fmt, "invalid", false).length, 0)
        compare(CostAmounts.sparklineMax(null, false), 0)
        compare(CostAmounts.sparklineMax("invalid", false), 0)
    }

    function test_averageDailyValueAndPeakPointSurviveNonArrayInputs() {
        compare(CostAmounts.averageDailyValue(null, false), null)
        compare(CostAmounts.averageDailyValue("invalid", false), null)
        compare(CostAmounts.peakPoint(null, false), null)
        compare(CostAmounts.peakPoint("invalid", false), null)
    }

    function test_spendHelpersSurviveNonArrayInputs() {
        var arrayLike = { length: 1, 0: null }
        compare(CostPresentation.spendDailyPoints(fmt, arrayLike, false).length, 0)
        compare(CostCurrency.spendCurrency(arrayLike), "USD")
        compare(CostCurrency.spendHasMixedCostCurrencies(arrayLike), false)
        compare(CostPresentation.spendTotals("invalid"), null)
    }

    function test_modelRowsLetTheCallerWordTheTokenHalf() {
        var rows = CostPresentation.modelRows(fmt, { models: [
            { label: "gpt", cost: 1, tokens: 2000, currency: "USD" }
        ] }, function(tokens) { return CostAmounts.tokenCountString(tokens) + " tokens" })
        compare(rows[0].value, "$1.00 · 2K tokens")
    }

    // A snapshot answered for a different window must not be summed into the
    // range the user has since selected.
    function test_costPeriodKeepsOnlyCliCalendarPeriods() {
        compare(CostPresentation.costPeriod("month-to-date"), "month-to-date")
        compare(CostPresentation.costPeriod("all"), "all")
        compare(CostPresentation.costPeriod("rolling:30"), "")
        compare(CostPresentation.costPeriod("ALL"), "")
        compare(CostPresentation.costPeriod(""), "")
        compare(CostPresentation.costPeriod(null), "")
        compare(CostPresentation.costPeriod({}), "")
    }

    function test_snapshotMatchesRangeSeparatesPeriodsFromDays() {
        var monthToDate = { historyDays: 26, period: "month-to-date" }
        verify(CostPresentation.snapshotMatchesRange(monthToDate, 30, "month-to-date"))
        verify(!CostPresentation.snapshotMatchesRange(monthToDate, 26, ""))
        verify(!CostPresentation.snapshotMatchesRange(monthToDate, 26, "all"))
        verify(!CostPresentation.snapshotMatchesRange({ historyDays: 30 }, 30, "all"))
        verify(CostPresentation.snapshotMatchesRange({ historyDays: 30, period: "" }, 30, ""))
        compare(CostPresentation.spendSnapshots({ codex: monthToDate,
            claude: { provider: "claude", historyDays: 26 } }, 26, null, "month-to-date"), [monthToDate])
    }

    function test_snapshotMatchesRangeRejectsAStaleWindow() {
        verify(CostPresentation.snapshotMatchesRange({ historyDays: 30 }, 30))
        verify(CostPresentation.snapshotMatchesRange({ historyDays: "30" }, "30"))
        verify(CostPresentation.snapshotMatchesRange({ historyDays: "30" }, 30))
        verify(CostPresentation.snapshotMatchesRange({ historyDays: 30 }, "30"))
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
        compare(CostCurrency.spendCurrency([{ totals: { currency: "EUR" } }]), "EUR")
        compare(CostCurrency.spendCurrency([{ totals: {}, daily: [dailyPoint("Mon", 1, 1, "GBP")] }]), "GBP")
        compare(CostCurrency.spendCurrency([]), "USD")
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

        compare(CostCurrency.spendCurrency(costs), "EUR")

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

    function test_spendCurrencyPreservesSelectionAndMixedCurrencyPolicy_data() {
        return [
            { tag: "measured-zero", costs: [
                { totals: { cost: null, currency: "USD" } },
                { totals: { cost: 0, currency: "EUR" } }
            ], currency: "EUR", mixed: false },
            { tag: "daily-before-later-provider-total", costs: [
                { totals: { currency: "USD" }, daily: [{ cost: 0, currency: "GBP" }] },
                { totals: { cost: 2, currency: "EUR" } }
            ], currency: "GBP", mixed: true },
            { tag: "totals-before-own-daily", costs: [
                { totals: { cost: 1, currency: "EUR" }, daily: [{ cost: 2, currency: "GBP" }] }
            ], currency: "EUR", mixed: true },
            { tag: "unusable-amounts-cannot-select-currency", costs: [
                { totals: { cost: "3", currency: "USD" },
                    daily: [null, { cost: false, currency: "GBP" }, { cost: Infinity, currency: "CAD" }] },
                { totals: { cost: 1, currency: "JPY" } }
            ], currency: "JPY", mixed: false },
            { tag: "token-only-totals-fallback", costs: [
                null, { totals: { tokens: 10, currency: "EUR" }, daily: [{ currency: "GBP" }] }
            ], currency: "EUR", mixed: false },
            { tag: "first-daily-usd-fallback", costs: [
                { daily: [null, { currency: "GBP" }] }, { totals: { currency: "EUR" } }
            ], currency: "USD", mixed: false },
            { tag: "unlabelled-total-inherits-selected-currency", costs: [
                { totals: { cost: 1 } }, { totals: { cost: 2, currency: "EUR" } }
            ], currency: "EUR", mixed: false },
            { tag: "unlabelled-daily-keeps-usd-default", costs: [
                { daily: [{ cost: 1 }] }, { totals: { cost: 2, currency: "EUR" } }
            ], currency: "EUR", mixed: true }
        ]
    }

    function test_spendCurrencyPreservesSelectionAndMixedCurrencyPolicy(data) {
        var original = JSON.stringify(data.costs)
        compare(CostCurrency.spendCurrency(data.costs), data.currency)
        compare(CostCurrency.spendHasMixedCostCurrencies(data.costs), data.mixed)
        compare(JSON.stringify(data.costs), original)
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

    function test_spendAggregatesRejectOverflow_data() {
        return [{tag: "cost", tokens: false}, {tag: "tokens", tokens: true}]
    }

    function test_spendAggregatesRejectOverflow(data) {
        var costs = []
        for (var index = 0; index < 3; index++) {
            var cost = data.tokens ? 2 : 1e308
            var tokens = data.tokens ? 1e308 : 5
            costs.push({totals: {cost: cost, tokens: tokens, currency: "USD"},
                daily: [dailyPoint("2026-09-01", cost, tokens, "USD"),
                    dailyPoint("2026-09-02", 0, 0, "USD")]})
        }
        var before = JSON.stringify(costs)
        var points = CostPresentation.spendDailyPoints(fmt, costs, data.tokens)
        compare(points.length, 1)
        compare(points[0].label, "2026-09-02")
        compare(points[0].value, 0)
        var days = CostChart.spendHeatmapDays(points, costs)
        compare(days.length, 2)
        compare(days[0], null)
        compare(days[1].value, 0)
        var totals = CostPresentation.spendTotals(costs)
        compare(data.tokens ? totals.tokens : totals.cost, null)
        compare(data.tokens ? totals.cost : totals.tokens, data.tokens ? 6 : 15)
        var healthyPoints = CostPresentation.spendDailyPoints(fmt, costs, !data.tokens)
        compare(healthyPoints.length, 2)
        compare(healthyPoints[0].value, data.tokens ? 6 : 15)
        compare(JSON.stringify(costs), before)
    }

    function test_spendHeatmapCellsPadTheOldestCornerAndKeepTheNewestDayLast() {
        var points = []
        for (var day = 0; day < 30; day++) {
            points.push({ label: "day-" + day, value: day, displayValue: "" })
        }

        var cells = CostChart.spendHeatmapCells(points, 35)
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
        var cells = CostChart.spendHeatmapCells(
            CostChart.spendHeatmapDays(points, costs), 14)
        compare(cells.length, 14)
        verify(cells[5] !== null, "the first day must occupy its calendar slot")
        compare(cells[5].label, "2026-09-01")
        compare(cells[8], null, "an unavailable day must leave a gap, not shift earlier weekdays")
        compare(cells[12].label, "2026-09-08")
        compare(cells[13].label, "2026-09-09")
        compare(cells[12].value, 8)
        var tokenCells = CostChart.spendHeatmapCells(
            CostChart.spendHeatmapDays(CostPresentation.spendDailyPoints(fmt, costs, true), costs), 14)
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
        compare(CostChart.spendHeatmapRowWeekdays(days, 1), [1, 2, 3, 4, 5, 6, 0])
        compare(CostChart.spendHeatmapRowWeekdays(days, 0), [0, 1, 2, 3, 4, 5, 6])
        compare(CostChart.spendHeatmapRowWeekdays(days, 6), [6, 0, 1, 2, 3, 4, 5])
        // An unusable locale value falls back to the ISO Monday start.
        compare(CostChart.spendHeatmapRowWeekdays(days, 7), [1, 2, 3, 4, 5, 6, 0])
        compare(CostChart.spendHeatmapRowWeekdays(days, "0"), [1, 2, 3, 4, 5, 6, 0])
        compare(CostChart.spendHeatmapRowWeekdays(days, 1.5), [1, 2, 3, 4, 5, 6, 0])
        compare(CostChart.spendHeatmapRowWeekdays(days), [1, 2, 3, 4, 5, 6, 0])
    }

    function test_spendHeatmapTrailingSlotsCloseTheNewestWeek() {
        // 2026-09-23 is a Wednesday.
        var days = []
        for (var day = 17; day <= 23; day++) {
            days.push({ label: "2026-09-" + day, value: day })
        }
        compare(CostChart.spendHeatmapTrailingSlots(days, 1), 4)
        compare(CostChart.spendHeatmapTrailingSlots(days, 0), 3)
        compare(CostChart.spendHeatmapTrailingSlots(days, 4), 0)
        // An unavailable newest day still ends the grid in its own slot.
        days[6] = null
        compare(CostChart.spendHeatmapTrailingSlots(days, 1), 4)
        // Unlabelled rows keep the newest day last, with no trailing gap.
        compare(CostChart.spendHeatmapTrailingSlots([{ label: "day-0" }], 1), 0)
        compare(CostChart.spendHeatmapTrailingSlots(undefined, 1), 0)
    }

    function test_spendHeatmapCellsLeaveTrailingSlotsAfterTheNewestDay() {
        var points = []
        for (var day = 0; day < 8; day++) {
            points.push({ label: "day-" + day, value: day, displayValue: "" })
        }
        var cells = CostChart.spendHeatmapCells(points, 14, 4)
        compare(cells.length, 14)
        compare(cells[0], null)
        compare(cells[1], null)
        compare(cells[2].label, "day-0")
        compare(cells[9].label, "day-7")
        for (var slot = 10; slot < 14; slot++) {
            compare(cells[slot], null)
        }
        // Capacity drops the oldest days first, never the trailing slots.
        cells = CostChart.spendHeatmapCells(points, 7, 4)
        compare(cells[0].label, "day-5")
        compare(cells[2].label, "day-7")
        compare(cells[6], null)
        compare(CostChart.spendHeatmapCells(points, 7, 9).length, 7)
        compare(CostChart.spendHeatmapCells(points, 7, -3)[6].label, "day-7")
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
        compare(CostChart.spendHeatmapRowWeekdays(data.days, 1), [])
    }

    function test_spendHeatmapRowWeekdaysFollowTheCalendarFallback() {
        var daily = []
        for (var day = 1; day <= 9; day++) {
            daily.push(dailyPoint("2026-09-0" + day, day === 9 ? null : day, day * 10, "USD"))
        }
        var costs = [{ totals: { currency: "USD" }, daily: daily }]
        var days = CostChart.spendHeatmapDays(
            CostPresentation.spendDailyPoints(fmt, costs, false), costs)
        // 2026-09-09 is a Wednesday; its unavailable slot still ends the grid.
        compare(CostChart.spendHeatmapRowWeekdays(days, 1)[0], 1)
        compare(CostChart.spendHeatmapTrailingSlots(days, 1), 4)

        var undated = [{ label: "day-0", value: 1 }, { label: "day-1", value: 2 }]
        compare(CostChart.spendHeatmapRowWeekdays(
            CostChart.spendHeatmapDays(undated, []), 1), [])
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
        var days = CostChart.spendHeatmapDays(points, costs)
        compare(days.length, 9, "metric filtering must preserve the loaded calendar boundaries")
        compare(CostChart.spendHeatmapDays([], costs), [])
        compare(days[4].value, 0)
        for (var i = 0; i < data.missing.length; i++) {
            compare(days[data.missing[i] - 1], null)
        }
        var cells = CostChart.spendHeatmapCells(days, 14)
        compare(cells[9].label, "2026-09-05")
        compare(cells[13], days[8])
    }

    function test_spendHeatmapDaysPreserveCalendarBoundaries(data) {
        var points = [{label: data.first, value: 0}, {label: data.last, value: 3}]
        var days = CostChart.spendHeatmapDays(points)
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
        var days = CostChart.spendHeatmapDays([{label: "1970-01-01", value: 2}, latest])
        compare(days.length, CostChart.maximumCostHistoryPoints)
        compare(days[0], null)
        compare(days[days.length - 1], latest)
        var cells = CostChart.spendHeatmapCells(
            CostChart.spendHeatmapDays([{label: "2026-09-01", value: 2}, latest]), 7)
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
            compare(CostChart.spendHeatmapDays(legacyCases[i]), legacyCases[i])
        }
        compare(CostChart.spendHeatmapDays(null), [])
    }

    function test_spendHeatmapCellsDropTheOldestDaysBeyondCapacity() {
        var cells = CostChart.spendHeatmapCells([
            { label: "a" }, { label: "b" }, { label: "c" }
        ], 2)
        compare(cells.length, 2)
        compare(cells[0].label, "b")
        compare(cells[1].label, "c")
    }

    function test_spendHeatmapCellsSurviveMissingAndNonsenseInput() {
        compare(CostChart.spendHeatmapCells(undefined, 7).length, 7)
        compare(CostChart.spendHeatmapCells("not an array", 2)[0], null)
        compare(CostChart.spendHeatmapCells([{ label: "a" }], 0).length, 0)
        compare(CostChart.spendHeatmapCells([{ label: "a" }], -4).length, 0)
        compare(CostChart.spendHeatmapCells([{ label: "a" }], NaN).length, 0)
        compare(CostChart.spendHeatmapCells([{ label: "a" }], 2.7).length, 2)
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
        verify(CostCurrency.spendHasMixedCostCurrencies([
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
        compare(CostTrust.costTrustSummary([]), null)
        compare(CostTrust.costTrustSummary(null), null)
        compare(CostTrust.costTrustSummary([{ totals: { currency: "USD" } }]), null)
        compare(CostTrust.costTrustSummary([trustedCost("USD", {
            priced: 3, unpriced: 0, unmetered: 0, estimated: 0
        }, "")]), null)
        compare(CostTrust.costTrustSummary([{
            totals: { currency: "USD" },
            trust: { coverage: { priced: "3" }, sourceKind: "not-a-semantic-value" }
        }]), null)

        function InheritedTrust() {}
        InheritedTrust.prototype.coverage = {
            priced: 0, unpriced: 1, unmetered: 0, estimated: 0
        }
        InheritedTrust.prototype.sourceKind = "unknown"
        compare(CostTrust.costTrustSummary([{
            totals: { currency: "USD" },
            trust: new InheritedTrust()
        }]), null)
    }

    function test_costTrustSummaryIgnoresTokenOnlySnapshots() {
        compare(CostTrust.costTrustSummary([{
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

        var summary = CostTrust.costTrustSummary([
            trustedCost("USD", {
                priced: 1, unpriced: 0, unmetered: 0, estimated: 1
            }, "listPrice"),
            emptySnapshot
        ])

        compare(summary.sourceKind, "listPrice")
        compare(summary.valueMode, "estimated")
    }

    function test_costTrustSummaryKeepsTokenOnlyGapsInAMixedTotal() {
        var summary = CostTrust.costTrustSummary([
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
        var summary = CostTrust.costTrustSummary([
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
        var summary = CostTrust.costTrustSummary([trustedCost("USD", {
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
        var summary = CostTrust.costTrustSummary([trustedCost("USD", {
            priced: 5, unpriced: 2, unmetered: 1, estimated: 0
        }, "vendor")])

        compare(summary.level, "warning")
        compare(summary.valueMode, "partial")
        compare(summary.sourceKind, "vendor")
        verify(summary.hasUnpriced)
        verify(summary.hasUnmetered)
    }

    function test_costTrustSummaryMakesExcludedRequestsPartial() {
        var summary = CostTrust.costTrustSummary([{
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
        var summary = CostTrust.costTrustSummary([
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
        var summary = CostTrust.costTrustSummary([{
            totals: { cost: 1, tokens: 10, currency: "USD" },
            trust: { coverage: null, sourceKind: "vendor", incompleteRequests: data.value }
        }])

        compare(summary.incompleteRequests, 0)
        compare(summary.valueMode, "plain")
        compare(summary.level, "information")
    }

    function test_costTrustSummaryBoundsSaturatedExcludedRequestCounts() {
        var summary = CostTrust.costTrustSummary([
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
        var summary = CostTrust.costTrustSummary([{
            totals: { tokens: 10, currency: "USD" },
            trust: { coverage: null, sourceKind: "", incompleteRequests: 4 }
        }])

        compare(summary.level, "warning")
        compare(summary.valueMode, "partial")
        compare(summary.incompleteRequests, 4)
    }

    function test_costTrustSummaryStaysQuietWithoutAnyDisplayedAmount() {
        compare(CostTrust.costTrustSummary([{
            totals: { tokens: 0, currency: "USD" },
            trust: { coverage: null, sourceKind: "", incompleteRequests: 4 }
        }]), null)
    }

    function test_costTrustNoticeKeyIgnoresTheExcludedRequestMagnitude() {
        var one = CostTrust.costTrustNoticeKey({
            level: "warning", sourceKind: "vendor", incompleteRequests: 1
        })
        var many = CostTrust.costTrustNoticeKey({
            level: "warning", sourceKind: "vendor", incompleteRequests: 9
        })
        var none = CostTrust.costTrustNoticeKey({
            level: "warning", sourceKind: "vendor", incompleteRequests: 0
        })

        compare(one, many)
        verify(one.indexOf("incomplete") !== -1)
        verify(none.indexOf("complete") !== -1)
        verify(none.indexOf("incomplete") === -1)
        compare(CostTrust.costTrustNoticeKey({ incompleteRequests: 3 }),
            "information||exact|priced|metered|incomplete")
        compare(CostTrust.costTrustNoticeKey({ incompleteRequests: 0 }), "")
    }

    function test_costTrustSummaryTreatsUnknownAsApproximateAndConservative() {
        var summary = CostTrust.costTrustSummary([
            trustedCost("USD", null, "listPrice"),
            trustedCost("USD", null, "unknown")
        ])

        compare(summary.level, "warning")
        compare(summary.valueMode, "approximate")
        compare(summary.sourceKind, "unknown")
    }

    function test_costTrustSummaryDoesNotClassifyLegacyCostFromTrustedSubset() {
        var summary = CostTrust.costTrustSummary([
            trustedCost("USD", null, "vendor"),
            { totals: { cost: 9, tokens: 90, currency: "USD" }, trust: null }
        ])

        compare(summary.level, "warning")
        compare(summary.valueMode, "approximate")
        compare(summary.sourceKind, "unknown")
    }

    function test_costTrustSummaryFoldsKnownSourcesWithoutCallingMixedIncomplete() {
        var summary = CostTrust.costTrustSummary([
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
        var summary = CostTrust.costTrustSummary([
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
        compare(CostTrust.costTrustSummary([{
            totals: { currency: "USD" },
            historyCoverageEstablished: false
        }]), null)
    }

    function test_costTrustNoticeDismissalSurvivesRefreshUntilMeaningChanges() {
        var estimated = CostTrust.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 0, unmetered: 0, estimated: 1
        }, "listPrice")])
        var initial = CostTrust.costTrustNoticeTransition(
            estimated, null, false)
        verify(initial.shouldShow)

        var dismissed = CostTrust.costTrustNoticeTransition(
            estimated, initial, true)
        verify(!dismissed.shouldShow)

        var refreshed = CostTrust.costTrustNoticeTransition(
            CostTrust.costTrustSummary([trustedCost("USD", {
                priced: 4, unpriced: 0, unmetered: 0, estimated: 1
            }, "listPrice")]),
            dismissed,
            false)
        verify(!refreshed.shouldShow)

        var partial = CostTrust.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 1, unmetered: 0, estimated: 1
        }, "listPrice")])
        var changed = CostTrust.costTrustNoticeTransition(
            partial, refreshed, false)
        verify(changed.shouldShow)
        verify(changed.key !== dismissed.key)

        var dismissedPartial = CostTrust.costTrustNoticeTransition(
            partial, changed, true)
        var returned = CostTrust.costTrustNoticeTransition(
            estimated, dismissedPartial, false)
        verify(returned.shouldShow)
    }

    function test_costTrustNoticeDismissalSurvivesNoticeRecreationPerScope() {
        var summary = CostTrust.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 1, unmetered: 0, estimated: 1
        }, "listPrice")])
        var initial = CostTrust.costTrustNoticeStoreTransition(
            summary, ({}), "provider:codex", false)
        verify(initial.state.shouldShow)

        var dismissed = CostTrust.costTrustNoticeStoreTransition(
            summary, initial.states, "provider:codex", true)
        verify(!dismissed.state.shouldShow)
        verify(dismissed.states !== initial.states)
        verify(!initial.states["provider:codex"].dismissed)

        var temporarilyMissing = CostTrust.costTrustNoticeStoreTransition(
            null, dismissed.states, "provider:codex", false)
        verify(!temporarilyMissing.state.shouldShow)

        // A new CostTrustNotice instance must recover the dismissal from its
        // persistent owner even if its summary binding was briefly empty.
        var recreated = CostTrust.costTrustNoticeStoreTransition(
            summary, temporarilyMissing.states, "provider:codex", false)
        verify(!recreated.state.shouldShow)

        // Provider details and aggregate Spend are separate information scopes.
        var aggregate = CostTrust.costTrustNoticeStoreTransition(
            summary, dismissed.states, "spend", false)
        verify(aggregate.state.shouldShow)
    }

    function test_costTrustNoticeStoreBoundsAndRejectsUnsafeScopes() {
        var summary = CostTrust.costTrustSummary([trustedCost("USD", {
            priced: 4, unpriced: 1, unmetered: 0, estimated: 1
        }, "listPrice")])
        var oversized = ({})
        for (var i = 0; i < 200; i++) {
            oversized["provider:" + i] = { key: "old", dismissed: true }
        }
        var bounded = CostTrust.costTrustNoticeStoreTransition(
            summary, oversized, "spend", false)
        verify(Object.keys(bounded.states).length <= 128)
        verify(Object.prototype.hasOwnProperty.call(bounded.states, "spend"))

        var unsafe = CostTrust.costTrustNoticeStoreTransition(
            summary, bounded.states, "__proto__", true)
        verify(!Object.prototype.hasOwnProperty.call(unsafe.states, "__proto__"))
        verify(unsafe.state.dismissed)
    }

    function test_costTrustNoticeTransitionRejectsMalformedSummaries() {
        var invalidSummaries = [null, undefined, [], "estimated", 7, ({})]
        for (var i = 0; i < invalidSummaries.length; i++) {
            var state = CostTrust.costTrustNoticeTransition(
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

        var state = CostTrust.costTrustNoticeTransition(
            summary, null, false)
        compare(state.key, "information|listPrice|estimated|priced|metered|complete")
        verify(state.shouldShow)
    }

    function test_costTrustNoticeTransitionRejectsMalformedPreviousState() {
        var summary = CostTrust.costTrustSummary([trustedCost("USD", {
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
            var state = CostTrust.costTrustNoticeTransition(
                summary, invalidStates[i], false)
            verify(state.key.length > 0)
            verify(state.key.length < 80)
            verify(!state.dismissed)
            verify(state.shouldShow)
        }
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
        compare(CostCurrency.spendCurrency([null]), "USD")
    }

    // The suite runs with TZ=America/Los_Angeles. The CLI's "today" is the
    // total of the day it scanned, so a scan from 22:00 on 09-23 still
    // describes the 23rd after midnight.
    function test_todayAmountsNeedAScanFromToday() {
        var payload = [{provider: "codex", historyDays: 30, currencyCode: "USD",
            updatedAt: new Date(2026, 8, 23, 22).toISOString(),
            sessionCostUSD: 1.25, sessionTokens: 1200,
            totals: {totalCost: 9, totalTokens: 9000}, daily: []}];
        var cost = CostResponse.response(JSON.stringify(payload), "", 30, 0).costs.codex;
        compare(cost.scanDay, "2026-09-23");

        var sameDay = CostAmounts.todayAmounts(cost, new Date(2026, 8, 23, 23, 30).getTime());
        compare(sameDay.cost, 1.25);
        compare(sameDay.tokens, 1200);

        var nextDay = CostAmounts.todayAmounts(cost, new Date(2026, 8, 24, 0, 30).getTime());
        compare(nextDay.cost, null);
        compare(nextDay.tokens, null);
        compare(nextDay.currency, "USD");
        verify(!CostAmounts.hasMetricValue(nextDay, false));
        verify(!CostAmounts.hasMetricValue(nextDay, true));
        // The retained snapshot itself is untouched.
        compare(cost.today.cost, 1.25);

        // Privacy mode keeps the scan date, so it hides the same stale total.
        var privateCost = Privacy.cost(cost, true);
        compare(privateCost.scanDay, "2026-09-23");
        compare(CostAmounts.todayAmounts(privateCost, new Date(2026, 8, 24, 0, 30).getTime()).cost, null);
        compare(Privacy.cost({scanDay: {}}, true).scanDay, "");

        // Without a scan date or a usable clock there is nothing to compare.
        payload[0].updatedAt = "not a date";
        var undated = CostResponse.response(JSON.stringify(payload), "", 30, 0).costs.codex;
        compare(undated.scanDay, "");
        compare(CostAmounts.todayAmounts(undated, new Date(2026, 8, 24, 0, 30).getTime()).cost, 1.25);
        compare(CostAmounts.todayAmounts(cost, NaN).cost, 1.25);
        compare(CostAmounts.todayAmounts(cost, "2026-09-24").cost, 1.25);
        compare(CostAmounts.todayAmounts(null, 0), null);
        compare(CostAmounts.todayAmounts({scanDay: "2026-09-23"}, 0), null);
    }
    function test_truncationKeepsSurrogatePairsWhole() {
        var emoji = "\uD83D\uDE00"
        compare(CostAmounts.boundedText("a".repeat(119) + emoji, 120), "a".repeat(119))
        compare(CostAmounts.boundedText("a".repeat(118) + emoji, 120), "a".repeat(118) + emoji)
    }

}
