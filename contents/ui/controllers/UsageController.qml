import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../ProviderFallbackQueue.js" as ProviderFallbackQueue
import "../ProviderIdentity.js" as ProviderIdentity
import "../ProviderNormalizer.js" as Normalizer
import "../ProviderOrder.js" as ProviderOrder
import "../ProviderRosterCache.js" as ProviderRosterCache
import "../ProviderSnapshot.js" as ProviderSnapshot
import "../PopupRefreshPolicy.js" as PopupRefreshPolicy
import "../UsageResponse.js" as UsageResponse
import "../UsageCache.js" as UsageCache

Item {
    id: controller

    property string commandPath: ""
    property string provider: ""
    property string sourceMode: ""
    property bool includeStatus: false
    property var selectedAccounts: ({})
    property int providerConfigRevision: 0
    property string providerConfigStamp: ""
    property string providerOrderRaw: ""
    property int refreshIntervalSec: 300
    property bool refreshOnOpen: false
    property bool popupVisible: false

    readonly property bool loading: lifecycle.loading
    readonly property string errorText: lifecycle.errorText
    readonly property var providerDisplayNames: lifecycle.providerDisplayNames
    readonly property string commandSource: lifecycle.commandSource
    readonly property double lastAttemptAtMs: lifecycle.usageLastRefreshAttemptAtMs
    readonly property double lastCompletedAtMs: lifecycle.usageLastCompletedAtMs
    readonly property bool refreshScheduled: lifecycle.usageRefreshScheduled

    signal snapshotReceived(var items)
    signal failed(string message)
    signal emptyRoster

    function refresh(bypassProviderRosterCache) {
        lifecycle.refreshNow(bypassProviderRosterCache);
    }
    function scheduleRefresh() {
        lifecycle.scheduleUsageRefresh();
    }
    function reset() {
        lifecycle.retireUsageCommands();
        lifecycle.usageRefreshScheduled = false;
        lifecycle.loading = false;
        lifecycle.usageLastCompletedAtMs = -1;
    }

    onPopupVisibleChanged: {
        if (popupVisible)
            Qt.callLater(lifecycle.refreshUsageOnOpen);
    }
    Component.onCompleted: {
        lifecycle.initialized = true;
        lifecycle.scheduleUsageRefresh();
    }
    Component.onDestruction: lifecycle.retireUsageCommands()

    Item {
        id: lifecycle
        property bool initialized: false
        property bool loading: false
        property string errorText: ""
        property var providerDisplayNames: ({})
        property double usageLastRefreshAttemptAtMs: -1
        property double usageLastCompletedAtMs: -1
        property string commandSource: buildCommand()
        property string providerConfigCommandSource: buildProviderConfigCommand()
        property var providerRosterCache: null
        property bool usageRefreshScheduled: false
        property int commandRunSerial: 0
        property var activeCommandDescriptors: ({})
        readonly property int defaultCommandTimeoutMs: 120000
        readonly property int maximumProviderSnapshots: Normalizer.maximumProviderSnapshots
        readonly property int maximumConcurrentProviderFallbackCommands: 8
        property var providerFallbackState: null
        readonly property string requestContext: JSON.stringify([controller.commandPath, controller.provider, controller.sourceMode, controller.includeStatus, controller.selectedAccounts, controller.providerConfigRevision])
        readonly property string rosterContext: JSON.stringify(providerRosterContext())

        onRequestContextChanged: {
            retireUsageCommands();
            loading = false;
            scheduleUsageRefresh();
        }
        onRosterContextChanged: invalidateProviderRosterCache()

        function buildCommand() {
            if (controller.commandPath.length === 0) {
                return "";
            }

            var parts = [Guards.shellQuote(controller.commandPath), "usage", "--format", "json", "--json-only"];

            if (controller.provider.length > 0) {
                parts.push("--provider");
                parts.push(Guards.shellQuote(controller.provider));
                var selectedAccount = selectedAccountForProvider(controller.provider);
                if (selectedAccount.length > 0) {
                    parts.push("--account");
                    parts.push(Guards.shellQuote(selectedAccount));
                }
            }

            if (controller.sourceMode.length > 0) {
                parts.push("--source");
                parts.push(Guards.shellQuote(controller.sourceMode));
            }

            if (controller.includeStatus) {
                parts.push("--status");
            }

            return parts.join(" ");
        }

        function buildProviderConfigCommand() {
            if (controller.commandPath.length === 0) {
                return "";
            }

            return [Guards.shellQuote(controller.commandPath), "config", "providers", "--format", "json", "--json-only"].join(" ");
        }

        function buildProviderUsageCommand(providerID) {
            var parts = [Guards.shellQuote(controller.commandPath), "usage", "--provider", Guards.shellQuote(ProviderIdentity.providerCliArgument(providerID)), "--format", "json", "--json-only"];

            if (controller.sourceMode.length > 0) {
                parts.push("--source");
                parts.push(Guards.shellQuote(controller.sourceMode));
            }

            var selectedAccount = selectedAccountForProvider(providerID);
            if (selectedAccount.length > 0) {
                parts.push("--account");
                parts.push(Guards.shellQuote(selectedAccount));
            }

            if (controller.includeStatus) {
                parts.push("--status");
            }

            return parts.join(" ");
        }

        function commandWithRunNonce(command) {
            if (command.length === 0) {
                return "";
            }
            commandRunSerial += 1;
            return CommandLedger.withRunNonce(command, commandRunSerial);
        }

        function connectUsageCommand(sourceName, descriptor) {
            if (sourceName.length === 0) {
                return;
            }

            activeCommandDescriptors = CommandLedger.opened(activeCommandDescriptors, sourceName, descriptor);
            usageSource.connectSource(sourceName);
        }

        function buildCommandDescriptor(kind, providerID, timeoutMs) {
            return CommandLedger.descriptor(kind, providerID, Date.now(), timeoutMs, defaultCommandTimeoutMs);
        }

        function providerRosterContext() {
            return {
                commandSource: providerConfigCommandSource,
                revision: controller.providerConfigRevision,
                stamp: controller.providerConfigStamp
            };
        }

        function buildProviderConfigCommandDescriptor() {
            var descriptor = buildCommandDescriptor("providerConfig", "");
            descriptor.providerRosterContext = providerRosterContext();
            return descriptor;
        }

        function finishUsageCommandSource(sourceName) {
            if (sourceName.length === 0) {
                return;
            }

            activeCommandDescriptors = CommandLedger.closed(activeCommandDescriptors, sourceName);
            usageSource.disconnectSource(sourceName);
        }

        function retireUsageCommandKind(kind) {
            var sourceNames = CommandLedger.sourcesOfKind(activeCommandDescriptors, kind);
            for (var i = 0; i < sourceNames.length; i++) {
                finishUsageCommandSource(sourceNames[i]);
            }
            return sourceNames.length;
        }

        function scheduleUsageRefresh() {
            if (!initialized || usageRefreshScheduled) {
                return;
            }
            usageRefreshScheduled = true;
            Qt.callLater(function () {
                if (!lifecycle.usageRefreshScheduled) {
                    return;
                }
                lifecycle.usageRefreshScheduled = false;
                lifecycle.refreshNow(false);
            });
        }

        function refreshNow(bypassProviderRosterCache) {
            usageRefreshScheduled = false;
            retireUsageCommands();

            if (commandSource.length === 0) {
                failUsageRefresh(i18n("Set the codexbar command path in widget settings."));
                return;
            }

            usageLastRefreshAttemptAtMs = Date.now();
            loading = true;
            errorText = "";
            if (canUseProviderFallback()) {
                startProviderFallback(bypassProviderRosterCache === true);
                return;
            }
            connectUsageCommand(commandWithRunNonce(commandSource), buildCommandDescriptor("usage", ""));
        }

        function hasSelectedAccountOverrides() {
            for (var providerID in controller.selectedAccounts) {
                if (Guards.hasOwnKey(controller.selectedAccounts, providerID) && String(controller.selectedAccounts[providerID] || "").length > 0) {
                    return true;
                }
            }
            return false;
        }

        function canUseProviderFallback() {
            return controller.sourceMode.length === 0 || hasSelectedAccountOverrides();
        }

        function startProviderFallback(bypassProviderRosterCache) {
            retireUsageCommandKind("usage");
            if (controller.provider.length > 0) {
                startProviderFallbackForProviders([Normalizer.providerSnapshotKey(controller.provider)]);
                return;
            }

            if (bypassProviderRosterCache !== true) {
                var cachedProviderIDs = ProviderRosterCache.read(providerRosterCache, providerRosterContext());
                if (cachedProviderIDs !== null) {
                    startProviderFallbackForProviders(cachedProviderIDs);
                    return;
                }
            }

            if (providerConfigCommandSource.length === 0) {
                failUsageRefresh(i18n("codexbar did not return JSON."));
                return;
            }

            connectUsageCommand(commandWithRunNonce(providerConfigCommandSource), buildProviderConfigCommandDescriptor());
        }

        function invalidateProviderRosterCache() {
            providerRosterCache = null;
        }

        function startProviderFallbackForProviders(providerIDs) {
            retireUsageCommandKind("providerFallback");
            providerFallbackState = null;

            var orderedProviderIDs = ProviderOrder.orderedItems(providerIDs, controller.providerOrderRaw);
            var requests = [];
            var providerLimit = Math.min(orderedProviderIDs.length, maximumProviderSnapshots);
            for (var i = 0; i < providerLimit; i++) {
                var providerID = Normalizer.normalizedProviderID(String(orderedProviderIDs[i] || ""));
                if (providerID.length === 0) {
                    continue;
                }
                var baseCommand = buildProviderUsageCommand(providerID);
                requests.push({
                    sourceName: commandWithRunNonce(baseCommand),
                    providerID: providerID
                });
            }

            var transition = ProviderFallbackQueue.begin(requests, {
                maximumConcurrent: maximumConcurrentProviderFallbackCommands,
                maximumSnapshots: maximumProviderSnapshots
            });
            if (transition.finished) {
                providerFallbackState = null;
                usageLastCompletedAtMs = -1;
                controller.emptyRoster();
                // A confirmed empty roster uses the popup's provider setup state.
                errorText = "";
                loading = false;
                return;
            }
            applyProviderFallbackTransition(transition);
        }

        function applyProviderFallbackTransition(transition) {
            providerFallbackState = transition.state;
            var sourcesToStart = transition.sourcesToStart;
            for (var i = 0; i < sourcesToStart.length; i++) {
                var request = sourcesToStart[i];
                connectUsageCommand(request.sourceName, buildCommandDescriptor("providerFallback", request.providerID));
            }
            if (transition.finished) {
                finishProviderFallback(transition.orderedItems);
            }
        }

        function completeProviderFallbackSlot(sourceName, item) {
            var transition = ProviderFallbackQueue.complete(providerFallbackState, {
                sourceName: sourceName,
                item: item
            });
            applyProviderFallbackTransition(transition);
        }

        function hasPendingCommandTimeouts() {
            return CommandLedger.hasDeadlines(activeCommandDescriptors);
        }

        function hasPendingPeriodicRefreshCommands() {
            return CommandLedger.hasAnyKind(activeCommandDescriptors, ["usage", "providerConfig", "providerFallback"]);
        }

        function expireCommands(nowMs) {
            var expired = CommandLedger.expired(activeCommandDescriptors, nowMs);
            for (var i = 0; i < expired.length; i++) {
                handleCommandTimeout(expired[i].sourceName, expired[i].descriptor);
            }
        }

        function handleCommandTimeout(sourceName, descriptor) {
            if (!descriptor || !CommandLedger.find(activeCommandDescriptors, sourceName)) {
                return;
            }

            switch (descriptor.kind) {
            case "usage":
                finishUsageCommandSource(sourceName);
                if (canUseProviderFallback()) {
                    startProviderFallback();
                    return;
                }
                failUsageRefresh(i18n("Loading usage timed out. Try again."));
                return;
            case "providerConfig":
                finishUsageCommandSource(sourceName);
                failUsageRefresh(i18n("Loading provider configuration timed out. Try again."));
                return;
            case "providerFallback":
                parseProviderFallbackOutput(sourceName, descriptor.providerID, "", i18n("Loading usage timed out. Try again."));
                return;
            default:
                finishUsageCommandSource(sourceName);
            }
        }

        function retireUsageCommands() {
            retireUsageCommandKind("usage");
            retireUsageCommandKind("providerConfig");
            retireUsageCommandKind("providerFallback");
            providerFallbackState = null;
        }

        function refreshUsageOnOpen() {
            if (PopupRefreshPolicy.shouldRefresh({
                enabled: controller.refreshOnOpen,
                visible: controller.popupVisible,
                loading: loading,
                scheduled: usageRefreshScheduled,
                commandSource: commandSource,
                lastAttemptAtMs: usageLastRefreshAttemptAtMs,
                lastCompletedAtMs: usageLastCompletedAtMs,
                nowMs: Date.now(),
                refreshIntervalSeconds: controller.refreshIntervalSec
            })) {
                refreshNow(false);
            }
        }

        function selectedAccountForProvider(providerID) {
            var key = Normalizer.providerSnapshotKey(providerID);
            return Guards.hasOwnKey(controller.selectedAccounts, key) ? String(controller.selectedAccounts[key] || "") : "";
        }

        function failUsageRefresh(message) {
            errorText = message;
            loading = false;
            controller.failed(message);
        }

        function responseMessage(result, roster) {
            switch (result.outcome) {
            case "tooLarge":
                return i18n("codexbar response exceeded the supported size.");
            case "invalidJson":
                return roster ? i18n("Could not parse CodexBar provider configuration: %1", result.message) : i18n("Could not parse codexbar JSON: %1", result.message);
            case "noProviders":
                return result.message || (roster ? i18n("Could not load CodexBar provider configuration.") : i18n("codexbar did not return provider data."));
            default:
                return result.message || (roster ? i18n("Could not load CodexBar provider configuration.") : i18n("codexbar did not return JSON."));
            }
        }

        function parseOutput(stdoutText, stderrText) {
            var result = UsageResponse.response(stdoutText, stderrText, "", Date.now());
            if (result.outcome !== "success") {
                if (result.outcome === "empty" && canUseProviderFallback()) {
                    startProviderFallback();
                    return;
                }
                failUsageRefresh(responseMessage(result, false));
                return;
            }
            finishProviderFallback(result.items);
        }

        function parseProviderConfigOutput(descriptor, stdoutText, stderrText) {
            if (!descriptor || !ProviderRosterCache.responseContextsMatch(descriptor.providerRosterContext, providerRosterContext())) {
                scheduleUsageRefresh();
                return;
            }
            var result = UsageResponse.roster(stdoutText, stderrText);
            if (result.outcome !== "success") {
                failUsageRefresh(responseMessage(result, true));
                return;
            }
            providerDisplayNames = result.displayNames;
            providerRosterCache = ProviderRosterCache.remember(result.providerIDs, descriptor.providerRosterContext);
            startProviderFallbackForProviders(result.providerIDs);
        }

        function parseProviderFallbackOutput(sourceName, providerID, stdoutText, stderrText) {
            finishUsageCommandSource(sourceName);
            var result = UsageResponse.response(stdoutText, stderrText, providerID, Date.now());
            var item = result.outcome === "success" ? result.items[0] : ProviderSnapshot.normalize({
                provider: providerID,
                source: controller.sourceMode || "auto",
                error: {
                    message: responseMessage(result, false)
                }
            }, Date.now());
            completeProviderFallbackSlot(sourceName, item);
        }

        function finishProviderFallback(orderedItems) {
            var items = ProviderOrder.orderedItems(orderedItems, controller.providerOrderRaw);
            // Match the applet cache policy: an expired CLI measurement cannot
            // postpone a refresh-on-open just because its command succeeded.
            if (UsageCache.reconcile([], items, Date.now()).some(function (item) {
                return !item.commandFailed && !item.usageStale;
            }))
                usageLastCompletedAtMs = Date.now();
            errorText = items.length === 0 ? i18n("codexbar did not return JSON.") : "";
            providerFallbackState = null;
            loading = false;
            controller.snapshotReceived(items);
        }
    }

    Plasma5Support.DataSource {
        id: usageSource

        engine: "executable"
        interval: 0

        onNewData: function (sourceName, data) {
            // A reply the ledger no longer holds is a late result from a
            // retired run. Dropping it is what keeps it from overwriting the
            // refresh that replaced it.
            var descriptor = CommandLedger.find(lifecycle.activeCommandDescriptors, sourceName);
            if (!descriptor) {
                return;
            }

            var stdoutText = data ? data["stdout"] : "";
            var stderrText = data ? data["stderr"] : "";
            switch (descriptor.kind) {
            case "providerConfig":
                lifecycle.finishUsageCommandSource(sourceName);
                lifecycle.parseProviderConfigOutput(descriptor, stdoutText, stderrText);
                return;
            case "providerFallback":
                lifecycle.parseProviderFallbackOutput(sourceName, descriptor.providerID, stdoutText, stderrText);
                return;
            case "usage":
                lifecycle.finishUsageCommandSource(sourceName);
                lifecycle.parseOutput(stdoutText, stderrText);
                return;
            default:
                lifecycle.finishUsageCommandSource(sourceName);
            }
        }
    }

    Timer {
        id: usageRefreshTimer

        interval: Math.max(1, controller.refreshIntervalSec) * 1000
        repeat: true
        running: controller.refreshIntervalSec > 0
        triggeredOnStart: false
        onTriggered: {
            if (!lifecycle.hasPendingPeriodicRefreshCommands()) {
                lifecycle.refreshNow(false);
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: lifecycle.hasPendingCommandTimeouts()
        onTriggered: lifecycle.expireCommands(Date.now())
    }
}
