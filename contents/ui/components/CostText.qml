import QtQuick
import "../CostPresentation.js" as CostPresentation
import "../ProviderNormalizer.js" as Normalizer
import "../ProviderIdentity.js" as ProviderIdentity
import "../Guards.js" as Guards

// Localized text for normalized cost snapshots and legacy dashboard rows.
// The caller supplies regional number formatting and already selected costs.
QtObject {
    id: root

    property var numberFormat: ({})

    function presentTokenCosts(snapshots) {
        var presented = ({})
        var keys = Object.keys(snapshots)
        for (var i = 0; i < keys.length; i++) {
            var snapshot = snapshots[keys[i]]
            var item = Guards.copyObject(snapshot)
            var windowLabel = snapshot.historyLabel !== null ? snapshot.historyLabel
                : Normalizer.boundedDisplayText(costHistoryWindowLabel({ period: snapshot.period }, snapshot.labelDays), 120)
            var currency = snapshot.currency
            item.windowLabel = windowLabel
            item.title = i18n("Cost")
            item.sessionLine = costLine(i18n("Today"), snapshot.sessionCost,
                snapshot.sessionTokens, currency)
            item.monthLine = costLine(windowLabel, snapshot.totals.cost,
                snapshot.totals.tokens, currency, snapshot.valueMode)
            item.windowValueLine = costValueLine(snapshot.totals.cost,
                snapshot.totals.tokens, currency, snapshot.valueMode)
            item.hintLine = tokenCostHint(snapshot.provider)
            presented[keys[i]] = item
        }
        return presented
    }

    function costHistoryWindowLabel(item, requestedHistoryDays) {
        switch (CostPresentation.costPeriod(item ? item.period : "")) {
        case "month-to-date":
            return i18n("Month to date")
        case "all":
            return i18n("All history")
        }
        var rawDays = item && item.historyDays !== undefined && item.historyDays !== null
            ? Normalizer.strictFiniteNumber(item.historyDays)
            : NaN
        if (!isFinite(rawDays) || rawDays <= 0) {
            rawDays = Normalizer.strictFiniteNumber(requestedHistoryDays)
        }
        if (!isFinite(rawDays) || rawDays <= 0) {
            return i18n("Last 30 days")
        }
        var days = Math.max(1, Math.floor(rawDays))
        return days === 1 ? i18n("Today") : i18np("Last %1 day", "Last %1 days", days)
    }

    function spendTotalLine(costs) {
        var totals = CostPresentation.spendTotals(costs)
        if (!totals) {
            return ""
        }
        var numericCost = Normalizer.strictFiniteNumber(totals.cost)
        var hasTokens = CostPresentation.hasMetricValue(totals, true)
        if (!isFinite(numericCost)) {
            return hasTokens ? usageCountText(totals.tokens, "tokens")
                : i18n("Tokens unavailable")
        }
        var trustSummary = CostPresentation.costTrustSummary(costs)
        var costValue = qualifiedCostValue(
            CostPresentation.amountString(root.numberFormat, numericCost, totals.currency),
            trustSummary ? trustSummary.valueMode : "plain")
        if (!hasTokens) {
            return totals.hasMixedCostCurrencies ? i18n("%1 subtotal", costValue) : i18n("%1 total", costValue)
        }
        var totalText = totals.hasMixedCostCurrencies
            ? i18n("%1 subtotal", costValue) : i18n("%1 total", costValue)
        return [totalText, usageCountText(totals.tokens, "tokens")].join(" \u00b7 ")
    }

    function dashboardLabelText(labelKey) {
        var labels = {
            codexDashboard: i18n("Codex dashboard"),
            openaiApi: i18n("OpenAI API"),
            openRouter: i18n("OpenRouter"),
            claudeAdmin: i18n("Claude Admin"),
            poe: i18n("Poe"),
            deepseek: i18n("DeepSeek"),
            minimax: i18n("MiniMax"),
            zai: i18n("Z.ai"),
            codeReviewRemaining: i18n("Code review remaining"),
            creditsRemaining: i18n("Credits remaining"),
            plan: i18n("Plan"),
            signedIn: i18n("Signed in"),
            today: i18n("Today"),
            last7Days: i18n("7d"),
            last30Days: i18n("30d"),
            currentMonth: i18n("This month"),
            topModel: i18n("Top model"),
            usageMix: i18n("Usage mix"),
            latest: i18n("Latest"),
            latestDashboardDay: i18n("Latest dashboard day")
        }
        return labels[labelKey] || ""
    }

    function dashboardPartText(part) {
        switch (part.kind) {
        case "text":
            return part.value
        case "percent":
            return i18n("%1%", Math.round(part.value))
        case "currency":
            return amountString(part.value, part.currency)
        case "tokens":
        case "requests":
        case "points":
            return usageCountText(part.value, part.kind)
        default:
            return tokenCountString(part.value)
        }
    }

    function dashboardDisplayRow(row) {
        var parts = row.parts.map(root.dashboardPartText)
        if (row.name.length > 0) {
            parts = [parts.length > 0 ? i18n("%1 (%2)", row.name, parts[0]) : row.name]
        }
        return {
            label: row.labelKey.length > 0 ? dashboardLabelText(row.labelKey) : row.label,
            value: Normalizer.boundedDisplayText(parts.join(" · "), 500)
        }
    }

    function qualifiedCostValue(value, valueMode) {
        switch (valueMode) {
        case "estimated":
            return i18n("%1 (estimated)", value)
        case "partial":
            return i18n("%1 (partial)", value)
        case "approximate":
            return i18n("%1 (approximate)", value)
        default:
            return value
        }
    }

    function costValueLine(cost, tokens, currency, valueMode) {
        var numericCost = Normalizer.strictFiniteNumber(cost)
        var numericTokens = Normalizer.strictFiniteNumber(tokens)
        var hasCost = isFinite(numericCost)
        var costValue = hasCost ? amountString(numericCost, currency) : "-"
        if (hasCost) {
            costValue = qualifiedCostValue(costValue, valueMode)
        }
        if (isFinite(numericTokens)) {
            return [costValue, usageCountText(numericTokens, "tokens")].join(" \u00b7 ")
        }
        return costValue
    }

    function costLine(label, cost, tokens, currency, valueMode) {
        var numericCost = Normalizer.strictFiniteNumber(cost)
        var numericTokens = Normalizer.strictFiniteNumber(tokens)
        var hasCost = isFinite(numericCost)
        var costValue = hasCost ? amountString(numericCost, currency) : "-"
        if (hasCost) {
            costValue = qualifiedCostValue(costValue, valueMode)
        }
        if (isFinite(numericTokens)) {
            return i18n("%1: %2", label,
                [costValue, usageCountText(numericTokens, "tokens")].join(" \u00b7 "))
        }
        return i18n("%1: %2", label, costValue)
    }

    function usageCountText(value, unit) {
        var text = CostPresentation.tokenCountString(value, root.numberFormat)
        var count = Number(text)
        // Compact counts such as 1K keep their own translation. Only the small
        // displayed integers go through KI18n's integer plural argument.
        var exact = isFinite(count)
        switch (unit) {
        case "tokens":
            return exact ? i18np("%1 token", "%1 tokens", count) : i18n("%1 tokens", text)
        case "requests":
            return exact ? i18np("%1 request", "%1 requests", count) : i18n("%1 requests", text)
        case "points":
            return exact ? i18np("%1 point", "%1 points", count) : i18n("%1 points", text)
        default:
            return text
        }
    }

    function tokenCostHint(providerID) {
        switch (ProviderIdentity.resolveProviderKey(providerID)) {
        case "antigravity":
            return i18n("Local Antigravity history includes token totals. Dollar costs are unavailable.")
        case "codex":
            return i18n("Estimated from local Codex logs for the selected account.")
        case "claude":
            return i18n("Estimated from local Claude logs.")
        default:
            return ""
        }
    }

    function amountString(value, currency) {
        return CostPresentation.amountString(root.numberFormat, value, currency)
    }

    function tokenCountString(tokens) {
        return CostPresentation.tokenCountString(tokens, root.numberFormat)
    }
}
