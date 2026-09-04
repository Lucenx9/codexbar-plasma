.pragma library
.import "Guards.js" as Guards

// Cost and spend presentation: number formatting, chart geometry, and the row
// and summary builders the Usage & Spend tab and the provider cost sections
// bind to.
//
// Like ProviderNormalizer.js this module must not reach for `Qt`, `Kirigami`,
// or `i18n`. Two consequences shape the interface:
//
//   * The caller supplies the words. Every function that would otherwise call
//     `i18n` returns figures rather than sentences, so the plural rules and the
//     placeholder order stay in QML where `i18np` lives.
//   * The caller supplies the locale separators through `numberFormat`, because
//     `Qt.locale()` is not reachable from a `.pragma library` module.
//
// Everything here is side-effect free apart from `paintRoundedTopBar`, which
// draws into a caller-supplied canvas context.

var maximumCostHistoryPoints = 365
var maximumCostTrustNoticeScopes = 128

// Locale separators, resolved once by the caller from `Qt.locale()`.
function numberFormat(groupSeparator, decimalPoint) {
    return {
        group: typeof groupSeparator === "string" ? groupSeparator : ",",
        decimal: typeof decimalPoint === "string" ? decimalPoint : "."
    }
}

function hasOwnKey(item, key) {
    return Guards.hasOwnKey(item, key)
}

function isUnsafeObjectKey(key) {
    return Guards.isUnsafeObjectKey(key)
}

function boundedText(value, limit) {
    if (value === null || value === undefined) {
        return ""
    }
    var text = String(value)
    return text.length > limit ? text.slice(0, limit) : text
}

// The metric the charts currently plot. Cost and tokens share one payload, so
// every scale, peak, and summary has to read the same switch.
function hasMetricValue(point, showsTokens) {
    if (!point) {
        return false
    }
    var value = showsTokens ? point.tokens : point.cost
    return typeof value === "number" && isFinite(value)
}

function metricValue(point, showsTokens) {
    if (!hasMetricValue(point, showsTokens)) {
        return 0
    }
    return showsTokens ? point.tokens : point.cost
}

function groupedDecimalString(fmt, value, digits) {
    var numeric = Number(value)
    if (!isFinite(numeric)) {
        return "-"
    }
    var parts = Math.abs(numeric).toFixed(digits).split(".")
    var whole = parts[0]
    var grouped = ""
    for (var i = 0; i < whole.length; i++) {
        if (i > 0 && (whole.length - i) % 3 === 0) {
            grouped += fmt.group
        }
        grouped += whole.charAt(i)
    }
    return parts.length > 1 ? grouped + fmt.decimal + parts[1] : grouped
}

// "Quota" is a credit balance, not money, so it prints as a bare rounded count.
// Like the money path it degrades to "-" for non-numeric input instead of
// printing "NaN".
function amountString(fmt, value, currency) {
    if (currency === "Quota") {
        var quotaAmount = Number(value)
        if (!isFinite(quotaAmount)) {
            return "-"
        }
        return String(Math.round(quotaAmount))
    }
    var numeric = Number(value)
    var negative = numeric < 0
    var amount = groupedDecimalString(fmt, Math.abs(numeric), 2)
    var code = typeof currency === "string" ? currency.trim() : ""
    if (code === "USD") {
        return negative ? "-$" + amount : "$" + amount
    }
    if (code.length === 0) {
        return (negative ? "-" : "") + amount
    }
    return (negative ? "-" : "") + code + " " + amount
}

function scaledTokenCount(value) {
    if (value >= 10) {
        return Number(value).toFixed(0)
    }
    return Number(value).toFixed(1).replace(/\.0$/, "")
}

function tokenCountString(tokens) {
    var value = Number(tokens)
    if (!isFinite(value)) {
        return "-"
    }
    var absValue = Math.abs(value)
    var sign = value < 0 ? "-" : ""
    // Round inside each unit before choosing it, so a value that rounds up
    // across a threshold promotes ("1M") instead of printing an overflowing
    // unit ("1000K").
    if (Math.round(absValue / 1000000) >= 1000) {
        return sign + scaledTokenCount(absValue / 1000000000) + "B"
    }
    if (Math.round(absValue / 1000) >= 1000) {
        return sign + scaledTokenCount(absValue / 1000000) + "M"
    }
    if (Math.round(absValue) >= 1000) {
        return sign + scaledTokenCount(absValue / 1000) + "K"
    }
    return Math.round(value).toString()
}

// Dense charts keep a one-pixel bar, so their drawing step must account for the
// bar width instead of the nominal point slot. Otherwise the newest bar extends
// beyond the right edge of the canvas.
function chartBarGeometry(width, count) {
    var numericWidth = Number(width)
    var safeWidth = isFinite(numericWidth) ? Math.max(0, numericWidth) : 0
    var numericCount = Math.floor(Number(count))
    var points = isFinite(numericCount) ? Math.max(1, numericCount) : 1
    var slotStep = safeWidth / points
    var gap = Math.max(0, Math.min(4, slotStep / 4))
    var barWidth = Math.max(1, slotStep - gap)

    if (barWidth > slotStep) {
        return {
            step: points > 1 ? Math.max(0, safeWidth - barWidth) / (points - 1) : 0,
            gap: gap,
            barWidth: barWidth,
            offset: 0
        }
    }

    return {
        step: slotStep,
        gap: gap,
        barWidth: barWidth,
        offset: Math.max(0, slotStep - barWidth) / 2
    }
}

// Keep the largest interactive marker fully inside the canvas at both ends.
function chartLineX(width, count, index, inset) {
    var numericWidth = Number(width)
    var safeWidth = isFinite(numericWidth) ? Math.max(0, numericWidth) : 0
    var numericCount = Math.floor(Number(count))
    var points = isFinite(numericCount) ? Math.max(1, numericCount) : 1
    var numericInset = Number(inset)
    var padding = Math.min(safeWidth / 2,
        isFinite(numericInset) ? Math.max(0, numericInset) : 0)

    if (points === 1) {
        return safeWidth / 2
    }

    var numericIndex = Math.floor(Number(index))
    var boundedIndex = isFinite(numericIndex)
        ? Math.max(0, Math.min(points - 1, numericIndex))
        : 0
    return padding + (safeWidth - padding * 2) * boundedIndex / (points - 1)
}

function chartLineIndexAt(width, count, positionX, inset) {
    var numericWidth = Number(width)
    var safeWidth = isFinite(numericWidth) ? Math.max(0, numericWidth) : 0
    var numericCount = Math.floor(Number(count))
    var points = isFinite(numericCount) ? Math.max(0, numericCount) : 0
    if (points === 0 || safeWidth === 0) {
        return -1
    }
    if (points === 1) {
        return 0
    }

    var numericInset = Number(inset)
    var padding = Math.min(safeWidth / 2,
        isFinite(numericInset) ? Math.max(0, numericInset) : 0)
    var numericPosition = Number(positionX)
    var boundedPosition = isFinite(numericPosition)
        ? Math.max(0, Math.min(safeWidth, numericPosition))
        : 0
    var drawableWidth = safeWidth - padding * 2
    var normalizedPosition = drawableWidth > 0
        ? (boundedPosition - padding) / drawableWidth
        : boundedPosition / safeWidth
    return Math.max(0, Math.min(points - 1,
        Math.round(normalizedPosition * (points - 1))))
}

function chartLineY(height, fraction, inset) {
    var numericHeight = Number(height)
    var safeHeight = isFinite(numericHeight) ? Math.max(0, numericHeight) : 0
    var numericInset = Number(inset)
    var padding = Math.min(safeHeight / 2,
        isFinite(numericInset) ? Math.max(0, numericInset) : 0)
    var numericFraction = Number(fraction)
    var boundedFraction = isFinite(numericFraction)
        ? Math.max(0, Math.min(1, numericFraction))
        : 0
    return safeHeight - padding - (safeHeight - padding * 2) * boundedFraction
}

function paintRoundedTopBar(context, x, baseline, width, height, radius) {
    var safeWidth = Math.max(0, width)
    var safeHeight = Math.max(0, height)
    var top = baseline - safeHeight
    var corner = Math.max(0, Math.min(radius, safeWidth / 2, safeHeight))

    context.beginPath()
    context.moveTo(x, baseline)
    context.lineTo(x, top + corner)
    context.quadraticCurveTo(x, top, x + corner, top)
    context.lineTo(x + safeWidth - corner, top)
    context.quadraticCurveTo(x + safeWidth, top, x + safeWidth, top + corner)
    context.lineTo(x + safeWidth, baseline)
    context.closePath()
    context.fill()
}

// Returns the peak of the currently plotted metric, so the bars keep their
// scale when the Usage & Spend tab switches between cost and tokens.
function sparklineMax(points, showsTokens) {
    var maximum = 0
    if (!points) {
        return maximum
    }
    for (var i = 0; i < points.length; i++) {
        maximum = Math.max(maximum, metricValue(points[i], showsTokens))
    }
    return maximum
}

function metricText(fmt, magnitude, currency, showsTokens) {
    return showsTokens
        ? tokenCountString(magnitude)
        : amountString(fmt, magnitude, currency || "USD")
}

function chartPoints(fmt, points, showsTokens) {
    var result = []
    if (!points) {
        return result
    }
    for (var i = 0; i < points.length; i++) {
        var point = points[i]
        if (!hasMetricValue(point, showsTokens)) {
            continue
        }
        var value = Math.max(0, metricValue(point, showsTokens))
        result.push({
            label: boundedText(point.label, 120),
            value: value,
            displayValue: metricText(fmt, value, point.currency, showsTokens)
        })
    }
    return result
}

// The newest plotted point, as a label and an already-formatted value. Returns
// null when there is nothing to summarise; the caller joins the two words.
function sparklineSummary(fmt, points, showsTokens) {
    if (!points || points.length === 0) {
        return null
    }
    var last = null
    for (var i = points.length - 1; i >= 0; i--) {
        if (hasMetricValue(points[i], showsTokens)) {
            last = points[i]
            break
        }
    }
    if (!last) {
        return null
    }
    return {
        label: last.label && last.label.length > 0 ? last.label : "",
        value: metricText(fmt, metricValue(last, showsTokens), last.currency, showsTokens)
    }
}

// Joins a money figure and a token figure with the separator the cost sections
// use. `tokensText` is the caller's already-worded token phrase, or "" to print
// the bare count.
function tokenSummary(fmt, cost, tokens, currency, tokensText) {
    var parts = []
    var costValue = Number(cost)
    var tokenValue = Number(tokens)
    if (isFinite(costValue) && costValue > 0) {
        parts.push(amountString(fmt, costValue, currency || "USD"))
    }
    if (isFinite(tokenValue) && tokenValue > 0) {
        parts.push(typeof tokensText === "string" && tokensText.length > 0
            ? tokensText
            : tokenCountString(tokenValue))
    }
    return parts.join(" · ")
}

// `entries` is an ordered list of `{ label, tokens }`. Rows with no positive
// token count are dropped rather than printed as zero.
function breakdownRows(entries) {
    var rows = []
    if (!entries) {
        return rows
    }
    for (var i = 0; i < entries.length; i++) {
        var value = Number(entries[i].tokens)
        if (!isFinite(value) || value <= 0) {
            continue
        }
        rows.push({
            label: entries[i].label,
            value: tokenCountString(value)
        })
    }
    return rows
}

// `tokensTextFor(tokens)` lets the caller word the token half of each summary.
function modelRows(fmt, tokenCost, tokensTextFor) {
    var rows = []
    if (!tokenCost || !tokenCost.models) {
        return rows
    }
    for (var i = 0; i < tokenCost.models.length; i++) {
        var item = tokenCost.models[i]
        rows.push({
            label: item.label,
            value: tokenSummary(fmt, item.cost, item.tokens, item.currency,
                tokensTextFor ? tokensTextFor(item.tokens) : "")
        })
    }
    return rows
}

// The last seven days, newest first, scaled against the peak of the selected
// metric so the bar lengths match the figures beside them. A point whose label
// the payload omitted gets `fallbackLabel`.
function historyRows(fmt, tokenCost, showsTokens, fallbackLabel) {
    if (!tokenCost || !tokenCost.daily || tokenCost.daily.length === 0) {
        return []
    }

    var recentDaily = tokenCost.daily.slice(Math.max(0, tokenCost.daily.length - 7))
    var visibleDaily = []
    for (var day = 0; day < recentDaily.length; day++) {
        if (hasMetricValue(recentDaily[day], showsTokens)) {
            visibleDaily.push(recentDaily[day])
        }
    }
    var rows = []
    var maximum = sparklineMax(visibleDaily, showsTokens)
    for (var i = visibleDaily.length - 1; i >= 0; i--) {
        var item = visibleDaily[i]
        var magnitude = Math.max(0, metricValue(item, showsTokens))
        var value = tokenSummary(fmt, item.cost, item.tokens, item.currency, "")
        rows.push({
            label: item.label && item.label.length > 0 ? item.label : fallbackLabel,
            value: value.length > 0
                ? value
                : metricText(fmt, 0, item.currency, showsTokens),
            percent: maximum > 0 ? Math.max(3, magnitude * 100 / maximum) : 0,
            isPeak: maximum > 0 && magnitude === maximum
        })
    }
    return rows
}

// The bars highlight the peak of the selected metric, so this has to name the
// same day, not the most expensive one. Returns null when nothing was spent.
function peakPoint(points, showsTokens) {
    if (!points || points.length === 0) {
        return null
    }
    var peak = null
    for (var i = 0; i < points.length; i++) {
        var magnitude = metricValue(points[i], showsTokens)
        if (!peak || magnitude > peak.magnitude) {
            peak = {
                label: points[i].label && points[i].label.length > 0 ? points[i].label : "",
                magnitude: magnitude,
                currency: points[i].currency || "USD"
            }
        }
    }
    return peak && peak.magnitude > 0 ? peak : null
}

function averageDailyValue(points, showsTokens) {
    if (!points || points.length === 0) {
        return null
    }
    var total = 0
    var count = 0
    var currency = "USD"
    for (var i = 0; i < points.length; i++) {
        if (!hasMetricValue(points[i], showsTokens)) {
            continue
        }
        total += Math.max(0, metricValue(points[i], showsTokens))
        count += 1
        if (points[i].currency) {
            currency = points[i].currency
        }
    }
    if (total <= 0) {
        return null
    }
    return { value: total / count, currency: currency }
}

function perMillionAmount(tokenCost) {
    if (!tokenCost || !tokenCost.totals) {
        return null
    }
    var cost = Number(tokenCost.totals.cost)
    var tokens = Number(tokenCost.totals.tokens)
    if (!isFinite(cost) || !isFinite(tokens) || cost <= 0 || tokens <= 0) {
        return null
    }
    return {
        value: cost * 1000000 / tokens,
        currency: tokenCost.totals.currency || "USD"
    }
}

// A cached cost snapshot belongs to the selected range only when the CLI
// answered for the same window; a stale snapshot must not be summed into a
// range the user has since changed.
function snapshotMatchesRange(tokenCost, historyDays) {
    if (!tokenCost) {
        return false
    }
    var snapshotDays = Number(tokenCost.historyDays)
    return isFinite(snapshotDays)
        && Math.floor(snapshotDays) === Math.floor(Number(historyDays))
}

// `titleFor` maps a provider ID to its display title, so the sort order matches
// what the Usage & Spend tab prints.
function spendSnapshots(tokenCosts, historyDays, titleFor) {
    var result = []
    for (var providerID in tokenCosts) {
        if (!hasOwnKey(tokenCosts, providerID)) {
            continue
        }
        var tokenCost = tokenCosts[providerID]
        if (!snapshotMatchesRange(tokenCost, historyDays)) {
            continue
        }
        result.push(tokenCost)
    }
    result.sort(function(a, b) {
        var left = titleFor ? titleFor(a.provider) : String(a.provider)
        var right = titleFor ? titleFor(b.provider) : String(b.provider)
        return left.localeCompare(right)
    })
    return result
}

function spendCurrency(costs) {
    var items = costs || []
    // A token-only snapshot still carries a fallback currency, but it must not
    // choose which priced providers participate in the money aggregate.
    for (var i = 0; i < items.length; i++) {
        var totals = items[i].totals || ({})
        if (hasMetricValue(totals, false)) {
            var totalsCurrency = boundedText(totals.currency || "", 12)
            if (totalsCurrency.length > 0) {
                return totalsCurrency
            }
        }
        var daily = items[i].daily || []
        for (var j = 0; j < daily.length; j++) {
            if (!hasMetricValue(daily[j], false)) {
                continue
            }
            var dailyCurrency = boundedText(daily[j].currency || "", 12)
            if (dailyCurrency.length > 0) {
                return dailyCurrency
            }
        }
    }
    for (var fallbackIndex = 0; fallbackIndex < items.length; fallbackIndex++) {
        var fallbackTotals = items[fallbackIndex].totals || ({})
        var fallbackCurrency = boundedText(fallbackTotals.currency || "", 12)
        if (fallbackCurrency.length > 0) {
            return fallbackCurrency
        }
        var fallbackDaily = items[fallbackIndex].daily || []
        if (fallbackDaily.length > 0) {
            return boundedText(fallbackDaily[0].currency || "USD", 12)
        }
    }
    return "USD"
}

function costMatchesSpendCurrency(cost, currency) {
    var totals = cost && cost.totals ? cost.totals : ({})
    return boundedText(totals.currency || currency, 12) === currency
}

// Cost figures from different currencies cannot share one aggregate. The
// caller uses this to label the selected-currency amount as a subtotal and to
// explain why token totals can cover more providers than money totals.
function spendHasMixedCostCurrencies(costs) {
    var items = costs || []
    var currency = spendCurrency(items)
    for (var i = 0; i < items.length; i++) {
        var totals = items[i].totals || ({})
        if (hasMetricValue(totals, false)
                && boundedText(totals.currency || currency, 12) !== currency) {
            return true
        }
        var daily = items[i].daily || []
        for (var j = 0; j < daily.length; j++) {
            if (hasMetricValue(daily[j], false)
                    && boundedText(daily[j].currency || "USD", 12) !== currency) {
                return true
            }
        }
    }
    return false
}

function acceptedCostCoverage(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
        return null
    }
    var fields = ["priced", "unpriced", "unmetered", "estimated"]
    for (var i = 0; i < fields.length; i++) {
        var field = fields[i]
        var count = value[field]
        if (!hasOwnKey(value, field)
                || typeof count !== "number"
                || !isFinite(count)
                || Math.floor(count) !== count
                || count < 0) {
            return null
        }
    }
    return value
}

function acceptedCostSourceKind(value) {
    return typeof value === "string"
            && ["listPrice", "vendor", "mixed", "unknown"]
                .indexOf(value) !== -1
        ? value
        : ""
}

// Provenance without observed cost, token, daily, or coverage data cannot
// qualify a displayed total. Missing token totals normalize to zero, so only a
// positive token count is evidence; explicit finite cost values matter at zero.
function costTrustSnapshotHasEvidence(item) {
    if (!item) {
        return false
    }

    var totals = item.totals || ({})
    if (hasMetricValue(totals, false)
            || (hasMetricValue(totals, true) && totals.tokens > 0)) {
        return true
    }

    var trust = item.trust
    var coverage = trust !== null
            && typeof trust === "object"
            && !Array.isArray(trust)
            && hasOwnKey(trust, "coverage")
        ? acceptedCostCoverage(trust.coverage)
        : null
    if (coverage && (coverage.priced > 0
            || coverage.unpriced > 0
            || coverage.unmetered > 0
            || coverage.estimated > 0)) {
        return true
    }

    var daily = Array.isArray(item.daily) ? item.daily : []
    for (var i = 0; i < daily.length; i++) {
        if (hasMetricValue(daily[i], false)
                || (hasMetricValue(daily[i], true) && daily[i].tokens > 0)) {
            return true
        }
    }
    return false
}

// Fold normalized pricing coverage and provenance into one presentation
// decision. The caller localizes it; wire enum values never cross this seam.
// For global spend, currency eligibility deliberately matches `spendTotals()`.
// Token-only snapshots still qualify a mixed total, but cannot create a notice
// when there is no finite cost to qualify.
function costTrustSummary(costs) {
    var items = Array.isArray(costs) ? costs : []
    if (items.length === 0) {
        return null
    }

    var currency = spendCurrency(items)
    var hasEstimated = false
    var hasUnpriced = false
    var hasUnmetered = false
    var hasListPrice = false
    var hasVendor = false
    var hasMixed = false
    var hasUnknown = false
    var hasUnclassifiedSource = false
    var hasDisplayedCost = false

    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        if (!costTrustSnapshotHasEvidence(item)) {
            continue
        }
        var itemHasCost = item && hasMetricValue(item.totals, false)
        if (!item || (itemHasCost && !costMatchesSpendCurrency(item, currency))) {
            continue
        }
        hasDisplayedCost = hasDisplayedCost
            || itemHasCost
        if (!hasOwnKey(item, "trust")
                || item.trust === null
                || typeof item.trust !== "object"
                || Array.isArray(item.trust)) {
            hasUnclassifiedSource = true
            continue
        }

        var coverage = hasOwnKey(item.trust, "coverage")
            ? acceptedCostCoverage(item.trust.coverage)
            : null
        if (coverage) {
            hasEstimated = hasEstimated || coverage.estimated > 0
            hasUnpriced = hasUnpriced || coverage.unpriced > 0
            hasUnmetered = hasUnmetered || coverage.unmetered > 0
        }

        var sourceKind = hasOwnKey(item.trust, "sourceKind")
            ? acceptedCostSourceKind(item.trust.sourceKind)
            : ""
        switch (sourceKind) {
        case "listPrice":
            hasListPrice = true
            break
        case "vendor":
            hasVendor = true
            break
        case "mixed":
            hasMixed = true
            break
        case "unknown":
            hasUnknown = true
            break
        default:
            hasUnclassifiedSource = true
            break
        }
    }

    var sourceKind = ""
    if (hasUnknown) {
        sourceKind = "unknown"
    } else if (hasMixed || (hasListPrice && hasVendor)) {
        sourceKind = "mixed"
    } else if (hasListPrice) {
        sourceKind = "listPrice"
    } else if (hasVendor) {
        sourceKind = "vendor"
    }

    if (hasListPrice || hasMixed) {
        hasEstimated = true
    }
    // A source reported by only part of the displayed total cannot describe
    // the whole amount. Keep all-legacy totals quiet, but make a mixed
    // classified/unclassified aggregate explicitly conservative.
    if (hasUnclassifiedSource && sourceKind.length > 0) {
        sourceKind = "unknown"
    }

    var isPartial = hasUnpriced || hasUnmetered
    if (!hasDisplayedCost
            || (!hasEstimated && !isPartial && sourceKind.length === 0)) {
        return null
    }

    return {
        level: isPartial || sourceKind === "unknown" ? "warning" : "information",
        valueMode: isPartial ? "partial"
            : (sourceKind === "unknown" ? "approximate"
            : (hasEstimated ? "estimated" : "plain")),
        sourceKind: sourceKind,
        hasEstimated: hasEstimated,
        hasUnpriced: hasUnpriced,
        hasUnmetered: hasUnmetered
    }
}

function costTrustNoticeKey(summary) {
    if (summary === null
            || typeof summary !== "object"
            || Array.isArray(summary)) {
        return ""
    }

    var sourceKind = hasOwnKey(summary, "sourceKind")
        ? acceptedCostSourceKind(summary.sourceKind)
        : ""
    var hasEstimated = hasOwnKey(summary, "hasEstimated")
        && summary.hasEstimated === true
    var hasUnpriced = hasOwnKey(summary, "hasUnpriced")
        && summary.hasUnpriced === true
    var hasUnmetered = hasOwnKey(summary, "hasUnmetered")
        && summary.hasUnmetered === true
    if (sourceKind.length === 0
            && !hasEstimated
            && !hasUnpriced
            && !hasUnmetered) {
        return ""
    }

    return [
        hasOwnKey(summary, "level") && summary.level === "warning"
            ? "warning" : "information",
        sourceKind,
        hasEstimated ? "estimated" : "exact",
        hasUnpriced ? "unpriced" : "priced",
        hasUnmetered ? "unmetered" : "metered"
    ].join("|")
}

// Keep dismissal state semantic rather than tying it to localized text or a
// freshly allocated summary object. Refreshes preserve a dismissal; a changed
// warning meaning becomes visible again, including a return to an older state.
function costTrustNoticeTransition(summary, previousState, shouldDismiss) {
    var key = costTrustNoticeKey(summary)
    var previousKey = ""
    var wasDismissed = false
    if (previousState !== null
            && typeof previousState === "object"
            && !Array.isArray(previousState)) {
        previousKey = hasOwnKey(previousState, "key")
                && typeof previousState.key === "string"
            ? previousState.key
            : ""
        wasDismissed = hasOwnKey(previousState, "dismissed")
            && previousState.dismissed === true
    }

    var dismissed = key.length > 0
        && key === previousKey
        && wasDismissed
    if (shouldDismiss === true && key.length > 0) {
        dismissed = true
    }
    return {
        key: key,
        dismissed: dismissed,
        shouldShow: key.length > 0 && !dismissed
    }
}

// The popup representation may be destroyed while the compact applet remains
// alive. Keep each surface's semantic notice state in the applet owner so a
// recreated notice does not forget that the user closed it.
function costTrustNoticeStoreTransition(summary, states, scope, shouldDismiss) {
    var safeScope = boundedText(scope, 120)
    if (safeScope.length === 0 || isUnsafeObjectKey(safeScope)) {
        safeScope = ""
    }
    var source = states !== null
            && typeof states === "object"
            && !Array.isArray(states)
        ? states
        : ({})
    var previousState = safeScope.length > 0 && hasOwnKey(source, safeScope)
        ? source[safeScope]
        : null
    var state = costTrustNoticeTransition(summary, previousState, shouldDismiss)
    var nextStates = ({})
    var copiedScopes = 0
    for (var existingScope in source) {
        if (!hasOwnKey(source, existingScope)
                || isUnsafeObjectKey(existingScope)
                || existingScope === safeScope
                || copiedScopes >= maximumCostTrustNoticeScopes - 1) {
            continue
        }
        nextStates[existingScope] = source[existingScope]
        copiedScopes += 1
    }
    var stateToStore = state
    if (state.key.length === 0
            && previousState !== null
            && typeof previousState === "object"
            && !Array.isArray(previousState)
            && hasOwnKey(previousState, "key")
            && typeof previousState.key === "string"
            && previousState.key.length > 0
            && hasOwnKey(previousState, "dismissed")
            && typeof previousState.dismissed === "boolean") {
        stateToStore = previousState
    }
    if (safeScope.length > 0 && stateToStore.key.length > 0) {
        nextStates[safeScope] = stateToStore
    }
    return { states: nextStates, state: state }
}

function spendDailyPoints(fmt, costs, showsTokens) {
    var items = costs || []
    var byDate = ({})
    var currency = spendCurrency(items)
    for (var i = 0; i < items.length; i++) {
        var daily = items[i].daily || []
        for (var j = 0; j < daily.length; j++) {
            var point = daily[j]
            var label = boundedText(point.label, 120)
            var pointCurrency = boundedText(point.currency || "USD", 12)
            // Mixed currencies cannot be summed as money, but token counts are
            // currency-free: filtering them would silently drop whole providers
            // from the chart.
            if (label.length === 0
                    || isUnsafeObjectKey(label)
                    || !hasMetricValue(point, showsTokens)
                    || (!showsTokens && pointCurrency !== currency)) {
                continue
            }
            if (!hasOwnKey(byDate, label)) {
                byDate[label] = { label: label, value: 0, currency: currency }
            }
            byDate[label].value += Math.max(0, metricValue(point, showsTokens))
        }
    }

    var result = []
    for (var day in byDate) {
        if (!hasOwnKey(byDate, day)) {
            continue
        }
        var item = byDate[day]
        item.displayValue = metricText(fmt, item.value, item.currency, showsTokens)
        result.push(item)
    }
    result.sort(function(a, b) { return a.label.localeCompare(b.label) })
    return result.slice(Math.max(0, result.length - maximumCostHistoryPoints))
}

// Money is summed only in the range currency. Tokens have no currency, so the
// total keeps every provider just like the token chart does.
function spendTotals(costs) {
    var items = costs || []
    if (items.length === 0) {
        return null
    }
    var currency = spendCurrency(items)
    var totalCost = 0
    var totalTokens = 0
    var hasCost = false
    for (var i = 0; i < items.length; i++) {
        var totals = items[i].totals || ({})
        totalTokens += Math.max(0, Number(totals.tokens) || 0)
        if (!costMatchesSpendCurrency(items[i], currency)
                || !hasMetricValue(totals, false)) {
            continue
        }
        totalCost += Math.max(0, totals.cost)
        hasCost = true
    }
    return {
        cost: hasCost ? totalCost : null,
        tokens: totalTokens,
        currency: currency,
        hasMixedCostCurrencies: spendHasMixedCostCurrencies(items)
    }
}

// The CLI reports whether its local log scan already covers the requested
// window; until it does, the earliest bars are short for a scan reason rather
// than a spend reason. A missing flag counts as established.
function historyStillBuilding(costs) {
    var items = costs || []
    for (var i = 0; i < items.length; i++) {
        if (items[i].historyCoverageEstablished === false) {
            return true
        }
    }
    return false
}
