import QtQuick
import QtTest
import "../contents/ui/config/ProviderDescriptor.js" as ProviderDescriptor

TestCase {
    name: "ProviderDescriptor"

    function field(overrides) {
        var result = {
            id: "workspace",
            kind: "text",
            title: "Workspace",
            value: "alpha",
            writeCommand: ["codexbar", "config", "set", "--value", "{value}"]
        }
        if (overrides) {
            for (var key in overrides) {
                result[key] = overrides[key]
            }
        }
        return result
    }

    function action(overrides) {
        var result = {
            id: "refresh",
            title: "Refresh",
            command: ["codexbar", "config", "action", "refresh"]
        }
        if (overrides) {
            for (var key in overrides) {
                result[key] = overrides[key]
            }
        }
        return result
    }

    function descriptor(fields, actions) {
        return { schemaVersion: 1, fields: fields || [], actions: actions || [] }
    }

    function repeated(value, count) {
        var values = []
        for (var i = 0; i < count; i++) {
            values.push(value)
        }
        return values
    }

    function test_publishesDescriptorBounds() {
        compare(ProviderDescriptor.maximumFields, 32)
        compare(ProviderDescriptor.maximumActions, 32)
        compare(ProviderDescriptor.maximumOptions, 64)
        compare(ProviderDescriptor.maximumCommandTokens, 64)
        compare(ProviderDescriptor.maximumTokenLength, 2048)
    }

    function test_unknownOrMissingSchemaIsInert() {
        var inputs = [null, undefined, {}, { schemaVersion: 2 }, { schemaVersion: "invalid" }]
        for (var i = 0; i < inputs.length; i++) {
            var normalized = ProviderDescriptor.normalize(inputs[i])
            compare(normalized.schemaVersion, 0)
            compare(normalized.fields.length, 0)
            compare(normalized.actions.length, 0)
        }
    }

    function test_normalizesSupportedFieldsAndActions() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ kind: "text" }),
            field({ id: "apiKey", kind: "secret" }),
            field({ id: "region", kind: "enum", options: [{ id: "eu", title: "Europe" }] }),
            field({ id: "enabled", kind: "boolean", value: false }),
            field({ id: "limit", kind: "number", value: 0 })
        ], [action()]), function(identifier) { return "Fallback " + identifier })

        compare(normalized.schemaVersion, 1)
        compare(normalized.fields.length, 5)
        compare(normalized.actions.length, 1)
        compare(normalized.fields[3].value, false)
        compare(normalized.fields[3].valueText, "false")
        compare(normalized.fields[4].value, 0)
        compare(normalized.fields[4].valueText, "0")
    }

    function test_missingTitleUsesValidatedFieldIdentifier() {
        var seen = ""
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ id: "workspace.id", title: "" })
        ]), function(identifier) {
            seen = identifier
            return "Known title"
        })

        compare(seen, "workspace.id")
        compare(normalized.fields[0].title, "Known title")
    }

    function test_structuredDisplayTextUsesFallbacksInsteadOfObjectStrings() {
        var called = false
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ title: { malformed: true }, description: ["bad"] }),
            field({ id: "region", kind: "enum", options: [
                { id: "eu", title: { malformed: true } }
            ] })
        ], [
            action({ title: { malformed: true }, description: ["bad"] })
        ]), function() {
            called = true
            return "Fallback"
        })

        verify(called)
        compare(normalized.fields[0].title, "Fallback")
        compare(normalized.fields[0].description, "")
        compare(normalized.fields[1].options[0].title, "eu")
        compare(normalized.actions.length, 0)
    }

    function test_numericZeroSelectsMatchingOption() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({
                id: "region",
                kind: "enum",
                value: 0,
                options: [{ id: "other" }, { id: "0", title: "Zero" }]
            })
        ]))

        compare(normalized.fields[0].value, 0)
        compare(normalized.fields[0].valueText, "0")
        compare(normalized.fields[0].selectedOptionIndex, 1)
    }

    function test_boundsFieldsActionsAndOptionsBeforeRendering() {
        var fields = []
        var actions = []
        var options = []
        for (var i = 0; i < 80; i++) {
            fields.push(field({ id: "field" + i, kind: "enum", options: options }))
            actions.push(action({ id: "action" + i }))
            options.push({ id: "option" + i })
        }
        var normalized = ProviderDescriptor.normalize(descriptor(fields, actions))

        compare(normalized.fields.length, 32)
        compare(normalized.actions.length, 32)
        compare(normalized.fields[0].options.length, 64)
    }

    function test_rejectsInvalidIdentifiersKindsAndOversizedStringValues() {
        var oversized = repeated("x", ProviderDescriptor.maximumTokenLength + 1).join("")
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ id: " leading" }),
            field({ id: "../escape" }),
            field({ id: "prototype pollution" }),
            field({ id: repeated("x", 129).join("") }),
            field({ id: "unsupported", kind: "command" }),
            field({ id: "oversized", value: oversized }),
            field({ id: "healthy" })
        ]))

        compare(normalized.fields.length, 1)
        compare(normalized.fields[0].id, "healthy")
    }

    function test_dropsInvalidOptionsAndStructuredValues() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({
                id: "region",
                kind: "enum",
                value: { nested: true },
                options: [null, { id: "../bad" }, { id: "good", title: ["bad"] }]
            })
        ]))

        compare(normalized.fields[0].value, "")
        compare(normalized.fields[0].options.length, 1)
        compare(normalized.fields[0].options[0].id, "good")
    }

    function test_rejectsOversizedOrMalformedCommandTokens() {
        var tooMany = ["codexbar", "config", "set"]
            .concat(repeated("token", ProviderDescriptor.maximumCommandTokens))
        var oversized = repeated("x", ProviderDescriptor.maximumTokenLength + 1).join("")
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ id: "tooMany", writeCommand: tooMany }),
            field({ id: "tooLong", writeCommand: ["codexbar", "config", "set", oversized] }),
            field({ id: "nonString", writeCommand: ["codexbar", "config", "set", 42] }),
            field({ id: "empty", writeCommand: ["codexbar", "config", "set", ""] }),
            field({ id: "healthy" })
        ]))

        compare(normalized.fields.length, 1)
        compare(normalized.fields[0].id, "healthy")
    }

    function test_firstAllowlistGateRejectsWrongCommands() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ id: "binary", writeCommand: ["other", "config", "set"] }),
            field({ id: "group", writeCommand: ["codexbar", "usage", "set"] }),
            field({ id: "subcommand", writeCommand: ["codexbar", "config", "action"] }),
            field({ id: "healthy" })
        ], [
            action({ id: "fieldCommand", command: ["codexbar", "config", "set"] }),
            action({ id: "healthyAction" })
        ]))

        compare(normalized.fields.length, 1)
        compare(normalized.actions.length, 1)
        compare(normalized.actions[0].id, "healthyAction")
    }

    function test_secondAllowlistGateRejectsMutatedCapabilities() {
        var normalized = ProviderDescriptor.normalize(descriptor([field()], [action()]))
        normalized.fields[0].writeCommand = ["sh", "-c", "malicious"]
        normalized.actions[0].command = ["codexbar", "config", "set"]

        verify(!ProviderDescriptor.planFieldWrite(normalized.fields[0], "value", "codexbar").ok)
        verify(!ProviderDescriptor.planSecretPrompt(normalized.fields[0], "codexbar").ok)
        verify(!ProviderDescriptor.planAction(normalized.actions[0], "codexbar").ok)
    }

    function test_fieldPlanQuotesCommandPathAndReplacementAsSingleTokens() {
        var normalized = ProviderDescriptor.normalize(descriptor([field()]))
        var plan = ProviderDescriptor.planFieldWrite(
            normalized.fields[0], "x'; touch /tmp/pwned; '", "/opt/codex bar's/codexbar")

        verify(plan.ok)
        compare(plan.commandLine,
            "'/opt/codex bar'\\''s/codexbar' 'config' 'set' '--value' 'x'\\''; touch /tmp/pwned; '\\'''" )
    }

    function test_onlyLiteralFirstCodexbarTokenUsesConfiguredPath() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ writeCommand: ["codexbar", "config", "set", "{value}", "codexbar"] })
        ]))
        var plan = ProviderDescriptor.planFieldWrite(normalized.fields[0], "unused", "/custom/codexbar")

        verify(plan.ok)
        compare(plan.commandLine, "'/custom/codexbar' 'config' 'set' 'unused' 'codexbar'")
    }

    function test_genericFieldPlanRejectsSecretBeforeInterpolation() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ kind: "secret", writeCommand: ["codexbar", "config", "set-api-key", "{value}"] })
        ]))
        var marker = "must-not-appear"
        var plan = ProviderDescriptor.planFieldWrite(normalized.fields[0], marker, "codexbar")

        verify(!plan.ok)
        compare(plan.reason, "secretRequiresPrompt")
        compare(plan.commandLine.indexOf(marker), -1)
    }

    function test_genericFieldPlanRequiresValuePlaceholder() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ writeCommand: ["codexbar", "config", "set", "--flag"] }),
            field({ id: "healthy", writeCommand: ["codexbar", "config", "set", "--value", "{value}"] })
        ]))
        var plan = ProviderDescriptor.planFieldWrite(normalized.fields[0], "dropped", "codexbar")

        verify(!plan.ok)
        compare(plan.reason, "missingValuePlaceholder")
        compare(plan.commandLine.indexOf("dropped"), -1)
        verify(ProviderDescriptor.planFieldWrite(normalized.fields[1], "kept", "codexbar").ok)
    }

    function test_secretPromptPlanRejectsNonSecretAndValueChannelCommands() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ writeCommand: ["codexbar", "config", "set", "--value", "{value}"] }),
            field({ id: "secretWithValue", kind: "secret", writeCommand: ["codexbar", "config", "set-api-key", "{value}"] })
        ]))

        verify(!ProviderDescriptor.planSecretPrompt(normalized.fields[0], "codexbar").ok)
        var valueChannelPlan = ProviderDescriptor.planSecretPrompt(normalized.fields[1], "codexbar")
        verify(!valueChannelPlan.ok)
        compare(valueChannelPlan.reason, "unsupportedCommand")
    }

    function test_secretPromptPlanHasNoValueChannel() {
        var normalized = ProviderDescriptor.normalize(descriptor([
            field({ kind: "secret", writeCommand: ["codexbar", "config", "set-api-key", "--stdin"] })
        ]))
        var plan = ProviderDescriptor.planSecretPrompt(normalized.fields[0], "/custom/codexbar")

        verify(plan.ok)
        compare(plan.commandLine, "'/custom/codexbar' 'config' 'set-api-key' '--stdin'")
        compare(plan.commandLine.indexOf("secret"), -1)
    }

    function test_actionPlanAppliesSecondAllowlistAndQuotesTokens() {
        var normalized = ProviderDescriptor.normalize(descriptor([], [
            action({ command: ["codexbar", "config", "action", "open dashboard"] })
        ]))
        var plan = ProviderDescriptor.planAction(normalized.actions[0], "codexbar")

        verify(plan.ok)
        compare(plan.commandLine, "'codexbar' 'config' 'action' 'open dashboard'")
    }

    function test_safeHttpsUrlPreservesCurrentPrefixPolicy() {
        compare(ProviderDescriptor.safeHttpsUrl("  HTTPS://example.com/path  "), "HTTPS://example.com/path")
        compare(ProviderDescriptor.safeHttpsUrl("http://example.com"), "")
        compare(ProviderDescriptor.safeHttpsUrl("javascript:alert(1)"), "")
        compare(ProviderDescriptor.safeHttpsUrl(null), "")
    }
}
