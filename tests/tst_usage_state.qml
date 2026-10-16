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
    function test_liveFailuresCannotUseRestoreAccountPin() {
        var previous = State.accepted([], [item("codex", 20, "old@example.test")], context, now).providers
        var failed = item("codex", 0, "", "offline")
        failed.account = "other@example.test"
        failed.accountKey = ""
        verify(!Cache.hasQuota(State.accepted(previous, [failed], context, now).providers[0]))
        var restored = State.restored([failed], previous, {codex: "verified-account"}, "", context, now)
        verify(Cache.hasQuota(restored.providers[0]))
        verify(restored.providers[0].usageStale)
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
