.pragma library
.import "ProviderNormalizer.js" as Normalizer

// Semantic sections for the existing provider-cost contract. QML supplies all
// translated labels and formats amounts; a balance never borrows a quota limit.
function section(providerID, cost) {
    var key = Normalizer.normalizedProviderID(providerID)
    if (key.length === 0 || key === "manus" || key === "synthetic" || !Normalizer.isCliRecord(cost)) {
        return null
    }
    var used = Normalizer.strictFiniteNumber(cost.used)
    if (!isFinite(used)) {
        return null
    }
    var limit = Normalizer.strictFiniteNumber(cost.limit)
    var personalUsed = Normalizer.strictFiniteNumber(cost.personalUsed)
    var currency = Normalizer.boundedDisplayText(cost.currencyCode || "USD", 12)
    var period = cost.period === null || cost.period === undefined ? null
        : Normalizer.boundedDisplayText(cost.period, 120)
    var kind = "spend"
    var titleKey = "extraUsage"

    // Preserve the established CLI compatibility cases before considering a
    // limit. These records describe balances even when a limit is present.
    if (key === "factory" && period === "Extra usage balance") {
        kind = "balance"
    } else if (key === "opencodego" && period === "Zen balance") {
        kind = "balance"
        titleKey = "zenBalance"
    } else if (key === "minimax" && period === "MiniMax points balance") {
        kind = "pointsBalance"
        titleKey = "credits"
    } else if (isFinite(limit) && limit > 0) {
        kind = "allowance"
        titleKey = currency === "Quota" ? "quotaUsage" : "extraUsage"
    } else if (key === "litellm") {
        return null
    } else if (key === "openai" || key === "claude") {
        titleKey = "apiSpend"
    }

    return {
        kind: kind,
        titleKey: titleKey,
        used: used,
        currency: currency,
        period: period,
        limit: kind === "allowance" ? limit : null,
        percentUsed: kind === "allowance" ? Normalizer.clamp((used / limit) * 100, 0, 100) : -1,
        personalUsed: kind === "allowance" && isFinite(personalUsed) && personalUsed > 0 ? personalUsed : null
    }
}

function resetCount(providerID, resetCredits) {
    if (Normalizer.normalizedProviderID(providerID) !== "codex" || !Normalizer.isCliRecord(resetCredits)) {
        return null
    }
    var count = Normalizer.strictFiniteNumber(resetCredits.availableCount)
    return isFinite(count) && count > 0 ? Math.round(count) : null
}
