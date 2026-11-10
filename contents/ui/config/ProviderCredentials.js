.pragma library
.import "../Guards.js" as Guards
.import "../ProviderIdentity.js" as Identity
.import "ProviderConfigProtocol.js" as Protocol

// Linux fetches verified at 0.82.0; OpenDesign joins at 0.83.0, WorkBuddy at 0.84.0. Writer
// acceptance alone is insufficient (several accepted providers are macOS-only).
var cookieMinimumVersions = {
    claude: 82, claudeplatform: 82, commandcode: 82, cursor: 82, mistral: 82,
    ollama: 82, opencodego: 82, parallel: 82, raycast: 82, tinyapi: 82,
    traecn: 82, typesafe: 82, xapi: 82, opendesign: 83, workbuddy: 84
}

function supportsCookie(provider, version, authentication) {
    var id = Identity.normalizedProviderID(provider)
    return Guards.hasOwnKey(cookieMinimumVersions, id)
        && Protocol.cliVersionAtLeast(version, 0, cookieMinimumVersions[id], 0)
        && (authentication === null || authentication === undefined
            || authentication.supportsConfigCookieHeader === true)
}

function supportsClear(version) {
    return Protocol.cliVersionAtLeast(version, 0, 82, 0)
}

function supportsLogin(provider, version) {
    return Identity.normalizedProviderID(provider) === "copilot"
        && Protocol.cliVersionAtLeast(version, 0, 80, 0)
}

function supportsSessionImport(provider, version, authentication) {
    return Identity.normalizedProviderID(provider) === "claudeplatform"
        && Protocol.cliVersionAtLeast(version, 0, 84, 0)
        && supportsCookie(provider, version, authentication)
}

var helperProviders = {
    "set-cookie": "*", "clear-credential": "*", login: "copilot",
    "cancel-login": "copilot", "import-session": "claudeplatform"
}

function helperCommand(scriptUrl, commandPath, action, provider) {
    if (!Guards.hasOwnKey(helperProviders, action)) return ""
    if (typeof commandPath !== "string" || !commandPath.trim()
            || Protocol.boundedProviderID(provider) !== provider || !provider
            || (helperProviders[action] !== "*" && helperProviders[action] !== provider)) return ""
    var script = String(scriptUrl)
    try {
        script = script.indexOf("file:///") === 0 ? decodeURIComponent(script.slice(7)) : ""
    } catch (error) { return "" }
    if (!script) return ""
    return ["python3", Guards.shellQuote(script), "--cli", Guards.shellQuote(commandPath),
        "--action", action, "--provider", Guards.shellQuote(provider)].join(" ")
}

// Helper results contain only these semantic fields, never CLI prose or paths.
function result(stdout, exitCode, provider, action) {
    if (Guards.isCommandPathFailure(exitCode)) return {status: "unavailable"}
    if (Guards.exitCode(exitCode) !== 0 || typeof stdout !== "string" || stdout.length > 1024)
        return {status: "failed"}
    var value
    try { value = JSON.parse(stdout) } catch (error) { return {status: "failed"} }
    if (Protocol.isCliRecord(value) && value.cancelled === true) return {status: "cancelled"}
    if (!Protocol.isCliRecord(value) || value.provider !== provider) return {status: "failed"}
    if (["cancelled", "expired", "conflict", "unavailable"].indexOf(value.status) >= 0)
        return {status: value.status}
    if (value.status !== "ok") return {status: "failed"}
    if (action === "set-cookie" && typeof value.enabled !== "boolean") return {status: "failed"}
    return {status: "ok", enabled: value.enabled === true}
}
