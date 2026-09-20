.pragma library
.import "Guards.js" as Guards

function response(text) {
    var empty = {status: "error", version: "", previous: "", path: ""}
    if (typeof text !== "string" || text.length > 16384) return empty
    var value
    try { value = JSON.parse(text) } catch (error) { return empty }
    if (!value || typeof value !== "object" || Array.isArray(value)) return empty
    if (["ready", "absent", "installed", "restored", "external", "busy", "no_previous", "error"].indexOf(value.status) < 0) return empty
    if (value.status === "absent") return {status: "absent", path: "", version: "", previous: ""}
    var version = /^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$/
    var path = typeof value.path === "string" && value.path.length <= 4096
        && /^\/[^\x00-\x1f\x7f]+\/codexbar-plasma\/cli\/current\/codexbar$/.test(value.path)
        && value.path.split("/").indexOf("..") < 0 ? value.path : ""
    if (["ready", "installed", "restored"].indexOf(value.status) >= 0
            && (typeof value.version !== "string" || !version.test(value.version) || !path)) return empty
    return {status: value.status, path: path,
        version: typeof value.version === "string" && version.test(value.version) ? value.version : "",
        previous: value.status !== "no_previous" && typeof value.previous === "string" && version.test(value.previous) ? value.previous : ""}
}

function nextResponse(previous, text) {
    var parsed = response(text)
    if (parsed.path || ["error", "busy", "external", "no_previous"].indexOf(parsed.status) < 0) return parsed
    var prior
    try { prior = response(JSON.stringify(previous)) }
    catch (error) { prior = response("") }
    return {status: parsed.status, path: prior.path, version: prior.version,
        previous: parsed.status === "no_previous" ? "" : prior.previous}
}

function needsInstallConfirmation(managed, updater) {
    if (!managed || typeof managed !== "object" || !updater || typeof updater !== "object") return false
    // A managed copy already installed (or being selected) needs no warning.
    if (typeof managed.version === "string" && managed.version.length > 0) return false
    if (updater.checked !== true) return false
    var externalPath = typeof updater.path === "string" ? updater.path : ""
    var externalVersion = typeof updater.version === "string" ? updater.version : ""
    if (externalPath.length === 0 || externalVersion.length === 0) return false
    // The managed helper always reports its own expected path, so an equal
    // path means the selection already points at the private copy.
    return externalPath !== managed.path
}

function command(scriptUrl, action, commandPath) {
    if (["status", "install", "update", "automatic", "rollback"].indexOf(action) < 0) return ""
    var url = String(scriptUrl)
    var script
    try { script = url.indexOf("file:///") === 0 ? decodeURIComponent(url.slice(7)) : "" }
    catch (error) { return "" }
    if (!script || typeof commandPath !== "string") return ""
    return "timeout --kill-after=2s 610s python3 " + Guards.shellQuote(script)
        + " --action " + Guards.shellQuote(action) + " --command " + Guards.shellQuote(commandPath.trim())
}
