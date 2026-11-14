import * as Guards from "./Guards.mjs";
import * as CostAmounts from "./CostAmounts.mjs";
import * as CostCurrency from "./CostCurrency.mjs";

// Semantic pricing confidence and bounded notice-dismissal transitions.
// QML owns localization and commits the returned notice state.

export var maximumCostTrustNoticeScopes = 128
export var maximumIncompleteRequests = 1000000000

export function acceptedCostCoverage(value) {
    if (!Guards.isRecord(value)) return null
    var fields = ["priced", "unpriced", "unmetered", "estimated"]
    for (var i = 0; i < fields.length; i++) {
        if (!validCoverageCount(value, fields[i])) return null
    }
    return value
}

// Excluded requests are counted, never summed into an amount. Keep the total
// bounded so a saturated upstream count cannot overflow the joined notice.
// Accepts a trust record, a daily point, or a model aggregate alike.
export function acceptedIncompleteRequests(trust) {
    if (!Guards.isRecord(trust)) return 0
    if (!Guards.hasOwnKey(trust, "incompleteRequests")) return 0
    var count = trust.incompleteRequests
    if (!Guards.isNonNegativeInteger(count)) return 0
    return Math.min(count, maximumIncompleteRequests)
}

export function boundedIncompleteRequests(count) {
    return Math.min(Math.max(0, count), maximumIncompleteRequests)
}

export function acceptedCostSourceKind(value) {
    return ["listPrice", "vendor", "mixed", "unknown"].indexOf(value) !== -1 ? value : ""
}

// Provenance without observed cost, token, daily, or coverage data cannot
// qualify a displayed total. Missing token totals normalize to zero, so only a
// positive token count is evidence; explicit finite cost values matter at zero.
export function costTrustSnapshotHasEvidence(item) {
    if (!item) return false
    if (hasObservedAmount(item.totals)) return true
    var coverage = trustCoverage(item.trust)
    if (coverageHasActivity(coverage)) return true
    var daily = CostAmounts.snapshotDaily(item)
    return daily.some(hasObservedAmount)
}

// Fold normalized pricing coverage and provenance into one presentation
// decision. The caller localizes it; wire enum values never cross this seam.
// For global spend, currency eligibility deliberately matches `spendTotals()`.
// Token-only snapshots still qualify a mixed total, but cannot create a notice
// when there is no finite cost to qualify.
export function costTrustSummary(costs) {
    var items = Array.isArray(costs) ? costs : []
    var currency = CostCurrency.spendCurrency(items)
    var state = {
        sources: { listPrice: false, vendor: false, mixed: false, unknown: false, unclassified: false },
        hasEstimated: false, hasUnpriced: false, hasUnmetered: false,
        hasDisplayedCost: false, hasDisplayedTokens: false, incompleteRequests: 0
    }
    for (var i = 0; i < items.length; i++) {
        if (!costTrustSnapshotHasEvidence(items[i])) continue
        if (CostAmounts.hasMetricValue(items[i].totals, false)
                && !CostCurrency.costMatchesSpendCurrency(items[i], currency)) continue
        accumulateTrust(state, items[i])
    }
    return summarizeTrust(state)
}

// Tokens include every currency. Their exclusions must not inherit the
// monetary summary's selected-currency filter or provenance qualifications.
export function incompleteTokenRequests(costs) {
    var items = Array.isArray(costs) ? costs : []
    var count = 0
    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        if (!hasPositiveTokens(CostAmounts.snapshotTotals(item))) continue
        var trust = Guards.hasOwnKey(item, "trust") ? item.trust : null
        count = boundedIncompleteRequests(count + acceptedIncompleteRequests(trust))
    }
    return count
}

// Today amounts do not carry daily trust metadata. Match the scan's local day
// while respecting the same stale-day policy as the displayed token amount.
export function todayIncompleteTokenRequests(snapshot, nowMs) {
    if (!hasPositiveTokens(CostAmounts.todayAmounts(snapshot, nowMs))) return 0
    var scanDay = ownText(snapshot, "scanDay")
    if (scanDay.length === 0) return 0
    var matches = CostAmounts.snapshotDaily(snapshot).filter(function(day) {
        return Guards.isRecord(day) && ownText(day, "label") === scanDay
    })
    return matches.length === 1 ? acceptedIncompleteRequests(matches[0]) : 0
}

export function costTrustNoticeKey(summary) {
    if (!Guards.isRecord(summary)) return ""
    var sourceKind = acceptedCostSourceKind(ownText(summary, "sourceKind"))
    var flags = [ownFlag(summary, "hasEstimated"), ownFlag(summary, "hasUnpriced"),
        ownFlag(summary, "hasUnmetered"), acceptedIncompleteRequests(summary) > 0]
    if (sourceKind.length === 0 && !flags.some(Boolean)) return ""
    var parts = [ownText(summary, "level") === "warning" ? "warning" : "information", sourceKind]
    var positive = ["estimated", "unpriced", "unmetered", "incomplete"]
    var negative = ["exact", "priced", "metered", "complete"]
    for (var i = 0; i < flags.length; i++) {
        parts.push(flags[i] ? positive[i] : negative[i])
    }
    return parts.join("|")
}

// Keep dismissal state semantic rather than tying it to localized text or a
// freshly allocated summary object. Refreshes preserve a dismissal; a changed
// warning meaning becomes visible again, including a return to an older state.
export function costTrustNoticeTransition(summary, previousState, shouldDismiss) {
    var key = costTrustNoticeKey(summary)
    if (key.length === 0) return { key: "", dismissed: false, shouldShow: false }
    var previous = Guards.isRecord(previousState) ? previousState : ({})
    var dismissed = shouldDismiss === true
        || (key === ownText(previous, "key") && ownFlag(previous, "dismissed"))
    return { key: key, dismissed: dismissed, shouldShow: !dismissed }
}

// The popup representation may be destroyed while the compact applet remains
// alive. Keep each surface's semantic notice state in the applet owner so a
// recreated notice does not forget that the user closed it.
export function costTrustNoticeStoreTransition(summary, states, scope, shouldDismiss) {
    var safeScope = CostAmounts.boundedText(scope, 120)
    if (Guards.isUnsafeObjectKey(safeScope)) safeScope = ""
    var source = Guards.isRecord(states) ? states : ({})
    var previousState = noticeStateForScope(source, safeScope)
    var state = costTrustNoticeTransition(summary, previousState, shouldDismiss)
    var nextStates = copyOtherNoticeScopes(source, safeScope)
    var stateToStore = state
    if (state.key.length === 0 && reusableNoticeState(previousState)) {
        stateToStore = previousState
    }
    if (safeScope.length > 0 && stateToStore.key.length > 0) {
        nextStates[safeScope] = stateToStore
    }
    return { states: nextStates, state: state }
}

export function validCoverageCount(coverage, field) {
    if (!Guards.hasOwnKey(coverage, field)) return false
    var count = coverage[field]
    return Guards.isNonNegativeInteger(count)
}

export function ownText(item, field) {
    if (!Guards.hasOwnKey(item, field)) return ""
    return typeof item[field] === "string" ? item[field] : ""
}

export function ownFlag(item, field) {
    return Guards.hasOwnKey(item, field) && item[field] === true
}

export function trustCoverage(trust) {
    if (!Guards.isRecord(trust)) return null
    return Guards.hasOwnKey(trust, "coverage") ? acceptedCostCoverage(trust.coverage) : null
}

export function coverageHasActivity(coverage) {
    if (!coverage) return false
    return [coverage.priced, coverage.unpriced, coverage.unmetered, coverage.estimated]
        .some(function(count) { return count > 0 })
}

export function hasPositiveTokens(amounts) {
    return CostAmounts.hasMetricValue(amounts, true) && amounts.tokens > 0
}

export function hasObservedAmount(amounts) {
    return CostAmounts.hasMetricValue(amounts, false) || hasPositiveTokens(amounts)
}

export function accumulateTrust(state, item) {
    state.hasDisplayedCost = state.hasDisplayedCost || CostAmounts.hasMetricValue(item.totals, false)
    state.hasDisplayedTokens = state.hasDisplayedTokens || hasPositiveTokens(item.totals)
    var trust = Guards.hasOwnKey(item, "trust") ? item.trust : null
    if (!Guards.isRecord(trust)) {
        state.sources.unclassified = true
        return
    }
    var coverage = trustCoverage(trust)
    accumulateCoverage(state, coverage)
    state.incompleteRequests = boundedIncompleteRequests(
        state.incompleteRequests + acceptedIncompleteRequests(trust))
    var sourceKind = acceptedCostSourceKind(ownText(trust, "sourceKind"))
    state.sources[sourceKind || "unclassified"] = true
}

export function summarySource(sources) {
    if (sources.unknown) return "unknown"
    var known = ["listPrice", "vendor", "mixed"].filter(function(kind) { return sources[kind] })
    if (known.length === 0) return ""
    if (sources.unclassified) return "unknown"
    return known.length > 1 ? "mixed" : known[0]
}

export function trustValueMode(partial, sourceKind, estimated) {
    if (partial) return "partial"
    if (sourceKind === "unknown") return "approximate"
    return estimated ? "estimated" : "plain"
}

export function summarizeTrust(state) {
    var sourceKind = summarySource(state.sources)
    var estimated = state.hasEstimated || state.sources.listPrice || state.sources.mixed
    var incomplete = qualifiedIncompleteRequests(state)
    var partial = state.hasUnpriced || state.hasUnmetered || incomplete > 0
    var mode = trustValueMode(partial, sourceKind, estimated)
    if (!shouldQualifyAmount(state.hasDisplayedCost, incomplete, mode, sourceKind)) return null
    return {
        level: partial || sourceKind === "unknown" ? "warning" : "information",
        valueMode: mode, sourceKind: sourceKind,
        hasEstimated: estimated, hasUnpriced: state.hasUnpriced, hasUnmetered: state.hasUnmetered,
        incompleteRequests: incomplete
    }
}

export function accumulateCoverage(state, coverage) {
    if (!coverage) return
    state.hasEstimated = state.hasEstimated || coverage.estimated > 0
    state.hasUnpriced = state.hasUnpriced || coverage.unpriced > 0
    state.hasUnmetered = state.hasUnmetered || coverage.unmetered > 0
}

export function qualifiedIncompleteRequests(state) {
    return state.hasDisplayedCost || state.hasDisplayedTokens ? state.incompleteRequests : 0
}

export function shouldQualifyAmount(hasCost, incomplete, mode, sourceKind) {
    if (!hasCost && incomplete === 0) return false
    return mode !== "plain" || sourceKind.length > 0
}

export function reusableNoticeState(state) {
    if (!Guards.isRecord(state)) return false
    if (ownText(state, "key").length === 0) return false
    return Guards.hasOwnKey(state, "dismissed") && typeof state.dismissed === "boolean"
}

export function copyOtherNoticeScopes(source, scope) {
    var result = ({})
    var count = 0
    for (var key in source) {
        if (!Guards.hasOwnKey(source, key)) continue
        if (Guards.isUnsafeObjectKey(key) || key === scope) continue
        result[key] = source[key]
        count++
        if (count >= maximumCostTrustNoticeScopes - 1) break
    }
    return result
}

export function noticeStateForScope(source, scope) {
    if (scope.length === 0) return null
    return Guards.hasOwnKey(source, scope) ? source[scope] : null
}
