.pragma library
.import "../Guards.js" as Guards
.import "../SafeText.mjs" as SafeText
.import "ProviderAuthentication.js" as Authentication

// Setup is a read-only projection. No command or config-field writer consumes it.
function linuxRoutes(setup, providerID) {
    if (!Guards.isRecord(setup) || setup.status !== "declared" || !Array.isArray(setup.routes))
        return []
    var routes = []
    for (var raw of setup.routes.slice(0, 8)) {
        var route = linuxRoute(raw, providerID)
        if (route) routes.push(route)
    }
    return routes
}

function linuxRoute(raw, providerID) {
    if (!Guards.isRecord(raw) || !validID(raw.id)
            || ["apiKey", "token", "deviceCode"].indexOf(raw.method) < 0
            || !Array.isArray(raw.platforms) || raw.platforms.slice(0, 8).indexOf("linux") < 0)
        return null
    var hint = Authentication.text(raw.hint, 512)
    var inputs = requiredInputs(raw.requiredInputs)
    if (!hint || !inputs) return null
    return {hint: hint, inputs: inputs, command: displayCommand(raw, providerID)}
}

function requiredInputs(raw) {
    // Dropping part of a required set could advertise an incomplete setup.
    if (!Array.isArray(raw) || raw.length > 8) return null
    var inputs = []
    for (var input of raw) {
        if (!Guards.isRecord(input) || !validID(input.id)) return null
        inputs.push({id: input.id, environmentVariables: Authentication.environmentNames(input.environmentVariables, 8)})
    }
    return inputs
}

function validID(value) {
    return typeof value === "string" && value.length <= 64 && /^[a-z][a-z0-9-]*$/.test(value)
        && SafeText.cliMessage(value, 64) === value
}

function displayCommand(raw, providerID) {
    if (raw.method === "deviceCode" && providerID === "copilot"
            && raw.command === "codexbar config login --provider copilot")
        return raw.command
    if (raw.method === "apiKey" && ["deepinfra", "elevenlabs"].indexOf(providerID) >= 0
            && raw.command === "codexbar config set-api-key --provider " + providerID + " --stdin")
        return raw.command
    return ""
}
