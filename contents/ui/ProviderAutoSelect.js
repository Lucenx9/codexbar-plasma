.pragma library
.import "NotificationMemo.js" as NotificationMemo
.import "OverviewProviders.js" as OverviewProviders
.import "ProviderNormalizer.js" as Normalizer

// The automatic provider selection: the one a user opening the popup most
// likely came for. Consumption decides it; incident severity only ranks
// providers that consumption cannot separate.

// The busiest quota row, or the provider cost meter when it reports further
// along. Rows without a percentage contribute nothing, and out-of-range CLI
// values are clamped instead of discarding the provider.
function usedPercent(item) {
    if (!item) {
        return -1;
    }

    var best = -1;
    var rows = item.rows || [];
    for (var i = 0; i < rows.length; i++) {
        if (rows[i] && rows[i].hasPercent) {
            var used = Number(rows[i].usedPercent);
            if (isFinite(used)) {
                best = Math.max(best, Normalizer.clamp(used, 0, 100));
            }
        }
    }
    if (item.providerCost && item.providerCost.percentUsed >= 0) {
        var providerCostUsed = Number(item.providerCost.percentUsed);
        if (isFinite(providerCostUsed)) {
            best = Math.max(best, Normalizer.clamp(providerCostUsed, 0, 100));
        }
    }
    return best;
}

// Severity contributes at most a single percentage point, so it breaks ties
// between equally used providers without ever outranking real consumption. A
// provider with no percentage at all is ordered by severity alone, and one
// carrying only an error never wins.
function score(item) {
    if (!item || OverviewProviders.isErrorOnly(item)) {
        return -1;
    }
    var percent = usedPercent(item);
    var incidentTieBreaker = NotificationMemo.severityRank(item.statusSeverity) / 100;
    return percent >= 0 ? percent + incidentTieBreaker : incidentTieBreaker;
}

// The first provider wins a tie, so a roster whose order the user chose keeps
// its head selected while nothing stands out. An empty or unusable roster
// answers 0: callers index a roster they have already checked is non-empty.
function bestIndex(items) {
    var source = Array.isArray(items) ? items : [];
    var bestScore = -1;
    var best = 0;
    for (var i = 0; i < source.length; i++) {
        var candidate = score(source[i]);
        if (candidate > bestScore) {
            bestScore = candidate;
            best = i;
        }
    }
    return best;
}
