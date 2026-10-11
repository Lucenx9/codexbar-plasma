.pragma library
.import "../Guards.js" as Guards
.import "ProviderConfigProtocol.js" as Protocol
.import "../ProviderIdentity.js" as Identity

// These are command modes, not a claim that a provider supports each mode.
// The released CLI owns provider-specific validation and persistence.
var modes = ["auto", "api", "cli", "oauth", "web"]

function planWrite(commandPath, provider, mode) {
    if (typeof commandPath !== "string" || commandPath.trim().length === 0
            || Protocol.boundedProviderID(provider) !== provider
            || typeof provider !== "string" || provider.length === 0
            || modes.indexOf(mode) < 0) {
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
