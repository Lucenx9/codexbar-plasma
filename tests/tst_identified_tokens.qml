import QtQuick
import QtTest
import "../contents/ui/IdentifiedTokens.js" as Identified
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "IdentifiedTokens"
    readonly property double endMs: 1792054407966

    function plan(remote) { return Identified.requestPlan("/tmp/CLI 'quoted'", 7, endMs, remote || ""); }
    function row(id, input) {
        return {id: id.repeat(64), timestampUnixMs: endMs, inputTokens: input,
            outputTokens: 10, cacheReadTokens: 40, reasoningTokens: 5};
    }
    function ledger(rows) {
        return {schemaVersion: 1, provider: "codex", startUnixMs: plan().startUnixMs,
            endUnixMs: endMs, records: rows || [row("a", 100), row("b", 200)],
            conflictingIDs: [], excludedCount: 0, partial: false};
    }
    function ledger2(rows) {
        var value = ledger(rows);
        value.schemaVersion = 2;
        value.records.forEach(function(record) {
            record.model = "gpt-5";
            record.pricingMode = "standard";
            record.includedInPlan = false;
        });
        return value;
    }
    function subtotal(tokens, requests) {
        return {kind: "identified-request-subtotal", totalTokens: tokens, requestCount: requests,
            conflictCount: 0, excludedCount: 0, partial: false, costUSD: null};
    }
    function remotePayload() {
        return {reports: [{host: "local", ledger: ledger()},
            {host: "build@host", ledger: ledger([row("a", 100), row("c", 300)])}],
            subtotal: subtotal(630, 3), allSourcesAvailable: true, partial: false};
    }
    function remotePayload2() {
        var value = remotePayload();
        value.reports[0].ledger = ledger2();
        value.reports[1].ledger = ledger2([row("a", 100), row("c", 300)]);
        value.reports.forEach(function(report, index) {
            report.source = index === 0 ? "local" : "ssh";
            report.collectedAt = "2026-10-15T10:13:27Z";
        });
        value.subtotal.costUSD = 0.0125;
        value.subtotal.unpricedRequestCount = 0;
        return value;
    }
    function decode(payload, remote, exit) {
        return Identified.decode(JSON.stringify(payload), exit === undefined ? 0 : exit, plan(remote));
    }
    function test_planUsesExactUtcWindowAndQuotesExecutable() {
        var local = plan();
        compare(local.outcome, "ready");
        compare(local.startUnixMs, 1791504000000);
        verify(local.command.indexOf("--identified-end " + endMs) >= 0);
        verify(local.command.indexOf("--remote") === -1);
        compare(plan("build@host").remoteHost, "build@host");
        compare(plan("local").remoteHost, "local");
        verify(Identified.processTimeoutSeconds + Identified.processKillAfterSeconds < Identified.requestDeadlineMs / 1000);
        compare(Identified.requestPlan("codexbar", 1, 0, "").startUnixMs, 0);
        compare(Identified.requestPlan("codexbar", 2, 0, "").outcome, "invalidSettings");
    }
    function test_invalidPlans_data() {
        return [{tag: "empty", command: "", days: 7, end: endMs, host: ""},
            {tag: "fractional", command: "codexbar", days: 1.5, end: endMs, host: ""},
            {tag: "too-long", command: "codexbar", days: 366, end: endMs, host: ""},
            {tag: "coerced", command: "codexbar", days: "7", end: endMs, host: ""},
            {tag: "time", command: "codexbar", days: 7, end: 253402300800000, host: ""},
            {tag: "option", command: "codexbar", days: 7, end: endMs, host: "-oProxyCommand=evil"},
            {tag: "shell", command: "codexbar", days: 7, end: endMs, host: "host; true"},
            {tag: "space", command: "codexbar", days: 7, end: endMs, host: " host"},
            {tag: "newline", command: "codexbar", days: 7, end: endMs, host: "host\n"},
            {tag: "unicode", command: "codexbar", days: 7, end: endMs, host: "höst"},
            {tag: "host-length", command: "codexbar", days: 7, end: endMs, host: "h".repeat(256)}];
    }
    function test_invalidPlans(data) {
        compare(Identified.requestPlan(data.command, data.days, data.end, data.host).outcome, "invalidSettings");
    }
    function test_localAggregateNeverExportsIdentities() {
        var value = ledger();
        var before = JSON.stringify(value);
        var result = decode(value);
        compare(result.outcome, "data");
        compare(result.snapshot.totalTokens, 320);
        compare(result.snapshot.requestCount, 2);
        compare(result.snapshot.allSourcesAvailable, true);
        compare(result.snapshot.partial, false);
        compare(result.snapshot.remoteRequested, false);
        compare(result.snapshot.startUnixMs, plan().startUnixMs);
        verify(!/records|reports|host|costUSD|"id"/.test(JSON.stringify(result)));
        verify(JSON.stringify(result).indexOf("a".repeat(64)) === -1);
        compare(JSON.stringify(value), before);
    }
    function test_schema2LocalTokensDoNotInventPrices() {
        var value = ledger2();
        var before = JSON.stringify(value);
        var result = decode(value);
        compare(result.outcome, "data");
        compare(result.snapshot.totalTokens, 320);
        compare(result.snapshot.requestCount, 2);
        compare(result.snapshot.apiEstimateUSD, null);
        compare(result.snapshot.unpricedRequestCount, null);
        verify(!/records|model|pricingMode|includedInPlan/.test(JSON.stringify(result)));
        compare(JSON.stringify(value), before);
    }
    function test_schema2UsesOnlyTheCliEstimate_data() {
        return [{tag: "priced", amount: 0.0125, unpriced: 0},
            {tag: "zero", amount: 0, unpriced: 0},
            {tag: "unknown", amount: null, unpriced: 1}];
    }
    function test_schema2UsesOnlyTheCliEstimate(data) {
        var value = remotePayload2();
        value.subtotal.costUSD = data.amount;
        value.subtotal.unpricedRequestCount = data.unpriced;
        var result = decode(value, "build@host");
        compare(result.outcome, "data");
        compare(result.snapshot.totalTokens, 630);
        compare(result.snapshot.apiEstimateUSD, data.amount);
        compare(result.snapshot.unpricedRequestCount, data.unpriced);
        verify(!/records|reports|build@host|collectedAt|model|pricingMode/.test(JSON.stringify(result)));
    }
    function test_zeroIsAvailableAndConflictsAreExcluded() {
        compare(decode(ledger([])).snapshot.totalTokens, 0);
        compare(decode(ledger([])).outcome, "data");
        var value = ledger();
        value.conflictingIDs = ["a".repeat(64), "c".repeat(64)];
        value.excludedCount = 2;
        var result = decode(value).snapshot;
        compare(result.totalTokens, 210);
        compare(result.requestCount, 1);
        compare(result.conflictCount, 2);
        compare(result.excludedCount, 2);
        verify(result.partial && result.requestsPartial && result.allSourcesAvailable);
    }
    function test_inclusiveWindowOptionalReasoningAndConflictLimit() {
        var value = ledger();
        value.records[0].timestampUnixMs = value.startUnixMs;
        delete value.records[0].reasoningTokens;
        value.records[1].reasoningTokens = null;
        compare(decode(value).snapshot.totalTokens, 320);
        value.records = [];
        for (var i = 0; i < 50000; i++)
            value.conflictingIDs.push(("0".repeat(64) + i.toString(16)).slice(-64));
        var result = decode(value);
        compare(result.outcome, "data");
        compare(result.snapshot.conflictCount, 50000);
        compare(result.snapshot.totalTokens, 0);
        verify(result.snapshot.requestsPartial);
    }
    function test_invalidLedgers_data() {
        return ["provider", "start", "end", "timestamp", "cache", "reasoning", "negative",
            "fractional", "coerced", "unsafe", "overflow", "sumOverflow", "duplicate", "duplicateConflict", "digest",
            "records", "conflicts", "excluded", "partial", "manyRecords", "manyConflicts"].map(function(tag) { return {tag: tag}; });
    }
    function test_invalidLedgers(data) {
        var value = ledger();
        switch (data.tag) {
        case "provider": value.provider = "claude"; break;
        case "start": value.startUnixMs++; break;
        case "end": value.endUnixMs++; break;
        case "timestamp": value.records[0].timestampUnixMs++; break;
        case "cache": value.records[0].cacheReadTokens = 101; break;
        case "reasoning": value.records[0].reasoningTokens = 11; break;
        case "negative": value.records[0].inputTokens = -1; break;
        case "fractional": value.records[0].inputTokens = 100.5; break;
        case "coerced": value.records[0].inputTokens = "100"; break;
        case "unsafe": value.records[0].inputTokens = 9007199254740992; break;
        case "overflow": value.records[0].inputTokens = 9007199254740991; break;
        case "sumOverflow": value.records[0].inputTokens = 9007199254740981; break;
        case "duplicate": value.records.push(value.records[0]); break;
        case "duplicateConflict": value.conflictingIDs = ["a".repeat(64), "a".repeat(64)]; break;
        case "digest": value.records[0].id = "A".repeat(64); break;
        case "records": value.records = {}; break;
        case "conflicts": value.conflictingIDs = {}; break;
        case "excluded": value.excludedCount = "0"; break;
        case "partial": value.partial = 0; break;
        case "manyRecords": value.records = new Array(50001).fill(null); break;
        case "manyConflicts": value.conflictingIDs = new Array(50001).fill("a".repeat(64)); break;
        }
        compare(decode(value).outcome, "unsupported");
    }
    function test_schemaMismatchIsDistinctFromMalformedData() {
        var value = ledger();
        value.schemaVersion = 3;
        compare(decode(value).outcome, "schemaMismatch");
        value = remotePayload2();
        value.reports[1].ledger.schemaVersion = 3;
        compare(decode(value, "build@host").outcome, "schemaMismatch");
        value.reports[1].ledger = ledger();
        compare(decode(value, "build@host").outcome, "schemaMismatch");
    }
    function test_schema2OptionalPricingMetadata() {
        var value = ledger2();
        value.records[0].model = null;
        delete value.records[0].pricingMode;
        delete value.records[1].model;
        value.records[1].pricingMode = null;
        value.records[1].includedInPlan = true;
        compare(decode(value).outcome, "data");
        value.records[0].pricingMode = "priority";
        compare(decode(value).outcome, "data");
    }
    function test_schema1IgnoresSchema2PricingFields() {
        var value = ledger();
        value.records[0].model = {};
        value.records[0].pricingMode = "unknown";
        value.records[0].includedInPlan = "unknown";
        var result = decode(value);
        compare(result.outcome, "data");
        compare(result.snapshot.totalTokens, 320);
        compare(result.snapshot.apiEstimateUSD, null);
    }
    function test_reportFailurePrecedence_data() {
        return [{tag: "malformed-first", expected: "unsupported"},
            {tag: "error-before-schema", expected: "unsupported"},
            {tag: "source-before-schema", expected: "unsupported"},
            {tag: "mixed-before-metadata", expected: "schemaMismatch"},
            {tag: "matching-missing-metadata", expected: "unsupported"}];
    }
    function test_reportFailurePrecedence(data) {
        var value = remotePayload2();
        switch (data.tag) {
        case "malformed-first":
            value.reports[0].ledger.records[0].inputTokens = -1;
            value.reports[1].ledger.schemaVersion = 3;
            break;
        case "error-before-schema":
            value.reports[1].error = "unavailable";
            value.reports[1].ledger.schemaVersion = 3;
            break;
        case "source-before-schema":
            value.reports[1].source = "local";
            value.reports[1].ledger.schemaVersion = 3;
            break;
        case "mixed-before-metadata":
            value.reports[0].ledger = ledger();
            delete value.reports[1].source;
            break;
        case "matching-missing-metadata":
            delete value.reports[1].source;
            break;
        }
        compare(decode(value, "build@host").outcome, data.expected);
    }
    function test_conflictingRowsStillObeyCountBounds() {
        var value = ledger();
        value.conflictingIDs = ["a".repeat(64), "b".repeat(64)];
        value.records[0].inputTokens = 9007199254740981;
        compare(decode(value).outcome, "unsupported");
        value.records[0].inputTokens = "100";
        compare(decode(value).outcome, "unsupported");
        value.records[0].inputTokens = 100;
        value.records[0].cacheReadTokens = -1;
        compare(decode(value).outcome, "unsupported");
    }
    function test_invalidSchema2Fields_data() {
        return ["model", "emptyModel", "longModel", "mode", "included", "missingIncluded",
            "source", "collectedAt", "priceString", "priceNegative", "priceOverflow", "missingPrice",
            "missingUnpriced", "negativeUnpriced", "fractionalUnpriced", "tooManyUnpriced", "pricedUnknown",
            "unpricedWithoutUnknown"].map(function(tag) { return {tag: tag}; });
    }
    function test_invalidSchema2Fields(data) {
        var value = remotePayload2();
        var record = value.reports[0].ledger.records[0];
        switch (data.tag) {
        case "model": record.model = {}; break;
        case "emptyModel": record.model = ""; break;
        case "longModel": record.model = "x".repeat(1025); break;
        case "mode": record.pricingMode = "fast"; break;
        case "included": record.includedInPlan = 1; break;
        case "missingIncluded": delete record.includedInPlan; break;
        case "source": value.reports[1].source = "local"; break;
        case "collectedAt": value.reports[0].collectedAt = "bad date"; break;
        case "priceString": value.subtotal.costUSD = "0.5"; break;
        case "priceNegative": value.subtotal.costUSD = -1; break;
        case "priceOverflow": value.subtotal.costUSD = 9007199254740992; break;
        case "missingPrice": delete value.subtotal.costUSD; break;
        case "missingUnpriced": delete value.subtotal.unpricedRequestCount; break;
        case "negativeUnpriced": value.subtotal.unpricedRequestCount = -1; break;
        case "fractionalUnpriced": value.subtotal.unpricedRequestCount = 0.5; break;
        case "tooManyUnpriced": value.subtotal.unpricedRequestCount = 4; break;
        case "pricedUnknown": value.subtotal.unpricedRequestCount = 1; break;
        case "unpricedWithoutUnknown": value.subtotal.costUSD = null; break;
        }
        compare(decode(value, "build@host").outcome, "unsupported");
    }
    function test_schema2RemoteFailureRetainsLocalTokensAndCliEstimate() {
        var value = remotePayload2();
        value.reports[1] = {host: "build@host", source: "ssh", error: "SECRET schema 2 SSH failure"};
        value.allSourcesAvailable = false;
        value.partial = true;
        value.subtotal.totalTokens = 320;
        value.subtotal.requestCount = 2;
        var result = decode(value, "build@host", 1);
        compare(result.outcome, "data");
        compare(result.snapshot.totalTokens, 320);
        compare(result.snapshot.apiEstimateUSD, 0.0125);
        verify(result.snapshot.localAvailable && !result.snapshot.remoteAvailable);
        verify(!result.snapshot.requestsPartial && result.snapshot.partial);
        verify(JSON.stringify(result).indexOf("SECRET") === -1);
    }
    function test_cliOwnsRemoteDeduplicationAndConflicts() {
        var value = remotePayload();
        var result = decode(value, "build@host").snapshot;
        compare(result.totalTokens, 630);
        compare(result.requestCount, 3);
        verify(result.remoteRequested && result.remoteAvailable && result.localAvailable);
        value.reports[1].ledger.records[0].inputTokens++;
        value.subtotal = subtotal(520, 2);
        value.subtotal.conflictCount = 1;
        value.subtotal.partial = true;
        value.partial = true;
        result = decode(value, "build@host").snapshot;
        compare(result.totalTokens, 520);
        verify(result.requestsPartial && result.allSourcesAvailable);
    }
    function test_sourceFailurePreservesUsefulData_data() { return [{tag: "local", index: 0, tokens: 420}, {tag: "remote", index: 1, tokens: 320}]; }
    function test_sourceFailurePreservesUsefulData(data) {
        var value = remotePayload();
        value.reports[data.index] = {host: data.index === 0 ? "local" : "build@host", error: "SECRET RAW ERROR"};
        value.allSourcesAvailable = false;
        value.partial = true;
        value.subtotal = subtotal(data.tokens, 2);
        var result = decode(value, "build@host", 1);
        compare(result.outcome, "data");
        compare(result.snapshot.totalTokens, data.tokens);
        verify(result.snapshot.partial && !result.snapshot.requestsPartial && !result.snapshot.allSourcesAvailable);
        compare(result.snapshot.localAvailable, data.index !== 0);
        compare(result.snapshot.remoteAvailable, data.index !== 1);
        verify(JSON.stringify(result).indexOf("SECRET") === -1);
        compare(decode(value, "build@host", 0).outcome, "unsupported");
    }
    function test_unavailableEnvelopeMayOmitSubtotal() {
        var value = {reports: [{host: "local", error: "unavailable"}], allSourcesAvailable: false, partial: true};
        compare(decode(value, "", 1).outcome, "unavailable");
        value.subtotal = null;
        compare(decode(value, "", 1).outcome, "unavailable");
        value.reports.push({host: "build@host", error: "unavailable"});
        compare(decode(value, "build@host", 1).outcome, "unavailable");
    }
    function test_retainedSubtotalMustMatchItsSingleSource() {
        var value = remotePayload();
        value.reports[1] = {host: "build@host", error: "unavailable"};
        value.allSourcesAvailable = false;
        value.partial = true;
        value.subtotal = subtotal(100, 1);
        compare(decode(value, "build@host", 1).outcome, "unsupported");
    }
    function test_badEnvelope_data() {
        return ["host", "order", "reports", "availability", "partial", "price", "missingPrice", "tokens", "requests",
            "excluded", "quality", "ledger", "errorAndLedger", "noSubtotal"].map(function(tag) { return {tag: tag}; });
    }
    function test_badEnvelope(data) {
        var value = remotePayload();
        switch (data.tag) {
        case "host": value.reports[1].host = "other"; break;
        case "order": value.reports.reverse(); break;
        case "reports": value.reports.push(value.reports[0]); break;
        case "availability": value.allSourcesAvailable = false; break;
        case "partial": value.partial = true; break;
        case "price": value.subtotal.costUSD = 0; break;
        case "missingPrice": delete value.subtotal.costUSD; break;
        case "tokens": value.subtotal.totalTokens = 9999; break;
        case "requests": value.subtotal.requestCount = 9; break;
        case "excluded": value.subtotal.excludedCount = 1; break;
        case "quality": value.subtotal.partial = true; value.partial = true; break;
        case "ledger": value.reports[1].ledger.records[0].inputTokens = {}; break;
        case "errorAndLedger": value.reports[1].error = "error"; break;
        case "noSubtotal": delete value.subtotal; break;
        }
        compare(decode(value, "build@host").outcome, "unsupported");
    }
    function test_transportAndBounds() {
        compare(Identified.decode(" ".repeat(SafeText.maximumCliJsonLength + 1), 0, plan()).outcome, "tooLarge");
        compare(Identified.decode("{", 0, plan()).outcome, "invalidJson");
        compare(Identified.decode({}, 0, plan()).outcome, "empty");
        compare(Identified.decode("", 0, plan()).outcome, "empty");
        compare(decode(ledger(), "", 127).outcome, "commandUnavailable");
        compare(decode(ledger(), "", 137).outcome, "timeout");
        compare(decode(ledger(), "", 255).outcome, "unsupported");
        compare(decode(ledger(), "", 1).outcome, "unsupported");
        compare(decode(ledger(), "build@host").outcome, "unsupported");
        compare(decode(remotePayload()).outcome, "unsupported");
        compare(decode(ledger(), "", "").outcome, "unsupported");
        compare(decode(ledger(), "", [0]).outcome, "unsupported");
    }
}
