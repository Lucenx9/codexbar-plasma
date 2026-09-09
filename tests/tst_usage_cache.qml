import QtQuick
import QtTest
import "../contents/ui/UsageCache.js" as Cache

TestCase {
    name: "UsageCache"

    readonly property double nowMs: Date.parse("2026-09-09T12:00:00Z")
    readonly property string context: "0123456789abcdef0123456789abcdef"

    function snapshot(provider, percent, account) {
        var row = {
            lane: "primary",
            label: "Sensitive label",
            hasPercent: true,
            usedPercent: percent,
            leftPercent: 100 - percent,
            resetsAt: "2026-09-09T14:00:00Z",
            paceKnown: true,
            paceEtaSeconds: 60,
            pace: "Sensitive forecast"
        };
        return {
            provider: provider,
            account: account || "secret@example.test",
            rows: [row],
            primaryRow: row,
            error: "",
            title: "Private name",
            updatedAt: "2026-09-09T11:52:00Z",
            status: "Private incident",
            credits: 20,
            cwd: "/private/path",
            auth: "Bearer sensitive"
        };
    }

    function failed(provider, account) {
        return {
            provider: provider,
            account: account || "",
            rows: [],
            primaryRow: null,
            error: "Synthetic failure",
            updatedAt: ""
        };
    }

    function fresh() {
        return Cache.reconcile([], [snapshot("codex", 72), snapshot("claude", 28)], nowMs);
    }

    function test_failureKeepsMeasurementTimeAndDoesNotMutateInputs() {
        var previous = fresh();
        var next = Cache.reconcile(previous, [failed("codex"), snapshot("claude", 45)], nowMs + 60000);
        compare(next[0].rows[0].usedPercent, 72);
        compare(next[0].lastGoodAtMs, nowMs - 480000);
        verify(next[0].usageStale);
        compare(next[0].error, "Synthetic failure");
        verify(!next[0].rows[0].paceKnown);
        compare(next[0].rows[0].paceEtaSeconds, 0);
        compare(next[0].primaryRow, next[0].rows[0]);
        verify(!previous[0].usageStale);
        verify(previous[0].rows[0].paceKnown);
        compare(next[1].rows[0].usedPercent, 45);
        verify(!next[1].usageStale);
        var retried = Cache.reconcile(next, [failed("codex")], nowMs + 120000);
        compare(retried[0].lastGoodAtMs, next[0].lastGoodAtMs);
        compare(retried.length, 1);
    }

    function test_recoveryAndMeasuredZeroReplaceOldData() {
        var stale = Cache.reconcile(fresh(), [failed("codex")], nowMs);
        var zero = Cache.reconcile(stale, [snapshot("codex", 0)], nowMs)[0];
        compare(zero.rows[0].usedPercent, 0);
        compare(zero.error, "");
        verify(!zero.usageStale);
        var empty = failed("codex");
        empty.error = "";
        compare(Cache.reconcile(stale, [empty], nowMs)[0].rows.length, 0);
        compare(Cache.reconcile(stale, [], nowMs).length, 0);
    }

    function test_accountMismatchAndFirstFailureCannotBorrowQuotas() {
        compare(Cache.reconcile(fresh(), [failed("codex", "other@example.test")], nowMs)[0].rows.length, 0);
        compare(Cache.reconcile([], [failed("codex")], nowMs)[0].rows.length, 0);
    }

    function test_failuresStopReusingExpiredMeasurements() {
        var previous = fresh();
        var deadline = previous[0].lastGoodAtMs + Cache.maximumAgeMs;
        var stale = Cache.reconcile(previous, [failed("codex")], deadline);
        verify(stale[0].usageStale);
        compare(Cache.expiredProviderIDs(stale, deadline), []);
        compare(Cache.expiredProviderIDs(stale, deadline + 1), ["codex"]);
        compare(Cache.expiredProviderIDs(stale, previous[0].lastGoodAtMs - 1), ["codex"]);
        compare(Cache.expiredProviderIDs(previous, deadline + 1), []);
        for (var items of [previous, stale]) {
            var expired = Cache.reconcile(items, [failed("codex")], deadline + 1)[0];
            compare(expired.rows.length, 0);
            compare(expired.lastGoodAtMs, 0);
            verify(!expired.usageStale);
            compare(expired.error, "Synthetic failure");
        }
    }

    function test_failedPayloadWithQuotasCannotReplaceLastSuccess() {
        var incoming = snapshot("codex", 0);
        incoming.error = "Synthetic failure";
        var result = Cache.reconcile(fresh(), [incoming], nowMs);
        verify(result[0].usageStale);
        compare(result[0].rows[0].usedPercent, 72);
    }

    function test_freshStatusSurvivesQuotaFailureAndExpiry() {
        var previous = fresh();
        var incoming = Object.assign(failed("codex"), {
            statusKnown: true, status: "New outage", statusSeverity: "major",
            statusIncidentKey: "incident-2", hasIncident: true,
            statusUrl: "https://status.openai.com/"
        });
        var retained = Cache.reconcile(previous, [incoming], nowMs)[0];
        verify(retained.usageStale && retained.statusKnown && retained.hasIncident);
        compare(retained.rows[0].usedPercent, 72);
        compare(retained.status, incoming.status);
        compare(retained.statusSeverity, incoming.statusSeverity);
        compare(retained.statusIncidentKey, incoming.statusIncidentKey);
        compare(retained.statusUrl, incoming.statusUrl);
        compare(previous[0].status, "Private incident");
        var unavailable = Cache.reconcile([retained], [failed("codex")], nowMs)[0];
        verify(!unavailable.statusKnown);
        // An unknown status must not keep showing the previous outage:
        // badges gate on hasIncident alone.
        compare(unavailable.status, "");
        compare(unavailable.statusSeverity, "");
        compare(unavailable.statusIncidentKey, "");
        verify(!unavailable.hasIncident);
        compare(unavailable.statusUrl, "");
        var expired = Cache.withCurrentStatus(failed("codex"), retained);
        verify(expired.statusKnown && expired.hasIncident);
        compare(expired.rows.length, 0);
        incoming.hasIncident = false;
        incoming.statusSeverity = "";
        incoming.statusIncidentKey = "";
        incoming.status = "Operational";
        var recovered = Cache.reconcile([unavailable], [incoming], nowMs)[0];
        verify(recovered.usageStale && recovered.statusKnown && !recovered.hasIncident);
        compare(recovered.status, "Operational");
        compare(recovered.statusSeverity, "");
        compare(recovered.statusIncidentKey, "");
    }

    function test_extraLaneQuotasSurviveRestart() {
        var extra = {
            lane: "extra",
            label: "Sensitive extra",
            hasPercent: true,
            usedPercent: 90,
            leftPercent: 10,
            resetsAt: "2026-09-09T14:00:00Z",
            paceKnown: false,
            paceEtaSeconds: 0,
            pace: ""
        };
        var item = snapshot("codex", 72);
        item.rows.push(extra);
        var encoded = Cache.encode(Cache.reconcile([], [item], nowMs), context, nowMs);
        verify(encoded.length > 0);
        var result = Cache.decode(encoded, context, nowMs);
        compare(result.length, 1);
        compare(result[0].usage.extra.usedPercent, 90);
        compare(result[0].usage.primary.usedPercent, 72);
        var extraOnly = snapshot("claude", 28);
        extraOnly.rows = [extra];
        var extraEncoded = Cache.encode(Cache.reconcile([], [extraOnly], nowMs), context, nowMs);
        verify(extraEncoded.length > 0);
        compare(Cache.decode(extraEncoded, context, nowMs)[0].usage.extra.usedPercent, 90);
        for (var secret of ["Sensitive extra"])
            verify(extraEncoded.indexOf(secret) < 0, secret);
    }

    function test_staleRetentionDropsSupplementalSections() {
        var item = snapshot("codex", 72);
        item.providerCost = { percentUsed: 32 };
        item.codexCreditLimit = { title: "t", used: 1, limit: 2, remaining: 1, usedPercent: 50, leftPercent: 50, resetsAt: "" };
        item.providerDetails = [{ title: "t", rows: [] }];
        var previous = Cache.reconcile([], [item], nowMs);
        var retained = Cache.reconcile(previous, [failed("codex")], nowMs)[0];
        verify(retained.usageStale);
        compare(retained.rows[0].usedPercent, 72);
        compare(retained.providerDetails.length, 0);
        verify(retained.usageDashboard === null);
        verify(retained.providerCost === null);
        verify(retained.resetCredits === null);
        verify(retained.tokenCost === null);
        verify(retained.codexCreditLimit === null);
        verify(retained.credits === null);
    }

    function test_ancientMeasurementCannotStampFresh() {
        var item = snapshot("codex", 72);
        item.updatedAt = "2026-09-07T11:00:00Z";
        var result = Cache.reconcile([], [item], nowMs)[0];
        verify(result.usageStale);
        compare(result.lastGoodAtMs, Date.parse("2026-09-07T11:00:00Z"));
        var missing = snapshot("claude", 28);
        missing.updatedAt = "";
        var fallback = Cache.reconcile([], [missing], nowMs)[0];
        verify(!fallback.usageStale);
        compare(fallback.lastGoodAtMs, nowMs);
    }

    function test_redactedRoundTripAndContextIsolation() {
        var encoded = Cache.encode(fresh(), context, nowMs);
        for (var secret of ["secret@", "Sensitive", "Private", "Bearer", "/private", "credits", "account"])
            verify(encoded.indexOf(secret) < 0, secret);
        var result = Cache.decode(encoded, context, nowMs);
        compare(result.length, 2);
        compare(result[0].provider, "codex");
        compare(result[0].usage.primary.usedPercent, 72);
        compare(result[0].usage.updatedAt, "2026-09-09T11:52:00.000Z");
        compare(result[0].usage.primary.resetsAt, "2026-09-09T14:00:00.000Z");
        compare(Cache.decode(encoded, "fedcba9876543210fedcba9876543210", nowMs).length, 0);
        compare(Cache.decode(encoded, "", nowMs).length, 0);
        compare(Cache.encode(fresh(), "", nowMs), "");
    }

    function test_expiredFutureAndInvalidTimestampsDoNotRestore() {
        var encoded = JSON.parse(Cache.encode(fresh(), context, nowMs));
        for (var value of [nowMs - Cache.maximumAgeMs - 1, nowMs + 1, 0, -1, "123", null]) {
            encoded.snapshots.forEach(function (item) {
                item.measuredAt = value;
            });
            compare(Cache.decode(JSON.stringify(encoded), context, nowMs).length, 0);
        }
        encoded.snapshots[0].measuredAt = nowMs - Cache.maximumAgeMs;
        compare(Cache.decode(JSON.stringify(encoded), context, nowMs).length, 1);
    }

    function test_corruptOversizedAndUnknownVersionCachesAreIgnored() {
        for (var raw of ["", "{", "null", "[]", "true", "42", Array(Cache.maximumBytes + 2).join("x")])
            compare(Cache.decode(raw, context, nowMs).length, 0);
        var value = JSON.parse(Cache.encode(fresh(), context, nowMs));
        value.version = 2;
        compare(Cache.decode(JSON.stringify(value), context, nowMs).length, 0);
        value.version = 1;
        value.snapshots = Array(Cache.maximumEntries + 1).fill(value.snapshots[0]);
        compare(Cache.decode(JSON.stringify(value), context, nowMs).length, 0);
    }

    function test_restorationRebuildsOnlyValidQuotaFields() {
        var value = JSON.parse(Cache.encode(fresh(), context, nowMs));
        var item = value.snapshots[0];
        item.account = "must not survive";
        item.windows.primary.auth = "must not survive";
        item.windows.primary.resetsAt = "not a timestamp";
        item.windows.secondary = {
            usedPercent: 0
        };
        item.windows.tertiary = {
            usedPercent: "75"
        };
        item.windows.extra = {
            usedPercent: 90,
            label: "must not survive"
        };
        value.snapshots.push(item);
        value.snapshots.push({
            provider: "__proto__",
            measuredAt: nowMs,
            windows: item.windows
        });
        var result = Cache.decode(JSON.stringify(value), context, nowMs);
        compare(result.length, 2);
        compare(result[0].usage.primary.resetsAt, "");
        compare(result[0].usage.secondary.usedPercent, 0);
        verify(result[0].usage.tertiary === undefined);
        verify(JSON.stringify(result).indexOf("must not survive") < 0);
        for (var percent of [-1, 101, null, "0"]) {
            item.windows.primary.usedPercent = percent;
            verify(Cache.decode(JSON.stringify(value), context, nowMs)[0].usage.primary === undefined);
        }
    }

    function test_persistenceHasBoundedProviderCountAndNoArbitraryLanes() {
        var items = [];
        for (var i = 0; i < Cache.maximumEntries + 10; i++)
            items.push(snapshot("future-provider-" + i, 0));
        var encoded = Cache.encode(Cache.reconcile([], items, nowMs), context, nowMs);
        verify(encoded.length < Cache.maximumBytes);
        compare(Cache.decode(encoded, context, nowMs).length, Cache.maximumEntries);
    }

    function test_byteLimitAppliesBeforeSavingAndCountsUtf8OnRead() {
        var oversized = snapshot(Array(Cache.maximumBytes + 1).join("x"), 72);
        compare(Cache.encode(Cache.reconcile([], [oversized], nowMs), context, nowMs), "");
        var cache = JSON.parse(Cache.encode(fresh(), context, nowMs));
        cache.ignored = Array(Cache.maximumBytes / 2).join("界");
        var raw = JSON.stringify(cache);
        verify(raw.length < Cache.maximumBytes);
        compare(Cache.decode(raw, context, nowMs).length, 0);
        var unicode = Cache.reconcile([], [snapshot("future-界", 72)], nowMs);
        compare(Cache.decode(Cache.encode(unicode, context, nowMs), context, nowMs)[0].provider, "future-界");
    }
}
