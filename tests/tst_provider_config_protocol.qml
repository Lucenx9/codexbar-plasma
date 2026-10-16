import QtQuick
import QtTest
import "../contents/ui/config/ProviderConfigProtocol.js" as ProviderConfigProtocol
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "ProviderConfigProtocol"

    function commandResponse(payload, stderrText, exitCode) {
        return ProviderConfigProtocol.response(payload === undefined ? "" : JSON.stringify(payload),
            stderrText, exitCode, "command")
    }

    function diagnosticResponse(payload, stderrText, exitCode) {
        return ProviderConfigProtocol.response(JSON.stringify(payload), stderrText, exitCode, "diagnostic")
    }

    function repeated(value, count) {
        var values = []
        for (var i = 0; i < count; i++) {
            values.push(value)
        }
        return values
    }

    function test_rawRepliesBoundAndRedactParserErrors() {
        var secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890"
        var oversized = "x".repeat(SafeText.maximumCliJsonLength + 1)
        for (var kind of ["list", "enabledRoster", "command", "setApiKey", "diagnostic"]) {
            var result = ProviderConfigProtocol.response('{"api_key":"' + secret, "", 0, kind)
            compare(result.outcome, "invalidJson")
            verify(result.value === undefined)
            verify(result.message.indexOf(secret) < 0)
            verify(result.message.length <= SafeText.maximumCliMessageLength)
            result = ProviderConfigProtocol.response(oversized, "", 0, kind)
            compare(result.outcome, "tooLarge")
            verify(result.value === undefined)
            compare(result.message, "")
        }
        compare(ProviderConfigProtocol.response("{}", "", 0, "unknown").outcome, "invalidPayload")
        for (var value of [[], {}, {toString: null}]) {
            for (var kind of ["list", "enabledRoster", "command", "setApiKey", "diagnostic"]) {
                var malformed = ProviderConfigProtocol.response(value, "", 0, kind)
                compare(malformed.outcome, "invalidPayload")
                verify(malformed.value === undefined)
            }
        }
    }

    function test_rawRepliesPreserveCommandSpecificEmptyAndParsePrecedence() {
        compare(ProviderConfigProtocol.response("[]", "", 0, "list").outcome, "success")
        compare(ProviderConfigProtocol.response("[]", "", 0, "command").outcome, "invalidPayload")
        compare(ProviderConfigProtocol.response("", "", 124, "list").outcome, "empty")
        compare(ProviderConfigProtocol.response("", "", 124, "command").outcome, "timeout")
        compare(ProviderConfigProtocol.response("", "", 124, "diagnostic").outcome, "timeout")
        compare(ProviderConfigProtocol.response("{", "failed", 7, "list").outcome, "invalidJson")
        var enabled = ProviderConfigProtocol.response("{", "failed", 7, "enabledRoster")
        compare(enabled.outcome, "exitCodeError")
        compare(enabled.message, "failed")
        compare(enabled.exitCode, 7)
        verify(enabled.value === undefined)
    }

    function test_missingExitCodesFailClosed() {
        var payload = JSON.stringify([{provider: "codex", enabled: true}])
        for (var exitCode of [NaN, null, "", "x", [0]]) {
            compare(ProviderConfigProtocol.response("", "", exitCode, "setApiKey").outcome, "exitCodeError")
            compare(ProviderConfigProtocol.response(payload, "", exitCode, "enabledRoster").outcome, "exitCodeError")
        }
        compare(ProviderConfigProtocol.response("", "", "0", "setApiKey").outcome, "success")
        compare(ProviderConfigProtocol.response(payload, "", "0", "enabledRoster").outcome, "success")
    }

    function test_fullAndEnabledRosterProfilesKeepTheirRecordContracts() {
        var payload = JSON.stringify([
            {provider: "codex", enabled: true, displayName: "Codex"},
            {provider: "claude", enabled: false},
            {provider: "future", enabled: true}
        ])
        for (var kind of ["list", "enabledRoster"]) {
            var result = ProviderConfigProtocol.response(payload, "loader noise", 0, kind,
                function(provider) { return "Fallback " + provider })
            compare(result.outcome, "success")
            compare(result.value.length, 3)
            compare(result.value[1].displayName, "Fallback claude")
            verify(!result.value[1].enabled)
            var failed = ProviderConfigProtocol.response(payload, "", 7, kind)
            compare(failed.outcome, "exitCodeError")
            verify(failed.value === undefined)
        }
        var mixed = '[null,{"provider":"codex","enabled":true}]'
        compare(ProviderConfigProtocol.response(mixed, "", 0, "list").outcome, "invalidPayload")
        compare(ProviderConfigProtocol.response(mixed, "", 0, "enabledRoster").value.length, 1)
        payload = JSON.stringify(repeated({provider: "codex", enabled: true}, 300))
        compare(ProviderConfigProtocol.response(payload, "", 0, "list").outcome, "invalidPayload")
        compare(ProviderConfigProtocol.response(payload, "", 0, "enabledRoster").value.length, 256)
    }

    function test_successfulDiagnosticReturnsOnlyItsDisplayProjection() {
        var payload = {provider: "codex", auth: {configured: true, apiKey: "private"},
            settings: {workspace: "private"}, fetchAttempts: [{headers: "private"}]}
        var result = ProviderConfigProtocol.response(JSON.stringify(payload), "", 0, "diagnostic")
        compare(result.outcome, "success")
        compare(result.value.provider, "codex")
        verify(result.value.authConfigured)
        compare(result.value.settingsKeys, "workspace")
        compare(result.value.fetchAttempts, 1)
        verify(JSON.stringify(result.value).indexOf("private") < 0)
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
                    writeCommand: [
                        "codexbar", "config", "set", "--value", "{value}"
                    ]
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

    function test_providerListReportsOnlyValidatedDescriptorSupport() {
        var withoutDescriptors = ProviderConfigProtocol.normalizeProviderList([
            provider("codex"),
            provider("claude", { descriptor: { schemaVersion: 2 } })
        ])
        verify(!ProviderConfigProtocol.providerListHasSupportedDescriptors(
            withoutDescriptors))

        var withEmptyDescriptor = ProviderConfigProtocol.normalizeProviderList(
            provider("codex", { descriptor: {
                schemaVersion: 1,
                fields: [],
                actions: []
            } }))
        verify(ProviderConfigProtocol.providerListHasSupportedDescriptors(
            withEmptyDescriptor))
    }

    function test_cliVersionComparisonGatesVersionedCapabilities() {
        verify(ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.54.0", 0, 54, 0))
        verify(ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.56.2\n", 0, 54, 0))
        // Self-built and distro CLI builds decorate the release version with
        // build metadata or revision suffixes; the gate must still read it.
        verify(ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.56.2+g4b1c2d", 0, 54, 0))
        verify(ProviderConfigProtocol.cliVersionAtLeast(
            "codexbar 0.54.1-1", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.54.0-rc2", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.53.9+dev", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.53.9-1", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast(
            "CodexBar 0.53.9", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast(
            "unknown", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast(
            { version: "0.56.2" }, 0, 54, 0))
    }

    function test_cliVersionDistinguishesPrereleasesFromReleaseBuilds() {
        var prereleases = ["-rc2", "-alpha.1", "-beta.2+build", "~rc1", "-1~rc1"]
        for (var i = 0; i < prereleases.length; i++) {
            verify(!ProviderConfigProtocol.cliVersionAtLeast(
                "CodexBar 0.54.0" + prereleases[i], 0, 54, 0))
            verify(ProviderConfigProtocol.cliVersionAtLeast(
                "CodexBar 0.54.1" + prereleases[i], 0, 54, 0))
        }
        var releases = ["", "+g4b1c2d", "-1", "-1ubuntu1"]
        for (var j = 0; j < releases.length; j++) {
            verify(ProviderConfigProtocol.cliVersionAtLeast(
                "CodexBar 0.54.0" + releases[j], 0, 54, 0))
        }
        verify(!ProviderConfigProtocol.cliVersionAtLeast("0.54.0.1", 0, 54, 0))
        verify(!ProviderConfigProtocol.cliVersionAtLeast("0.54.0-", 0, 54, 0))
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

    function test_commandResponseTreatsHealthyEnvelopeAsSuccessDespiteStderr() {
        var loaderNoise = "/usr/lib/x86_64-linux-gnu/libcurl.so.4:"
            + " no version information available"
            + " (required by /usr/local/bin/codexbar)"
        var result = commandResponse(
            { provider: "codex", enabled: true }, loaderNoise, 0)
        compare(result.outcome, "success")
        compare(result.value.provider, "codex")
        compare(commandResponse(
            [{ provider: "codex", enabled: false }], loaderNoise, 0).outcome, "success")
        verify(commandResponse({}, loaderNoise, 0).outcome === "success")
    }

    function test_commandResponseRejectsUnsupportedPayloadShapes() {
        var inputs = [null, true, 1, "ok", [], [{ provider: "codex" }, "bad"]]
        inputs.push(repeated({}, ProviderConfigProtocol.maximumProviderItems + 1))
        for (var i = 0; i < inputs.length; i++) {
            compare(commandResponse(inputs[i], "", 0).outcome,
                "invalidPayload")
        }
    }

    function test_commandResponsePrefersTheCliEnvelopeOverStderrAndExitCodes() {
        var secret = "sk-abcdefghijklmnop"
        var result = commandResponse(
            { error: { message: "Authorization: Bearer " + secret } },
            "token=" + secret + " ambient noise",
            1)
        compare(result.outcome, "envelopeError")
        compare(result.message.indexOf(secret), -1)
        verify(result.message.indexOf("[redacted]") !== -1)
        verify(result.message.length <= 500)
    }

    function test_commandResponseRejectsErrorsWithoutReadableMessages_data() {
        return [
            {tag: "missing", error: {}},
            {tag: "empty", error: {message: ""}},
            {tag: "whitespace", error: {message: "   "}},
            {tag: "object", error: {message: {detail: "failed"}}},
            {tag: "array", error: {message: ["failed"]}},
            {tag: "null-toString", error: {message: {toString: null}}}
        ]
    }

    function test_commandResponseRejectsErrorsWithoutReadableMessages(data) {
        var payload = {provider: "codex", error: data.error}
        var result = commandResponse(payload, "", 0)
        compare(result.outcome, "envelopeError")
        compare(result.message, "")
        compare(ProviderConfigProtocol.response(JSON.stringify(payload), "", 0, "setApiKey").outcome, "envelopeError")
        compare(commandResponse([payload], "", 0).outcome,
            "envelopeError")
    }

    function test_commandResponseClassifiesCancellationOnACleanExit() {
        var cases = [
            { cancelled: true },
            { status: "cancelled" },
            { status: "Canceled" }
        ]
        for (var i = 0; i < cases.length; i++) {
            var result = commandResponse(cases[i], "", 0)
            compare(result.outcome, "cancelled")
            verify(result.value === undefined)
        }
    }

    function test_commandResponseClassifiesStatusFlaggedFailures() {
        var failed = commandResponse(
            { status: "failed", message: "token=" + "sk-abcdefghijklmnop" }, "", 0)
        compare(failed.outcome, "statusError")
        verify(failed.message.indexOf("[redacted]") !== -1)

        var bare = commandResponse({ status: "error" }, "", 0)
        compare(bare.outcome, "statusError")
        compare(bare.message, "")
    }

    function test_commandResponseRejectsUnknownDescriptorStatuses() {
        var statuses = ["queued", "unknown", "", null, true]
        for (var i = 0; i < statuses.length; i++) {
            var result = commandResponse(
                { status: statuses[i] }, "", 0)
            compare(result.outcome, "invalidPayload")
        }

        compare(commandResponse(
            { status: "ok" }, "", 0).outcome, "success")
    }

    function test_commandResponseRejectsStatusBearingArrays() {
        var payloads = [
            [{ status: "queued" }],
            [{ provider: "codex" }, { status: "ok" }]
        ]
        for (var i = 0; i < payloads.length; i++) {
            compare(commandResponse(
                payloads[i], "", 0).outcome, "invalidPayload")
        }
    }

    function test_commandResponseRejectsStructuredDescriptorStatuses() {
        var statuses = [["ok"], ["cancelled"], ["error"], { value: "ok" }]
        for (var i = 0; i < statuses.length; i++) {
            compare(commandResponse(
                { status: statuses[i] }, "", 0).outcome, "invalidPayload")
        }
    }

    function test_commandResponseKeepsHistoricalFailurePrecedence() {
        compare(commandResponse({ provider: "x" }, "", 124).outcome,
            "timeout")
        compare(commandResponse({ provider: "x" },
            "ambient stderr", 137).outcome, "stderrError")
        var exited = commandResponse({ provider: "x" }, "", 3)
        compare(exited.outcome, "exitCodeError")
        compare(exited.exitCode, 3)

        compare(commandResponse(
            { cancelled: true }, "ambient stderr", 0).outcome, "stderrError")
        compare(commandResponse(
            { cancelled: true }, "", 7).outcome, "exitCodeError")
        compare(commandResponse(
            { status: "failed" }, "ambient stderr", 0).outcome, "stderrError")
        compare(commandResponse(
            { status: "failed" }, "", 7).outcome, "exitCodeError")

        // Without a payload, stderr keeps its historical priority over generic
        // exit codes, but a printed-nothing timeout still names the timeout.
        compare(commandResponse(null, "disk full", 7).outcome,
            "stderrError")
        compare(commandResponse(null, "disk full", 124).outcome,
            "stderrError")
        compare(commandResponse(null, "", 9).outcome, "exitCodeError")
        compare(commandResponse(null, "", 124).outcome, "timeout")
        compare(commandResponse(null, "", 0).outcome, "invalidPayload")
        compare(commandResponse(undefined, "", 0).outcome, "empty")
    }

    function test_setApiKeyAllowsOnlySupportedOrActuallyEmptyOutput() {
        compare(ProviderConfigProtocol.response('{"provider":"codex"}', "", 0, "setApiKey").outcome, "success")
        var empty = ProviderConfigProtocol.response("", "", 0, "setApiKey")
        compare(empty.outcome, "success")
        verify(empty.value === undefined)
        for (var text of ["null", '"ok"', "[]", "true"]) {
            compare(ProviderConfigProtocol.response(text, "", 0, "setApiKey").outcome, "invalidPayload")
        }
        compare(ProviderConfigProtocol.response("", "", 1, "setApiKey").outcome, "exitCodeError")
        compare(ProviderConfigProtocol.response("", "", 124, "setApiKey").outcome, "timeout")
        compare(ProviderConfigProtocol.response("", "write failed", 0, "setApiKey").outcome, "stderrError")
    }

    function test_commandResponseRedactsTheStandaloneStderrReason() {
        var secret = "sk-abcdefghijklmnop"
        var result = commandResponse(
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

    function test_diagnosticFetchErrorDoesNotFailTheCommand() {
        var report = { schemaVersion: "1.0", provider: "codex", auth: {}, settings: {},
            fetchAttempts: [], error: { category: "unknown", safeDescription: "Fetch failed" } }
        var before = JSON.stringify(report)
        compare(diagnosticResponse(report, "loader warning", 0).outcome, "success")
        compare(diagnosticResponse([report], "", 0).outcome, "success")
        compare(diagnosticResponse(report, "", 3).outcome, "exitCodeError")
        compare(diagnosticResponse(report, "", 124).outcome, "timeout")
        compare(JSON.stringify(report), before)
        // Config writes keep treating the same error field as command failure.
        compare(commandResponse(report, "", 0).outcome, "envelopeError")
    }

    function test_incompleteDiagnosticCannotBypassCommandErrors() {
        var report = { schemaVersion: "1.0", provider: "codex", auth: {}, settings: {},
            fetchAttempts: [], error: {} }
        for (var field of ["schemaVersion", "provider", "auth", "settings", "fetchAttempts"]) {
            var incomplete = JSON.parse(JSON.stringify(report))
            delete incomplete[field]
            compare(diagnosticResponse(incomplete, "", 0).outcome, "envelopeError")
        }
        compare(diagnosticResponse(repeated(report,
            ProviderConfigProtocol.maximumProviderItems + 1), "", 0).outcome, "envelopeError")
        report.status = "failed"
        compare(diagnosticResponse(report, "", 0).outcome, "statusError")
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
