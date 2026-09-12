import QtQuick
import QtTest
import "../contents/ui/UsageResponse.js" as UsageResponse
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "UsageResponse"

    function healthy(provider, used) {
        return {provider: provider, account: "Synthetic account",
            usage: {primary: {usedPercent: used}},
            pace: {primary: {willLastToReset: false, etaSeconds: 1800}}};
    }

    function broken() {
        var item = {provider: "codex"};
        Object.defineProperty(item, "usage", {enumerable: true, get: function() { throw new Error("Synthetic invalid record"); }});
        return item;
    }

    function test_malformedSiblingOrder_data() {
        var cases = [];
        for (var scoped of [false, true])
            for (var index of [0, 1, 2])
                for (var used of [0, 72])
                    cases.push({tag: scoped + "-" + index + "-" + used,
                        scoped: scoped, index: index, used: used});
        return cases;
    }

    function test_malformedSiblingOrder(data) {
        var payload = [{provider: "codex", error: {message: {toString: null}}},
            healthy(data.scoped ? "deliberately-wrong" : "codex", data.used)];
        payload.splice(data.index, 0, broken());
        var result = UsageResponse.records(payload, data.scoped ? "codex" : "", 123456);
        compare(result.outcome, "success");
        compare(result.items.length, 1);
        var item = result.items[0];
        compare(item.provider, "codex");
        compare(item.commandFailed, false);
        compare(item.rows[0].usedPercent, data.used);
        compare(item.usageReceivedAtMs, 123456);
        compare(item.rows[0].paceObservedAtMs, 123456);
    }

    function test_throwingIdentityOnlyDropsItsOwnProvider() {
        var item = {};
        Object.defineProperty(item, "provider", {enumerable: true, get: function() { throw new Error("Synthetic identity"); }});
        var result = UsageResponse.records([item, healthy("claude", 0)], "", 1);
        compare(result.outcome, "success");
        compare(result.items.length, 1);
        compare(result.items[0].provider, "claude");
    }

    function test_allMalformedRecordsFail() {
        compare(UsageResponse.records([broken(), broken()], "", 1).outcome, "noProviders");
        compare(UsageResponse.records([broken(), broken()], "codex", 1).outcome, "invalidJson");
    }

    function test_boundedEnvelopes_data() {
        return [{tag: "empty", value: "", outcome: "empty"},
            {tag: "malformed", value: "{", outcome: "invalidJson"},
            {tag: "null", value: "null", outcome: "noProviders"},
            {tag: "empty-list", value: "[]", outcome: "noProviders"},
            {tag: "scalar", value: "42", outcome: "noProviders"},
            {tag: "object", value: "{}", outcome: "noProviders"},
            {tag: "unsafe-id", value: '{"provider":"__proto__"}', outcome: "noProviders"},
            {tag: "oversized", value: "x".repeat(SafeText.maximumCliJsonLength + 1), outcome: "tooLarge"}];
    }

    function test_boundedEnvelopes(data) {
        compare(UsageResponse.response(data.value, "", "", 1).outcome, data.outcome);
    }

    function test_limitsApplyBeforeReadingRecords() {
        var aggregate = [];
        for (var i = 0; i < Normalizer.maximumProviderSnapshots; i++)
            aggregate.push(healthy("synthetic" + i, 0));
        aggregate.push(broken());
        compare(UsageResponse.records(aggregate, "", 1).items.length, Normalizer.maximumProviderSnapshots);
        var accounts = Array(Normalizer.maximumAccountSnapshots).fill(null);
        accounts.push(healthy("codex", 72));
        compare(UsageResponse.records(accounts, "codex", 1).outcome, "noProviders");
    }

    function test_rosterDistinguishesEmptyFromInvalid() {
        compare(UsageResponse.roster("[]", "").outcome, "success");
        compare(UsageResponse.roster("null", "").outcome, "noProviders");
        var result = UsageResponse.roster(JSON.stringify([
            {provider: "codex", displayName: "Synthetic Codex", enabled: true},
            {provider: "claude", enabled: false}]), "");
        compare(result.providerIDs, ["codex"]);
        compare(result.displayNames.codex, "Synthetic Codex");
    }

    function test_errorsAreRedactedAndBounded() {
        var result = UsageResponse.response("", "Authorization: Bearer synthetic-secret-abcdef " + "x".repeat(5000), "", 1);
        verify(result.message.indexOf("synthetic-secret-abcdef") < 0);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
    }
}
