import QtQuick
import QtTest
import "../contents/ui/UsageCache.js" as Cache
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/PanelDisplay.js" as PanelDisplay
import "../contents/ui/ProviderSnapshot.js" as Snapshot
import "../contents/ui/UsageState.js" as State
import "../contents/ui/PrivacyPresentation.js" as Privacy
import "../contents/ui/components" as Components

TestCase {
    name: "UsageCachePace"

    readonly property double nowMs: Date.parse("2026-09-11T12:00:00Z")

    function i18n(text, value) { return text.replace("%1", value); }
    function i18np(one, many, value) { return i18n(value === 1 ? one : many, value); }

    Components.UsageWindowText { id: windowText }

    function test_privacyCannotRestoreStaleForecasts_data() {
        return [
            {tag: "failed-refresh", failed: true, age: 60000, stale: true},
            {tag: "expired-measurement", failed: false, age: Cache.maximumAgeMs + 1, stale: true},
            {tag: "fresh-control", failed: false, age: 60000, stale: false}
        ];
    }

    function test_privacyCannotRestoreStaleForecasts(data) {
        var snapshot = Snapshot.normalize({provider: "codex", usage: {
            updatedAt: new Date(nowMs - data.age).toISOString(),
            dataConfidence: "exact", primary: {usedPercent: 72}
        }, pace: {primary: {stage: "behind", deltaPercent: -20,
            expectedUsedPercent: 40, willLastToReset: false, etaSeconds: 3600}}}, nowMs);
        snapshot.rows[0].pace = windowText.paceSummaryPartsText(snapshot.rows[0].paceParts);
        verify(snapshot.rows[0].pace.length > 0);
        var original = JSON.stringify(snapshot);
        var state = State.accepted([], [snapshot], "", nowMs);
        if (data.failed) {
            state = State.failed(state.providers, [Snapshot.normalize({provider: "codex",
                error: {message: "offline"}}, nowMs)], "", nowMs);
        }
        var retained = state.providers[0];
        var presented = Privacy.provider(retained, true, {rowLabels: ["Session"]});
        // main.qml rebuilds localized pace from these parts in privacy mode.
        var pace = windowText.paceSummaryPartsText(presented.rows[0].paceParts);
        compare(retained.usageStale, data.stale);
        compare(pace.length === 0, data.stale);
        compare(PanelDisplay.rowForMode(presented.rows, "runOut", "auto") === null, data.stale);
        compare(JSON.stringify(snapshot), original);
    }

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
