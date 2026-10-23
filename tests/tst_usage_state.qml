import QtQuick
import QtTest
import "../contents/ui/UsageState.js" as State
import "../contents/ui/UsageCache.js" as Cache
import "../contents/ui/ProviderSnapshot.js" as Snapshot
import "../contents/ui/ProviderViewModel.js" as View

TestCase {
    name: "UsageState"
    readonly property double now: Date.UTC(2026, 9, 16, 12)
    readonly property string context: "0123456789abcdef0123456789abcdef"

    function item(provider, percent, account, error, measuredAt) {
        var payload = {provider: provider}
        if (error) payload.error = {message: error}
        else payload.usage = {account: account || "private@example.test",
            updatedAt: new Date(measuredAt === undefined ? now : measuredAt).toISOString(),
            primary: {usedPercent: percent}}
        var snapshot = Snapshot.normalize(payload, now)
        return View.presented(snapshot, {title: "Localized title", rows: snapshot.rows,
            planText: "Localized plan", status: "", error: snapshot.error,
            placeholder: "", providerCost: null, resetCredits: null, tokenCost: null,
            usageDashboard: null, dashboardUrl: "https://example.test/private", statusUrl: "", changelogUrl: ""})
    }
    function fresh() {
        return State.accepted([], [item("codex", 20), item("claude", 40)], context, now).providers
    }
    function test_largeRosterKeepsTheCachePrefixThatFits() {
        var incoming = [];
        for (var i = 0; i < 31; i++) {
            var provider = item("provider-" + i, 40);
            var rows = [];
            for (var lane of ["primary", "secondary", "tertiary"])
                rows.push({lane: lane, hasPercent: true, usedPercent: 40,
                    resetsAt: new Date(now + 3600000).toISOString()});
            for (var extra = 0; extra < 24; extra++)
                rows.push({lane: "extra", windowId: "window-" + extra, hasPercent: true,
                    usedPercent: 40, resetsAt: new Date(now + 3600000).toISOString()});
            provider.rows = rows;
            incoming.push(provider);
        }
        var result = State.accepted(fresh(), incoming, context, now);
        compare(result.providers.length, incoming.length);
        verify(result.refreshCompleted);
        verify(result.cacheValue.length > 0);
        verify(Cache.withinByteLimit(result.cacheValue));
        var restored = Cache.decode(result.cacheValue, context, now);
        verify(restored.length > 0 && restored.length < incoming.length);
        compare(restored.map(function(provider) { return provider.provider; }),
            incoming.slice(0, restored.length).map(function(provider) { return provider.provider; }));
        compare(Cache.encode(result.providers.slice(0, restored.length + 1), context, now), result.cacheValue);
    }

    function test_liveSuccessAndFailurePublishDifferentClockAndNotificationIntents() {
        var previous = fresh()
        var saved = JSON.stringify(previous)
        var result = State.accepted(previous, [item("codex", 0, "", "offline"), item("claude", 50)], context, now + 1000)
        compare(result.label, "stale")
        verify(result.refreshCompleted)
        verify(result.receivedFreshUsage)
        verify(!result.advanceClock)
        verify(result.providers[0].usageStale)
        compare(result.providers[0].lastGoodAtMs, now)
        compare(result.providers[0].rows[0].usedPercent, 20)
        compare(JSON.stringify(previous), saved)
        var failed = State.failed(previous, [item("codex", 0, "", "offline"), item("claude", 0, "", "offline")], context, now + 2000)
        verify(!failed.refreshCompleted)
        verify(!failed.receivedFreshUsage)
        verify(failed.advanceClock)
        compare(failed.label, "stale")
        verify(failed.cacheValue.indexOf("private@example.test") < 0)
        verify(failed.cacheValue.indexOf("Localized") < 0)
        verify(failed.cacheValue.indexOf("https://") < 0)
        compare(Cache.decode(failed.cacheValue, context, now + 2000).length, 2)
    }
    function test_emptySuccessReplacesQuotaAndMissingContextDoesNotOverwriteDisk() {
        var result = State.accepted(fresh(), [item("codex", undefined)], "", now)
        compare(result.label, "updated")
        compare(result.cacheValue, null)
        verify(!Cache.hasQuota(result.providers[0]))
        var failure = State.failed([], [], context, now)
        compare(failure.label, "clear")
        compare(failure.cacheValue, "")
        var empty = State.accepted(fresh(), [], context, now)
        compare(empty.label, "clear")
        verify(!empty.receivedFreshUsage)
    }
    function test_invalidationClearsOnlySelectedProviderAndPersistsHealthySibling() {
        var previous = fresh()
        var result = State.invalidated(previous, "codex", item("codex", undefined), context, now)
        compare(result.providers.length, 2)
        verify(!Cache.hasQuota(result.providers[0]))
        compare(Cache.decode(result.cacheValue, context, now)[0].provider, "claude")
        compare(result.label, "clear")
        compare(State.invalidated(previous, "codex", item("codex", undefined), "", now).cacheValue, null)
        var cleared = State.invalidated(previous, "", null, "", now)
        compare(cleared.providers, [])
        compare(cleared.cacheValue, "")
        compare(previous[0].rows[0].usedPercent, 20)
    }
    function test_restoreMergesMissingCachedProvidersAndPreservesEarlyFreshLabel() {
        var previous = State.accepted([], [item("codex", 60)], "", now).providers
        var cached = fresh()
        var result = State.restored(previous, cached, {}, "claude,codex", context, now)
        compare(result.label, "stale")
        compare(result.providers.map(function(p) { return p.provider }), ["claude", "codex"])
        verify(result.providers[0].usageStale)
        verify(!result.providers[1].usageStale)
        compare(result.providers[1].rows[0].usedPercent, 60)
        verify(!result.refreshCompleted)
        compare(State.restored(previous, [], {}, "", context, now).label, "keep")
        compare(State.restored(previous, cached, {}, "", "", now), null)
        compare(State.restored([], [], {}, "", context, now).cacheValue, "")
    }
    function test_accountOverridesArePublishedButNotPersisted() {
        var accounts = {codex: "work@example.test"}
        var live = [item("codex", 80, "work@example.test"), item("claude", 12)]
        function saved(result) {
            return Cache.decode(result.cacheValue, context, now).map(function(entry) {
                return entry.provider + ":" + entry.usage.primary.usedPercent
            }).join(",")
        }
        var accepted = State.accepted([], live, context, now, accounts)
        compare(accepted.providers.length, 2)
        compare(accepted.providers[0].rows[0].usedPercent, 80)
        compare(saved(accepted), "claude:12")
        var failed = State.failed(accepted.providers, [item("codex", 0, "", "offline"),
            item("claude", 0, "", "offline")], context, now, accounts)
        verify(Cache.hasQuota(failed.providers[0]))
        compare(saved(failed), "claude:12")
        compare(saved(State.invalidated(accepted.providers, "claude", item("claude", undefined),
            context, now, accounts)), "")
        // A late restore keeps the selected account's live failure free of
        // the default account's cached quota, then republishes only siblings.
        var restored = State.restored([item("codex", 0, "", "offline")], fresh(), accounts, "", context, now)
        verify(!Cache.hasQuota(restored.providers[0]))
        compare(restored.providers.map(function(p) { return p.provider }), ["codex", "claude"])
        compare(saved(restored), "claude:40")
        compare(saved(State.accepted([], live, context, now)), "codex:80,claude:12")
    }
    function test_expiryPreservesCurrentStatusButRemovesMeasurementAndDiskQuota() {
        var previous = State.failed(fresh(), [item("codex", 0, "", "offline"), item("claude", 0, "", "offline")], context, now).providers
        previous[0].statusKnown = true
        previous[0].status = "Current outage"
        previous[0].statusSeverity = "major"
        previous[0].hasIncident = true
        // Keep a younger stale sibling to exercise the keep-label branch.
        previous[1].lastGoodAtMs = now + 1000
        var time = now + Cache.maximumAgeMs + 1
        var result = State.expired(previous, [item("codex", 0, "", "expired")], context, time)
        compare(result.label, "keep")
        compare(result.providers[0].lastGoodAtMs, 0)
        verify(!result.providers[0].usageStale)
        verify(!Cache.hasQuota(result.providers[0]))
        compare(result.providers[0].status, "Current outage")
        compare(Cache.decode(result.cacheValue, context, time).length, 1)
        verify(previous[0].usageStale)
        var all = State.expired(result.providers, [item("claude", 0, "", "expired")], context, time + 1000)
        compare(all.label, "clear")
        compare(all.cacheValue, "")
        compare(State.expired(fresh(), [], context, now), null)
    }
}
