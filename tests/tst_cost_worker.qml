import QtQuick
import QtTest
import "../contents/ui/CostWorkerRequest.mjs" as CostWorkerRequest
import "../contents/ui/SafeText.mjs" as SafeText

TestCase {
    name: "CostWorker"
    property var reply: null

    WorkerScript {
        id: worker
        source: "../contents/ui/CostWorker.mjs"
        onMessage: function (messageObject) {
            reply = messageObject;
        }
    }

    function init() {
        reply = null;
    }

    function test_failureOutcomes_data() {
        return [
            {
                tag: "invalid-json",
                stdout: "{",
                exit: 0,
                outcome: "invalidJson"
            },
            {
                tag: "unsupported",
                stdout: "null",
                exit: 0,
                outcome: "unsupported"
            },
            {
                tag: "empty",
                stdout: "",
                exit: 0,
                outcome: "empty"
            },
            {
                tag: "oversized",
                stdout: " ".repeat(SafeText.maximumCliJsonLength + 100),
                exit: 0,
                outcome: "tooLarge"
            },
            {
                tag: "exit-precedence",
                stdout: " ".repeat(SafeText.maximumCliJsonLength + 100),
                exit: 1,
                outcome: "tooLarge"
            },
            {
                tag: "process-failure",
                stdout: "[]",
                exit: 124,
                outcome: "commandFailed"
            },
            {
                tag: "bad-shape",
                stdout: {
                    nested: [1, 2, 3]
                },
                exit: 0,
                outcome: "invalidJson"
            }
        ];
    }
    function test_failureOutcomes(data) {
        tryCompare(worker, "ready", true);
        var request = CostWorkerRequest.message({
            serial: 9,
            historyDays: 30
        }, data.stdout, "", data.exit);
        if (typeof request.stdoutText === "string")
            verify(request.stdoutText.length <= SafeText.maximumCliJsonLength + 1);
        worker.sendMessage(request);
        tryVerify(function () {
            return reply !== null;
        });
        compare(reply.serial, 9);
        compare(reply.result.outcome, data.outcome);
        compare(reply.result.costs, undefined);
    }

    function test_partialFailureAndUnknownAmountsSurviveTransfer() {
        tryCompare(worker, "ready", true);
        var payload = [
            {
                provider: "codex",
                totals: {
                    totalTokens: 123
                }
            },
            {
                provider: "claude",
                error: {
                    code: 1,
                    message: "synthetic failure"
                }
            }
        ];
        worker.sendMessage(CostWorkerRequest.message({
            serial: 10,
            historyDays: 30
        }, JSON.stringify(payload), "", 1));
        tryVerify(function () {
            return reply !== null;
        });
        compare(reply.result.outcome, "partial");
        compare(reply.result.failedProviders, ["claude"]);
        compare(reply.result.costs.codex.totals.cost, null);
        compare(reply.result.costs.codex.totals.tokens, 123);
    }

    function test_normalizesOffThread() {
        tryCompare(worker, "ready", true);
        worker.sendMessage({
            serial: 7,
            stdoutText: JSON.stringify([
                {
                    provider: "codex",
                    totals: {
                        totalCost: 12,
                        totalTokens: 120
                    }
                }
            ]),
            stderrText: "",
            historyDays: 30,
            exitCode: 0
        });
        compare(reply, null);
        tryVerify(function () {
            return reply !== null;
        });
        compare(reply.serial, 7);
        compare(reply.result.outcome, "success");
        compare(reply.result.costs.codex.totals.cost, 12);
        compare(reply.result.costs.codex.totals.tokens, 120);
    }
}
