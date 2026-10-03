import QtQuick
import QtTest
import "../contents/ui/AccountResponse.js" as AccountResponse
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "AccountResponse"
    function parse(payload) {
        return AccountResponse.response(JSON.stringify(payload), "", "codex", 1000);
    }
    function test_failuresRetainNoReplacementOptions_data() {
        return [
            {
                tag: "missing",
                text: undefined,
                outcome: "empty"
            },
            {
                tag: "broken",
                text: "{",
                outcome: "invalidJson"
            },
            {
                tag: "unsupported",
                text: "null",
                outcome: "empty"
            },
            {
                tag: "object",
                text: "{}",
                outcome: "empty"
            },
            {
                tag: "large",
                text: " ".repeat(SafeText.maximumCliJsonLength + 1),
                outcome: "tooLarge"
            }
        ];
    }
    function test_failuresRetainNoReplacementOptions(data) {
        var result = AccountResponse.response(data.text, "synthetic error", "codex", 1000);
        compare(result.outcome, data.outcome);
        compare(result.options, undefined);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
    }
    function test_confirmedEmptyAndMissingTokenAccountsClearLists() {
        compare(parse([]).options, []);
        var missing = parse({
            provider: "codex",
            error: {
                message: "No token accounts configured for codex."
            }
        });
        compare(missing.outcome, "success");
        compare(missing.options, []);
    }
    function test_validSiblingsAndNamedErrorsRemainUsable() {
        var result = parse([
            {
                provider: "claude",
                account: "Work  Team",
                usage: {
                    primary: {
                        usedPercent: 0
                    }
                }
            },
            null,
            {
                account: "Work  Team",
                usage: {
                    primary: {
                        usedPercent: 90
                    }
                }
            },
            {
                error: {
                    message: "failed"
                }
            },
            {
                account: "Work Team",
                error: {
                    message: "named failure"
                }
            }
        ]);
        compare(result.outcome, "success");
        compare(result.options.length, 2);
        compare(result.options[0].provider, "codex");
        compare(result.options[0].accountKey, "Work  Team");
        compare(result.options[0].rows[0].usedPercent, 0);
        compare(result.options[1].accountKey, "Work Team");
        verify(result.options[1].commandFailed);
        compare(result.options[0].usageReceivedAtMs, 1000);
    }
    function test_malformedErrorMessageGetsSemanticFailure() {
        var result = parse({
            error: {
                message: {
                    toString: null
                }
            }
        });
        compare(result.outcome, "commandFailed");
        compare(result.message, "");
    }
    function test_failuresAreRedactedAtThePublicBoundary() {
        var secret = "sk-synthetic123456789";
        var stderrResult = AccountResponse.response("", "Authorization: Bearer " + secret, "codex", 1000);
        var recordResult = parse({
            error: {
                message: "api_key=" + secret
            }
        });
        for (var result of [stderrResult, recordResult]) {
            compare(result.options, undefined);
            verify(result.message.indexOf(secret) < 0);
            verify(result.message.indexOf("[redacted]") >= 0);
        }
    }
    function test_duplicateAccountsPreferFirstHealthyRecord_data() {
        var cases = [];
        for (var message of ["failed", "", {toString: null}])
            for (var failedFirst of [true, false])
                for (var used of [0, 42])
                    cases.push({tag: JSON.stringify(message) + "-" + failedFirst + "-" + used,
                        message: message, failedFirst: failedFirst, used: used});
        return cases;
    }
    function test_duplicateAccountsPreferFirstHealthyRecord(data) {
        var healthy = {account: "Synthetic account", usage: {primary: {usedPercent: data.used}}};
        var failed = {account: "Synthetic account", error: {message: data.message}};
        var records = data.failedFirst ? [failed, healthy] : [healthy, failed];
        records.splice(1, 0, {account: "Other account", error: {message: "Other failure"}});
        // Later healthy and failed duplicates must not replace the first healthy record.
        records.push({account: "Synthetic account", usage: {primary: {usedPercent: 99}}}, failed);
        var result = parse(records);
        compare(result.outcome, "success");
        compare(result.options.length, 2);
        compare(result.options[0].accountKey, "Synthetic account");
        compare(result.options[0].commandFailed, false);
        compare(result.options[0].rows[0].usedPercent, data.used);
        compare(result.options[0].usageReceivedAtMs, 1000);
        compare(result.options[1].accountKey, "Other account");
        compare(result.options[1].commandFailed, true);
    }
    function test_failedDuplicatesKeepFirstErrorAndDistinctKeys() {
        var result = parse([
            {account: "Work  Team", error: {message: "First failure"}},
            {account: "Work Team", usage: {primary: {usedPercent: 0}}},
            {account: "Work  Team", error: {message: "Later failure"}}
        ]);
        compare(result.outcome, "success");
        compare(result.options.map(function(item) { return item.accountKey; }), ["Work  Team", "Work Team"]);
        compare(result.options[0].error, "First failure");
        compare(result.options[1].rows[0].usedPercent, 0);
    }
    function test_recordExceptionsAreContained() {
        var bad = {};
        Object.defineProperty(bad, "usage", {
            enumerable: true,
            get: function () {
                throw new Error("synthetic record failure");
            }
        });
        var result = AccountResponse.records([
            {
                account: "before"
            },
            bad,
            {
                account: "after"
            }
        ], "codex", 1000);
        compare(result.outcome, "success");
        compare(result.options.map(function (item) {
            return item.accountKey;
        }), ["before", "after"]);
        result = AccountResponse.records([bad], "codex", 1000);
        compare(result.outcome, "recordError");
        compare(result.options, undefined);
    }
    function test_recordBoundsAndSafeProviderKeys() {
        var items = [];
        for (var i = 0; i < 1000; i++)
            items.push({
                account: "account " + i
            });
        compare(parse(items).options.length, Normalizer.maximumAccountSnapshots);
        compare(AccountResponse.records(items, "__proto__", 1000).outcome, "empty");
    }
}
