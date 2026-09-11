import QtQuick
import QtTest
import "../contents/ui/UsageCache.js" as Cache

TestCase {
    name: "UsageCacheRestore"

    function snapshot(percent, account, updatedAt) {
        var row = { lane: "primary", hasPercent: true, usedPercent: percent,
            leftPercent: 100 - percent, paceKnown: false };
        return { provider: "claude", account: account, rows: [row], primaryRow: row,
            error: "", updatedAt: updatedAt };
    }

    function test_delayedRestorePreservesRetainedLiveMeasurement_data() {
        return [
            { tag: "without-account", account: "" },
            { tag: "with-account", account: "work@example.test" }
        ];
    }

    function test_delayedRestorePreservesRetainedLiveMeasurement(data) {
        var nowMs = Date.parse("2026-09-11T12:00:00Z");
        // Disk restoration contains no account identity. Its fingerprint is
        // verified only after an early live success and a failed retry.
        var cached = Cache.reconcile([], [snapshot(20, "", "2026-09-11T11:00:00Z")], nowMs);
        cached[0].usageStale = true;
        var live = Cache.reconcile([], [snapshot(80, data.account, "2026-09-11T11:55:00Z")], nowMs);
        var failure = { provider: "claude", account: "", rows: [], primaryRow: null,
            error: "Synthetic failure", updatedAt: "", statusKnown: true,
            status: "New outage", statusSeverity: "major", statusIncidentKey: "incident-2",
            hasIncident: true, statusUrl: "https://status.claude.com/" };
        var retained = Cache.reconcile(live, [failure], nowMs + 1000);
        compare(retained[0].rows[0].usedPercent, 80);
        verify(retained[0].usageStale);
        var before = JSON.stringify(retained);

        var restored = Cache.restore(cached, retained, nowMs + 2000);
        compare(restored.length, 1);
        compare(restored[0].rows[0].usedPercent, 80);
        compare(restored[0].lastGoodAtMs, Date.parse("2026-09-11T11:55:00Z"));
        verify(restored[0].usageStale);
        compare(restored[0].error, failure.error);
        verify(restored[0].statusKnown && restored[0].hasIncident);
        compare(restored[0].statusIncidentKey, failure.statusIncidentKey);
        compare(JSON.stringify(retained), before);
        compare(cached[0].rows[0].usedPercent, 20);
    }
}
