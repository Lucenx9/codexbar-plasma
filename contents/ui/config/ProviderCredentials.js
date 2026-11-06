.pragma library
.import "../Guards.js" as Guards
.import "../ProviderIdentity.js" as Identity
.import "ProviderConfigProtocol.js" as Protocol

// Linux fetches verified at 0.82.0; OpenDesign joins at 0.83.0. Writer
// acceptance alone is insufficient (several accepted providers are macOS-only).
var cookieProviders = ["claude", "claudeplatform", "commandcode", "cursor", "mistral",
    "ollama", "opencodego", "parallel", "raycast", "tinyapi", "traecn", "typesafe", "xapi"]

function supportsCookie(provider, version, authentication) {
    var id = Identity.normalizedProviderID(provider)
    return Protocol.cliVersionAtLeast(version, 0, id === "opendesign" ? 83 : 82, 0)
        && (id === "opendesign" || cookieProviders.indexOf(id) >= 0)
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

function helperCommand(scriptUrl, commandPath, action, provider) {
    if (["set-cookie", "clear-credential", "login", "cancel-login"].indexOf(action) < 0
            || typeof commandPath !== "string" || !commandPath.trim()
            || Protocol.boundedProviderID(provider) !== provider || !provider
            || ((action === "login" || action === "cancel-login") && provider !== "copilot")) return ""
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
