.pragma library
.import "../Guards.js" as Guards
.import "ProviderConfigProtocol.js" as Protocol
.import "../ProviderIdentity.js" as Identity
.import "ProviderAuthentication.js" as Authentication

// Older inventories have no per-provider modes. The CLI still validates writes.
var modes = Authentication.supportedSourceModes.slice()

// The CLI dump is normalized and redacted upstream. Retain only source enums,
// never credential placeholders or arbitrary configuration fields.
function savedSources(payload) {
    if (!Protocol.isCliRecord(payload) || !Guards.hasOwnKey(payload, "providers")) return null
    if (!Array.isArray(payload.providers) || payload.providers.length > Protocol.maximumProviderItems) return null
    var result = {}
    for (var i = 0; i < payload.providers.length; i++) {
        var item = payload.providers[i]
        if (!Protocol.isCliRecord(item) || !Guards.hasOwnKey(item, "id")) continue
        var id = Protocol.boundedProviderID(item.id)
        if (!id) continue
        var key = "provider:" + id
        var mode = Guards.hasOwnKey(item, "source") ? item.source : "auto"
        result[key] = Guards.hasOwnKey(result, key) || modes.indexOf(mode) < 0 ? "" : mode
    }
    return result
}

function savedMode(sources, provider) {
    var key = "provider:" + Protocol.boundedProviderID(provider)
    return Protocol.isCliRecord(sources) && Guards.hasOwnKey(sources, key)
        && modes.indexOf(sources[key]) >= 0 ? sources[key] : ""
}

function withSavedMode(sources, provider, mode) {
    var next = Guards.copyObject(sources)
    next["provider:" + Protocol.boundedProviderID(provider)] = mode
    return next
}

function availableModes(authentication) {
    if (authentication === undefined || authentication === null) return modes.slice()
    var result = []
    var listed = Guards.hasOwnKey(authentication, "sourceModes") ? authentication.sourceModes : null
    if (!Array.isArray(listed)) return result
    for (var i = 0; i < Math.min(listed.length, Authentication.maximumListItems); i++) {
        if (modes.indexOf(listed[i]) >= 0 && result.indexOf(listed[i]) < 0) result.push(listed[i])
    }
    return result
}

function planWrite(commandPath, provider, mode, authentication) {
    if (typeof commandPath !== "string" || commandPath.trim().length === 0
            || Protocol.boundedProviderID(provider) !== provider
            || typeof provider !== "string" || provider.length === 0
            || availableModes(authentication).indexOf(mode) < 0) {
        return {ok: false}
    }
    return {
        ok: true,
        commandLine: [Guards.shellQuote(commandPath), "config set-source --provider",
            Guards.shellQuote(provider), "--source", Guards.shellQuote(mode),
            "--format json --json-only"].join(" ")
    }
}

function resultMatches(payload, provider, mode) {
    return Protocol.isCliRecord(payload)
        && Guards.hasOwnKey(payload, "provider")
        && Protocol.boundedProviderID(payload.provider).length > 0
        && Identity.resolveProviderKey(payload.provider) === Identity.resolveProviderKey(provider)
        && Guards.hasOwnKey(payload, "source") && payload.source === mode
        && modes.indexOf(mode) >= 0
        && Guards.hasOwnKey(payload, "enabled") && typeof payload.enabled === "boolean"
}
