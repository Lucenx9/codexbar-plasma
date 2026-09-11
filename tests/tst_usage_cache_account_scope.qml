import QtQuick
import QtTest
import "../contents/ui/UsageCache.js" as Cache

TestCase {
    name: "UsageCacheAccountScope"

    readonly property double nowMs: Date.parse("2026-09-11T12:00:00Z")

    function test_failedRefreshRespectsAccountKeys_data() {
        return [
            { tag: "collapsed-account-label", oldKey: "Work  Team", newKey: "Work Team",
                oldAccount: "Work Team", newAccount: "Work Team", retain: false },
            { tag: "organization-only", oldKey: "Organization A", newKey: "Organization B",
                oldAccount: "", newAccount: "", retain: false },
            { tag: "same-key", oldKey: "Work  Team", newKey: "Work  Team",
                oldAccount: "Work Team", newAccount: "Work Team", retain: true },
            { tag: "unidentified-failure", oldKey: "Work  Team", newKey: "",
                oldAccount: "Work Team", newAccount: "", retain: true }
        ];
    }

    function test_failedRefreshRespectsAccountKeys(data) {
        // normalizeProvider keeps the validated key separately from the bounded
        // display label, which can collapse distinct account names to one text.
        var prior = {
            provider: "codex", account: data.oldAccount, accountKey: data.oldKey,
            error: "", updatedAt: "", rows: [
                { lane: "primary", hasPercent: true, usedPercent: 72 }
            ]
        };
        var previous = Cache.reconcile([], [prior], nowMs);
        var incoming = {
            provider: "codex", account: data.newAccount, accountKey: data.newKey,
            error: "Synthetic failure", updatedAt: "", rows: []
        };
        var result = Cache.reconcile(previous, [incoming], nowMs + 60000)[0];
        compare(result.rows.length, data.retain ? 1 : 0);
        compare(result.accountKey, data.retain ? data.oldKey : data.newKey);
        compare(result.usageStale, data.retain);
        compare(result.lastGoodAtMs, data.retain ? nowMs : 0);
        compare(result.error, "Synthetic failure");
        if (data.retain)
            compare(result.rows[0].usedPercent, 72);
        compare(previous[0].rows[0].usedPercent, 72);
        verify(!previous[0].usageStale);
        compare(incoming.rows.length, 0);
    }
}
