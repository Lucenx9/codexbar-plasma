.pragma library
.import "ProviderNormalizer.mjs" as Normalizer

// Grok uses neutral spend for its wallet and Neuralwatt mirrors the remaining
// balance in used. Other providers can report spend alongside a balance.
function isWalletRecord(key, cost, used, limit) {
    if (limit > 0) return false
    if (key === "grok") return used === 0 && (limit === 0 || Normalizer.hasOwnKey(cost, "balance"))
    return key === "neuralwatt" && Normalizer.hasOwnKey(cost, "balance")
}

function isUsdAmount(cost, amount) {
    return cost.currencyCode === "USD" && Number.isFinite(amount) && amount >= 0
}

function unbudgetedSpendTitle(key, cost, used, limit) {
    if (key === "litellm") {
        // The released key/user spend report explicitly uses a zero budget.
        return limit === 0 && isUsdAmount(cost, used) ? "apiSpend" : null
    }
    // A Codex account without a credit cap emits an empty placeholder.
    if (key === "codex" && cost.currencyCode === "Credits" && used === 0) return null
    return ["openai", "claude"].indexOf(key) >= 0 ? "apiSpend" : "extraUsage"
}

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
    if (isWalletRecord(key, cost, used, limit)) {
        var balance = Normalizer.ownField(cost, "balance")
        if ((cost.limit != null && limit !== 0) || !isUsdAmount(cost, balance)) return null
        kind = "balance"
        titleKey = "credits"
        used = balance
    } else if (key === "factory" && period === "Extra usage balance") {
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
    } else {
        titleKey = unbudgetedSpendTitle(key, cost, used, limit)
        if (titleKey === null) return null
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

// The panel accepts monetary allowances only, with the same balance exceptions
// as the popup. Credits and quota counts keep their existing presentations.
function panelBudget(providerID, cost) {
    if (!Normalizer.isCliRecord(cost)) return null
    if (typeof cost.currencyCode !== "string") return null
    if (!/^[A-Z]{3}$/.test(cost.currencyCode)) return null
    var value = section(providerID, cost)
    return value && value.kind === "allowance" && value.used >= 0 ? value : null
}
