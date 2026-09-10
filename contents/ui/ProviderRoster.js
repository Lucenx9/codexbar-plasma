.pragma library
.import "SafeText.js" as SafeText
.import "config/ProviderConfigProtocol.js" as ProviderConfigProtocol

function providerTitle(value) {
    var words = value.replace(/[_-]/g, " ").split(" ");
    for (var i = 0; i < words.length; i++) {
        if (words[i].length > 0) {
            words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
        }
    }
    return words.join(" ");
}

function boundedMessage(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

// Settings use the shared CLI record contract, projected to enabled identities.
// Outcomes leave localized error wording and process state to the QML owner.
function response(stdoutValue, stderrValue) {
    var text = SafeText.cliJsonText(stdoutValue);
    if (text === null) {
        return { outcome: "tooLarge", providers: [], message: "" };
    }
    if (text.trim().length === 0) {
        var stderr = boundedMessage(stderrValue);
        return { outcome: stderr.length > 0 ? "cliError" : "empty", providers: [], message: stderr };
    }
    var payload;
    try {
        payload = JSON.parse(text);
    } catch (error) {
        return { outcome: "invalidJson", providers: [], message: boundedMessage(error.message) };
    }
    var message = ProviderConfigProtocol.commandError(payload);
    if (message.length > 0) {
        return { outcome: "cliError", providers: [], message: message };
    }
    var records = ProviderConfigProtocol.normalizeProviderList(payload, providerTitle);
    var providers = [];
    for (var i = 0; i < records.length; i++) {
        if (records[i].enabled) {
            providers.push({
                provider: records[i].provider,
                displayName: SafeText.cliMessage(records[i].displayName, 120)
            });
        }
    }
    return { outcome: "success", providers: providers, message: "" };
}
