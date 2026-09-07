.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer

// CLI 0.56.2 supplies stage, percentages and a forecast beside its English
// summary. Return semantic parts so QML can localize without parsing prose.
function summaryParts(pace) {
    if (!Normalizer.isCliRecord(pace)) {
        return [];
    }
    var parts = [];
    var stage = Guards.hasOwnKey(pace, "stage") ? pace.stage : "";
    var delta = Guards.hasOwnKey(pace, "deltaPercent") ? Normalizer.strictFiniteNumber(pace.deltaPercent) : NaN;
    var expected = Guards.hasOwnKey(pace, "expectedUsedPercent") ? Normalizer.strictFiniteNumber(pace.expectedUsedPercent) : NaN;
    if (stage === "onTrack") {
        parts.push({
            kind: "onTrack"
        });
    } else if (isFinite(delta)) {
        var percent = Math.round(Math.min(100, Math.abs(delta)));
        switch (stage) {
        case "slightlyAhead":
        case "ahead":
        case "farAhead":
            parts.push({
                kind: "deficit",
                percent: percent
            });
            break;
        case "slightlyBehind":
        case "behind":
        case "farBehind":
            parts.push({
                kind: "reserve",
                percent: percent
            });
            break;
        }
    }
    if (isFinite(expected)) {
        parts.push({
            kind: "expected",
            percent: Math.round(Math.max(0, Math.min(100, expected)))
        });
    }
    if (Guards.hasOwnKey(pace, "willLastToReset")) {
        if (pace.willLastToReset === true) {
            parts.push({
                kind: "lasts"
            });
        } else if (pace.willLastToReset === false && Guards.hasOwnKey(pace, "etaSeconds")) {
            var seconds = Normalizer.strictFiniteNumber(pace.etaSeconds);
            if (isFinite(seconds) && seconds >= 0) {
                parts.push({
                    kind: "runsOut",
                    seconds: Math.min(Normalizer.maximumPaceEtaSeconds, seconds)
                });
            }
        }
    }
    // Older or future payloads may only have prose. Preserve that bounded
    // fallback instead of making their forecast disappear.
    if (parts.length === 0 && Guards.hasOwnKey(pace, "summary") && typeof pace.summary === "string") {
        var summary = Normalizer.boundedDisplayText(pace.summary, 500);
        if (summary.length > 0) {
            parts.push({
                kind: "fallback",
                text: summary
            });
        }
    }
    return parts;
}
