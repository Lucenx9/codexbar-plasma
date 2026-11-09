.pragma library
.import "../Guards.js" as Guards
.import "ProviderConfigProtocol.js" as Protocol
.import "ProviderAuthentication.js" as Authentication

var modes = Authentication.supportedSourceModes.slice()

// The CLI dump is normalized and redacted upstream. Retain only source enums,
// never credential placeholders or arbitrary configuration fields.
function savedSources(payload) {
    if (!Protocol.isCliRecord(payload) || !Guards.hasOwnKey(payload, "providers")) return null
    if (!Array.isArray(payload.providers) || payload.providers.length > Protocol.maximumProviderItems) return null
    var result = {}
    for (var i = 0; i < payload.providers.length; i++) {
        var source = savedSource(payload.providers[i])
        if (!source) continue
        var key = "provider:" + source.id
        result[key] = Guards.hasOwnKey(result, key) ? "" : source.mode
    }
    return result
}

function savedSource(item) {
    if (!Protocol.isCliRecord(item) || !Guards.hasOwnKey(item, "id")) return null
    var id = Protocol.boundedProviderID(item.id)
    if (!id) return null
    var mode = Guards.hasOwnKey(item, "source") ? item.source : "auto"
    return {id: id, mode: modes.indexOf(mode) >= 0 ? mode : ""}
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
