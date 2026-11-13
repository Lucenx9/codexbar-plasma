.pragma library
.import "ProviderNormalizer.mjs" as Normalizer
.import "Guards.js" as Guards
.import "SubscriptionDates.mjs" as SubscriptionDates

function monthlyWindow(row) {
    if (!Normalizer.canPresentQuotaDetails(row) || row.hasPercent !== true) return false;
    var minutes = Normalizer.rateWindowMinutes(row.windowMinutes);
    return minutes >= 28 * 1440 && minutes <= 31 * 1440;
}

function measuredRemainder(row) {
    var used = row.usedPercent;
    if (!Guards.isFiniteNumber(used)) return null;
    return used >= 0 && used <= 100 ? 100 - used : null;
}

function resetTimestamp(row) {
    var reset = SubscriptionDates.date(row.resetsAt, false, "reset");
    return reset ? reset.timestampMs : NaN;
}

// An even division of the measured remainder, never a consumption forecast.
// Calendar dates count local days without assuming every day lasts 24 hours.
function dailyPercent(row, nowMs) {
    if (!monthlyWindow(row) || !Guards.isFiniteNumber(nowMs)) {
        return null;
    }
    if (Math.abs(nowMs) > 8640000000000000 || measuredRemainder(row) === null) return null;
    var resetMs = resetTimestamp(row);
    if (!isFinite(resetMs)) return null;
    if (resetMs <= nowMs) return null;
    if (resetMs - nowMs > (row.windowMinutes + 1440) * 60000) {
        return null;
    }
    var now = new Date(nowMs);
    var reset = new Date(resetMs);
    var today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    var resetDay = Date.UTC(reset.getFullYear(), reset.getMonth(), reset.getDate());
    var days = Math.max(1, Math.round((resetDay - today) / 86400000));
    return {percent: measuredRemainder(row) / days, days: days};
}
