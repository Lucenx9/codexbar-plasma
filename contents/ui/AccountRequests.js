.pragma library
.import "CommandLedger.js" as CommandLedger

// The command ledger is the only account loading state. Closing a request on
// completion, timeout or retirement releases only that request's loading state.
// QML owns command construction, registration, disconnection and payload effects.
function isLoading(commands, providerID) {
    var sources = CommandLedger.sourcesOfKind(commands, "account")
    for (var i = 0; i < sources.length; i++) {
        var descriptor = CommandLedger.find(commands, sources[i])
        if (descriptor.providerID === providerID) {
            return true
        }
    }
    return false
}

// Evaluate before QML closes the source. A registered request with obsolete
// context must still finish, but cannot publish data. An already retired source
// has no completion and cannot affect the request that replaced it.
function completion(commands, sourceName, currentCommand) {
    var descriptor = CommandLedger.find(commands, sourceName)
    if (!descriptor || descriptor.kind !== "account") {
        return null
    }
    return {
        providerID: descriptor.providerID,
        acceptsPayload: typeof currentCommand === "string" && currentCommand.length > 0
            && descriptor.commandSignature === currentCommand
    }
}
