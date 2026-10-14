import QtQuick
import QtTest
import "../contents/ui/ProviderSnapshot.js" as Snapshot
import "../contents/ui/UsageResponse.js" as UsageResponse
import "../contents/ui/AccountResponse.js" as AccountResponse
import "../contents/ui/PrivacyPresentation.js" as Privacy
import "../contents/ui/UsageCache.js" as Cache
import "../contents/ui/OverviewProviders.js" as Overview
import "../contents/ui/components" as Components

TestCase {
    name: "SubscriptionDates"

    function i18nc(context, source) {
        var text = source;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), String(arguments[i]));
        return text;
    }
    Components.TimeLabels { id: timeLabels; locale: Qt.locale("en_US") }

    function payload(usage) { return {provider: "sub2api", account: "demo@example.test", usage: usage}; }
    function normalized(usage) { return Snapshot.normalize(payload(usage), Date.parse("2026-10-14T12:00:00Z")); }
    function test_dates_data() {
        return [
            {tag: "iso", value: "2026-11-30T00:00:00Z", flag: undefined, valid: true, day: ""},
            {tag: "offset", value: "2026-11-30T03:15:12+02:30", flag: false, valid: true, day: ""},
            {tag: "fraction-bound", value: "2026-11-30T03:15:12.123456789+02:30", flag: false, valid: true, day: ""},
            {tag: "fraction-too-long", value: "2026-11-30T03:15:12.1234567890+02:30", valid: false},
            {tag: "fraction", value: "2026-11-30T03:15:12.123Z", flag: null, valid: true, day: ""},
            {tag: "date-only-serialized", value: "2026-11-30T00:00:00Z", flag: true, valid: true, day: "2026-11-30"},
            {tag: "date-only-offset", value: "2026-11-30T00:00:00+14:00", flag: true, valid: true, day: "2026-11-30"},
            {tag: "early-year", value: "0001-01-01T00:00:00Z", flag: true, valid: true, day: "0001-01-01"},
            {tag: "last-year", value: "9999-12-31T00:00:00Z", flag: true, valid: true, day: "9999-12-31"},
            {tag: "calendar", value: "2026-11-30", flag: true, valid: true, day: "2026-11-30"},
            {tag: "leap", value: "2028-02-29T00:00:00Z", flag: true, valid: true, day: "2028-02-29"},
            {tag: "flag-string", value: "2026-11-30T00:00:00Z", flag: "true", valid: true, day: ""},
            {tag: "flag-number", value: "2026-11-30T00:00:00Z", flag: 1, valid: true, day: ""},
            {tag: "flag-object", value: "2026-11-30T00:00:00Z", flag: {}, valid: true, day: ""},
            {tag: "missing", value: undefined, valid: false},
            {tag: "null", value: null, valid: false},
            {tag: "number", value: 1795996800000, valid: false},
            {tag: "boolean", value: true, valid: false},
            {tag: "object", value: {toString: null}, valid: false},
            {tag: "array", value: ["2026-11-30T00:00:00Z"], valid: false},
            {tag: "empty", value: "", valid: false},
            {tag: "huge", value: "2026-11-30T00:00:00Z".repeat(10000), valid: false},
            {tag: "not-iso", value: "November 30, 2026", valid: false},
            {tag: "missing-zone", value: "2026-11-30T00:00:00", valid: false},
            {tag: "calendar-missing-flag", value: "2026-11-30", valid: false},
            {tag: "calendar-false-flag", value: "2026-11-30", flag: false, valid: false},
            {tag: "calendar-invalid-flag", value: "2026-11-30", flag: "true", valid: false},
            {tag: "bad-leap", value: "2026-02-29T00:00:00Z", valid: false},
            {tag: "bad-century", value: "2100-02-29T00:00:00Z", flag: true, valid: false},
            {tag: "bad-day", value: "2026-11-31T00:00:00Z", flag: true, valid: false},
            {tag: "zero-day", value: "2026-11-00T00:00:00Z", valid: false},
            {tag: "bad-month", value: "2026-13-01T00:00:00Z", valid: false},
            {tag: "zero-year", value: "0000-11-30T00:00:00Z", valid: false},
            {tag: "large-year", value: "+100000-11-30T00:00:00Z", valid: false},
            {tag: "bad-hour", value: "2026-11-30T24:00:00Z", flag: true, valid: false},
            {tag: "bad-minute", value: "2026-11-30T00:60:00Z", valid: false},
            {tag: "bad-second", value: "2026-11-30T00:00:60Z", valid: false},
            {tag: "bad-offset", value: "2026-11-30T00:00:00+25:00", valid: false},
            {tag: "bad-offset-minute", value: "2026-11-30T00:00:00+01:60", valid: false},
            {tag: "trailing", value: "2026-11-30T00:00:00Z secret", valid: false}
        ];
    }
    function test_dates(data) {
        for (var field of ["subscriptionRenewsAt", "subscriptionExpiresAt"]) {
            var usage = {primary: {usedPercent: 42}};
            usage[field] = data.value;
            if (data.flag !== undefined) usage[field + "IsDateOnly"] = data.flag;
            var before = JSON.stringify(usage);
            var result = normalized(usage);
            compare(result.rows[0].usedPercent, 42);
            compare(result.subscriptionDates.length, data.valid ? 1 : 0);
            if (data.valid) {
                var date = result.subscriptionDates[0];
                compare(date.kind, field === "subscriptionRenewsAt" ? "renews" : "expires");
                compare(date.calendarDay, data.day);
                if (data.day === "") {
                    compare(date.timestampMs, Date.parse(data.value));
                    compare(timeLabels.subscriptionDate(date), new Date(date.timestampMs).toLocaleDateString(Qt.locale("en_US"), Locale.ShortFormat)
                        + ", " + timeLabels.clockTime(date.timestampMs));
                } else {
                    var calendar = new Date(0);
                    calendar.setFullYear(Number(data.day.slice(0, 4)), Number(data.day.slice(5, 7)) - 1, Number(data.day.slice(8, 10)));
                    calendar.setHours(12, 0, 0, 0);
                    compare(timeLabels.subscriptionDate(date), calendar.toLocaleDateString(Qt.locale("en_US"), Locale.ShortFormat));
                }
            }
            compare(JSON.stringify(usage), before);
        }
    }
    function test_bothFieldsAndOldPayloads() {
        var dates = normalized({subscriptionRenewsAt: "2026-11-01T08:30:00Z",
            subscriptionExpiresAt: "2026-11-30T00:00:00Z", subscriptionExpiresAtIsDateOnly: true}).subscriptionDates;
        compare(dates.length, 2);
        compare(dates[0].kind, "renews");
        compare(dates[1].kind, "expires");
        compare(normalized({primary: {usedPercent: 42, resetsAt: "2026-11-01T00:00:00Z"}}).subscriptionDates, []);
        compare(normalized({subscriptionRenewsAtIsDateOnly: true}).subscriptionDates, []);
        compare(normalized({subscriptionRenewsAt: "bad", subscriptionExpiresAt: "2026-11-30T00:00:00Z"}).subscriptionDates.length, 1);
        function InheritedUsage() {}
        InheritedUsage.prototype.subscriptionRenewsAt = "2026-11-30T00:00:00Z";
        compare(normalized(new InheritedUsage()).subscriptionDates, []);
        InheritedUsage.prototype.subscriptionExpiresAtIsDateOnly = true;
        var ownDate = new InheritedUsage();
        ownDate.subscriptionExpiresAt = "2026-11-30T00:00:00Z";
        compare(normalized(ownDate).subscriptionDates[0].calendarDay, "");
    }
    function presented(usage, now) {
        var result = normalized(usage);
        result.primaryRow = result.rows[0] || null;
        result.tokenCost = null;
        return Cache.reconcile([], [result], now)[0];
    }
    function test_privacyStaleAndAccountPaths() {
        var now = Date.parse("2026-10-14T12:00:00Z");
        var raw = payload({primary: {usedPercent: 42}, subscriptionExpiresAt: "2026-11-30T00:00:00Z"});
        var accounts = AccountResponse.records([raw], "sub2api", now);
        var usage = UsageResponse.records([raw], "", now);
        compare(accounts.outcome, "success");
        compare(accounts.options[0].subscriptionDates, usage.items[0].subscriptionDates);
        var item = presented(raw.usage, now);
        var before = JSON.stringify(item);
        compare(Privacy.provider(item, false, {}), item);
        var hidden = Privacy.provider(item, true, {title: "Provider", usage: "Usage", rowLabels: []});
        compare(hidden.subscriptionDates, []);
        compare(hidden.rows[0].usedPercent, 42);
        verify(JSON.stringify(hidden).indexOf("2026-11-30") < 0);
        verify(Cache.encode([item], "a".repeat(32), now).indexOf("subscription") < 0);
        var failure = presented({}, now);
        failure.error = "Synthetic timeout";
        var retained = Cache.reconcile([item], [failure], now + 1000)[0];
        verify(retained.usageStale);
        compare(retained.rows[0].usedPercent, 42);
        compare(retained.subscriptionDates, []);
        var oldAccount = JSON.parse(before);
        oldAccount.updatedAt = "2026-10-01T00:00:00Z";
        var selected = Cache.reconcile([], [oldAccount], now)[0];
        verify(selected.usageStale);
        compare(selected.subscriptionDates, []);
        failure.account = "different@example.test";
        failure.accountKey = "different@example.test";
        var changedAccount = Cache.reconcile([item], [failure], now + 1000)[0];
        verify(!changedAccount.usageStale);
        compare(changedAccount.subscriptionDates, []);
        compare(Cache.reconcile([item], [presented({}, now)], now)[0].subscriptionDates, []);
        compare(JSON.stringify(item), before);
    }
    function test_datesOnlyAreUsefulAndInvalidEnrichmentPreservesQuotas() {
        var dateOnly = normalized({subscriptionExpiresAt: "2026-11-30T00:00:00Z"});
        compare(dateOnly.placeholder, "");
        dateOnly.updatedAt = "2020-01-01T00:00:00Z";
        var supplemental = Cache.reconcile([], [dateOnly], Date.parse("2026-10-14T12:00:00Z"))[0];
        verify(!supplemental.usageStale);
        compare(supplemental.subscriptionDates, dateOnly.subscriptionDates);
        dateOnly.credits = null; dateOnly.tokenCost = null;
        dateOnly.error = "Synthetic optional enrichment failure";
        compare(Overview.visibleItems([dateOnly], "").length, 1);
        dateOnly.subscriptionDates = [];
        compare(Overview.visibleItems([dateOnly], "").length, 0);
        var result = UsageResponse.records([payload({primary: {usedPercent: 42}, subscriptionExpiresAt: {toString: null}})], "", 1000);
        compare(result.outcome, "success");
        compare(result.items[0].rows[0].usedPercent, 42);
        compare(result.items[0].subscriptionDates, []);
    }
}
