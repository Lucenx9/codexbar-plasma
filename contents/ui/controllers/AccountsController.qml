import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../AccountRequests.js" as AccountRequests
import "../AccountResponse.js" as AccountResponse
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../ProviderIdentity.js" as ProviderIdentity
import "../ProviderNormalizer.js" as Normalizer
import "../ProviderSnapshot.js" as ProviderSnapshot

Item {
    id: controller

    property string commandPath: ""
    property string sourceMode: ""
    property bool includeStatus: false

    readonly property var options: lifecycle.options

    function load(providerID) {
        return lifecycle.request(providerID);
    }

    function loadingForProvider(providerID) {
        var key = Normalizer.normalizedProviderID(providerID);
        return key.length > 0 && AccountRequests.isLoading(lifecycle.commands, key);
    }

    function errorForProvider(providerID) {
        var key = Normalizer.normalizedProviderID(providerID);
        return key.length > 0 && Guards.hasOwnKey(lifecycle.errors, key) ? lifecycle.errors[key] : "";
    }

    // The owning applet calls this when its CLI/configuration identity changes.
    // Ordinary usage refreshes and account selection preserve these lists.
    function reset() {
        lifecycle.retireRequests();
        lifecycle.options = ({});
        lifecycle.errors = ({});
    }

    Component.onDestruction: lifecycle.retireRequests()

    Item {
        id: lifecycle

        property var commands: ({})
        property var options: ({})
        property var errors: ({})
        property int runSerial: 0
        readonly property int accountCommandTimeoutMs: 60000
        readonly property string commandContext: JSON.stringify([controller.commandPath, controller.sourceMode, controller.includeStatus])

        onCommandContextChanged: retireRequests()

        function command(providerID) {
            if (controller.commandPath.length === 0)
                return "";
            var parts = [Guards.shellQuote(controller.commandPath), "usage", "--provider", Guards.shellQuote(ProviderIdentity.providerCliArgument(providerID)), "--all-accounts", "--format", "json", "--json-only"];
            if (controller.sourceMode.length > 0)
                parts.push("--source", Guards.shellQuote(controller.sourceMode));
            if (controller.includeStatus)
                parts.push("--status");
            return parts.join(" ");
        }

        function request(providerID) {
            var key = Normalizer.normalizedProviderID(providerID);
            if (key.length === 0 || controller.loadingForProvider(key))
                return false;
            var baseCommand = command(key);
            if (baseCommand.length === 0) {
                setError(key, i18n("Set the codexbar command path in widget settings."));
                return false;
            }
            setError(key, "");
            runSerial += 1;
            var source = CommandLedger.withRunNonce(baseCommand, runSerial);
            var descriptor = CommandLedger.descriptor("account", key, Date.now(), accountCommandTimeoutMs);
            descriptor.commandSignature = baseCommand;
            commands = CommandLedger.opened(commands, source, descriptor);
            accountsSource.connectSource(source);
            return true;
        }

        function setError(providerID, message) {
            var next = Guards.copyObject(errors);
            var text = ProviderSnapshot.message(message);
            if (text.length > 0)
                next[providerID] = text;
            else
                delete next[providerID];
            errors = next;
        }

        function finishRequest(sourceName) {
            commands = CommandLedger.closed(commands, sourceName);
            accountsSource.disconnectSource(sourceName);
        }

        function retireRequests() {
            var sources = CommandLedger.sourcesOfKind(commands, "account");
            for (var i = 0; i < sources.length; i++)
                finishRequest(sources[i]);
        }

        function acceptReply(sourceName, stdoutText, stderrText) {
            var descriptor = CommandLedger.find(commands, sourceName);
            var decision = AccountRequests.completion(commands, sourceName, descriptor ? command(descriptor.providerID) : "");
            if (!decision)
                return;
            finishRequest(sourceName);
            if (!decision.acceptsPayload)
                return;
            var result = AccountResponse.response(stdoutText, stderrText, decision.providerID, Date.now());
            var message = "";
            switch (result.outcome) {
            case "success":
                var next = Guards.copyObject(options);
                next[decision.providerID] = result.options;
                options = next;
                break;
            case "tooLarge":
                message = i18n("codexbar response exceeded the supported size.");
                break;
            case "empty":
                message = result.message || i18n("codexbar did not return account data.");
                break;
            case "invalidJson":
                message = i18n("Could not parse codexbar account JSON: %1", result.message);
                break;
            case "recordError":
                message = i18n("Could not read a codexbar account record: %1", result.message);
                break;
            case "commandFailed":
                message = result.message || i18n("codexbar command failed.");
                break;
            }
            setError(decision.providerID, message);
        }

        function expireRequests(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            for (var i = 0; i < expired.length; i++) {
                finishRequest(expired[i].sourceName);
                setError(expired[i].descriptor.providerID, i18n("Loading accounts timed out. Try again."));
            }
        }
    }

    Plasma5Support.DataSource {
        id: accountsSource
        engine: "executable"
        interval: 0
        onNewData: function (sourceName, data) {
            lifecycle.acceptReply(sourceName, data ? data["stdout"] : "", data ? data["stderr"] : "");
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: CommandLedger.hasDeadlines(lifecycle.commands)
        onTriggered: lifecycle.expireRequests(Date.now())
    }
}
