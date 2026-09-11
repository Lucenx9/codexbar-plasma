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

    function test_pinnedCacheRestoreKeepsIdentityFreeQuota() {
        // encode() stores no identities, so a decoded entry always has an empty
        // key. For a provider pinned to an explicit account the cache context
        // already verified that scope, and an identified early failure must not
        // drop its quota. Automatic accounts are not pinned: the CLI may hand
        // them a different identity between sessions, so they keep the check.
        var cached = Cache.reconcile([], [{
            provider: "codex", account: "", accountKey: "",
            error: "", updatedAt: "", rows: [
                { lane: "primary", hasPercent: true, usedPercent: 72 }
            ]
        }], nowMs);
        var failure = {
            provider: "codex", account: "", accountKey: "Organization A",
            error: "Synthetic failure", updatedAt: "", rows: []
        };
        var pinned = Cache.restore(cached, [failure], nowMs + 60000,
            { codex: "Organization A" });
        compare(pinned.length, 1);
        compare(pinned[0].rows.length, 1);
        compare(pinned[0].rows[0].usedPercent, 72);
        compare(pinned[0].lastGoodAtMs, nowMs);
        verify(pinned[0].usageStale);
        compare(pinned[0].error, "Synthetic failure");
        // Another provider's pin never covers this one.
        compare(Cache.restore(cached, [failure], nowMs + 60000,
            { claude: "Organization A" })[0].rows.length, 0);
        compare(Cache.restore(cached, [failure], nowMs + 60000,
            { codex: "" })[0].rows.length, 0);
        compare(Cache.restore(cached, [failure], nowMs + 60000, ({}))[0].rows.length, 0);
        compare(Cache.restore(cached, [failure], nowMs + 60000)[0].rows.length, 0);
        // The live refresh path never receives a pin and keeps rejecting it.
        compare(Cache.reconcile(cached, [failure], nowMs + 60000)[0].rows.length, 0);
    }
}
