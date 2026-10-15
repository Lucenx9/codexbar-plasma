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

// Settings use the shared CLI record contract, projected to enabled identities.
// Outcomes leave localized error wording and process state to the QML owner.
function response(stdoutValue, stderrValue, exitCode) {
    var result = ProviderConfigProtocol.response(
        stdoutValue, stderrValue, exitCode, "enabledRoster", providerTitle);
    var records = result.outcome === "success" ? result.value : [];
    var providers = [];
    for (var i = 0; i < records.length; i++) {
        if (records[i].enabled) {
            providers.push({
                provider: records[i].provider,
                displayName: SafeText.cliMessage(records[i].displayName, 120)
            });
        }
    }
    return { outcome: result.outcome, providers: providers, message: result.message, exitCode: result.exitCode };
}
