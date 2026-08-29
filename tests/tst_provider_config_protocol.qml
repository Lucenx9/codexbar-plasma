import QtQuick
import QtTest
import "../contents/ui/config/ProviderConfigProtocol.js" as ProviderConfigProtocol

TestCase {
    name: "ProviderConfigProtocol"

    function repeated(value, count) {
        var values = []
        for (var i = 0; i < count; i++) {
            values.push(value)
        }
        return values
    }

    function provider(providerID, overrides) {
        var item = {
            provider: providerID,
            displayName: "Provider " + providerID,
            enabled: false,
            defaultEnabled: false
        }
        if (overrides) {
            for (var key in overrides) {
                item[key] = overrides[key]
            }
        }
        return item
    }

    function test_publishesRenderWorkBounds() {
        compare(ProviderConfigProtocol.maximumProviderItems, 256)
        compare(ProviderConfigProtocol.maximumDiagnosticListItems, 64)
    }

    function test_providerListResultRequiresTheRevisionItStartedWith() {
        verify(ProviderConfigProtocol.providerListResultIsCurrent(
            { providerConfigRevision: 7 }, 7))
        verify(!ProviderConfigProtocol.providerListResultIsCurrent(
            { providerConfigRevision: 7 }, 8))
        verify(!ProviderConfigProtocol.providerListResultIsCurrent({}, 0))
        verify(!ProviderConfigProtocol.providerListResultIsCurrent(null, 0))
    }

    function test_normalizesSingletonAndPreservesCliProviderSpelling() {
        var seen = []
        var normalized = ProviderConfigProtocol.normalizeProviderList({
            provider: "  groqcloud  ",
            displayName: { malformed: true },
            enabled: 1,
            defaultEnabled: true,
            descriptor: {
                schemaVersion: 1,
                fields: [{
                    id: "workspace",
                    kind: "text",
                    title: "",
                    writeCommand: ["codexbar", "config", "set"]
                }]
            }
        }, function(identifier) {
            seen.push(identifier)
            return "Fallback " + identifier
        })

        compare(normalized.length, 1)
        compare(normalized[0].provider, "groqcloud")
        compare(normalized[0].displayName, "Fallback groqcloud")
        verify(!normalized[0].enabled)
        verify(normalized[0].defaultEnabled)
        compare(normalized[0].descriptor.fields.length, 1)
        compare(normalized[0].descriptor.fields[0].title, "Fallback workspace")
        compare(seen.join(","), "groqcloud,workspace")
    }

    function test_acceptsArraysSkipsMalformedRowsAndPreservesDuplicates() {
        var oversized = repeated("x", 129).join("")
        var normalized = ProviderConfigProtocol.normalizeProviderList([
            null,
            [],
            "codex",
            provider(""),
            provider("constructor"),
            provider("bad\u0007id"),
            provider(oversized),
            provider("future/provider:v2", { enabled: true }),
            provider("codex"),
            provider("codex")
        ], function(identifier) { return identifier })

        compare(normalized.length, 3)
        compare(normalized[0].provider, "future/provider:v2")
        verify(normalized[0].enabled)
        compare(normalized[1].provider, "codex")
        compare(normalized[2].provider, "codex")
    }

    function test_providerCapAppliesToInputPositionsBeforeFiltering() {
        var payload = repeated(null, ProviderConfigProtocol.maximumProviderItems)
        payload.push(provider("codex"))

        compare(ProviderConfigProtocol.normalizeProviderList(payload).length, 0)
    }

    function test_boundsDisplayNamesAndUsesProviderIdWithoutResolver() {
        var normalized = ProviderConfigProtocol.normalizeProviderList(provider("codex", {
            displayName: repeated("n", 140).join("")
        }))
        compare(normalized[0].displayName.length, 120)

        normalized = ProviderConfigProtocol.normalizeProviderList(provider("codex", {
            displayName: null
        }))
        compare(normalized[0].displayName, "codex")
    }

    function test_commandErrorReadsOnlyFirstEnvelope() {
        compare(ProviderConfigProtocol.commandError([
            { value: true },
            { error: { message: "later failure" } }
        ]), "")
        compare(ProviderConfigProtocol.commandError([
            { error: { message: "first failure" } },
            { error: { message: "later failure" } }
        ]), "first failure")
        compare(ProviderConfigProtocol.commandError({ error: { message: "single failure" } }),
            "single failure")
    }

    function test_commandErrorRedactsAndBoundsCliText() {
        var secret = "sk-abcdefghijklmnop"
        var message = ProviderConfigProtocol.commandError({ error: {
            message: "Authorization: Bearer " + secret + " " + repeated("x", 800).join("")
        } })

        compare(message.indexOf(secret), -1)
        verify(message.indexOf("[redacted]") !== -1)
        verify(message.length <= 500)
    }

    function test_commandErrorRejectsAbsentOrMalformedEnvelopes() {
        var inputs = [null, undefined, {}, [], false, { error: {} }, { error: { message: "" } }]
        for (var i = 0; i < inputs.length; i++) {
            compare(ProviderConfigProtocol.commandError(inputs[i]), "")
        }
    }

    function test_commandOutcomeTreatsHealthyEnvelopeAsSuccessDespiteStderr() {
        var loaderNoise = "/usr/lib/x86_64-linux-gnu/libcurl.so.4:"
            + " no version information available"
            + " (required by /usr/local/bin/codexbar)"
        var result = ProviderConfigProtocol.commandOutcome(
            { provider: "codex", enabled: true }, loaderNoise, 0)
        compare(result.outcome, "success")
        verify(result.value === undefined)
        compare(ProviderConfigProtocol.commandOutcome(
            [{ provider: "codex", enabled: false }], loaderNoise, 0).outcome, "success")
        verify(ProviderConfigProtocol.commandOutcome({}, loaderNoise, 0).outcome === "success")
    }

    function test_commandOutcomeRejectsUnsupportedPayloadShapes() {
        var inputs = [null, true, 1, "ok", [], [{ provider: "codex" }, "bad"]]
        inputs.push(repeated({}, ProviderConfigProtocol.maximumProviderItems + 1))
        for (var i = 0; i < inputs.length; i++) {
            compare(ProviderConfigProtocol.commandOutcome(inputs[i], "", 0).outcome,
                "invalidPayload")
        }
    }

    function test_commandOutcomePrefersTheCliEnvelopeOverStderrAndExitCodes() {
        var secret = "sk-abcdefghijklmnop"
        var result = ProviderConfigProtocol.commandOutcome(
            { error: { message: "Authorization: Bearer " + secret } },
            "token=" + secret + " ambient noise",
            1)
        compare(result.outcome, "envelopeError")
        compare(result.message.indexOf(secret), -1)
        verify(result.message.indexOf("[redacted]") !== -1)
        verify(result.message.length <= 500)
    }

    function test_commandOutcomeClassifiesCancellationOnACleanExit() {
        var cases = [
            { cancelled: true },
            { status: "cancelled" },
            { status: "Canceled" }
        ]
        for (var i = 0; i < cases.length; i++) {
            var result = ProviderConfigProtocol.commandOutcome(cases[i], "", 0)
            compare(result.outcome, "cancelled")
            verify(result.value === undefined)
        }
    }

    function test_commandOutcomeClassifiesStatusFlaggedFailures() {
        var failed = ProviderConfigProtocol.commandOutcome(
            { status: "failed", message: "token=" + "sk-abcdefghijklmnop" }, "", 0)
        compare(failed.outcome, "statusError")
        verify(failed.message.indexOf("[redacted]") !== -1)

        var bare = ProviderConfigProtocol.commandOutcome({ status: "error" }, "", 0)
        compare(bare.outcome, "statusError")
        compare(bare.message, "")
    }

    function test_commandOutcomeRejectsUnknownDescriptorStatuses() {
        var statuses = ["queued", "unknown", "", null, true]
        for (var i = 0; i < statuses.length; i++) {
            var result = ProviderConfigProtocol.commandOutcome(
                { status: statuses[i] }, "", 0)
            compare(result.outcome, "invalidPayload")
        }

        compare(ProviderConfigProtocol.commandOutcome(
            { status: "ok" }, "", 0).outcome, "success")
    }

    function test_commandOutcomeKeepsHistoricalFailurePrecedence() {
        compare(ProviderConfigProtocol.commandOutcome({ provider: "x" }, "", 124).outcome,
            "timeout")
        compare(ProviderConfigProtocol.commandOutcome({ provider: "x" },
            "ambient stderr", 137).outcome, "stderrError")
        var exited = ProviderConfigProtocol.commandOutcome({ provider: "x" }, "", 3)
        compare(exited.outcome, "exitCodeError")
        compare(exited.exitCode, 3)

        compare(ProviderConfigProtocol.commandOutcome(
            { cancelled: true }, "ambient stderr", 0).outcome, "stderrError")
        compare(ProviderConfigProtocol.commandOutcome(
            { cancelled: true }, "", 7).outcome, "exitCodeError")
        compare(ProviderConfigProtocol.commandOutcome(
            { status: "failed" }, "ambient stderr", 0).outcome, "stderrError")
        compare(ProviderConfigProtocol.commandOutcome(
            { status: "failed" }, "", 7).outcome, "exitCodeError")

        // Without a payload, stderr keeps its historical priority over generic
        // exit codes, but a printed-nothing timeout still names the timeout.
        compare(ProviderConfigProtocol.commandOutcome(null, "disk full", 7).outcome,
            "stderrError")
        compare(ProviderConfigProtocol.commandOutcome(null, "disk full", 124).outcome,
            "stderrError")
        compare(ProviderConfigProtocol.commandOutcome(null, "", 9).outcome, "exitCodeError")
        compare(ProviderConfigProtocol.commandOutcome(null, "", 124).outcome, "timeout")
        compare(ProviderConfigProtocol.commandOutcome(null, "", 0).outcome, "invalidPayload")
        compare(ProviderConfigProtocol.commandOutcome(undefined, "", 0).outcome, "empty")
    }

    function test_setApiKeyAllowsOnlySupportedOrActuallyEmptyOutput() {
        verify(ProviderConfigProtocol.setApiKeyOutcomeIsSuccess(
            ProviderConfigProtocol.commandOutcome({ provider: "codex" }, "", 0)))
        verify(ProviderConfigProtocol.setApiKeyOutcomeIsSuccess(
            ProviderConfigProtocol.commandOutcome(undefined, "", 0)))
        verify(!ProviderConfigProtocol.setApiKeyOutcomeIsSuccess(
            ProviderConfigProtocol.commandOutcome(null, "", 0)))
        verify(!ProviderConfigProtocol.setApiKeyOutcomeIsSuccess(
            ProviderConfigProtocol.commandOutcome("ok", "", 0)))
    }

    function test_commandOutcomeRedactsTheStandaloneStderrReason() {
        var secret = "sk-abcdefghijklmnop"
        var result = ProviderConfigProtocol.commandOutcome(
            null, "request failed with api_key=" + secret + repeated("y", 700).join(""), 1)
        compare(result.outcome, "stderrError")
        compare(result.message.indexOf(secret), -1)
        verify(result.message.indexOf("[redacted]") !== -1)
        verify(result.message.length <= 500)
    }

    function test_descriptorUnsupportedRecognizesTheCompatibilityPhrases() {
        var phrases = [
            "unknown option", "unknown argument", "unrecognized option",
            "unrecognized argument", "unexpected option", "unexpected argument",
            "unsupported option", "unsupported argument", "invalid option"
        ]
        for (var i = 0; i < phrases.length; i++) {
            var message = phrases[i] + " --descriptors"
            compare(ProviderConfigProtocol.descriptorUnsupportedMessage("", message), message)
            compare(ProviderConfigProtocol.descriptorUnsupportedMessage(
                JSON.stringify({ error: { message: message } }), ""), message)
        }
    }

    function test_descriptorUnsupportedUsesStderrBeforeStructuredStdout() {
        var stdoutText = JSON.stringify({ error: { message: "unknown option descriptor from stdout" } })
        var stderrText = "unsupported argument descriptor from stderr"
        compare(ProviderConfigProtocol.descriptorUnsupportedMessage(stdoutText, stderrText), stderrText)
    }

    function test_descriptorUnsupportedRejectsNearMissesAndMalformedJson() {
        var cases = [
            { stdout: "", stderr: "unknown option --verbose" },
            { stdout: "", stderr: "descriptor request failed" },
            { stdout: "not json", stderr: "" },
            { stdout: JSON.stringify({ error: { message: "unknown option --verbose" } }), stderr: "" },
            { stdout: JSON.stringify({ error: { message: "descriptor request failed" } }), stderr: "" }
        ]
        for (var i = 0; i < cases.length; i++) {
            compare(ProviderConfigProtocol.descriptorUnsupportedMessage(
                cases[i].stdout, cases[i].stderr), "")
        }
    }

    function test_descriptorUnsupportedRedactsTheReturnedMessage() {
        var secret = "sk-abcdefghijklmnop"
        var message = ProviderConfigProtocol.descriptorUnsupportedMessage(
            "", "unknown option descriptor token=" + secret)
        compare(message.indexOf(secret), -1)
        verify(message.indexOf("[redacted]") !== -1)
    }

    function test_normalizesBoundedDiagnosticWithoutRetainingAttempts() {
        var attempts = [{ secret: "one" }, { secret: "two" }, { secret: "three" }]
        var normalized = ProviderConfigProtocol.normalizeProviderDiagnostic({
            provider: "codex",
            displayName: "Codex",
            source: "api",
            sourceMode: "manual",
            auth: { configured: true, modes: ["oauth", "token"] },
            settings: { workspace: true, region: "eu" },
            fetchAttempts: attempts
        })

        compare(normalized.provider, "codex")
        compare(normalized.displayName, "Codex")
        compare(normalized.source, "api")
        compare(normalized.sourceMode, "manual")
        verify(normalized.authConfigured)
        compare(normalized.authModes, "oauth, token")
        compare(normalized.settingsKeys, "region, workspace")
        compare(normalized.fetchAttempts, 3)
        compare(JSON.stringify(normalized).indexOf("secret"), -1)
    }

    function test_diagnosticUsesOnlyFirstArrayItemAndStrictShapes() {
        var normalized = ProviderConfigProtocol.normalizeProviderDiagnostic([
            { provider: "first", auth: { configured: 1 }, settings: [] },
            { provider: "second", auth: { configured: true } }
        ])
        compare(normalized.provider, "first")
        verify(!normalized.authConfigured)
        compare(normalized.settingsKeys, "")

        var empty = ProviderConfigProtocol.normalizeProviderDiagnostic("malformed")
        compare(empty.provider, "")
        compare(empty.displayName, "")
        compare(empty.authModes, "")
        compare(empty.fetchAttempts, 0)
    }

    function test_diagnosticListCapAppliesBeforeFiltering() {
        var modes = repeated("m", ProviderConfigProtocol.maximumDiagnosticListItems)
        modes.push("after-cap")
        var normalized = ProviderConfigProtocol.normalizeProviderDiagnostic({
            auth: { modes: modes }
        })

        compare(normalized.authModes.indexOf("after-cap"), -1)
        compare(normalized.authModes.split(", ").length, 64)
    }

    function test_diagnosticSettingsCapAppliesBeforeSorting() {
        var settings = ({})
        for (var i = 0; i < ProviderConfigProtocol.maximumDiagnosticListItems; i++) {
            settings["z" + (i < 10 ? "0" : "") + i] = true
        }
        settings.aAfterCap = true

        var normalized = ProviderConfigProtocol.normalizeProviderDiagnostic({ settings: settings })
        compare(normalized.settingsKeys.indexOf("aAfterCap"), -1)
        verify(normalized.settingsKeys.indexOf("z00") !== -1)
        verify(normalized.settingsKeys.indexOf("z63") !== -1)
    }

    function test_diagnosticTextIsRedactedAndBounded() {
        var secret = "sk-abcdefghijklmnop"
        var normalized = ProviderConfigProtocol.normalizeProviderDiagnostic({
            source: "token=" + secret + repeated("x", 400).join(""),
            auth: { modes: ["Bearer " + secret] }
        })

        compare(normalized.source.indexOf(secret), -1)
        compare(normalized.authModes.indexOf(secret), -1)
        verify(normalized.source.length <= 120)
        verify(normalized.authModes.length <= 500)
    }
}
