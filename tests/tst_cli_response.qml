import QtQuick
import QtTest
import "../contents/ui/CliResponse.js" as CliResponse
import "../contents/ui/AccountResponse.js" as AccountResponse
import "../contents/ui/CostResponse.js" as CostResponse
import "../contents/ui/UsageResponse.js" as UsageResponse
import "../contents/ui/SessionResponse.js" as SessionResponse
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "CliResponse"

    function failure(provider) {
        return {
            provider: provider,
            error: {
                kind: "provider",
                code: 1,
                message: "Synthetic failure"
            }
        };
    }
    function test_rejectedExitCodes_data() {
        return [undefined, null, "0", "1", false, true, -1, 2, 124, 126, 127, 137, 255, NaN, Infinity].map(function (code, i) {
            return {
                tag: String(i),
                code: code
            };
        });
    }
    function test_rejectedExitCodes(data) {
        var payload = JSON.stringify([failure("codex")]);
        var results = [CliResponse.decode(payload, "", data.code, 256), AccountResponse.response(payload, "", "codex", 1, data.code), CostResponse.response(payload, "", 30, data.code), UsageResponse.response(payload, "", "", 1, data.code), UsageResponse.roster("[]", "", data.code), SessionResponse.response("[]", "", data.code)];
        for (var result of results) {
            compare(result.outcome, "commandFailed");
            compare(Object.keys(result).sort(), ["message", "outcome"]);
        }
    }
    function test_stdoutMustBeText() {
        for (var value of [0, false, [],
            {},
            {
                toString: null
            }
        ])
            compare(CliResponse.decode(value, "", 0, 0).outcome, "invalidJson");
        var throwing = {};
        throwing.toString = function () {
            throw new Error("must not coerce stdout");
        };
        compare(CliResponse.decode(throwing, "", 0, 0).outcome, "invalidJson");
    }
    function test_exitOneNeedsAnErrorWithinTheConsumedRecords() {
        for (var payload of [[],
            {},
            null, 0, [
                {
                    provider: "codex"
                }
            ], [
                {
                    provider: "codex",
                    error: "failed"
                }
            ], [
                {
                    provider: "codex",
                    error: {
                        kind: "provider",
                        code: "1"
                    }
                }
            ], [failure("__proto__")], [
                {
                    provider: "codex",
                    error: {
                        kind: "unexpected",
                        code: 1
                    }
                }
            ]]) {
            compare(CliResponse.decode(JSON.stringify(payload), "", 1, 256).outcome, "commandFailed");
        }
        var payload = JSON.stringify([
            {
                provider: "pi"
            },
            failure("codex")]);
        compare(CliResponse.decode(payload, "", 1, 1).outcome, "commandFailed");
        compare(CliResponse.decode(payload, "", 1, 2).outcome, "success");
        compare(CliResponse.decode(payload, "", 1, 0).outcome, "commandFailed");
        compare(SessionResponse.response(payload, "", 1).outcome, "commandFailed");
        compare(UsageResponse.roster(payload, "", 1).outcome, "commandFailed");
    }
    // docs/cli.md (0.76.0) exit codes: the process exits with the code of its
    // last failed fetch and records that code on the provider's error.
    function test_documentedFailureExitCodesKeepTheirStructuredErrors_data() {
        return [1, 2, 3, 4].map(function (code) {
            return {
                tag: String(code),
                code: code
            };
        });
    }
    function test_documentedFailureExitCodesKeepTheirStructuredErrors(data) {
        var record = failure("codex");
        record.error.code = data.code;
        var text = JSON.stringify([record,
            {
                provider: "pi",
                usage: {
                    primary: {
                        usedPercent: 10
                    }
                }
            }
        ]);
        var usage = UsageResponse.response(text, "", "", 1000, data.code);
        compare(usage.outcome, "success");
        compare(usage.items.length, 2);
        verify(usage.items[0].commandFailed);
        compare(UsageResponse.response(JSON.stringify([record]), "", "codex", 1000, data.code).outcome, "success");
        record.error.code = data.code === 1 ? 2 : 1;
        compare(CliResponse.decode(JSON.stringify([record]), "", data.code, 256).outcome, "commandFailed");
    }
    function test_runtimeAndCostProviderErrorsExplainTheExit() {
        // 0.76.0 Linux: `usage --source web` reports kind "runtime"; cost
        // provider errors carry no kind.
        var web = failure("codex");
        web.error.kind = "runtime";
        web.error.message = "Error: selected source requires web support and is only supported on macOS.";
        var usage = UsageResponse.response(JSON.stringify([web]), "", "codex", 1000, 1);
        compare(usage.outcome, "success");
        verify(usage.items[0].commandFailed);
        var timedOut = {
            provider: "codex",
            error: {
                code: 4,
                message: "Cost scan timed out"
            }
        };
        var cost = CostResponse.response(JSON.stringify([timedOut,
            {
                provider: "pi",
                totals: {
                    totalCost: 2
                }
            }
        ]), "", 30, 4);
        compare(cost.outcome, "partial");
        compare(cost.failedProviders, ["codex"]);
        compare(cost.costs.pi.totals.cost, 2);
        compare(cost.message, "Cost scan timed out");
    }
    function test_cliPseudoProviderExplainsOnlyArgumentErrors() {
        for (var kind of ["config", "runtime", undefined]) {
            var record = {
                provider: "cli",
                error: {
                    code: 1,
                    message: "Whole-command failure"
                }
            };
            if (kind !== undefined)
                record.error.kind = kind;
            compare(CliResponse.decode(JSON.stringify([record]), "", 1, 256).outcome, "commandFailed");
        }
    }
    function test_mixedUsageAndCostKeepHealthySiblings() {
        var text = JSON.stringify([failure("codex"),
            {
                provider: "pi",
                usage: {
                    primary: {
                        usedPercent: 10
                    }
                },
                totals: {
                    totalCost: 2
                }
            }
        ]);
        var usage = UsageResponse.response(text, "", "", 1000, 1);
        compare(usage.outcome, "success");
        compare(usage.items.length, 2);
        verify(usage.items[0].commandFailed);
        compare(usage.items[1].rows[0].usedPercent, 10);
        var cost = CostResponse.response(text, "", 30, 1);
        compare(cost.outcome, "partial");
        compare(cost.failedProviders, ["codex"]);
        compare(cost.costs.pi.totals.cost, 2);
    }
    function test_accountExitOnePreservesMissingAndNamedFailures() {
        var missing = failure("claude");
        missing.error.message = "No token accounts configured for claude.";
        compare(AccountResponse.response(JSON.stringify([missing]), "", "claude", 1, 1).options, []);
        var named = failure("claude");
        named.account = "Work";
        var result = AccountResponse.response(JSON.stringify([named,
            {
                provider: "claude",
                account: "Home"
            }
        ]), "", "claude", 1, 1);
        compare(result.options.length, 2);
        verify(result.options[0].commandFailed);
        compare(result.options[1].accountKey, "Home");
    }
    function test_argumentErrorStillReportsUnsupportedPeriod() {
        var text = JSON.stringify([
            {
                provider: "cli",
                error: {
                    kind: "args",
                    code: 1,
                    message: "Unknown option --period"
                }
            }
        ]);
        var result = CostResponse.response(text, "", 30, 1);
        compare(result.outcome, "commandFailed");
        verify(result.argumentsRejected);
        compare(result.costs, undefined);
    }
    function test_boundedRedactedEnvelope_data() {
        return [
            {
                tag: "missing",
                text: undefined,
                code: 0,
                outcome: "empty"
            },
            {
                tag: "empty-exit-one",
                text: "",
                code: 1,
                outcome: "empty"
            },
            {
                tag: "invalid",
                text: "{",
                code: 0,
                outcome: "invalidJson"
            },
            {
                tag: "large",
                text: "x".repeat(SafeText.maximumCliJsonLength + 1),
                code: 0,
                outcome: "tooLarge"
            },
            {
                tag: "process-failure",
                text: "[]",
                code: 127,
                outcome: "commandFailed"
            }
        ];
    }
    function test_boundedRedactedEnvelope(data) {
        var result = CliResponse.decode(data.text, "Authorization: Bearer synthetic-secret-abcdef\n" + "x".repeat(1000), data.code, 256);
        compare(result.outcome, data.outcome);
        compare(result.payload, undefined);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
        verify(result.message.indexOf("synthetic-secret-abcdef") === -1);
    }
}
