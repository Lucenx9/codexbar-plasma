.pragma library
.import "../Guards.js" as Guards
.import "../SafeText.js" as SafeText
.import "../ProviderIdentity.js" as Identity

var supportedSourceModes = ["auto", "api", "cli", "oauth", "web"]
var maximumListItems = 64

// This inventory describes CLI writers, not complete Linux authentication flows.
// Missing metadata keeps the legacy UI; malformed advertised capabilities deny writes.
function normalize(value, providerID) {
    if (value === undefined || value === null) return null
    var result = {sourceModes: [], supportsConfigAPIKey: false,
        supportsConfigCookieHeader: false, environmentVariables: [], tokenAccounts: null, loginCommand: ""}
    if (!record(value)) return result
    var sources = own(value, "sourceModes")
    if (Array.isArray(sources)) {
        for (var i = 0; i < Math.min(sources.length, maximumListItems); i++) {
            var mode = sources[i]
            if (supportedSourceModes.indexOf(mode) >= 0 && result.sourceModes.indexOf(mode) < 0)
                result.sourceModes.push(mode)
        }
    }
    result.supportsConfigAPIKey = own(value, "supportsConfigAPIKey") === true
    result.supportsConfigCookieHeader = own(value, "supportsConfigCookieHeader") === true
    var variables = own(value, "environmentVariables")
    if (Array.isArray(variables)) {
        for (var j = 0; j < Math.min(variables.length, maximumListItems); j++) {
            var name = variables[j]
            if (typeof name === "string" && name.length <= 128 && /^[A-Z_][A-Z0-9_]*$/.test(name)
                    && result.environmentVariables.indexOf(name) < 0)
                result.environmentVariables.push(name)
        }
    }
    var accounts = own(value, "tokenAccounts")
    if (record(accounts)) {
        var title = text(own(accounts, "title"), 120)
        var hint = text(own(accounts, "setupHint"), 512)
        if (title.length > 0 || hint.length > 0) result.tokenAccounts = {title: title, setupHint: hint}
    }
    // A read-only hint for the sole released login command, never an executable action.
    if (Identity.resolveProviderKey(providerID) === "copilot"
            && own(value, "loginCommand") === "codexbar config login --provider copilot")
        result.loginCommand = "codexbar config login --provider copilot"
    return result
}

function record(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function own(value, key) {
    return Guards.hasOwnKey(value, key) ? value[key] : undefined
}

function text(value, limit) {
    return typeof value === "string" ? SafeText.cliMessage(value, limit) : ""
}
