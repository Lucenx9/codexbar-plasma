.pragma library
.import "Guards.js" as Guards
.import "SafeText.js" as SafeText

function response(text) {
    var empty = {status: "error", version: "", path: "", manager: "external", latest: "", releaseUrl: ""}
    if (typeof text !== "string" || text.length > 16384) return empty
    var value
    try { value = JSON.parse(text) } catch (error) { return empty }
    if (!value || typeof value !== "object" || Array.isArray(value)) return empty
    var statuses = ["missing", "unknown", "local", "available", "current", "uncomparable", "network_error"]
    if (statuses.indexOf(value.status) < 0) return empty
    var versionPattern = /^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})([-+][0-9A-Za-z.-]{1,64})?$/
    var stablePattern = /^v(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$/
    var version = typeof value.version === "string" && versionPattern.test(value.version) ? value.version : ""
    var path = typeof value.path === "string" && value.path.length <= 4096
        && value.path.charAt(0) === "/" && !/[\x00-\x1f\x7f]/.test(value.path) ? value.path : ""
    var manager = ["pacman", "dpkg", "rpm", "apk", "homebrew"].indexOf(value.manager) >= 0 ? value.manager : "external"
    var tag = typeof value.tag === "string" && stablePattern.test(value.tag) ? value.tag : ""
    if (["available", "current", "uncomparable"].indexOf(value.status) >= 0
            && (tag.length === 0 || value.latest !== tag.slice(1))) return empty
    if (["available", "current", "local"].indexOf(value.status) >= 0 && version.length === 0) return empty
    return {status: value.status, version: SafeText.cliMessage(version, 128),
        path: SafeText.redactCredentialsWithinSourceLimit(path, 1024), manager: manager,
        latest: tag.length > 0 ? tag.slice(1) : "",
        releaseUrl: tag.length > 0 ? "https://github.com/steipete/CodexBar/releases/tag/" + tag : ""}
}

function command(scriptUrl, commandPath, localOnly) {
    var url = String(scriptUrl)
    var script = ""
    try { script = url.indexOf("file:///") === 0 ? decodeURIComponent(url.slice(7)) : "" }
    catch (error) { return "" }
    if (!script || typeof commandPath !== "string" || !commandPath.trim()) return ""
    return "timeout --kill-after=2s 45s python3 " + Guards.shellQuote(script)
        + " --command " + Guards.shellQuote(commandPath.trim())
        + (localOnly ? " --local-only" : "")
}
