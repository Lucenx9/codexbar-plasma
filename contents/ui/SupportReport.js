.pragma library
.import "SafeText.js" as SafeText
.import "CliUpdate.js" as CliUpdate
.import "Guards.js" as Guards
.import "ProviderIdentity.js" as ProviderIdentity

var modules = ["QtQuick", "QtQuick.Controls", "QtQuick.Layouts", "QtQuick.Dialogs",
    "org.kde.kirigami", "org.kde.kcmutils", "org.kde.plasma.core",
    "org.kde.plasma.components", "org.kde.plasma.extras", "org.kde.plasma.plasmoid",
    "org.kde.plasma.plasma5support", "org.kde.kquickcontrolsaddons"]
var tools = ["python3", "timeout", "kpackagetool6", "notify-send", "curl", "jq", "sha256sum", "flock"]

function command(scriptUrl, commandPath) {
    var url = String(scriptUrl)
    var script
    try { script = url.indexOf("file:///") === 0 ? decodeURIComponent(url.slice(7)) : "" }
    catch (error) { return "" }
    if (!script || typeof commandPath !== "string" || !commandPath.trim()
            || commandPath.length > 4096 || /[\x00-\x1f\x7f]/.test(commandPath)) return ""
    return "timeout --kill-after=2s 90s python3 " + Guards.shellQuote(script)
        + " --command " + Guards.shellQuote(commandPath.trim())
}

function record(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function providerID(value) {
    return typeof value === "string" && /^[a-z][a-z0-9_-]{0,127}$/.test(value)
        && ProviderIdentity.providerMapKey(value) === value
}

function version(value) {
    return typeof value === "string" && /^[0-9]{1,6}\.[0-9]{1,6}(\.[0-9]{1,6})?([-+][0-9A-Za-z.-]{1,64})?$/.test(value)
        ? value : "unknown"
}

// This stricter sharing projection also removes personal locations and IDs.
// No arbitrary diagnostic JSON is appended to the report.
function sharedText(value, limit) {
    if (typeof value !== "string") return ""
    return SafeText.cliDiagnostic(value, SafeText.maximumDiagnosticLength)
        .replace(/\/(?:home|Users)\/[^\/\s]+/g, "/home/[user]")
        .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, "[email]")
        .replace(/\b(?:account|org|organization|workspace|project)[-_ ]?id["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;]+)/gi, "identifier=[redacted]")
        .replace(/\b(?:acct|org|proj|workspace)_[A-Za-z0-9_-]+\b/g, "[identifier]")
        .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[token]")
        .replace(/\b(?:https?|wss?):\/\/[^\s"'<>]+/gi, "[url]")
        .replace(/[\x00-\x1f\x7f\u0060<>]/g, " ")
        .slice(0, limit || 1024)
}

function response(text) {
    var empty = {valid: false, environment: {}, selected: CliUpdate.response(""), system: CliUpdate.response(""),
        providers: {status: "unavailable", enabled: []}, tools: {}}
    empty.selected.status = ""
    empty.system.status = ""
    if (typeof text !== "string" || text.length > 32768) return empty
    var value
    try { value = JSON.parse(text) } catch (error) { return empty }
    if (!record(value) || !record(value.environment) || !record(value.selected)
            || !record(value.system) || !record(value.providers) || !record(value.tools)) return empty
    var environment = record(value.environment) ? value.environment : {}
    empty.environment = {plasma: version(environment.plasma), frameworks: version(environment.frameworks), qt: version(environment.qt)}
    empty.selected = cliRecord(value.selected)
    empty.system = cliRecord(value.system)
    if (record(value.providers) && value.providers.status === "checked" && Array.isArray(value.providers.enabled)
            && value.providers.enabled.length <= 256) {
        var ids = []
        for (var i = 0; i < value.providers.enabled.length; i++) {
            var id = value.providers.enabled[i]
            if (!providerID(id)) return empty
            if (ids.indexOf(id) < 0) ids.push(id)
        }
        empty.providers = {status: "checked", enabled: ids}
    }
    if (record(value.tools)) {
        for (var t = 0; t < tools.length; t++) {
            if (typeof value.tools[tools[t]] === "boolean") empty.tools[tools[t]] = value.tools[tools[t]]
        }
    }
    empty.valid = true
    return empty
}

function cliRecord(value) {
    var clean = {}
    for (var field of ["status", "version", "path", "manager"]) {
        clean[field] = typeof value[field] === "string" ? value[field] : ""
    }
    return CliUpdate.response(JSON.stringify(clean))
}

function cliLines(title, value) {
    return ["### " + title, "- Version: " + (value.version || "unknown"),
        "- Probe status: " + (value.status || "not checked"),
        "- Resolved path: " + (sharedText(value.path, 1024) || "unavailable"),
        "- Installation: " + (value.path ? value.manager : "unknown")]
}

function markdown(input) {
    var facts = input.facts || response("")
    var lines = ["## CodexBar Plasma support report", "", "Collected: " + sharedText(input.timestamp, 64),
        "", "### Environment", "- Widget: " + version(input.widgetVersion),
        "- KDE Plasma: " + (facts.environment.plasma || "not checked"),
        "- KDE Frameworks: " + (facts.environment.frameworks || "not checked"),
        "- Qt: " + (facts.environment.qt || "not checked"), ""]
    lines = lines.concat(cliLines("Selected CLI", facts.selected))
    lines.push("- Command selection: " + (input.commandPath === "codexbar" ? "PATH (codexbar)"
        : typeof input.commandPath === "string" && input.commandPath.charAt(0) === "/" ? "absolute path" : "custom command name (omitted)"))
    lines.push("", "### System CLI (PATH)")
    lines = lines.concat(cliLines("PATH resolution", facts.system).slice(1))
    lines.push("- Same resolved path as selected: " + (facts.selected.path && facts.system.path
        ? (facts.selected.path === facts.system.path ? "yes" : "no") : "unknown"))
    lines.push("", "### Providers", "- Enabled IDs: " + (facts.providers.status !== "checked" ? "unavailable"
        : facts.providers.enabled.length ? facts.providers.enabled.join(", ") : "none"))
    lines.push("- Provider override (Diagnostics form): " + (providerID(input.providerOverride) ? input.providerOverride : input.providerOverride ? "invalid/omitted" : "none"),
        "- Source override (Diagnostics form): " + (["auto", "web", "cli", "oauth", "api"].indexOf(input.sourceOverride) >= 0 ? input.sourceOverride : input.sourceOverride ? "invalid/omitted" : "none"),
        "", "### Support collection", sharedText(input.checkError, 500) || (facts.valid ? "Offline facts collected; unknown fields could not be identified." : "Offline facts unavailable; module checks may still be available."),
        "", "### Latest Diagnostics error", sharedText(input.lastError, 1024) || "None observed in this Diagnostics session.",
        "", "### Required QML modules")
    var checks = input.modules || {}
    for (var m = 0; m < modules.length; m++) {
        var state = checks[modules[m]]
        lines.push("- " + modules[m] + ": " + (state === true ? "available" : state === false ? "unavailable" : "not checked"))
    }
    lines.push("", "### Supporting tools")
    for (var t = 0; t < tools.length; t++) {
        var present = facts.tools[tools[t]]
        lines.push("- " + tools[t] + ": " + (present === true ? "available" : present === false ? "not found" : "not checked"))
    }
    lines.push("", "Configuration dumps, provider diagnostic output and account lists are excluded; recognized sensitive text is redacted.",
        "Unknown/unavailable facts are partial results, not successful checks.")
    return lines.join("\n").slice(0, 24000)
}
