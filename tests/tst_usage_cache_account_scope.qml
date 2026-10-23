import QtQuick
import QtTest
import "../contents/ui/Guards.js" as Guards
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

    function test_accountOverridesStayOutOfDiskCacheInBothDirections() {
        // encode() stores no identities and the cache context no longer covers
        // the memory-only selection, so an overridden provider is neither saved
        // nor restored, while its siblings keep both directions.
        var context = Qt.md5("account-scope")
        var items = Cache.reconcile([], ["codex", "claude"].map(function(id, index) {
            return { provider: id, account: "", accountKey: "", error: "", updatedAt: "",
                rows: [{ lane: "primary", hasPercent: true, usedPercent: 70 + index }] }
        }), nowMs)
        function saved(accounts) {
            return Cache.decode(Cache.encode(items, context, nowMs, accounts), context, nowMs)
                .map(function(entry) { return entry.provider }).join(",")
        }
        compare(saved(), "codex,claude")
        compare(saved({ codex: "Organization A" }), "claude")
        compare(saved({ codex: "" }), "codex,claude")
        compare(saved({ codex: 7 }), "codex,claude")
        compare(saved(JSON.parse('{"__proto__": {"codex": "A"}}')), "codex,claude")
        compare(Cache.encode(items, context, nowMs, { codex: "A", claude: "B" }), "")

        // An identity-free cached default quota must not cover an identified
        // or unidentified failure of the selected account, even when restored late.
        var failure = { provider: "codex", account: "", accountKey: "Organization A",
            error: "Synthetic failure", updatedAt: "", rows: [] }
        var anonymous = Guards.copyObject(failure)
        anonymous.accountKey = ""
        var accounts = { codex: "Organization A" }
        var restored = Cache.restore(items, [failure], nowMs + 60000, accounts)
        compare(restored.map(function(item) { return item.provider }), ["codex", "claude"])
        compare(restored[0].rows.length, 0)
        verify(restored[1].usageStale)
        compare(Cache.restore(items, [anonymous], nowMs + 60000, accounts)[0].rows.length, 0)
        compare(Cache.restore(items, [], nowMs + 60000, accounts)
            .map(function(item) { return item.provider }), ["claude"])
        // Without a selection the default account's unidentified failure still reuses it.
        compare(Cache.restore(items, [anonymous], nowMs + 60000)[0].rows.length, 1)
        compare(items[0].rows[0].usedPercent, 70)
    }
}
