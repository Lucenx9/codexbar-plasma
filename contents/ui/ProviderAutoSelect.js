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


// The first provider wins a tie, so a roster whose order the user chose keeps
// its head selected while nothing stands out. An empty or unusable roster
// answers 0: callers index a roster they have already checked is non-empty.
// A roster where every provider failed answers 0 as well. There is no
// no-selection state to fall back to: the popup and the panel must show a
// provider, and the first one at least surfaces its error instead of leaving
// the surfaces blank.
function bestIndex(items) {
    var source = Array.isArray(items) ? items : [];
    var bestPercent = -1;
    var bestSeverity = -1;
    var best = 0;
    for (var i = 0; i < source.length; i++) {
        var item = source[i];
        if (!item || OverviewProviders.isErrorOnly(item)) {
            continue;
        }
        // Missing percentages and idle quotas tie on consumption; incidents
        // distinguish them without outweighing even fractional positive usage.
        var percent = Math.max(0, usedPercent(item));
        var severity = NotificationMemo.severityRank(item.statusSeverity);
        if (percent > bestPercent || (percent === bestPercent && severity > bestSeverity)) {
            bestPercent = percent;
            bestSeverity = severity;
            best = i;
        }
    }
    return best;
}
