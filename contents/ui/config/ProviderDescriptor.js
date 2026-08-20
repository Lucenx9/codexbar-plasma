.pragma library
.import "../Guards.js" as Guards
.import "../SafeText.js" as SafeText

// Pure trust boundary for the proposed provider-settings descriptor contract.
// The Providers page keeps transport negotiation, process state, i18n, prompts,
// and effects; this module only validates untrusted descriptor data and prepares
// commands that the page may execute after a second authorization check.

var maximumFields = 32
var maximumActions = 32
var maximumOptions = 64
var maximumCommandTokens = 64
var maximumTokenLength = 2048
var maximumIdentifierLength = 128

function emptyDescriptor() {
    return { schemaVersion: 0, fields: [], actions: [] }
}

function normalize(raw, fallbackFieldTitle) {
    if (!raw || Number(raw.schemaVersion) !== 1) {
        return emptyDescriptor()
    }

    var fields = []
    var rawFields = Array.isArray(raw.fields) ? raw.fields : []
    var fieldLimit = Math.min(rawFields.length, maximumFields)
    for (var i = 0; i < fieldLimit; i++) {
        var field = normalizeField(rawFields[i], fallbackFieldTitle)
        if (field) {
            fields.push(field)
        }
    }

    var actions = []
    var rawActions = Array.isArray(raw.actions) ? raw.actions : []
    var actionLimit = Math.min(rawActions.length, maximumActions)
    for (var j = 0; j < actionLimit; j++) {
        var action = normalizeAction(rawActions[j])
        if (action) {
            actions.push(action)
        }
    }
    return { schemaVersion: 1, fields: fields, actions: actions }
}

function normalizeField(raw, fallbackFieldTitle) {
    if (!raw || !raw.id || !raw.kind || !isSupportedFieldKind(raw.kind)) {
        return null
    }
    var fieldID = identifier(raw.id)
    if (fieldID.length === 0) {
        return null
    }
    var command = normalizeCommandTokens(raw.writeCommand)
    if (command.length === 0 || !isAllowedCommand(command, "field")) {
        return null
    }

    var value = raw.value
    if (value !== undefined && value !== null
            && typeof value !== "string"
            && typeof value !== "number"
            && typeof value !== "boolean") {
        value = ""
    } else if (typeof value === "string" && value.length > maximumTokenLength) {
        return null
    }

    var options = normalizeOptions(raw.options)
    var normalizedValue = value === undefined || value === null ? "" : value
    var normalizedValueText = valueText(normalizedValue)
    return {
        id: fieldID,
        kind: String(raw.kind),
        title: raw.title
            ? SafeText.cliMessage(raw.title, 120)
            : fallbackTitle(fallbackFieldTitle, fieldID),
        description: raw.description ? SafeText.cliMessage(raw.description, 500) : "",
        value: normalizedValue,
        valueText: normalizedValueText,
        redactedValue: raw.redactedValue ? boundedCliMessage(raw.redactedValue) : "",
        required: raw.required === true,
        options: options,
        selectedOptionIndex: optionIndex(options, normalizedValueText),
        writeCommand: command
    }
}

function normalizeAction(raw) {
    if (!raw || !raw.id || !raw.title) {
        return null
    }
    var actionID = identifier(raw.id)
    var actionTitle = SafeText.cliMessage(raw.title, 120)
    if (actionID.length === 0 || actionTitle.length === 0) {
        return null
    }
    var command = normalizeCommandTokens(raw.command)
    if (command.length === 0 || !isAllowedCommand(command, "action")) {
        return null
    }
    return {
        id: actionID,
        kind: raw.kind ? String(raw.kind) : "command",
        title: actionTitle,
        description: raw.description ? SafeText.cliMessage(raw.description, 500) : "",
        command: command
    }
}

function planFieldWrite(field, value, commandPath) {
    if (!field || !isAllowedCommand(field.writeCommand, "field")) {
        return rejectedPlan("unsupportedCommand")
    }
    if (field.kind === "secret") {
        return rejectedPlan("secretRequiresPrompt")
    }
    return acceptedPlan(commandLineFromTokens(
        field.writeCommand, ({ "{value}": value }), commandPath))
}

// There is deliberately no value argument. The QML prompt reads the secret
// inside the child script and pipes it to stdin, so it never appears in argv.
function planSecretPrompt(field, commandPath) {
    if (!field || !isAllowedCommand(field.writeCommand, "field")) {
        return rejectedPlan("unsupportedCommand")
    }
    return acceptedPlan(commandLineFromTokens(field.writeCommand, ({}), commandPath))
}

function planAction(action, commandPath) {
    if (!action || !isAllowedCommand(action.command, "action")) {
        return rejectedPlan("unsupportedCommand")
    }
    return acceptedPlan(commandLineFromTokens(action.command, ({}), commandPath))
}

function safeHttpsUrl(value) {
    var text = String(value || "").trim()
    return text.toLowerCase().indexOf("https://") === 0 ? text : ""
}

function fallbackTitle(resolver, fieldID) {
    return typeof resolver === "function" ? resolver(fieldID) : fieldID
}

function boundedCliMessage(value) {
    return SafeText.cliMessage(
        SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
}

function isSupportedFieldKind(kind) {
    switch (String(kind)) {
    case "text":
    case "secret":
    case "enum":
    case "boolean":
    case "number":
        return true
    default:
        return false
    }
}

function identifier(value) {
    if (typeof value !== "string" || value.length === 0 || value.length > maximumIdentifierLength) {
        return ""
    }
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value) ? value : ""
}

function normalizeOptions(rawOptions) {
    var result = []
    if (!Array.isArray(rawOptions)) {
        return result
    }
    var optionLimit = Math.min(rawOptions.length, maximumOptions)
    for (var i = 0; i < optionLimit; i++) {
        var option = rawOptions[i]
        if (!option || option.id === undefined || option.id === null) {
            continue
        }
        var optionID = identifier(option.id)
        if (optionID.length === 0) {
            continue
        }
        result.push({
            id: optionID,
            title: option.title ? SafeText.cliMessage(option.title, 120) : optionID
        })
    }
    return result
}

function normalizeCommandTokens(tokens) {
    var result = []
    if (!Array.isArray(tokens) || tokens.length > maximumCommandTokens) {
        return result
    }
    for (var i = 0; i < tokens.length; i++) {
        if (typeof tokens[i] !== "string") {
            return []
        }
        var token = tokens[i]
        if (token.length === 0 || token.length > maximumTokenLength) {
            return []
        }
        result.push(token)
    }
    return result
}

function isAllowedCommand(commandTokens, purpose) {
    if (!Array.isArray(commandTokens) || commandTokens.length < 3) {
        return false
    }
    if (String(commandTokens[0]) !== "codexbar" || String(commandTokens[1]) !== "config") {
        return false
    }

    var subcommand = String(commandTokens[2])
    if (purpose === "field") {
        return subcommand === "set" || subcommand === "set-api-key"
    }
    if (purpose === "action") {
        return subcommand === "action"
    }
    return false
}

function valueText(value) {
    return value === undefined || value === null ? "" : String(value)
}

function optionIndex(options, value) {
    for (var i = 0; i < options.length; i++) {
        if (options[i].id === value) {
            return i
        }
    }
    return -1
}

function acceptedPlan(commandLine) {
    return { ok: true, reason: "", commandLine: commandLine }
}

function rejectedPlan(reason) {
    return { ok: false, reason: reason, commandLine: "" }
}

function commandLineFromTokens(commandTokens, replacements, commandPath) {
    var parts = []
    for (var i = 0; i < commandTokens.length; i++) {
        var token = commandTokens[i]
        if (i === 0 && token === "codexbar" && String(commandPath || "").length > 0) {
            token = commandPath
        }
        parts.push(Guards.shellQuote(applyTokenReplacements(token, replacements)))
    }
    return parts.join(" ")
}

function applyTokenReplacements(token, replacements) {
    var result = String(token)
    for (var key in replacements) {
        if (!Guards.hasOwnKey(replacements, key)) {
            continue
        }
        result = result.split(key).join(String(replacements[key]))
    }
    return result
}
