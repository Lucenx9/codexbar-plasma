import QtQuick
import QtTest
import "../contents/ui/UsageCache.js" as Cache
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/PanelDisplay.js" as PanelDisplay

TestCase {
    name: "UsageCachePace"

    readonly property double nowMs: Date.parse("2026-09-11T12:00:00Z")

    function test_successfulMeasurementForecastsRespectFreshness_data() {
        return [
            { tag: "expired-primary", age: Cache.maximumAgeMs + 1, lane: "primary", used: 72, stale: true },
            { tag: "expired-secondary", age: Cache.maximumAgeMs + 1, lane: "secondary", used: 72, stale: true },
            { tag: "expired-zero", age: 2 * Cache.maximumAgeMs, lane: "primary", used: 0, stale: true },
            { tag: "exact-retention-boundary", age: Cache.maximumAgeMs, lane: "primary", used: 72, stale: false },
            { tag: "fresh", age: 60000, lane: "primary", used: 72, stale: false }
        ];
    }

    function test_successfulMeasurementForecastsRespectFreshness(data) {
        // Same public normalization and row shape as main.qml's addWindow.
        var row = Object.assign({ lane: data.lane, label: "Synthetic quota", pace: "Synthetic forecast" },
            Normalizer.rateWindowMetrics({ usedPercent: data.used }, {
                willLastToReset: false, expectedUsedPercent: 40, etaSeconds: 3600
            }, true));
        var incoming = {
            provider: "codex",
            account: "synthetic@example.test",
            error: "",
            updatedAt: new Date(nowMs - data.age).toISOString(),
            rows: [row],
            primaryRow: data.lane === "primary" ? row : null,
            statusKnown: true,
            status: "Synthetic current incident",
            statusSeverity: "major",
            statusIncidentKey: "synthetic-incident",
            hasIncident: true
        };
        var original = JSON.stringify(incoming);
        var result = Cache.reconcile([], [incoming], nowMs)[0];

        compare(result.usageStale, data.stale);
        compare(result.lastGoodAtMs, nowMs - data.age);
        compare(result.rows[0].usedPercent, data.used);
        compare(result.status, incoming.status);
        compare(result.statusKnown, true);
        compare(result.hasIncident, true);
        // These are the public panel selectors used by pace/run-out text.
        compare(PanelDisplay.rowForMode(result.rows, "runOut", "auto"), data.stale ? null : result.rows[0]);
        compare(PanelDisplay.rowForMode(result.rows, "pace", "auto"), data.stale ? null : result.rows[0]);
        compare(result.rows[0].paceKnown, !data.stale);
        compare(result.rows[0].paceEtaSeconds, data.stale ? 0 : 3600);
        compare(result.rows[0].pacePercent, data.stale ? -1 : 40);
        compare(result.rows[0].pace, data.stale ? "" : "Synthetic forecast");
        compare(result.primaryRow, data.lane === "primary" ? result.rows[0] : null);
        compare(JSON.stringify(incoming), original);
    }
}
