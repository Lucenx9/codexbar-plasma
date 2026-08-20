import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "components" as Components
import "Guards.js" as Guards
import "NotificationMemo.js" as NotificationMemo
import "NotificationPlanner.js" as NotificationPlanner
import "PanelElements.js" as PanelElements
import "CommandLedger.js" as CommandLedger
import "CostPresentation.js" as CostPresentation
import "ProviderIdentity.js" as ProviderIdentity
import "ProviderNormalizer.js" as Normalizer
import "QuotaThresholds.js" as QuotaThresholds
import "SafeText.js" as SafeText
import "ThemeContrast.js" as ThemeContrast
import "UsageDetails.js" as UsageDetails
import "UpdateLogic.js" as UpdateLogic

PlasmoidItem {
    id: root

    Plasmoid.icon: "view-statistics"
    Plasmoid.title: "CodexBar"
    toolTipMainText: Plasmoid.title
    toolTipSubText: panelToolTipText()
    toolTipTextFormat: Text.PlainText
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refreshNow()
        }
    ]

    property string commandPath: (Plasmoid.configuration.commandPath || "codexbar").trim()
    property string provider: (Plasmoid.configuration.provider || "").trim()
    property string source: (Plasmoid.configuration.source || "").trim()
    property int refreshIntervalSec: isFinite(Number(Plasmoid.configuration.refreshInterval)) ? Math.max(0, Number(Plasmoid.configuration.refreshInterval)) : 300
    property bool includeStatus: Plasmoid.configuration.includeStatus
    property bool costUsageEnabled: Plasmoid.configuration.costUsageEnabled !== false
    property int costHistoryDays: isFinite(Number(Plasmoid.configuration.costHistoryDays)) ? Math.max(1, Math.min(365, Number(Plasmoid.configuration.costHistoryDays))) : 30
    // The cost payload already carries per-day tokens next to per-day cost, so
    // switching the plotted metric never needs a second CLI call.
    property string costHistoryMetric: safeCostHistoryMetric(Plasmoid.configuration.costHistoryMetric)
    readonly property bool costHistoryShowsTokens: costHistoryMetric === "tokens"
    // Resolved once: a .pragma library module cannot reach Qt.locale().
    readonly property var costNumberFormat: CostPresentation.numberFormat(
        Qt.locale().groupSeparator, Qt.locale().decimalPoint)
    property bool usageBarsShowUsed: Plasmoid.configuration.usageBarsShowUsed === true
    property bool showQuotaWarningMarkers: Plasmoid.configuration.showQuotaWarningMarkers !== false
    readonly property int quotaWarningPercent: QuotaThresholds.warningPercent(
        Plasmoid.configuration.quotaWarningPercent)
    // Derived from the warning step so a critical threshold configured below it
    // can never make the "major" level unreachable.
    readonly property int quotaCriticalPercent: QuotaThresholds.criticalPercent(
        quotaWarningPercent,
        Plasmoid.configuration.quotaCriticalPercent)
    property bool enableNotifications: Plasmoid.configuration.enableNotifications !== false
    property bool notifyStatusIncidents: Plasmoid.configuration.notifyStatusIncidents !== false
    property bool notifyQuotaWarnings: Plasmoid.configuration.notifyQuotaWarnings !== false
    property bool notifyPredictivePaceWarnings: Plasmoid.configuration.notifyPredictivePaceWarnings === true
    property bool notifyLimitResets: Plasmoid.configuration.notifyLimitResets !== false
    property bool updateChecksEnabled: Plasmoid.configuration.updateChecksEnabled !== false
    property bool updateNotificationsEnabled: Plasmoid.configuration.updateNotificationsEnabled !== false
    property bool autoUpdateEnabled: Plasmoid.configuration.autoUpdateEnabled === true
    property int autoUpdateIntervalHours: isFinite(Number(Plasmoid.configuration.autoUpdateIntervalHours)) ? Math.max(1, Math.min(168, Number(Plasmoid.configuration.autoUpdateIntervalHours))) : 24
    property string autoUpdateLastCheck: Plasmoid.configuration.autoUpdateLastCheck || ""
    property string menuBarDisplayMode: safeMenuBarDisplayMode(Plasmoid.configuration.menuBarDisplayMode)
    property string panelElementOrderRaw: Plasmoid.configuration.panelElementOrder || ""
    property bool resetTimesShowAbsolute: Plasmoid.configuration.resetTimesShowAbsolute === true
    property bool showProviderChangelogs: Plasmoid.configuration.showProviderChangelogs === true
    property bool autoSelectProvider: Plasmoid.configuration.autoSelectProvider === true
    property string overviewProviderIDsRaw: Plasmoid.configuration.overviewProviderIDs || ""
    readonly property int maxOverviewProviders: 3
    property int providerConfigRevision: boundedConfigRevision(Plasmoid.configuration.providerConfigRevision)
    property var providers: []
    property var providerDisplayNames: ({})
    property string errorText: ""
    property string lastUpdatedText: ""
    property bool loading: false
    property string commandSource: buildCommand()
    property string providerConfigCommandSource: buildProviderConfigCommand()
    property string providerConfigWatchCommand: buildProviderConfigWatchCommand()
    property string providerConfigStamp: ""
    readonly property int providerConfigWatchIntervalMs: 60000
    property int commandRunSerial: 0
    property var activeUsageCommands: ({})
    readonly property int usageCommandTimeoutMs: 120000
    readonly property int maximumExtraRateWindows: Normalizer.maximumExtraRateWindows
    readonly property int maximumProviderSnapshots: Normalizer.maximumProviderSnapshots
    readonly property int maximumAccountSnapshots: Normalizer.maximumAccountSnapshots
    readonly property int maximumCostSnapshots: Normalizer.maximumCostSnapshots
    readonly property int maximumCostHistoryPoints: Normalizer.maximumCostHistoryPoints
    readonly property int maximumCostHistoryScanItems: Normalizer.maximumCostHistoryScanItems
    readonly property int maximumModelBreakdownsPerDay: Normalizer.maximumModelBreakdownsPerDay
    readonly property int maximumConcurrentProviderFallbackCommands: 8
    property var pendingProviderCommands: ({})
    property var fallbackProviderQueue: []
    property int activeProviderFallbackCount: 0
    property var fallbackProviderOrder: []
    property var fallbackProviderResults: ({})
    property var fallbackProviderSeen: ({})
    property int pendingProviderCount: 0
    property bool providerFallbackActive: false
    property string costCommandSource: buildCostCommand()
    readonly property bool costLoading: CommandLedger.hasKind(activeUsageCommands, "cost")
    property var tokenCosts: ({})
    property string costErrorText: ""
    property string sessionsCommandSource: buildSessionsCommand()
    property var sessions: []
    property string sessionsErrorText: ""
    property string sessionsLastUpdatedText: ""
    property bool sessionsLoading: false
    property bool sessionsInitialized: false
    readonly property int maximumSessions: Normalizer.maximumSessions
    readonly property int sessionsCommandTimeoutMs: 60000
    property string selectedProviderID: ""
    property string selectedGlobalView: "overview"
    property bool selectionInitialized: false
    property var selectedAccounts: ({})
    property var accountOptions: ({})
    property var accountErrors: ({})
    property var accountLoading: ({})
    property var pendingAccountCommands: ({})
    readonly property int accountCommandTimeoutMs: 60000
    property var notificationMemo: ({})
    property var notificationRefreshPending: ({})
    property bool notificationsPrimed: false
    property string connectedUpdateCommandSource: ""
    readonly property int widgetUpdateCheckTimeoutMs: 60000
    readonly property int widgetAutoUpdateTimeoutMs: 600000
    readonly property int widgetUpdateMinimumTimerDelayMs: 60000
    property string updateStatusText: boundedWidgetUpdateText(Plasmoid.configuration.widgetUpdateLastStatus)
    property string updateErrorText: boundedWidgetUpdateText(Plasmoid.configuration.widgetUpdateLastError)
    property string lastNotifiedUpdateVersion: Plasmoid.configuration.lastNotifiedUpdateVersion || ""
    readonly property bool verticalFormFactor: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var overviewProviderItems: overviewProviders()
    readonly property bool globalNavigationAvailable: provider.length === 0
    readonly property bool overviewAvailable: globalNavigationAvailable && providers.length > 1 && overviewProviderItems.length > 0
    readonly property bool spendAvailable: globalNavigationAvailable && costUsageEnabled
    readonly property bool sessionsAvailable: globalNavigationAvailable
    readonly property int selectedProviderIndex: providerIndexForID(selectedProviderID)
    readonly property bool globalViewSelected: selectionInitialized && selectedProviderID.length === 0
    readonly property bool overviewSelected: overviewAvailable && globalViewSelected && selectedGlobalView === "overview"
    readonly property bool spendSelected: spendAvailable && globalViewSelected && selectedGlobalView === "spend"
    readonly property bool sessionsSelected: sessionsAvailable && globalViewSelected && selectedGlobalView === "sessions"
    readonly property bool providerUsageFeedbackVisible: !spendSelected && !sessionsSelected
    readonly property var selectedProviderData: providers.length > 0 && selectedProviderIndex >= 0
        ? providers[Math.min(selectedProviderIndex, providers.length - 1)]
        : null
    readonly property real roundedSurfaceRadius: Kirigami.Units.cornerRadius
        + Kirigami.Units.smallSpacing
    // Radius for a small surface drawn inside a roundedSurfaceRadius container.
    // Concentric rounding wants the inner radius reduced by the inset between
    // the two edges, and popup surfaces inset their content by smallSpacing, so
    // this is roundedSurfaceRadius minus that inset by construction.
    readonly property real nestedSurfaceRadius: Kirigami.Units.cornerRadius
    // Two-step de-emphasis scale for popup text. A supporting label uses the
    // secondary step and the value it annotates uses the stronger step, so a
    // label/value pair keeps its hierarchy without inventing a new opacity per
    // section. 0.7 is the lowest step where Kirigami.Theme.textColor still
    // clears WCAG AA 4.5:1 against the Breeze Light popup background.
    readonly property real secondaryTextOpacity: 0.7
    readonly property real valueTextOpacity: 0.85
    // Shared track height for the credits, cost, and usage meters that stack in
    // one provider detail view. Derived from gridUnit so it follows the user
    // font size instead of pinning a device pixel count.
    readonly property real meterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.4)
    // Thinner track for meters that sit inside a scannable list row (overview
    // rows, cost history rows) instead of leading a detail section. Keeping the
    // two scales apart is what makes the primary meters read as primary.
    readonly property real compactMeterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.28)

    onCommandSourceChanged: Qt.callLater(refreshNow)
    onCostUsageEnabledChanged: Qt.callLater(refreshCost)
    onCostHistoryDaysChanged: Qt.callLater(refreshCost)
    onProviderConfigRevisionChanged: Qt.callLater(refreshNow)
    onAutoSelectProviderChanged: updateSelectedProvider()
    onOverviewProviderIDsRawChanged: updateSelectedProvider()
    onEnableNotificationsChanged: resetNotificationMemo()
    onNotifyStatusIncidentsChanged: resetNotificationMemo()
    onNotifyQuotaWarningsChanged: resetNotificationMemo()
    onNotifyPredictivePaceWarningsChanged: resetNotificationMemo()
    // The memo stores the level each row was last observed at. Keeping it across
    // a threshold change would suppress a warning the new lower threshold should
    // raise, and leave a row armed at a level the new higher threshold no longer
    // reaches.
    onQuotaWarningPercentChanged: resetNotificationMemo()
    onQuotaCriticalPercentChanged: resetNotificationMemo()
    onNotifyLimitResetsChanged: resetNotificationMemo()
    onUpdateChecksEnabledChanged: {
        if (updateChecksEnabled) {
            Qt.callLater(function() { root.checkForWidgetUpdate(true) })
        } else {
            updateCheckTimer.stop()
        }
    }
    onAutoUpdateIntervalHoursChanged: scheduleNextUpdateCheck()
    onAutoUpdateEnabledChanged: {
        if (updateChecksEnabled && autoUpdateEnabled) {
            Qt.callLater(function() { root.checkForWidgetUpdate(true) })
        }
    }
    onProvidersChanged: {
        if (providers.length === 0) {
            selectedProviderID = ""
            if (!globalNavigationAvailable) {
                selectionInitialized = false
            }
            resetNotificationMemo()
            return
        }
        updateSelectedProvider()
        Qt.callLater(processNotifications)
    }

    Component.onCompleted: {
        if (providerConfigWatchCommand.length > 0) {
            providerConfigWatcher.connectSource(providerConfigWatchCommand)
        }
        refreshNow()
        if (updateChecksEnabled) {
            scheduleNextUpdateCheck()
            Qt.callLater(checkForWidgetUpdate)
        }
    }

    function buildCommand() {
        if (commandPath.length === 0) {
            return ""
        }

        var parts = [
            shellQuote(commandPath),
            "usage",
            "--format",
            "json",
            "--json-only"
        ]

        if (provider.length > 0) {
            parts.push("--provider")
            parts.push(shellQuote(provider))
            var selectedAccount = selectedAccountForProvider(provider)
            if (selectedAccount.length > 0) {
                parts.push("--account")
                parts.push(shellQuote(selectedAccount))
            }
        }

        if (source.length > 0) {
            parts.push("--source")
            parts.push(shellQuote(source))
        }

        if (includeStatus) {
            parts.push("--status")
        }

        return parts.join(" ")
    }

    function buildProviderAccountsCommand(providerID) {
        if (commandPath.length === 0) {
            return ""
        }

        var parts = [
            shellQuote(commandPath),
            "usage",
            "--provider",
            shellQuote(providerCliArgument(providerID)),
            "--all-accounts",
            "--format",
            "json",
            "--json-only"
        ]

        if (source.length > 0) {
            parts.push("--source")
            parts.push(shellQuote(source))
        }

        if (includeStatus) {
            parts.push("--status")
        }

        return parts.join(" ")
    }

    function buildProviderConfigCommand() {
        if (commandPath.length === 0) {
            return ""
        }

        return [
            shellQuote(commandPath),
            "config",
            "providers",
            "--format",
            "json",
            "--json-only"
        ].join(" ")
    }

    function buildProviderConfigWatchCommand() {
        var script = [
            "config=${CODEXBAR_CONFIG:-};",
            "case \"$config\" in '~/'*) config=\"$HOME/${config#\\~/}\";; esac;",
            "if [ -z \"$config\" ]; then",
            "xdg=${XDG_CONFIG_HOME:-};",
            "case \"$xdg\" in '~/'*) xdg=\"$HOME/${xdg#\\~/}\";; esac;",
            "case \"$xdg\" in",
            "/*) config=\"$xdg/codexbar/config.json\";;",
            "*) config=\"$HOME/.config/codexbar/config.json\"; if [ ! -e \"$config\" ] && [ -e \"$HOME/.codexbar/config.json\" ]; then config=\"$HOME/.codexbar/config.json\"; fi;;",
            "esac;",
            "fi;",
            "if [ -r \"$config\" ]; then cksum \"$config\"; else printf missing; fi"
        ].join(" ")
        return ["sh", "-c", shellQuote(script)].join(" ")
    }

    function buildProviderUsageCommand(providerID) {
        var parts = [
            shellQuote(commandPath),
            "usage",
            "--provider",
            shellQuote(providerCliArgument(providerID)),
            "--format",
            "json",
            "--json-only"
        ]

        if (source.length > 0) {
            parts.push("--source")
            parts.push(shellQuote(source))
        }

        var selectedAccount = selectedAccountForProvider(providerID)
        if (selectedAccount.length > 0) {
            parts.push("--account")
            parts.push(shellQuote(selectedAccount))
        }

        if (includeStatus) {
            parts.push("--status")
        }

        return parts.join(" ")
    }

    function buildCostCommand() {
        if (commandPath.length === 0) {
            return ""
        }
        if (!costUsageEnabled) {
            return ""
        }

        var parts = [
            shellQuote(commandPath),
            "cost",
            "--format",
            "json",
            "--json-only",
            "--days",
            String(costHistoryDays)
        ]

        if (provider.length > 0) {
            parts.push("--provider")
            parts.push(shellQuote(provider))
        }

        return parts.join(" ")
    }

    function buildSessionsCommand() {
        if (commandPath.length === 0) {
            return ""
        }
        return [shellQuote(commandPath), "sessions", "--json-v2"].join(" ")
    }

    function shellQuote(value) {
        return Guards.shellQuote(value)
    }

    function safeMenuBarDisplayMode(value) {
        var mode = String(value || "percent")
        if (mode === "percent" || mode === "pace" || mode === "both"
                || mode === "resetTime" || mode === "runOut") {
            return mode
        }
        return "percent"
    }

    function safeCostHistoryMetric(value) {
        return String(value || "cost") === "tokens" ? "tokens" : "cost"
    }

    function panelElementOrder() {
        return PanelElements.normalizedOrder(panelElementOrderRaw)
    }

    function boundedConfigRevision(value) {
        var revision = Number(value)
        if (!isFinite(revision)) {
            return 0
        }
        return Math.max(0, Math.min(2147480000, Math.floor(revision)))
    }

    function boundedDisplayText(value, maximumLength) {
        var limit = Number(maximumLength)
        if (!isFinite(limit) || limit <= 0) {
            limit = 500
        }
        limit = Math.min(2000, Math.floor(limit))
        return SafeText.boundedDisplayText(value, limit)
    }

    function boundedWidgetUpdateText(value) {
        return boundedDisplayText(value, 500)
    }

    function boundedCliMessage(value) {
        return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
    }

    function isCliRecord(value) {
        return Normalizer.isCliRecord(value)
    }

    function normalizedProviderID(value) {
        return Normalizer.normalizedProviderID(value)
    }

    function hasOwnKey(item, key) {
        return Guards.hasOwnKey(item, key)
    }

    function isUnsafeObjectKey(key) {
        return Guards.isUnsafeObjectKey(key)
    }

    function providerMapKey(providerID) {
        return Normalizer.providerSnapshotKey(providerID)
    }

    function commandWithRunNonce(command) {
        if (command.length === 0) {
            return ""
        }
        commandRunSerial += 1
        return CommandLedger.withRunNonce(command, commandRunSerial)
    }

    function connectUsageCommand(sourceName, descriptor) {
        if (sourceName.length === 0) {
            return
        }

        activeUsageCommands = CommandLedger.opened(activeUsageCommands, sourceName, descriptor)
        usageSource.connectSource(sourceName)
    }

    function buildUsageCommandDescriptor(kind, providerID, timeoutMs) {
        return CommandLedger.descriptor(
            kind, providerID, Date.now(), timeoutMs, usageCommandTimeoutMs)
    }

    function buildCostCommandDescriptor() {
        var descriptor = buildUsageCommandDescriptor("cost", "")
        descriptor.costHistoryDays = costHistoryDays
        return descriptor
    }

    function finishUsageCommandSource(sourceName) {
        if (sourceName.length === 0) {
            return
        }

        usageSource.disconnectSource(sourceName)
        activeUsageCommands = CommandLedger.closed(activeUsageCommands, sourceName)
    }

    // Retiring by kind is what makes a late reply harmless: the source name
    // leaves the ledger, so routing no longer recognises it.
    function retireUsageCommandKind(kind) {
        var sourceNames = CommandLedger.sourcesOfKind(activeUsageCommands, kind)
        for (var i = 0; i < sourceNames.length; i++) {
            finishUsageCommandSource(sourceNames[i])
        }
        return sourceNames.length
    }

    function refreshNow() {
        retireUsageCommands()
        retireStaleAccountCommands()
        refreshCost()
        if (sessionsInitialized) {
            refreshSessions()
        }
        providerFallbackActive = false

        if (commandSource.length === 0) {
            loading = false
            errorText = i18n("Set the codexbar command path in widget settings.")
            return
        }

        loading = true
        errorText = ""
        if (canUseProviderFallback()) {
            startProviderFallback()
            return
        }
        connectUsageCommand(
            commandWithRunNonce(commandSource),
            buildUsageCommandDescriptor("usage", ""))
    }

    function retireUsageCommands() {
        retireUsageCommandKind("usage")
        retireUsageCommandKind("providerConfig")
        if (retireUsageCommandKind("sessions") > 0) {
            sessionsLoading = false
        }
        for (var command in pendingProviderCommands) {
            finishUsageCommandSource(command)
        }
        // Account loads are user-triggered; keep them alive across usage refreshes
        // so their replies can still populate the account picker.
        pendingProviderCommands = ({})
        fallbackProviderQueue = []
        activeProviderFallbackCount = 0
        fallbackProviderOrder = []
        fallbackProviderResults = ({})
        fallbackProviderSeen = ({})
        pendingProviderCount = 0
    }

    function handleProviderConfigWatch(stdoutText) {
        var stamp = stdoutText.trim()
        if (stamp.length === 0) {
            return
        }
        if (providerConfigStamp.length === 0) {
            providerConfigStamp = stamp
            return
        }
        if (stamp === providerConfigStamp) {
            return
        }
        providerConfigStamp = stamp
        Qt.callLater(refreshNow)
    }

    function refreshCost() {
        retireUsageCommandKind("cost")

        if (costCommandSource.length === 0) {
            tokenCosts = ({})
            costErrorText = ""
            applyTokenCosts()
            return
        }

        costErrorText = ""
        connectUsageCommand(
            commandWithRunNonce(costCommandSource),
            buildCostCommandDescriptor())
    }

    function refreshSessions() {
        retireUsageCommandKind("sessions")

        sessionsInitialized = true
        if (sessionsCommandSource.length === 0) {
            sessionsLoading = false
            sessionsErrorText = i18n("Set the codexbar command path in widget settings.")
            return
        }

        sessionsLoading = true
        sessionsErrorText = ""
        connectUsageCommand(
            commandWithRunNonce(sessionsCommandSource),
            buildUsageCommandDescriptor("sessions", "", sessionsCommandTimeoutMs))
    }

    function parseOutput(stdoutText, stderrText) {
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            if (canUseProviderFallback()) {
                startProviderFallback()
                return
            }
            providers = []
            errorText = stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("codexbar did not return JSON.")
            loading = false
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            providers = []
            errorText = i18n("Could not parse codexbar JSON: %1", error.message)
            loading = false
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var nextProviders = []
        var itemLimit = Math.min(items.length, maximumProviderSnapshots)
        for (var i = 0; i < itemLimit; i++) {
            if (!isCliRecord(items[i]) || normalizedProviderID(items[i].provider).length === 0) {
                continue
            }
            nextProviders.push(normalizeProvider(items[i]))
        }

        markNotificationProvidersFresh(nextProviders)
        providers = nextProviders
        errorText = nextProviders.length === 0 ? boundedCliMessage(stderrText) : ""
        lastUpdatedText = i18n("Updated %1", Qt.formatDateTime(new Date(), "hh:mm"))
        loading = false
    }

    function hasSelectedAccountOverrides() {
        for (var providerID in selectedAccounts) {
            if (hasOwnKey(selectedAccounts, providerID)
                && String(selectedAccounts[providerID] || "").length > 0) {
                return true
            }
        }
        return false
    }

    function canUseProviderFallback() {
        return source.length === 0 || hasSelectedAccountOverrides()
    }

    function startProviderFallback() {
        providerFallbackActive = true
        retireUsageCommandKind("usage")
        if (provider.length > 0) {
            startProviderFallbackForProviders([providerKey(provider)])
            return
        }

        if (providerConfigCommandSource.length === 0) {
            providers = []
            errorText = i18n("codexbar did not return JSON.")
            loading = false
            return
        }

        connectUsageCommand(
            commandWithRunNonce(providerConfigCommandSource),
            buildUsageCommandDescriptor("providerConfig", ""))
    }

    function parseProviderConfigOutput(stdoutText, stderrText) {
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            providers = []
            errorText = stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("Could not load CodexBar provider configuration.")
            loading = false
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            providers = []
            errorText = i18n("Could not parse CodexBar provider configuration: %1", error.message)
            loading = false
            return
        }

        var entries = Normalizer.normalizeProviderConfigEntries(payload)
        providerDisplayNames = entries.displayNames
        startProviderFallbackForProviders(entries.providerIDs)
    }

    function startProviderFallbackForProviders(providerIDs) {
        for (var existingCommand in pendingProviderCommands) {
            finishUsageCommandSource(existingCommand)
        }
        pendingProviderCommands = ({})
        fallbackProviderQueue = []
        activeProviderFallbackCount = 0
        fallbackProviderOrder = []
        fallbackProviderResults = ({})
        fallbackProviderSeen = ({})
        pendingProviderCount = 0

        var seenCommands = ({})
        var commands = ({})
        var commandList = []
        var providerLimit = Math.min(providerIDs.length, maximumProviderSnapshots)
        for (var i = 0; i < providerLimit; i++) {
            var providerID = normalizedProviderID(String(providerIDs[i] || ""))
            if (providerID.length === 0) {
                continue
            }
            var baseCommand = buildProviderUsageCommand(providerID)
            if (seenCommands[baseCommand]) {
                continue
            }
            seenCommands[baseCommand] = true
            var command = commandWithRunNonce(baseCommand)
            commands[command] = providerID
            commandList.push(command)
            fallbackProviderOrder.push(providerID)
            pendingProviderCount++
        }

        pendingProviderCommands = commands
        fallbackProviderQueue = commandList
        pumpProviderFallbackCommands()
        if (pendingProviderCount === 0) {
            providers = []
            errorText = i18n("No enabled CodexBar providers.")
            loading = false
        }
    }

    function pumpProviderFallbackCommands() {
        var queue = fallbackProviderQueue.slice()
        while (activeProviderFallbackCount < maximumConcurrentProviderFallbackCommands
                && queue.length > 0) {
            var sourceName = queue.shift()
            var providerID = pendingProviderCommands[sourceName] || ""
            if (providerID.length === 0) {
                continue
            }
            activeProviderFallbackCount++
            connectUsageCommand(
                sourceName,
                buildUsageCommandDescriptor("providerFallback", providerID))
        }
        fallbackProviderQueue = queue
    }

    function parseProviderFallbackOutput(sourceName, stdoutText, stderrText) {
        var providerID = pendingProviderCommands[sourceName] || ""
        if (providerID.length === 0) {
            return
        }
        var commands = copyObject(pendingProviderCommands)
        delete commands[sourceName]
        pendingProviderCommands = commands
        finishUsageCommandSource(sourceName)

        if (hasOwnKey(fallbackProviderSeen, providerID)) {
            completeProviderFallbackCommand()
            return
        }
        var seen = copyObject(fallbackProviderSeen)
        seen[providerID] = true
        fallbackProviderSeen = seen

        var normalizedItems = []
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            normalizedItems.push(normalizeProvider(providerErrorPayload(
                providerID,
                stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("codexbar did not return JSON."))))
        } else {
            var payload
            try {
                payload = JSON.parse(trimmed)
                var items = Array.isArray(payload) ? payload : [payload]
                var itemLimit = Math.min(items.length, maximumAccountSnapshots)
                for (var i = 0; i < itemLimit; i++) {
                    if (!isCliRecord(items[i])) {
                        continue
                    }
                    var providerItem = copyObject(items[i])
                    // A provider-scoped command may only update the requested
                    // provider, even if a malformed CLI payload claims another id.
                    providerItem.provider = providerID
                    normalizedItems.push(normalizeProvider(providerItem))
                }
            } catch (error) {
                normalizedItems.push(normalizeProvider(providerErrorPayload(
                    providerID,
                    i18n("Could not parse codexbar JSON: %1", error.message))))
            }
        }

        var results = copyObject(fallbackProviderResults)
        results[providerID] = normalizedItems
        fallbackProviderResults = results
        completeProviderFallbackCommand()
    }

    function completeProviderFallbackCommand() {
        activeProviderFallbackCount = Math.max(0, activeProviderFallbackCount - 1)
        pendingProviderCount = Math.max(0, pendingProviderCount - 1)
        pumpProviderFallbackCommands()

        if (pendingProviderCount === 0) {
            finishProviderFallback()
        }
    }

    function finishProviderFallback() {
        var nextProviders = []
        // This global delegate budget deliberately wins over completeness if a
        // future provider-scoped CLI response starts returning many accounts.
        for (var i = 0; i < fallbackProviderOrder.length
                && nextProviders.length < maximumProviderSnapshots; i++) {
            var providerID = fallbackProviderOrder[i]
            var items = fallbackProviderResults[providerID] || []
            for (var j = 0; j < items.length
                    && nextProviders.length < maximumProviderSnapshots; j++) {
                nextProviders.push(items[j])
            }
        }

        markNotificationProvidersFresh(nextProviders)
        providers = nextProviders
        errorText = nextProviders.length === 0 ? i18n("codexbar did not return JSON.") : ""
        lastUpdatedText = i18n("Updated %1", Qt.formatDateTime(new Date(), "hh:mm"))
        loading = false
        pendingProviderCommands = ({})
        fallbackProviderQueue = []
        activeProviderFallbackCount = 0
        fallbackProviderSeen = ({})
        pendingProviderCount = 0
        applyTokenCosts()
    }

    function providerErrorPayload(providerID, message) {
        return {
            provider: providerID,
            source: source.length > 0 ? source : "auto",
            error: {
                code: 1,
                kind: "provider",
                message: message
            }
        }
    }

    function loadAccounts(providerID) {
        var normalizedProviderID = providerKey(providerID)
        if (accountLoadingForProvider(normalizedProviderID)) {
            return
        }

        var command = buildProviderAccountsCommand(normalizedProviderID)
        if (command.length === 0) {
            setAccountError(normalizedProviderID, i18n("Set the codexbar command path in widget settings."))
            return
        }

        setAccountError(normalizedProviderID, "")
        setAccountLoading(normalizedProviderID, true)
        var connectedCommand = commandWithRunNonce(command)
        var commands = copyObject(pendingAccountCommands)
        commands[connectedCommand] = {
            providerID: normalizedProviderID,
            commandSignature: command,
            deadlineMs: Date.now() + accountCommandTimeoutMs
        }
        pendingAccountCommands = commands
        connectUsageCommand(connectedCommand, {
            kind: "account",
            providerID: normalizedProviderID,
            deadlineMs: 0
        })
    }

    function accountCommandIsCurrent(descriptor) {
        return descriptor
            && descriptor.commandSignature === buildProviderAccountsCommand(descriptor.providerID)
    }

    function retireStaleAccountCommands() {
        var commands = copyObject(pendingAccountCommands)
        var staleProviders = ({})
        for (var sourceName in commands) {
            if (!hasOwnKey(commands, sourceName)) {
                continue
            }
            var descriptor = commands[sourceName]
            if (accountCommandIsCurrent(descriptor)) {
                continue
            }
            var providerID = descriptor ? providerMapKey(descriptor.providerID) : ""
            finishUsageCommandSource(sourceName)
            delete commands[sourceName]
            if (providerID.length > 0) {
                staleProviders[providerID] = true
            }
        }
        pendingAccountCommands = commands
        for (var staleProviderID in staleProviders) {
            if (hasOwnKey(staleProviders, staleProviderID)) {
                setAccountLoading(staleProviderID, false)
            }
        }
    }

    function hasPendingUsageCommandTimeouts() {
        return CommandLedger.hasDeadlines(activeUsageCommands)
    }

    function expireUsageCommands(nowMs) {
        var expired = CommandLedger.expired(activeUsageCommands, nowMs)
        for (var i = 0; i < expired.length; i++) {
            handleUsageCommandTimeout(expired[i].sourceName, expired[i].descriptor)
        }
    }

    // The ledger entry already proves the command is the live one for its kind,
    // so the kind alone decides how the timeout is reported.
    function handleUsageCommandTimeout(sourceName, descriptor) {
        if (!descriptor || !CommandLedger.find(activeUsageCommands, sourceName)) {
            return
        }

        switch (descriptor.kind) {
        case "usage":
            finishUsageCommandSource(sourceName)
            if (canUseProviderFallback()) {
                startProviderFallback()
                return
            }
            providers = []
            loading = false
            errorText = i18n("Loading usage timed out. Try again.")
            return
        case "cost":
            finishUsageCommandSource(sourceName)
            costErrorText = i18n("Loading cost data timed out. Try again.")
            applyTokenCosts()
            return
        case "sessions":
            finishUsageCommandSource(sourceName)
            sessionsLoading = false
            sessionsErrorText = i18n("Loading sessions timed out. Try again.")
            return
        case "providerConfig":
            finishUsageCommandSource(sourceName)
            providers = []
            loading = false
            errorText = i18n("Loading provider configuration timed out. Try again.")
            return
        case "providerFallback":
            parseProviderFallbackOutput(
                sourceName,
                "",
                i18n("Loading usage timed out. Try again."))
            return
        default:
            finishUsageCommandSource(sourceName)
        }
    }

    function hasPendingAccountCommands() {
        for (var sourceName in pendingAccountCommands) {
            if (hasOwnKey(pendingAccountCommands, sourceName)) {
                return true
            }
        }
        return false
    }

    function expirePendingAccountCommands(nowMs) {
        var commands = copyObject(pendingAccountCommands)
        var expired = []
        for (var pendingSourceName in commands) {
            if (!hasOwnKey(commands, pendingSourceName)) {
                continue
            }
            var descriptor = commands[pendingSourceName]
            var deadline = Number(descriptor.deadlineMs)
            if (!isFinite(deadline) || nowMs < deadline) {
                continue
            }
            expired.push({ sourceName: pendingSourceName, providerID: descriptor.providerID })
            delete commands[pendingSourceName]
        }
        if (expired.length === 0) {
            return
        }

        pendingAccountCommands = commands
        for (var i = 0; i < expired.length; i++) {
            var item = expired[i]
            var sourceName = item.sourceName
            var providerID = item.providerID
            finishUsageCommandSource(sourceName)
            setAccountLoading(providerID, false)
            setAccountError(providerID, i18n("Loading accounts timed out. Try again."))
        }
    }

    function parseProviderAccountsOutput(sourceName, stdoutText, stderrText) {
        var descriptor = pendingAccountCommands[sourceName] || null
        var providerID = descriptor ? descriptor.providerID : ""
        if (providerID.length === 0) {
            return
        }

        var commands = copyObject(pendingAccountCommands)
        delete commands[sourceName]
        pendingAccountCommands = commands
        finishUsageCommandSource(sourceName)
        setAccountLoading(providerID, false)
        if (!accountCommandIsCurrent(descriptor)) {
            return
        }

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            setAccountError(providerID, stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("codexbar did not return account data."))
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            setAccountError(providerID, i18n("Could not parse codexbar account JSON: %1", error.message))
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var options = []
        var message = ""
        var sawMissingTokenAccountsError = false
        var itemLimit = Math.min(items.length, maximumAccountSnapshots)
        for (var i = 0; i < itemLimit; i++) {
            var item = items[i]
            if (!isCliRecord(item)) {
                continue
            }
            var accountItem = copyObject(item)
            accountItem.provider = providerID
            var normalized = normalizeProvider(accountItem)
            if (normalized.error.length > 0 && accountLabel(normalized).length === 0) {
                if (Normalizer.isMissingTokenAccountsError(normalized.error)) {
                    sawMissingTokenAccountsError = true
                } else {
                    message = normalized.error
                }
                continue
            }
            options.push(normalized)
        }

        var dedupedOptions = Normalizer.dedupeAccountOptions(options)
        var accountError = ""
        if (dedupedOptions.length === 0) {
            if (message.length > 0) {
                accountError = message
            } else if (items.length > 0 && !sawMissingTokenAccountsError) {
                accountError = i18n("codexbar did not return account data.")
            }
        }
        if (accountError.length === 0) {
            setAccountOptions(providerID, dedupedOptions)
        }
        setAccountError(providerID, accountError)
    }

    function parseCostOutput(stdoutText, stderrText, requestedHistoryDays) {
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            costErrorText = stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("codexbar cost did not return JSON.")
            applyTokenCosts()
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            costErrorText = i18n("Could not parse codexbar cost JSON: %1", error.message)
            applyTokenCosts()
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var nextCosts = ({})
        var costMessage = ""
        var itemLimit = Math.min(items.length, maximumCostSnapshots)
        for (var i = 0; i < itemLimit; i++) {
            var item = items[i]
            if (!isCliRecord(item)) {
                continue
            }
            if (costMessage.length === 0 && item && item.error && item.error.message) {
                costMessage = boundedCliMessage(item.error.message)
            }
            var cost = normalizeTokenCost(item, requestedHistoryDays)
            var providerID = cost ? providerMapKey(cost.provider) : ""
            if (cost && providerID.length > 0) {
                nextCosts[providerID] = cost
            }
        }

        if (costMessage.length > 0) {
            var mergedCosts = copyObject(tokenCosts)
            for (var providerKeyName in nextCosts) {
                if (hasOwnKey(nextCosts, providerKeyName)) {
                    mergedCosts[providerKeyName] = nextCosts[providerKeyName]
                }
            }
            tokenCosts = mergedCosts
            costErrorText = costMessage
        } else {
            tokenCosts = nextCosts
            costErrorText = ""
        }
        applyTokenCosts()
    }

    function parseSessionsOutput(stdoutText, stderrText) {
        sessionsLoading = false
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            sessionsErrorText = stderrText.trim().length > 0
                ? boundedCliMessage(stderrText)
                : i18n("codexbar sessions did not return JSON.")
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            sessionsErrorText = i18n("Could not parse codexbar sessions JSON: %1", error.message)
            return
        }

        // null means the payload shape is unsupported. It must not read as an
        // empty successful snapshot, which would wipe the visible sessions.
        var nextSessions = Normalizer.normalizeSessions(payload)
        if (nextSessions === null) {
            sessionsErrorText = i18n("codexbar sessions returned an unsupported JSON payload.")
            return
        }
        sessions = nextSessions
        sessionsErrorText = ""
        sessionsLastUpdatedText = i18n("Updated %1", Qt.formatDateTime(new Date(), "hh:mm"))
    }

    function sessionTitle(item) {
        if (!item) {
            return i18n("Untitled session")
        }
        return item.projectName.length > 0
            ? item.projectName
            : (item.sessionName.length > 0 ? item.sessionName : i18n("Untitled session"))
    }

    function sessionSubtitle(item) {
        if (!item) {
            return ""
        }
        var details = []
        if (item.provider.length > 0) {
            details.push(providerTitle(item.provider))
        }
        if (item.host.length > 0) {
            details.push(item.host)
        }
        if (item.source.length > 0) {
            details.push(item.source)
        }
        return details.join(" - ")
    }

    function sessionActivityText(item, nowMs) {
        if (!item || !isFinite(Number(item.activityMs)) || Number(item.activityMs) <= 0) {
            return ""
        }
        var currentTimeMs = Number(nowMs)
        if (!isFinite(currentTimeMs) || currentTimeMs <= 0) {
            currentTimeMs = Date.now()
        }
        var elapsedSeconds = Math.max(0, Math.floor((currentTimeMs - Number(item.activityMs)) / 1000))
        if (elapsedSeconds < 60) {
            return i18n("Just now")
        }
        var minutes = Math.floor(elapsedSeconds / 60)
        if (minutes < 60) {
            return i18np("%1 minute ago", "%1 minutes ago", minutes)
        }
        var hours = Math.floor(minutes / 60)
        if (hours < 24) {
            return i18np("%1 hour ago", "%1 hours ago", hours)
        }
        var days = Math.floor(hours / 24)
        return i18np("%1 day ago", "%1 days ago", days)
    }

    function normalizeTokenCost(item, requestedHistoryDays) {
        if (!item || !item.provider) {
            return null
        }

        var providerID = providerMapKey(item.provider)
        if (providerID.length === 0) {
            return null
        }
        var currency = boundedDisplayText(item.currencyCode || "USD", 12)
        var emittedHistoryDays = Number(item.historyDays)
        var fallbackHistoryDays = Number(requestedHistoryDays)
        var historyDays = isFinite(emittedHistoryDays) && emittedHistoryDays > 0
            ? Math.max(1, Math.min(maximumCostHistoryPoints, Math.floor(emittedHistoryDays)))
            : (isFinite(fallbackHistoryDays) && fallbackHistoryDays > 0
            ? Math.max(1, Math.min(maximumCostHistoryPoints, Math.floor(fallbackHistoryDays)))
            : 30)
        var windowLabel = boundedDisplayText(item.historyLabel || costHistoryWindowLabel(item, historyDays), 120)
        return {
            provider: providerID,
            historyDays: historyDays,
            // Older payloads omit the flag; absent means "do not warn".
            historyCoverageEstablished: item.historyCoverageIsEstablished !== false,
            title: i18n("Cost"),
            sessionLine: costLine(i18n("Today"), item.sessionCostUSD, item.sessionTokens, currency),
            monthLine: costLine(windowLabel, item.last30DaysCostUSD, item.last30DaysTokens, currency),
            windowValueLine: costValueLine(item.last30DaysCostUSD, item.last30DaysTokens, currency),
            hintLine: tokenCostHint(providerID),
            totals: Normalizer.normalizeCostTotals(item.totals, item.last30DaysCostUSD, item.last30DaysTokens, currency),
            models: Normalizer.normalizeCostModels(item.daily, currency, historyDays),
            daily: Normalizer.normalizeCostDaily(item.daily, currency, historyDays)
        }
    }

    function costHistoryWindowLabel(item, requestedHistoryDays) {
        var rawDays = item && item.historyDays !== undefined && item.historyDays !== null
            ? Number(item.historyDays)
            : NaN
        if (!isFinite(rawDays) || rawDays <= 0) {
            rawDays = Number(requestedHistoryDays)
        }
        if (!isFinite(rawDays) || rawDays <= 0) {
            return i18n("Last 30 days")
        }
        var days = Math.max(1, Math.floor(rawDays))
        return days === 1 ? i18n("Today") : i18np("Last %1 day", "Last %1 days", days)
    }

    function paintRoundedTopBar(context, x, baseline, width, height, radius) {
        CostPresentation.paintRoundedTopBar(context, x, baseline, width, height, radius)
    }

    function chartBarGeometry(width, count) {
        return CostPresentation.chartBarGeometry(width, count)
    }

    function chartLineX(width, count, index, inset) {
        return CostPresentation.chartLineX(width, count, index, inset)
    }

    function chartLineIndexAt(width, count, positionX, inset) {
        return CostPresentation.chartLineIndexAt(width, count, positionX, inset)
    }

    function chartLineY(height, fraction, inset) {
        return CostPresentation.chartLineY(height, fraction, inset)
    }

    function buildChartBarGradient(context, accent, baseline, topOpacity, bottomOpacity) {
        var gradient = context.createLinearGradient(0, 0, 0, Math.max(1, baseline))
        gradient.addColorStop(0, canvasColor(accent, topOpacity))
        gradient.addColorStop(1, canvasColor(accent, bottomOpacity))
        return gradient
    }

    function costSparklineSummary(points) {
        var summary = CostPresentation.sparklineSummary(costNumberFormat, points, costHistoryShowsTokens)
        if (!summary) {
            return ""
        }
        return i18n("%1: %2", summary.label.length > 0 ? summary.label : i18n("Latest"), summary.value)
    }

    function costChartPoints(points) {
        return CostPresentation.chartPoints(costNumberFormat, points, costHistoryShowsTokens)
    }

    function spendProviderCosts() {
        return CostPresentation.spendSnapshots(tokenCosts, costHistoryDays, function(providerID) {
            return providerTitle(providerID)
        })
    }

    function spendDailyPoints() {
        return CostPresentation.spendDailyPoints(costNumberFormat, spendProviderCosts(), costHistoryShowsTokens)
    }

    function spendCurrency(costs) {
        return CostPresentation.spendCurrency(costs || spendProviderCosts())
    }

    function spendTotalLine() {
        var totals = CostPresentation.spendTotals(spendProviderCosts())
        if (!totals) {
            return ""
        }
        return i18n("%1 total - %2 tokens",
            CostPresentation.amountString(costNumberFormat, totals.cost, totals.currency),
            CostPresentation.tokenCountString(totals.tokens))
    }

    function setCostHistoryDays(days) {
        var nextDays = Math.max(1, Math.min(maximumCostHistoryPoints, Math.floor(Number(days) || 30)))
        Plasmoid.configuration.costHistoryDays = nextDays
    }

    function setCostHistoryMetric(metric) {
        Plasmoid.configuration.costHistoryMetric = safeCostHistoryMetric(metric)
    }

    // The CLI reports whether its local log scan already covers the requested
    // window; until it does, the earliest bars are short for a scan reason
    // rather than a spend reason.
    function spendHistoryStillBuilding() {
        return CostPresentation.historyStillBuilding(spendProviderCosts())
    }

    function costBreakdownRows(tokenCost) {
        if (!tokenCost || !tokenCost.totals) {
            return []
        }

        var totals = tokenCost.totals
        return CostPresentation.breakdownRows([
            { label: i18n("Total tokens"), tokens: totals.tokens },
            { label: i18n("Input"), tokens: totals.inputTokens },
            { label: i18n("Output"), tokens: totals.outputTokens },
            { label: i18n("Cache read"), tokens: totals.cacheReadTokens },
            { label: i18n("Cache write"), tokens: totals.cacheCreationTokens }
        ])
    }

    function costModelRows(tokenCost) {
        return CostPresentation.modelRows(costNumberFormat, tokenCost, function(tokens) {
            return i18n("%1 tokens", CostPresentation.tokenCountString(Number(tokens)))
        })
    }

    function costHistoryRows(tokenCost) {
        return CostPresentation.historyRows(costNumberFormat, tokenCost, costHistoryShowsTokens, i18n("Latest"))
    }

    function costPeakLine(points) {
        var peak = CostPresentation.peakPoint(points, costHistoryShowsTokens)
        if (!peak) {
            return ""
        }
        return i18n("Peak: %1 - %2",
            peak.label.length > 0 ? peak.label : i18n("Latest"),
            costHistoryShowsTokens
                ? CostPresentation.tokenCountString(peak.magnitude)
                : CostPresentation.amountString(costNumberFormat, peak.magnitude, peak.currency))
    }

    function costAverageDailyLine(points) {
        var average = CostPresentation.averageDailyValue(points, costHistoryShowsTokens)
        if (!average) {
            return ""
        }
        return i18n("Average/day: %1", costHistoryShowsTokens
            ? CostPresentation.tokenCountString(average.value)
            : CostPresentation.amountString(costNumberFormat, average.value, average.currency))
    }

    function costPerMillionLine(tokenCost) {
        var perMillion = CostPresentation.perMillionAmount(tokenCost)
        if (!perMillion) {
            return ""
        }
        return i18n("Average: %1 / 1M tokens",
            CostPresentation.amountString(costNumberFormat, perMillion.value, perMillion.currency))
    }

    readonly property int usageDashboardRowLimit: 10
    readonly property int usageDashboardMaxDepth: 4

    function usageDashboard(providerID, usage, item) {
        var kpis = []
        var rows = []
        var dashboardState = {
            rowLimit: usageDashboardRowLimit,
            maxDepth: usageDashboardMaxDepth,
            seen: []
        }
        var sources = [
            { title: i18n("Codex dashboard"), value: item.openaiDashboard },
            { title: i18n("OpenAI API"), value: usage.openAIAPIUsage },
            { title: i18n("OpenRouter"), value: usage.openRouterUsage },
            { title: i18n("Claude Admin"), value: usage.claudeAdminAPIUsage },
            { title: i18n("Poe"), value: usage.poeUsage },
            { title: i18n("DeepSeek"), value: usage.deepseekUsage },
            { title: i18n("MiniMax"), value: usage.minimaxUsage },
            { title: i18n("Z.ai"), value: usage.zaiUsage }
        ]

        for (var i = 0; i < sources.length; i++) {
            appendDashboardSource(kpis, rows, sources[i].title, sources[i].value, dashboardState, 0)
            if (rows.length >= dashboardState.rowLimit && kpis.length >= 4) {
                break
            }
        }

        if (kpis.length === 0 && rows.length === 0) {
            return null
        }
        return {
            kpis: kpis.slice(0, 4),
            rows: rows.slice(0, usageDashboardRowLimit)
        }
    }

    function appendDashboardSource(kpis, rows, title, source, state, depth) {
        if (!isDashboardObject(source)) {
            return
        }
        if (!state) {
            state = {
                rowLimit: usageDashboardRowLimit,
                maxDepth: usageDashboardMaxDepth,
                seen: []
            }
        }
        depth = depth || 0

        var sourceRows = usageDashboardRows(source, state, depth)
        if (sourceRows.length === 0) {
            return
        }

        if (kpis.length < 4) {
            kpis.push({
                label: title,
                value: sourceRows[0].value
            })
        }

        for (var i = 0; i < sourceRows.length && rows.length < state.rowLimit; i++) {
            rows.push({
                label: sourceRows[i].label,
                value: sourceRows[i].value
            })
        }
    }

    function isDashboardObject(source) {
        return source && typeof source === "object" && !Array.isArray(source)
    }

    function usageDashboardRows(source, state, depth) {
        state = state || {
            rowLimit: usageDashboardRowLimit,
            maxDepth: usageDashboardMaxDepth,
            seen: []
        }
        depth = depth || 0
        var rows = []
        if (!isDashboardObject(source) || depth > state.maxDepth || state.seen.indexOf(source) !== -1) {
            return rows
        }
        state.seen.push(source)
        appendDashboardMetric(rows, i18n("Code review remaining"), source.codeReviewRemainingPercent, "percent")
        appendDashboardMetric(rows, i18n("Credits remaining"), source.creditsRemaining, "number")
        appendDashboardMetric(rows, i18n("Plan"), source.accountPlan, "text")
        appendDashboardMetric(rows, i18n("Signed in"), source.signedInEmail, "text")

        appendDashboardPeriodRow(rows, i18n("Today"), source.currentDay || source.today)
        appendDashboardPeriodRow(rows, i18n("7d"), source.last7Days)
        appendDashboardPeriodRow(rows, source.historyWindowLabel || i18n("30d"), source.last30Days)
        appendDashboardPeriodRow(rows, i18n("This month"), source.currentMonth || source.month || source.billingSummary)

        appendDashboardTopRow(rows, i18n("Top model"), source.topModels)
        appendDashboardTopRow(rows, i18n("Usage mix"), source.topUsageTypes)
        appendDashboardLatestDailyRow(rows, source.daily)
        appendDashboardLatestBreakdownRow(rows, source.usageBreakdown || source.dailyBreakdown)
        if (rows.length < state.rowLimit && depth < state.maxDepth && isDashboardObject(source.modelUsage)) {
            appendDashboardSource([], rows, i18n("Models"), source.modelUsage, state, depth + 1)
        }
        state.seen.pop()
        return rows.slice(0, state.rowLimit)
    }

    function appendDashboardMetric(rows, label, value, kind) {
        var text = dashboardValueText(value, kind)
        if (text.length === 0) {
            return
        }
        rows.push({
            label: boundedDisplayText(label, 120),
            value: text
        })
    }

    function appendDashboardPeriodRow(rows, label, source) {
        if (!isCliRecord(source)) {
            return
        }
        var parts = []
        var currency = boundedDisplayText(source.currency || source.currencyCode || "USD", 12)
        var cost = source.costUSD !== undefined ? source.costUSD : (source.cost !== undefined ? source.cost : source.totalCost)
        var tokens = source.totalTokens !== undefined ? source.totalTokens : source.tokens
        var requests = source.requests !== undefined ? source.requests : source.requestCount
        var points = source.points !== undefined ? source.points : source.totalPoints

        if (isFinite(Number(cost))) {
            parts.push(amountString(Number(cost), currency))
        }
        if (isFinite(Number(tokens)) && Number(tokens) > 0) {
            parts.push(i18n("%1 tokens", tokenCountString(Number(tokens))))
        }
        if (isFinite(Number(requests)) && Number(requests) > 0) {
            parts.push(i18n("%1 requests", tokenCountString(Number(requests))))
        }
        if (isFinite(Number(points)) && Number(points) > 0) {
            parts.push(i18n("%1 points", tokenCountString(Number(points))))
        }
        if (parts.length === 0) {
            appendDashboardMetric(rows, label, source.value || source.total || source.used, "number")
            return
        }
        rows.push({
            label: boundedDisplayText(label, 120),
            value: boundedDisplayText(parts.join(" · "), 500)
        })
    }

    function appendDashboardTopRow(rows, label, items) {
        if (!items || !Array.isArray(items) || items.length === 0) {
            return
        }
        var item = items[0] || ({})
        var name = boundedDisplayText(item.name || item.model || item.label || item.type || "", 120)
        if (name.length === 0) {
            return
        }
        var suffix = dashboardTopSuffix(item)
        rows.push({
            label: boundedDisplayText(label, 120),
            value: boundedDisplayText(suffix.length > 0 ? i18n("%1 (%2)", name, suffix) : name, 500)
        })
    }

    function appendDashboardLatestDailyRow(rows, items) {
        if (!items || !Array.isArray(items) || items.length === 0) {
            return
        }
        var item = items[items.length - 1] || ({})
        appendDashboardPeriodRow(rows, item.label || item.day || item.date || i18n("Latest"), item)
    }

    function appendDashboardLatestBreakdownRow(rows, items) {
        if (!items || !Array.isArray(items) || items.length === 0) {
            return
        }
        var item = items[items.length - 1] || ({})
        var label = item.day || item.date || item.label || i18n("Latest dashboard day")
        appendDashboardPeriodRow(rows, label, {
            costUSD: item.costUSD,
            totalTokens: item.totalTokens,
            requests: item.requests,
            points: item.points,
            value: item.totalCreditsUsed
        })
    }

    function dashboardValueText(value, kind) {
        if (value === null || value === undefined) {
            return ""
        }
        if (kind === "text") {
            return boundedDisplayText(value, 120)
        }
        if (kind === "percent") {
            var percent = Number(value)
            return isFinite(percent) ? i18n("%1%", Math.round(percent)) : ""
        }
        if (kind === "tokens") {
            var tokens = Number(value)
            return isFinite(tokens) ? i18n("%1 tokens", tokenCountString(tokens)) : ""
        }
        if (kind === "currency") {
            var cost = Number(value)
            return isFinite(cost) ? amountString(cost, "USD") : ""
        }
        var number = Number(value)
        if (!isFinite(number)) {
            return boundedDisplayText(value, 120)
        }
        return tokenCountString(number)
    }

    function dashboardTopSuffix(item) {
        if (isFinite(Number(item.costUSD))) {
            return amountString(Number(item.costUSD), "USD")
        }
        if (isFinite(Number(item.points))) {
            return i18n("%1 points", tokenCountString(Number(item.points)))
        }
        if (isFinite(Number(item.totalTokens))) {
            return i18n("%1 tokens", tokenCountString(Number(item.totalTokens)))
        }
        if (isFinite(Number(item.requests))) {
            return i18n("%1 requests", tokenCountString(Number(item.requests)))
        }
        return ""
    }

    function providerTokenCost(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 ? tokenCosts[key] || null : null
    }

    function applyTokenCosts() {
        if (!providers || providers.length === 0) {
            return
        }

        var nextProviders = []
        for (var i = 0; i < providers.length; i++) {
            var item = copyObject(providers[i])
            item.tokenCost = providerTokenCost(item.provider)
            nextProviders.push(item)
        }
        providers = nextProviders
    }

    function selectedAccountForProvider(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return ""
        }
        var selected = selectedAccounts[key]
        return selected ? String(selected) : ""
    }

    function accountOptionsForProvider(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return []
        }
        return accountOptions[key] || []
    }

    function accountErrorForProvider(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return ""
        }
        return accountErrors[key] ? String(accountErrors[key]) : ""
    }

    function accountLoadingForProvider(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && accountLoading[key] === true
    }

    function setAccountOptions(providerID, options) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var next = copyObject(accountOptions)
        next[key] = options || []
        accountOptions = next
    }

    function setAccountError(providerID, message) {
        var next = copyObject(accountErrors)
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var cleanMessage = boundedCliMessage(message)
        if (cleanMessage.length > 0) {
            next[key] = cleanMessage
        } else {
            delete next[key]
        }
        accountErrors = next
    }

    function setAccountLoading(providerID, value) {
        var next = copyObject(accountLoading)
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        if (value) {
            next[key] = true
        } else {
            delete next[key]
        }
        accountLoading = next
    }

    function accountLabel(item) {
        return Normalizer.accountLabel(item)
    }

    function accountSubtitle(item) {
        if (!item) {
            return ""
        }
        var parts = []
        if (item.loginMethod && item.loginMethod.length > 0) {
            parts.push(item.loginMethod)
        }
        if (item.organization && item.organization.length > 0 && item.organization !== item.account) {
            parts.push(item.organization)
        }
        return parts.join(" · ")
    }

    function accountIsSelected(option, currentItem) {
        if (!option) {
            return false
        }
        var label = accountLabel(option)
        var selected = selectedAccountForProvider(option.provider)
        if (selected.length > 0) {
            return label === selected
        }
        return currentItem && currentItem.provider === option.provider && label === accountLabel(currentItem)
    }

    function selectAccount(providerID, accountLabel) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var label = String(accountLabel || "")
        var next = copyObject(selectedAccounts)
        if (label.length > 0) {
            next[key] = label
        } else {
            delete next[key]
        }
        selectedAccounts = next
        setNotificationProviderRefreshPending(key, true)

        var options = accountOptionsForProvider(key)
        for (var i = 0; i < options.length; i++) {
            if (root.accountLabel(options[i]) === label) {
                replaceProviderSnapshot(key, options[i])
                Qt.callLater(refreshNow)
                return
            }
        }
        Qt.callLater(refreshNow)
    }

    function replaceProviderSnapshot(providerID, snapshot) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var replacement = copyObject(snapshot)
        replacement.tokenCost = providerTokenCost(key)
        var nextProviders = []
        for (var i = 0; i < providers.length; i++) {
            nextProviders.push(providers[i].provider === key ? replacement : providers[i])
        }
        providers = nextProviders
    }

    function normalizeProvider(item) {
        var usage = isCliRecord(item.usage) ? item.usage : ({})
        var pace = isCliRecord(item.pace) ? item.pace : ({})
        var rows = []
        var providerID = providerMapKey(item.provider || "unknown")
        if (providerID.length === 0) {
            providerID = "unknown"
        }

        var primaryRow = addWindow(rows, rateWindowLabel(providerID, "primary"), usage.primary, pace.primary, true, "primary")
        addWindow(rows, rateWindowLabel(providerID, "secondary"), usage.secondary, pace.secondary, true, "secondary")
        addWindow(rows, rateWindowLabel(providerID, "tertiary"), usage.tertiary, null, true, "tertiary")

        var extras = Array.isArray(usage.extraRateWindows) ? usage.extraRateWindows : []
        var extraLimit = Math.min(extras.length, maximumExtraRateWindows)
        for (var i = 0; i < extraLimit; i++) {
            var extra = extras[i]
            if (isCliRecord(extra) && isCliRecord(extra.window)) {
                addWindow(rows, boundedDisplayText(extra.title || extra.id || i18n("Extra"), 120), extra.window, null, extra.usageKnown !== false, "extra")
            }
        }

        var identity = isCliRecord(usage.identity) ? usage.identity : ({})
        var error = isCliRecord(item.error) ? item.error : null
        var status = isCliRecord(item.status) ? item.status : null
        var severity = Normalizer.statusSeverity(status)
        var credits = isCliRecord(item.credits) ? item.credits : null
        var displayName = item.displayName || item.title || providerDisplayNames[providerID] || ""
        var providerDetails = UsageDetails.normalizeSections(usage.details)
        var providerUsageDashboard = providerDetails.length > 0 ? null : usageDashboard(providerID, usage, item)
        var hasSupplementalUsage = providerDetails.length > 0 || providerUsageDashboard !== null
        var placeholder = providerPlaceholder(providerID, rows, usage, item, error, hasSupplementalUsage)

        return {
            provider: providerID,
            title: boundedDisplayText(providerTitle(providerID, displayName), 120),
            source: boundedDisplayText(item.source || "", 120),
            version: boundedDisplayText(item.version || "", 120),
            account: boundedDisplayText(item.account || identity.accountEmail || usage.accountEmail || "", 256),
            organization: boundedDisplayText(identity.accountOrganization || usage.accountOrganization || "", 256),
            loginMethod: boundedDisplayText(identity.loginMethod || usage.loginMethod || "", 120),
            rows: rows,
            primaryRow: primaryRow,
            providerDetails: providerDetails,
            usageDashboard: providerUsageDashboard,
            providerCost: providerCostSection(providerID, usage.providerCost),
            resetCredits: resetCreditsSection(providerID, usage.codexResetCredits),
            tokenCost: providerTokenCost(providerID),
            planText: boundedDisplayText(planText(providerID, usage, item), 120),
            dashboardUrl: providerDashboardUrl(providerID),
            statusUrl: safeStatusUrl(providerID, status && status.url ? status.url : ""),
            changelogUrl: providerChangelogUrl(providerID),
            credits: credits && credits.remaining !== null && credits.remaining !== undefined && isFinite(Number(credits.remaining))
                ? Number(credits.remaining)
                : null,
            status: boundedDisplayText(status ? statusText(status) : "", 500),
            statusSeverity: severity,
            statusIncidentKey: boundedDisplayText(Normalizer.statusIncidentKey(status), 128),
            hasIncident: severity.length > 0,
            error: boundedCliMessage(error && error.message ? error.message : ""),
            placeholder: placeholder,
            updatedAt: boundedDisplayText(usage.updatedAt || (credits ? credits.updatedAt : ""), 128)
        }
    }

    function providerPlaceholder(providerID, rows, usage, item, error, hasSupplementalUsage) {
        if ((rows && rows.length > 0) || hasSupplementalUsage === true) {
            return ""
        }

        var message = error && error.message ? String(error.message).trim() : ""
        if (message.length > 0 && message !== "Found sessions, but no rate limit events yet.") {
            return ""
        }

        if (rateLimitsUnavailable(providerID, usage, item)) {
            return i18n("Limits not available")
        }

        return i18n("No usage yet")
    }

    function rateLimitsUnavailable(providerID, usage, item) {
        var key = providerKey(providerID)
        if (key !== "antigravity" && key !== "doubao" && key !== "codex") {
            return false
        }

        var identity = usage && usage.identity ? usage.identity : ({})
        var hasIdentity = (item && item.account && item.account.length > 0)
            || (identity.accountEmail && identity.accountEmail.length > 0)
            || (identity.accountOrganization && identity.accountOrganization.length > 0)
            || (identity.loginMethod && identity.loginMethod.length > 0)
        if (!hasIdentity) {
            return false
        }

        return !usage.primary && !usage.secondary && !usage.tertiary
    }

    // The clamped percentages come from the normalizer; the words stay here,
    // because every text field below is either translated or formatted against
    // the current theme/locale, which a `.pragma library` may not reach.
    function addWindow(rows, label, window, pace, usageKnown, lane) {
        var metrics = Normalizer.rateWindowMetrics(window, pace, usageKnown)
        if (metrics === null) {
            return null
        }

        var row = {
            lane: lane || "",
            label: boundedDisplayText(label, 120),
            hasPercent: metrics.hasPercent,
            usedPercent: metrics.usedPercent,
            leftPercent: metrics.leftPercent,
            pacePercent: metrics.pacePercent,
            paceOnTop: metrics.paceOnTop,
            paceEtaSeconds: metrics.paceEtaSeconds,
            resetsAt: boundedDisplayText(
                window.resetsAt === undefined || window.resetsAt === null ? "" : window.resetsAt,
                128),
            resetDescription: boundedDisplayText(window.resetDescription || "", 500),
            reset: boundedDisplayText(resetText(window, false), 500),
            pace: boundedDisplayText(pace && pace.summary ? pace.summary : "", 500)
        }
        rows.push(row)
        return row
    }

    function rateWindowLabel(providerID, lane) {
        var key = providerKey(providerID)
        if (lane === "primary") {
            switch (key) {
            case "alibaba":
            case "opencode":
            case "opencodego":
                return i18n("5-hour")
            case "amp":
                return i18n("Amp Free")
            case "antigravity":
                return i18n("Gemini Models")
            case "azureopenai":
                return i18n("Status")
            case "bedrock":
                return i18n("Budget")
            case "commandcode":
            case "manus":
                return i18n("Monthly credits")
            case "copilot":
                return i18n("Premium")
            case "cursor":
                return i18n("Total")
            case "factory":
                return i18n("Standard")
            case "doubao":
            case "grok":
            case "groq":
            case "vertexai":
                return i18n("Requests")
            case "gemini":
                return i18n("Pro")
            case "kilo":
            case "kiro":
            case "mimo":
            case "warp":
            case "abacus":
                return i18n("Credits")
            case "kimi":
                return i18n("Weekly")
            case "minimax":
                return i18n("Prompts")
            case "openai":
                return i18n("Spend")
            case "openrouter":
                return i18n("API key limit")
            case "poe":
                return i18n("Points")
            case "zed":
                return i18n("Edit predictions")
            default:
                return i18n("Session")
            }
        }
        if (lane === "secondary") {
            switch (key) {
            case "antigravity":
                return i18n("Claude and GPT")
            case "amp":
                return i18n("Balance")
            case "azureopenai":
                return i18n("Deployment")
            case "bedrock":
                return i18n("Cost")
            case "copilot":
                return i18n("Chat")
            case "cursor":
                return i18n("Auto")
            case "factory":
                return i18n("Premium")
            case "doubao":
            case "kimi":
                return i18n("Rate limit")
            case "gemini":
                return i18n("Flash")
            case "grok":
                return i18n("On-demand")
            case "groq":
            case "vertexai":
                return i18n("Tokens")
            case "kilo":
                return i18n("Kilo Pass")
            case "kiro":
                return i18n("Bonus")
            case "mimo":
            case "minimax":
                return i18n("Window")
            case "openai":
                return i18n("Requests")
            case "warp":
                return i18n("Add-on credits")
            case "zed":
                return i18n("Billing cycle")
            default:
                return i18n("Weekly")
            }
        }
        if (lane === "tertiary") {
            if (key === "alibaba" || key === "opencodego") {
                return i18n("Monthly")
            }
            if (key === "claude") {
                return i18n("Sonnet")
            }
            if (key === "cursor") {
                return i18n("API")
            }
            if (key === "gemini") {
                return i18n("Flash Lite")
            }
            return i18n("Opus")
        }
        return i18n("Usage")
    }

    function providerCostSection(providerID, cost) {
        var key = providerKey(providerID)
        if (key === "manus" || key === "synthetic") {
            return null
        }

        if (!isCliRecord(cost)) {
            return null
        }

        var used = Number(cost.used)
        var limit = Number(cost.limit)
        var currency = boundedDisplayText(cost.currencyCode || "USD", 12)
        var period = boundedDisplayText(cost.period || i18n("This month"), 120)
        var hasUsed = isFinite(used)
        var hasLimit = isFinite(limit) && limit > 0
        if (!hasUsed) {
            return null
        }

        if (key === "factory" && period === "Extra usage balance") {
            return {
                title: i18n("Extra usage"),
                percentUsed: -1,
                spendLine: i18n("Balance: %1", amountString(used, currency)),
                percentLine: "",
                personalSpendLine: ""
            }
        }

        if (key === "opencodego" && period === "Zen balance") {
            return {
                title: i18n("Zen balance"),
                percentUsed: -1,
                spendLine: i18n("Balance: %1", amountString(used, currency)),
                percentLine: "",
                personalSpendLine: ""
            }
        }

        if (key === "minimax" && period === "MiniMax points balance") {
            return {
                title: i18n("Credits"),
                percentUsed: -1,
                spendLine: i18n("Balance: %1", Math.round(used)),
                percentLine: "",
                personalSpendLine: ""
            }
        }

        if (hasLimit) {
            var percent = clamp((used / limit) * 100, 0, 100)
            return {
                title: currency === "Quota" ? i18n("Quota usage") : i18n("Extra usage"),
                percentUsed: percent,
                spendLine: i18n("%1: %2 / %3", localizedPeriod(period), amountString(used, currency), amountString(limit, currency)),
                percentLine: i18n("%1% used", Math.round(percent)),
                personalSpendLine: cost.personalUsed && Number(cost.personalUsed) > 0
                    ? i18n("Your spend: %1", amountString(Number(cost.personalUsed), currency))
                    : ""
            }
        }

        if (key === "litellm") {
            return null
        }

        return {
            title: key === "openai" || key === "claude"
                ? i18n("API spend")
                : i18n("Extra usage"),
            percentUsed: -1,
            spendLine: i18n("%1: %2", localizedPeriod(period), amountString(used, currency)),
            percentLine: "",
            personalSpendLine: ""
        }
    }

    function resetCreditsSection(providerID, resetCredits) {
        if (providerKey(providerID) !== "codex" || !resetCredits) {
            return null
        }

        var count = Number(resetCredits.availableCount)
        if (!isFinite(count) || count <= 0) {
            return null
        }

        return {
            title: i18n("Reset credits"),
            line: i18np("%1 available", "%1 available", Math.round(count))
        }
    }

    function resetText(window, absolute) {
        if (!window.resetsAt) {
            return window.resetDescription && window.resetDescription.length > 0 ? window.resetDescription : ""
        }

        var date = new Date(window.resetsAt)
        if (isNaN(date.getTime())) {
            return String(window.resetsAt)
        }

        if (absolute === true) {
            return Qt.formatDateTime(date, "ddd HH:mm")
        }

        if (window.resetDescription && window.resetDescription.length > 0) {
            return window.resetDescription
        }

        var remainingMs = date.getTime() - Date.now()
        if (remainingMs <= 0) {
            return i18n("now")
        }
        var minutes = Math.max(1, Math.round(remainingMs / 60000))
        if (minutes < 60) {
            return i18np("%1 min", "%1 min", minutes)
        }
        var hours = Math.floor(minutes / 60)
        var restMinutes = minutes % 60
        if (hours < 24) {
            return restMinutes > 0 ? i18n("%1h %2m", hours, restMinutes) : i18np("%1h", "%1h", hours)
        }
        var days = Math.floor(hours / 24)
        var restHours = hours % 24
        return restHours > 0 ? i18n("%1d %2h", days, restHours) : i18np("%1d", "%1d", days)
    }

    function usageResetText(row) {
        if (!row) {
            return ""
        }
        if (row.resetsAt || row.resetDescription) {
            return resetText({
                resetsAt: row.resetsAt || "",
                resetDescription: row.resetDescription || ""
            }, resetTimesShowAbsolute)
        }
        return String(row.reset || "")
    }

    function statusText(status) {
        var indicator = String(status.indicator || "")
        var description = String(status.description || "").trim()
        if (indicator.length === 0 || indicator === "none") {
            return description
        }

        var labels = {
            "minor": i18n("Partial outage"),
            "major": i18n("Major outage"),
            "critical": i18n("Critical issue"),
            "maintenance": i18n("Maintenance"),
            "unknown": i18n("Status unknown")
        }
        var text = labels[indicator] || indicator
        return description.length > 0 ? text + ": " + description : text
    }

    function statusBadgeColor(severity) {
        switch (String(severity || "")) {
        case "critical":
        case "major":
            return Kirigami.Theme.negativeTextColor
        case "minor":
        case "maintenance":
            return Kirigami.Theme.neutralTextColor
        case "unknown":
            return Kirigami.Theme.textColor
        default:
            return "transparent"
        }
    }

    function statusBadgeText(severity) {
        switch (String(severity || "")) {
        case "critical":
            return i18n("Critical")
        case "major":
            return i18n("Major")
        case "minor":
            return i18n("Issue")
        case "maintenance":
            return i18n("Maint.")
        case "unknown":
            return i18n("Unknown")
        default:
            return ""
        }
    }

    function statusMessageType(severity) {
        switch (String(severity || "")) {
        case "critical":
        case "major":
            return Kirigami.MessageType.Error
        case "minor":
        case "maintenance":
            return Kirigami.MessageType.Warning
        default:
            return Kirigami.MessageType.Information
        }
    }

    function primaryIncidentProvider() {
        var ranked = {
            "critical": 5,
            "major": 4,
            "minor": 3,
            "maintenance": 2,
            "unknown": 1
        }
        var best = null
        var bestRank = 0
        for (var i = 0; i < providers.length; i++) {
            var item = providers[i]
            var rank = item && item.statusSeverity ? ranked[item.statusSeverity] || 0 : 0
            if (rank > bestRank) {
                best = item
                bestRank = rank
            }
        }
        return best
    }

    function quotaWarningMarkers(row) {
        if (!showQuotaWarningMarkers || !row || !row.hasPercent) {
            return []
        }
        return QuotaThresholds.markers(
            quotaWarningPercent,
            quotaCriticalPercent,
            usageBarsShowUsed)
    }

    // The thresholds used to surface only as two ticks on the provider detail
    // meter, so an almost exhausted window looked exactly like an idle one on
    // the panel and in the overview. Every meter fill reads its colour from
    // this one level; the provider accent stays in charge below the warning
    // step, and the same setting that hides the markers hides the colour.
    function quotaSeverity(row) {
        if (!showQuotaWarningMarkers || !row || !row.hasPercent) {
            return ""
        }
        return QuotaThresholds.level(row.usedPercent, quotaWarningPercent, quotaCriticalPercent)
    }

    function quotaMeterColor(row, accent) {
        var severity = quotaSeverity(row)
        return severity.length > 0 ? statusBadgeColor(severity) : accent
    }

    // Quota, pace, and reset memo state is threshold-derived and has to be
    // rebuilt whenever a setting changes. Provider status is not: a settings
    // change is not a status transition, so the status baseline survives the
    // reset. Dropping it would either re-announce an ongoing incident or, once
    // the first observation is silently primed, swallow an incident that starts
    // while the provider is still refreshing.
    function resetNotificationMemo() {
        notificationMemo = NotificationPlanner.transition(
            [], notificationMemo, ({ mode: "reset" })).nextMemo
        notificationsPrimed = false
        Qt.callLater(processNotifications)
    }

    function notificationProviderRefreshPending(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && notificationRefreshPending[key] === true
    }

    function setNotificationProviderRefreshPending(providerID, pending) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var nextPending = copyObject(notificationRefreshPending)
        if (pending) {
            nextPending[key] = true
        } else {
            delete nextPending[key]
        }
        notificationRefreshPending = nextPending
    }

    function markNotificationProvidersFresh(items) {
        var nextPending = copyObject(notificationRefreshPending)
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || (item.error && String(item.error).length > 0)) {
                continue
            }
            var providerID = providerMapKey(item.provider)
            if (providerID.length === 0) {
                continue
            }
            var selectedAccount = selectedAccountForProvider(providerID)
            if (selectedAccount.length > 0 && accountLabel(item) !== selectedAccount) {
                continue
            }
            delete nextPending[providerID]
        }
        notificationRefreshPending = nextPending
    }

    function notificationScopeKey(item) {
        if (!item) {
            return JSON.stringify(["", ""])
        }
        var providerID = providerMapKey(item.provider)
        var selectedAccount = selectedAccountForProvider(providerID)
        var currentAccount = selectedAccount.length > 0 ? selectedAccount : accountLabel(item)
        return JSON.stringify([providerID, currentAccount])
    }

    function paceWarningActive(row) {
        return row && row.paceOnTop === false && Number(row.paceEtaSeconds) > 0
    }

    function paceEtaText(seconds) {
        var minutes = Math.max(1, Math.round(Number(seconds) / 60))
        if (minutes < 60) {
            return i18np("%1 minute", "%1 minutes", minutes)
        }
        var hours = Math.max(1, Math.round(minutes / 60))
        if (hours < 48) {
            return i18np("%1 hour", "%1 hours", hours)
        }
        var days = Math.max(1, Math.round(hours / 24))
        return i18np("%1 day", "%1 days", days)
    }

    // Usage at or above this percent arms a row for reset detection; once armed,
    // dropping to or below the floor fires a single "limit reset" notification.
    // Mirrors the macOS weekly-limit reset detector, scoped to limits the user
    // was actually near so routine short-window resets stay quiet.
    readonly property int limitResetArmThreshold: 80
    readonly property int limitResetFloor: 5

    function quotaNotificationLevel(row) {
        if (!row || !row.hasPercent) {
            return ""
        }
        return QuotaThresholds.level(
            row.usedPercent,
            quotaWarningPercent,
            quotaCriticalPercent)
    }

    // QML resolves account identity, refresh freshness, configured thresholds,
    // and the rows to display. The pure planner receives only semantic
    // observations and returns ordered intents; it never sees i18n or effects.
    function notificationObservationRows(item) {
        var sourceRows = item && Array.isArray(item.rows) ? item.rows : []
        var result = []
        for (var i = 0; i < sourceRows.length; i++) {
            var row = sourceRows[i]
            result.push({
                lane: row && row.lane ? String(row.lane) : "",
                label: row && row.label ? String(row.label) : "",
                resetsAt: row && row.resetsAt ? String(row.resetsAt) : "",
                hasPercent: row && row.hasPercent === true,
                usedPercent: row ? Number(row.usedPercent) : NaN,
                quotaLevel: quotaNotificationLevel(row),
                paceActive: paceWarningActive(row)
            })
        }
        return result
    }

    function notificationObservations() {
        var result = []
        for (var i = 0; i < providers.length; i++) {
            var item = providers[i]
            if (!item) {
                continue
            }
            result.push({
                providerIndex: i,
                providerID: providerMapKey(item.provider),
                scopeID: notificationScopeKey(item),
                pending: notificationProviderRefreshPending(item.provider),
                statusActive: item.hasIncident === true
                    && String(item.statusSeverity || "").length > 0
                    && String(item.status || "").length > 0,
                statusSeverity: String(item.statusSeverity || ""),
                statusIncidentKey: String(item.statusIncidentKey || ""),
                rows: notificationObservationRows(item)
            })
        }
        return result
    }

    function notificationPlannerOptions(mode) {
        return {
            mode: mode,
            statusEnabled: notifyStatusIncidents,
            quotaEnabled: notifyQuotaWarnings,
            paceEnabled: notifyPredictivePaceWarnings,
            resetEnabled: notifyLimitResets,
            resetArmThreshold: limitResetArmThreshold,
            resetFloor: limitResetFloor
        }
    }

    function dispatchNotificationIntents(intents, observations) {
        for (var i = 0; i < intents.length; i++) {
            var intent = intents[i]
            var observation = observations[intent.observationIndex]
            var item = observation ? providers[observation.providerIndex] : null
            if (!item) {
                continue
            }
            if (intent.kind === "status") {
                sendPlasmaNotification(
                    i18n("%1 status issue", item.title),
                    item.status,
                    notificationUrgency(intent.severity))
                continue
            }

            var rows = Array.isArray(item.rows) ? item.rows : []
            var row = rows[intent.rowIndex]
            if (!row) {
                continue
            }
            if (intent.kind === "quota") {
                var body = i18n("%1 is %2% used", row.label, Math.round(row.usedPercent))
                var resetLine = resetLabel(usageResetText(row))
                if (resetLine.length > 0) {
                    body += ". " + resetLine
                }
                sendPlasmaNotification(
                    intent.severity === "major"
                        ? i18n("%1 quota critical", item.title)
                        : i18n("%1 quota warning", item.title),
                    body,
                    notificationUrgency(intent.severity))
            } else if (intent.kind === "pace") {
                sendPlasmaNotification(
                    i18n("%1 pace warning", item.title),
                    i18n("%1 may run out in %2", row.label, paceEtaText(row.paceEtaSeconds)),
                    "normal")
            } else if (intent.kind === "reset") {
                sendPlasmaNotification(
                    i18n("%1 limit reset", item.title),
                    i18n("%1 is back to %2% used", row.label, Math.round(row.usedPercent)),
                    "low")
            }
        }
    }

    function processNotifications() {
        if (!enableNotifications || providers.length === 0) {
            return
        }
        var observations = notificationObservations()
        var mode = notificationsPrimed ? "observe" : "prime"
        var result = NotificationPlanner.transition(
            observations,
            notificationMemo,
            notificationPlannerOptions(mode))
        // Commit the full transition before running any external effect. A
        // re-entrant refresh cannot observe the old baseline and notify twice.
        notificationMemo = result.nextMemo
        notificationsPrimed = true
        dispatchNotificationIntents(result.intents, observations)
    }

    function notificationRank(severity) {
        return NotificationMemo.severityRank(severity)
    }

    function notificationUrgency(severity) {
        switch (String(severity || "")) {
        case "critical":
        case "major":
            return "critical"
        case "unknown":
            return "low"
        default:
            return "normal"
        }
    }

    function sendPlasmaNotification(title, body, urgency) {
        var cleanTitle = String(title || "CodexBar").trim()
        var cleanBody = String(body || "").trim()
        var cleanUrgency = String(urgency || "normal").trim()
        if (cleanTitle.length === 0) {
            cleanTitle = "CodexBar"
        }
        if (cleanUrgency !== "low" && cleanUrgency !== "normal" && cleanUrgency !== "critical") {
            cleanUrgency = "normal"
        }
        var command = "if command -v notify-send >/dev/null 2>&1; then notify-send --app-name=CodexBar --icon=view-statistics --urgency="
            + shellQuote(cleanUrgency) + " -- " + shellQuote(cleanTitle) + " " + shellQuote(cleanBody) + "; fi"
        // A shell assignment cannot directly prefix the reserved word `if`.
        notificationSource.connectSource(commandWithRunNonce(":; " + command))
    }

    function updateScriptPath() {
        var url = Qt.resolvedUrl("../../scripts/update-widget.sh").toString()
        if (url.indexOf("file://") === 0) {
            return decodeURIComponent(url.substring(7))
        }
        return decodeURIComponent(url)
    }

    function buildUpdateCommand(installMode) {
        var scriptPath = updateScriptPath()
        var mode = installMode ? " --install" : " --check"
        var updateCommand = "if [ -x " + shellQuote(scriptPath) + " ]; then "
            + shellQuote(scriptPath) + mode
            + "; else printf '%s\\n' " + shellQuote(missingUpdateScriptJson()) + "; fi"
        return "sh -c " + shellQuote(updateCommand)
    }

    function missingUpdateScriptJson() {
        return JSON.stringify({
            status: "error",
            message: i18n("Widget updater script is missing from the installed package.")
        })
    }

    function updateCheckDue(forceCheck) {
        return UpdateLogic.updateCheckDue(
            updateChecksEnabled,
            autoUpdateLastCheck,
            autoUpdateIntervalHours,
            Date.now(),
            forceCheck === true)
    }

    function checkForWidgetUpdate(forceCheck) {
        if (connectedUpdateCommandSource.length > 0) {
            return
        }
        if (!updateCheckDue(forceCheck)) {
            scheduleNextUpdateCheck()
            return
        }
        updateCheckTimer.stop()
        setWidgetUpdateState(i18n("Checking for widget updates..."), "", false)
        connectedUpdateCommandSource = commandWithRunNonce(buildUpdateCommand(autoUpdateEnabled))
        updateSource.connectSource(connectedUpdateCommandSource)
        updateCommandTimeoutTimer.interval = autoUpdateEnabled
            ? widgetAutoUpdateTimeoutMs
            : widgetUpdateCheckTimeoutMs
        updateCommandTimeoutTimer.restart()
    }

    function scheduleNextUpdateCheck(lastCheckOverride) {
        updateCheckTimer.stop()
        if (!updateChecksEnabled || connectedUpdateCommandSource.length > 0) {
            return
        }
        var lastCheck = lastCheckOverride === undefined ? autoUpdateLastCheck : lastCheckOverride
        updateCheckTimer.interval = UpdateLogic.nextUpdateCheckDelay(
            updateChecksEnabled,
            lastCheck,
            autoUpdateIntervalHours,
            Date.now(),
            widgetUpdateMinimumTimerDelayMs)
        updateCheckTimer.restart()
    }

    function finishUpdateCommand(sourceName) {
        updateCommandTimeoutTimer.stop()
        updateSource.disconnectSource(sourceName)
        connectedUpdateCommandSource = ""
        var completedAt = new Date().toISOString()
        Plasmoid.configuration.autoUpdateLastCheck = completedAt
        scheduleNextUpdateCheck(completedAt)
    }

    function handleUpdateCommandTimeout() {
        if (connectedUpdateCommandSource.length === 0) {
            return
        }
        var sourceName = connectedUpdateCommandSource
        finishUpdateCommand(sourceName)
        setWidgetUpdateState(
            i18n("Widget update failed."),
            i18n("Widget update operation timed out."))
    }

    function setWidgetUpdateState(statusText, errorText, persistState) {
        updateStatusText = boundedWidgetUpdateText(statusText)
        updateErrorText = boundedWidgetUpdateText(errorText)
        if (persistState === false) {
            return
        }
        Plasmoid.configuration.widgetUpdateLastStatus = updateStatusText
        Plasmoid.configuration.widgetUpdateLastError = updateErrorText
    }

    function handleUpdateData(sourceName, stdoutText, stderrText) {
        if (sourceName !== connectedUpdateCommandSource) {
            return
        }
        finishUpdateCommand(sourceName)

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            setWidgetUpdateState(
                i18n("Widget update check failed."),
                stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("Widget update check returned no data."))
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            setWidgetUpdateState(
                i18n("Widget update check failed."),
                i18n("Could not parse widget update JSON: %1", error.message))
            return
        }

        processUpdateCheck(payload)
    }

    function processUpdateCheck(payload) {
        var status = String(payload && payload.status ? payload.status : "")
        var message = boundedCliMessage(payload && payload.message ? payload.message : "")
        var version = String(payload && payload.remoteVersion ? payload.remoteVersion : "")
        var url = String(payload && payload.assetUrl ? payload.assetUrl : "")

        if (status === "error") {
            setWidgetUpdateState(
                i18n("Widget update check failed."),
                message.length > 0 ? message : i18n("Widget update check failed."))
            return
        }

        if (status === "available") {
            var availableStatus = version.length > 0
                ? i18n("Widget update %1 is available.", version)
                : i18n("A widget update is available.")
            setWidgetUpdateState(availableStatus, "")
            if (!autoUpdateEnabled) {
                notifyAvailableUpdate(version, url)
            }
            return
        }
        if (status === "installed") {
            var restartText = i18n("Restart Plasma to apply the new widget version.")
            setWidgetUpdateState(version.length > 0
                ? i18n("Widget update %1 installed. %2", version, restartText)
                : i18n("Widget update installed. %1", restartText), "")
            notifyInstalledUpdate(version)
            return
        }
        if (status === "current") {
            setWidgetUpdateState(i18n("Widget is up to date."), "")
            return
        }
        if (status === "skipped") {
            setWidgetUpdateState(message.length > 0 ? message : i18n("Widget update skipped."), "")
            return
        }

        setWidgetUpdateState(
            i18n("Widget update check failed."),
            i18n("Unknown widget update status: %1", status))
    }

    function notifyAvailableUpdate(version, url) {
        if (!enableNotifications || !updateNotificationsEnabled) {
            return
        }
        var cleanVersion = String(version || "").trim()
        var memoKey = cleanVersion.length > 0 ? cleanVersion : url
        if (memoKey.length === 0 || memoKey === lastNotifiedUpdateVersion) {
            return
        }
        lastNotifiedUpdateVersion = memoKey
        Plasmoid.configuration.lastNotifiedUpdateVersion = memoKey
        var title = i18n("CodexBar widget update available")
        var body = cleanVersion.length > 0
            ? i18n("Version %1 is available.", cleanVersion)
            : i18n("A new widget version is available.")
        sendPlasmaNotification(title, body, "normal")
    }

    function notifyInstalledUpdate(version) {
        if (!enableNotifications || !updateNotificationsEnabled) {
            return
        }
        var cleanVersion = String(version || "").trim()
        var title = i18n("CodexBar widget update installed")
        var restartText = i18n("Restart Plasma to apply the new widget version.")
        var body = cleanVersion.length > 0
            ? i18n("Version %1 was installed. %2", cleanVersion, restartText)
            : i18n("A widget update was installed. %1", restartText)
        sendPlasmaNotification(title, body, "normal")
    }

    function planText(providerID, usage, item) {
        var identity = usage.identity || ({})
        var method = identity.loginMethod || usage.loginMethod || ""
        if (providerKey(providerID) === "codex" && method.length > 0) {
            return capitalize(method)
        }
        return ""
    }

    function providerKey(value) {
        return ProviderIdentity.resolveProviderKey(value)
    }

    function providerCliArgument(value) {
        return ProviderIdentity.providerCliArgument(value)
    }

    function providerTitle(value, displayName) {
        var key = providerKey(value)
        var preferred = String(displayName || "").trim()
        if (preferred.length > 0) {
            return preferred
        }

        var names = {
            "abacus": i18n("Abacus AI"),
            "aiand": i18n("ai&"),
            "alibaba": i18n("Alibaba"),
            "alibabatokenplan": i18n("Alibaba Token Plan"),
            "amp": i18n("Amp"),
            "antigravity": i18n("Antigravity"),
            "augment": i18n("Augment"),
            "azureopenai": i18n("Azure OpenAI"),
            "bedrock": i18n("AWS Bedrock"),
            "chutes": i18n("Chutes"),
            "claude": i18n("Claude"),
            "clawrouter": i18n("ClawRouter"),
            "clinepass": i18n("ClinePass"),
            "codebuff": i18n("Codebuff"),
            "codex": i18n("Codex"),
            "commandcode": i18n("Command Code"),
            "copilot": i18n("Copilot"),
            "crof": i18n("Crof"),
            "crossmodel": i18n("CrossModel"),
            "cursor": i18n("Cursor"),
            "deepgram": i18n("Deepgram"),
            "deepinfra": i18n("DeepInfra"),
            "deepseek": i18n("DeepSeek"),
            "devin": i18n("Devin"),
            "doubao": i18n("Doubao"),
            "elevenlabs": i18n("ElevenLabs"),
            "factory": i18n("Droid"),
            "fireworks": i18n("Fireworks"),
            "gemini": i18n("Gemini"),
            "grok": i18n("Grok"),
            "groq": i18n("Groq"),
            "ibmbob": i18n("IBM Bob"),
            "jetbrains": i18n("JetBrains AI"),
            "kilo": i18n("Kilo"),
            "kimi": i18n("Kimi Code"),
            "kimik2": i18n("Kimi K2 (unofficial)"),
            "kiro": i18n("Kiro"),
            "litellm": i18n("LiteLLM"),
            "llmproxy": i18n("LLM Proxy"),
            "longcat": i18n("LongCat"),
            "manus": i18n("Manus"),
            "mimo": i18n("Xiaomi MiMo"),
            "minimax": i18n("MiniMax"),
            "mistral": i18n("Mistral"),
            "moonshot": i18n("Moonshot / Kimi Open Platform"),
            "neuralwatt": i18n("Neuralwatt"),
            "notion": i18n("Notion AI"),
            "ollama": i18n("Ollama"),
            "openai": i18n("OpenAI"),
            "opencode": i18n("OpenCode"),
            "opencodego": i18n("OpenCode Go"),
            "openrouter": i18n("OpenRouter"),
            "perplexity": i18n("Perplexity"),
            "poe": i18n("Poe"),
            "qoder": i18n("Qoder"),
            "qwencloud": i18n("Qwen Cloud"),
            "sakana": i18n("Sakana AI"),
            "stepfun": i18n("StepFun"),
            "sub2api": i18n("sub2api"),
            "synthetic": i18n("Synthetic"),
            "t3chat": i18n("T3 Chat"),
            "venice": i18n("Venice"),
            "vertexai": i18n("Vertex AI"),
            "warp": i18n("Warp"),
            "wayfinder": i18n("Wayfinder"),
            "windsurf": i18n("Windsurf"),
            "xai": i18n("xAI"),
            "zai": i18n("z.ai / GLM"),
            "zed": i18n("Zed"),
            "zenmux": i18n("ZenMux"),
            "zoommate": i18n("ZoomMate")
        }

        if (hasOwnKey(names, key)) {
            return names[key]
        }

        var words = String(key).replace(/[_-]/g, " ").split(" ")
        for (var i = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
            }
        }
        return words.join(" ")
    }

    function providerIconSource(value) {
        var fileName = ProviderIdentity.providerIconFileName(value)
        if (fileName.length === 0) {
            return "view-statistics"
        }
        return Qt.resolvedUrl("../icons/providers/" + fileName)
    }

    function providerIconIsMask(value) {
        return true
    }

    function providerColor(value) {
        var channels = ProviderIdentity.providerBrandColorChannels(value)
        if (channels.length !== 3) {
            return Kirigami.Theme.highlightColor
        }
        return Qt.rgba(channels[0], channels[1], channels[2], 1)
    }

    function providerDashboardUrl(providerID) {
        return ProviderIdentity.providerDashboardUrl(providerID)
    }

    function providerDocsUrl(providerID) {
        return ProviderIdentity.providerDocsUrl(providerID)
    }

    function providerLoginUrl(providerID) {
        return ProviderIdentity.providerLoginUrl(providerID)
    }

    function providerStatusUrl(providerID) {
        return ProviderIdentity.providerStatusUrl(providerID)
    }

    function safeStatusUrl(providerID, url) {
        return Normalizer.safeStatusUrl(providerStatusUrl(providerID), url)
    }

    function providerChangelogUrl(providerID) {
        switch (providerKey(providerID)) {
        case "codex":
            return "https://github.com/openai/codex/releases"
        case "claude":
            return "https://github.com/anthropics/claude-code/releases"
        case "gemini":
            return "https://github.com/google-gemini/gemini-cli/releases"
        case "grok":
            return "https://x.ai/news"
        default:
            return ""
        }
    }

    function actionRows(item) {
        if (!item) {
            return []
        }

        var rows = []
        rows.push({
            title: accountLoadingForProvider(item.provider) ? i18n("Loading accounts...") : i18n("Accounts..."),
            icon: "user-identity",
            action: "accounts",
            enabled: !accountLoadingForProvider(item.provider)
        })

        var accountAction = providerAccountAction(item)
        if (accountAction) {
            rows.push(accountAction)
        }

        if (item.dashboardUrl && item.dashboardUrl.length > 0) {
            rows.push({ title: i18n("Usage Dashboard"), icon: "view-statistics", action: "dashboard", enabled: true })
        }
        if (safeStatusUrl(item.provider, item.statusUrl).length > 0) {
            rows.push({ title: i18n("Status Page"), icon: "network-connect", action: "status", enabled: true })
        }
        if (showProviderChangelogs && item.changelogUrl && item.changelogUrl.length > 0) {
            rows.push({ title: i18n("Changelog"), icon: "view-list-details", action: "changelog", enabled: true })
        }
        var docsUrl = providerDocsUrl(item.provider)
        if (docsUrl.length > 0) {
            rows.push({ title: i18n("Docs"), icon: "help-contents", action: "docs", url: docsUrl, enabled: true })
        }

        rows.push({ title: i18n("Refresh"), icon: "view-refresh", action: "refresh", enabled: true, separatorBefore: true })
        rows.push({ title: i18n("Settings..."), icon: "configure", action: "settings", enabled: true })
        rows.push({ title: i18n("About CodexBar"), icon: "help-about", action: "about", enabled: true })
        return rows
    }

    function providerAccountAction(item) {
        var title = item.account && item.account.length > 0 ? i18n("Switch Account...") : i18n("Add Account...")
        var loginUrl = providerLoginUrl(item.provider)
        switch (providerKey(item.provider)) {
        case "devin":
            return { title: i18n("Open Devin..."), icon: "internet-services", action: "account-url", url: "https://app.devin.ai/settings/usage", enabled: true }
        case "factory":
            return { title: i18n("Open Droid in Browser..."), icon: "internet-services", action: "account-url", url: "https://app.factory.ai", enabled: true }
        case "manus":
            return { title: title, icon: "internet-services", action: "account-url", url: "https://manus.im", enabled: true }
        case "mimo":
            return { title: title, icon: "internet-services", action: "account-url", url: "https://platform.xiaomimimo.com/api/v1/genLoginUrl?currentPath=%2F%23%2Fconsole%2Fbalance", enabled: true }
        case "perplexity":
            return { title: title, icon: "internet-services", action: "account-url", url: "https://www.perplexity.ai/", enabled: true }
        default:
            return loginUrl.length > 0
                ? { title: title, icon: "internet-services", action: "account-url", url: loginUrl, enabled: true }
                : null
        }
    }

    function performAction(actionRow) {
        var actionID = actionRow && actionRow.action ? actionRow.action : actionRow
        var item = selectedProviderData
        if (actionID === "dashboard" && item) {
            Qt.openUrlExternally(item.dashboardUrl)
        } else if (actionID === "status" && item) {
            Qt.openUrlExternally(safeStatusUrl(item.provider, item.statusUrl))
        } else if (actionID === "changelog" && item) {
            Qt.openUrlExternally(item.changelogUrl)
        } else if (actionID === "docs" && actionRow && actionRow.url) {
            Qt.openUrlExternally(actionRow.url)
        } else if (actionID === "accounts" && item) {
            root.loadAccounts(item.provider)
        } else if (actionID === "account-url" && actionRow && actionRow.url) {
            Qt.openUrlExternally(actionRow.url)
        } else if (actionID === "refresh") {
            root.refreshNow()
        } else if (actionID === "about") {
            Qt.openUrlExternally("https://github.com/steipete/CodexBar")
        } else if (actionID === "settings") {
            var action = Plasmoid.internalAction("configure")
            if (action) {
                action.trigger()
            }
        }
    }

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function canvasColor(color, alpha) {
        var opacity = alpha === undefined ? color.a : alpha
        return "rgba("
            + Math.round(color.r * 255) + ", "
            + Math.round(color.g * 255) + ", "
            + Math.round(color.b * 255) + ", "
            + opacity + ")"
    }

    function contrastTextColor(color) {
        var luminance = (0.2126 * color.r) + (0.7152 * color.g) + (0.0722 * color.b)
        return luminance > 0.62 ? Qt.rgba(0.08, 0.08, 0.1, 1) : Qt.rgba(1, 1, 1, 1)
    }

    function readableAccentColor(accent, background) {
        var surface = background || Kirigami.Theme.backgroundColor
        return ThemeContrast.readableAccentColor(
            accent,
            surface,
            Kirigami.Theme.textColor)
    }

    function providerReadableColor(value, background) {
        return readableAccentColor(
            providerColor(value),
            background || Kirigami.Theme.backgroundColor)
    }

    function copyObject(item) {
        return Guards.copyObject(item)
    }

    function hasAdditionalSections(item) {
        return item && (item.credits !== null || item.resetCredits || item.usageDashboard || item.providerCost || item.tokenCost) ? true : false
    }

    function capitalize(value) {
        var text = String(value || "")
        if (text.length === 0) {
            return ""
        }
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    function localizedPeriod(value) {
        var text = String(value || "").trim()
        switch (text.toLowerCase()) {
        case "last 30 days":
            return i18n("Last 30 days")
        case "this month":
            return i18n("This month")
        case "today":
            return i18n("Today")
        default:
            return text
        }
    }

    // Four- and five-figure totals are unreadable as a bare digit run, and
    // Number.toLocaleString with 'f' localizes the decimal mark without adding
    // group separators, so the grouping is applied here.
    function groupedDecimalString(value, digits) {
        return CostPresentation.groupedDecimalString(costNumberFormat, value, digits)
    }

    function amountString(value, currency) {
        return CostPresentation.amountString(costNumberFormat, value, currency)
    }

    // Same figures as costLine without the window label, for surfaces that
    // already state the range once (the Usage & Spend range selector).
    function costValueLine(cost, tokens, currency) {
        var costValue = isFinite(Number(cost)) ? amountString(Number(cost), currency) : "-"
        if (isFinite(Number(tokens))) {
            return i18n("%1 - %2 tokens", costValue, tokenCountString(Number(tokens)))
        }
        return costValue
    }

    function costLine(label, cost, tokens, currency) {
        var costValue = isFinite(Number(cost)) ? amountString(Number(cost), currency) : "-"
        if (isFinite(Number(tokens))) {
            return i18n("%1: %2 - %3 tokens", label, costValue, tokenCountString(Number(tokens)))
        }
        return i18n("%1: %2", label, costValue)
    }

    function tokenCountString(tokens) {
        return CostPresentation.tokenCountString(tokens)
    }

    function tokenCostHint(providerID) {
        switch (providerKey(providerID)) {
        case "codex":
            return i18n("Estimated from local Codex logs for the selected account.")
        case "claude":
            return i18n("Estimated from local Claude logs.")
        default:
            return ""
        }
    }

    function firstUsageRow(item) {
        if (!item || !item.rows) {
            return null
        }
        for (var i = 0; i < item.rows.length; i++) {
            if (item.rows[i] && item.rows[i].hasPercent) {
                return item.rows[i]
            }
        }
        return null
    }

    function usageRowForLane(item, lane) {
        if (!item || !item.rows) {
            return null
        }
        for (var i = 0; i < item.rows.length; i++) {
            if (item.rows[i] && item.rows[i].lane === lane && item.rows[i].hasPercent) {
                return item.rows[i]
            }
        }
        return null
    }

    function switcherMetricRow(item) {
        if (!item || !item.rows || item.rows.length === 0) {
            return null
        }

        var key = providerKey(item.provider)
        var primary = usageRowForLane(item, "primary")
        var secondary = usageRowForLane(item, "secondary")
        if (key === "factory") {
            return secondary || primary || firstUsageRow(item)
        }
        if (key === "perplexity") {
            if (primary && primary.leftPercent > 0) {
                return primary
            }
            return secondary || usageRowForLane(item, "tertiary") || primary || firstUsageRow(item)
        }
        if (key === "cursor" && primary && primary.leftPercent <= 0
                && item.providerCost && item.providerCost.percentUsed >= 0) {
            var used = clamp(Number(item.providerCost.percentUsed), 0, 100)
            return {
                lane: "providerCost",
                label: i18n("Included plan"),
                hasPercent: true,
                usedPercent: used,
                leftPercent: clamp(100 - used, 0, 100),
                pacePercent: -1,
                paceOnTop: true,
                reset: "",
                pace: ""
            }
        }

        return primary || secondary || firstUsageRow(item)
    }

    function switcherPercent(item) {
        var row = switcherMetricRow(item)
        return row ? displayPercent(row) : -1
    }

    function isOverviewErrorOnly(item) {
        return item
            && item.error
            && item.error.length > 0
            && (!item.rows || item.rows.length === 0)
            && providerPlaceholderText(item).length === 0
            && item.credits === null
            && !item.resetCredits
            && !item.providerCost
            && !item.tokenCost
    }

    function overviewProviders() {
        var eligible = []
        if (!providers) {
            return eligible
        }
        for (var i = 0; i < providers.length; i++) {
            if (!isOverviewErrorOnly(providers[i])) {
                eligible.push(providers[i])
            }
        }

        var configured = configuredOverviewProviderIDs()
        if (String(overviewProviderIDsRaw || "").trim().length === 0) {
            return eligible.slice(0, maxOverviewProviders)
        }
        if (configured.length === 0) {
            return []
        }

        var selected = ({})
        for (var j = 0; j < configured.length; j++) {
            selected[configured[j]] = true
        }

        var result = []
        for (var k = 0; k < eligible.length; k++) {
            if (hasOwnKey(selected, String(eligible[k].provider))) {
                result.push(eligible[k])
                if (result.length >= maxOverviewProviders) {
                    break
                }
            }
        }
        return result
    }

    function configuredOverviewProviderIDs() {
        var raw = String(overviewProviderIDsRaw || "").trim()
        if (raw.length === 0 || raw === "__none__") {
            return []
        }
        var parts = raw.split(",")
        var result = []
        var seen = ({})
        for (var i = 0; i < parts.length; i++) {
            var trimmed = String(parts[i] || "").trim()
            if (trimmed.length === 0) {
                continue
            }
            // The settings page stores raw CLI provider IDs (e.g. groqcloud,
            // alibaba-coding-plan); normalize them to match the providerKey
            // form used for eligible[k].provider at runtime.
            var id = normalizedProviderID(trimmed)
            if (id.length === 0 || hasOwnKey(seen, id)) {
                continue
            }
            seen[id] = true
            result.push(id)
            if (result.length >= maxOverviewProviders) {
                break
            }
        }
        return result
    }

    function providerIndex(item) {
        return item ? providerIndexForID(item.provider) : -1
    }

    function providerIndexForID(providerID) {
        var id = String(providerID || "")
        if (id.length === 0 || !providers) {
            return -1
        }
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].provider === id) {
                return i
            }
        }
        return -1
    }

    function overviewDetailText(item) {
        if (!item) {
            return ""
        }
        if (item.account && item.account.length > 0) {
            return item.account
        }
        if (item.status && item.status.length > 0) {
            return item.status
        }
        var placeholder = providerPlaceholderText(item)
        if (placeholder.length > 0) {
            return placeholder
        }
        if (item.source && item.source.length > 0) {
            return item.source
        }
        return ""
    }

    function providerPlaceholderText(item) {
        if (!item || !item.placeholder || item.placeholder.length === 0) {
            return ""
        }
        if (item.provider === "codex" && item.tokenCost) {
            return ""
        }
        return item.placeholder
    }

    function displayPercent(row) {
        if (!row || !row.hasPercent) {
            return 0
        }
        return usageBarsShowUsed ? row.usedPercent : row.leftPercent
    }

    function paceMarkerPercent(row) {
        if (!row || row.pacePercent < 0) {
            return -1
        }
        return usageBarsShowUsed ? row.pacePercent : clamp(100 - row.pacePercent, 0, 100)
    }

    function percentSuffix() {
        return usageBarsShowUsed ? i18n("used") : i18n("left")
    }

    function resetLabel(value) {
        var text = String(value || "").trim()
        if (text.length === 0) {
            return ""
        }
        // Only split where a unit letter runs into the next number
        // ("Resets5h30m" -> "Resets 5h 30m"). Splitting digit-then-letter as
        // well would also tear a number away from its own unit and render our
        // own compact durations ("2h 30m") as "2 h 30 m".
        text = text
            .replace(/([A-Za-z])(\d)/g, "$1 $2")
            .replace(/\)([A-Za-z])/g, ") $1")
            .replace(/(am|pm)\(/ig, "$1 (")
            .replace(/\s+/g, " ")
        if (/^resets\b/i.test(text)) {
            var rest = text.replace(/^resets\s*/i, "")
            return resetLabelLooksLikeTime(rest) ? i18n("Resets %1", rest) : rest
        }
        return resetLabelLooksLikeTime(text) ? i18n("Resets %1", text) : text
    }

    function resetLabelLooksLikeTime(value) {
        var text = String(value || "").trim()
        if (text.length === 0) {
            return false
        }
        if (/^(now|today|tomorrow)\b/i.test(text)) {
            return true
        }
        if (/^\d{1,2}(:\d{2})?\s*(am|pm)(\s*\([^)]+\))?$/i.test(text)) {
            return true
        }
        if (/^\d{1,2}:\d{2}(\s*\([^)]+\))?$/.test(text)) {
            return true
        }
        if (/^\S+\s+\d{1,2}:\d{2}(\s*\([^)]+\))?$/.test(text)) {
            return true
        }
        return /^\d+\s*(min|m|h|hr|hour|hours|d|day|days)(\s+\d+\s*(min|m|h|hr|hour|hours|d|day|days))*$/i.test(text)
    }

    function providerCountText(count) {
        var total = Math.max(0, Math.round(Number(count) || 0))
        return i18np("%1 provider", "%1 providers", total)
    }

    function clamp(value, minimum, maximum) {
        return Normalizer.clamp(value, minimum, maximum)
    }

    function primaryProvider() {
        return providers.length > 0 ? providers[0] : null
    }

    function selectedCompactProvider() {
        if (autoSelectProvider && selectedProviderData) {
            return selectedProviderData
        }
        return primaryProvider()
    }

    function selectGlobalView(viewID) {
        var candidate = String(viewID || "")
        if ((candidate === "overview" && !overviewAvailable)
                || (candidate === "spend" && !spendAvailable)
                || (candidate === "sessions" && !sessionsAvailable)) {
            return
        }
        if (candidate !== "overview" && candidate !== "spend" && candidate !== "sessions") {
            return
        }

        selectedGlobalView = candidate
        selectedProviderID = ""
        selectionInitialized = true
        if (candidate === "sessions" && !sessionsInitialized) {
            refreshSessions()
        }
    }

    function updateSelectedProvider() {
        if (!providers || providers.length === 0) {
            return
        }

        if (autoSelectProvider) {
            // Don't override a global tab the user explicitly chose;
            // auto-select only drives the initial pick and provider tabs.
            if (selectionInitialized && globalViewSelected) {
                return
            }
            selectedProviderID = providers[autoSelectedProviderIndex()].provider
            selectionInitialized = true
            return
        }

        if (!selectionInitialized) {
            selectedProviderID = overviewAvailable ? "" : providers[0].provider
            selectedGlobalView = "overview"
            selectionInitialized = true
            return
        }
        if (selectedProviderIndex < 0
                && (!globalViewSelected
                    || (selectedGlobalView === "overview" && !overviewAvailable)
                    || (selectedGlobalView === "spend" && !spendAvailable)
                    || (selectedGlobalView === "sessions" && !sessionsAvailable))) {
            selectedProviderID = providers[0].provider
        }
    }

    function autoSelectedProviderIndex() {
        var bestIndex = 0
        var bestScore = -1
        for (var i = 0; i < providers.length; i++) {
            var score = autoSelectScore(providers[i])
            if (score > bestScore) {
                bestScore = score
                bestIndex = i
            }
        }
        return bestIndex
    }

    function autoSelectScore(item) {
        if (!item || isOverviewErrorOnly(item)) {
            return -1
        }
        var percent = autoSelectUsedPercent(item)
        var incidentTieBreaker = notificationRank(item.statusSeverity) / 100
        return percent >= 0 ? percent + incidentTieBreaker : incidentTieBreaker
    }

    function autoSelectUsedPercent(item) {
        if (!item) {
            return -1
        }

        var best = -1
        var rows = item.rows || []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].hasPercent) {
                var used = Number(rows[i].usedPercent)
                if (isFinite(used)) {
                    best = Math.max(best, clamp(used, 0, 100))
                }
            }
        }
        if (item.providerCost && item.providerCost.percentUsed >= 0) {
            var providerCostUsed = Number(item.providerCost.percentUsed)
            if (isFinite(providerCostUsed)) {
                best = Math.max(best, clamp(providerCostUsed, 0, 100))
            }
        }
        return best
    }

    function compactProviders() {
        if (!providers || providers.length <= 1
                || Plasmoid.configuration.showMultiProviderInPanel !== true) {
            return []
        }

        var result = []
        for (var i = 0; i < providers.length && result.length < 4; i++) {
            if (switcherPercent(providers[i]) >= 0) {
                result.push(providers[i])
            }
        }
        return result
    }

    function compactText() {
        var item = selectedCompactProvider()
        if (!item) {
            return loading ? i18n("Loading") : "CodexBar"
        }

        var parts = []
        if (Plasmoid.configuration.showProviderInPanel) {
            parts.push(item.title)
        }

        var display = menuBarDisplayText(item)
        if (Plasmoid.configuration.showPercentInPanel && display.length > 0) {
            parts.push(display)
        }

        if (Plasmoid.configuration.showCreditsInPanel && item.credits !== null) {
            parts.push(i18n("%1cr", formatNumber(item.credits)))
        }

        return parts.join(" ")
    }

    function panelToolTipText() {
        var lines = []
        for (var i = 0; i < providers.length && lines.length < 6; i++) {
            var item = providers[i]
            if (!item) {
                continue
            }
            // Vertical panels collapse to a bare icon, so the tooltip is the only
            // incident surface there; never drop status just because usage exists.
            var incident = item.hasIncident && item.status.length > 0 ? item.status : ""
            var percent = switcherPercent(item)
            var line = ""
            if (percent >= 0) {
                line = i18n("%1: %2% %3", item.title, Math.round(percent), percentSuffix())
                if (incident.length > 0) {
                    line = i18n("%1 - %2", line, incident)
                }
            } else if (incident.length > 0) {
                line = i18n("%1: %2", item.title, incident)
            }
            if (line.length > 0) {
                lines.push(line)
            }
        }
        if (loading) {
            lines.push(i18n("Refreshing usage..."))
        }
        if (lines.length === 0 && errorText.length > 0) {
            return boundedDisplayText(errorText, 500)
        }
        return lines.join("\n")
    }

    function menuBarDisplayText(item) {
        if (!item) {
            return ""
        }

        var mode = String(menuBarDisplayMode || "percent")
        if (mode === "pace") {
            return primaryPaceText(item)
        }
        if (mode === "both") {
            var percentText = primaryPercentText(item)
            var paceText = primaryPaceText(item)
            if (percentText.length > 0 && paceText.length > 0) {
                return i18n("%1 - %2", percentText, paceText)
            }
            return percentText.length > 0 ? percentText : paceText
        }
        if (mode === "resetTime") {
            return primaryResetText(item)
        }
        if (mode === "runOut") {
            return primaryRunOutText(item)
        }
        return primaryPercentText(item)
    }

    function primaryPercentText(item) {
        var percent = switcherPercent(item)
        return percent >= 0 ? i18n("%1%", Math.round(percent)) : ""
    }

    function primaryPaceText(item) {
        var row = switcherMetricRow(item)
        if (!row || row.pacePercent < 0) {
            return ""
        }
        var shownPace = paceMarkerPercent(row)
        if (shownPace < 0) {
            return ""
        }
        return row.paceOnTop
            ? i18n("%1% pace", Math.round(shownPace))
            : i18n("%1% pace late", Math.round(shownPace))
    }

    // Duration-only forecast token. It stays empty unless the CLI actually
    // predicts exhaustion before the reset, so the panel never shows a
    // countdown the pace data does not support.
    function primaryRunOutText(item) {
        var row = switcherMetricRow(item)
        if (!paceWarningActive(row)) {
            return ""
        }
        return paceEtaText(row.paceEtaSeconds)
    }

    function primaryResetText(item) {
        var row = switcherMetricRow(item)
        var reset = usageResetText(row)
        if (reset.length === 0) {
            return ""
        }
        return resetLabel(reset)
    }

    // Credit balances are plain counts, so they share the popup's grouped,
    // locale-aware figure formatting instead of printing a bare digit run with
    // a hardcoded decimal mark. A whole balance keeps no fractional part, so a
    // depleted account reads as "0" rather than "0.0".
    function formatNumber(value) {
        var numeric = Number(value)
        if (!isFinite(numeric)) {
            return "-"
        }
        var magnitude = Math.abs(numeric)
        var digits = magnitude >= 100 || magnitude === Math.round(magnitude) ? 0 : 1
        return (numeric < 0 ? "-" : "") + groupedDecimalString(magnitude, digits)
    }

    Plasma5Support.DataSource {
        id: usageSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var rawStdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stdoutText = SafeText.cliJsonText(rawStdoutText)
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            if (stdoutText === null) {
                stdoutText = ""
                stderrText = i18n("codexbar response exceeded the supported size.")
            }

            // A reply the ledger no longer holds is a late result from a
            // retired run. Dropping it is what keeps it from overwriting the
            // refresh that replaced it.
            var descriptor = CommandLedger.find(root.activeUsageCommands, sourceName)
            if (!descriptor) {
                return
            }

            switch (descriptor.kind) {
            case "cost":
                var requestedHistoryDays = descriptor.costHistoryDays !== undefined
                    ? descriptor.costHistoryDays
                    : root.costHistoryDays
                root.finishUsageCommandSource(sourceName)
                root.parseCostOutput(stdoutText, stderrText, requestedHistoryDays)
                return
            case "sessions":
                root.finishUsageCommandSource(sourceName)
                root.parseSessionsOutput(stdoutText, stderrText)
                return
            case "providerConfig":
                root.finishUsageCommandSource(sourceName)
                root.parseProviderConfigOutput(stdoutText, stderrText)
                return
            case "account":
                root.parseProviderAccountsOutput(sourceName, stdoutText, stderrText)
                return
            case "providerFallback":
                root.parseProviderFallbackOutput(sourceName, stdoutText, stderrText)
                return
            case "usage":
                root.finishUsageCommandSource(sourceName)
                root.parseOutput(stdoutText, stderrText)
                return
            default:
                root.finishUsageCommandSource(sourceName)
            }
        }
    }

    Timer {
        id: usageRefreshTimer

        interval: Math.max(1, root.refreshIntervalSec) * 1000
        repeat: true
        running: root.refreshIntervalSec > 0
        triggeredOnStart: false
        onTriggered: {
            if (!root.hasPendingUsageCommandTimeouts()) {
                root.refreshNow()
            }
        }
    }

    Timer {
        id: usageCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: root.hasPendingUsageCommandTimeouts()
        triggeredOnStart: false
        onTriggered: root.expireUsageCommands(Date.now())
    }

    Timer {
        id: accountCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: root.hasPendingAccountCommands()
        triggeredOnStart: false
        onTriggered: root.expirePendingAccountCommands(Date.now())
    }

    Plasma5Support.DataSource {
        id: providerConfigWatcher

        engine: "executable"
        interval: root.providerConfigWatchIntervalMs

        onNewData: function(sourceName, data) {
            if (sourceName !== root.providerConfigWatchCommand) {
                return
            }
            var stdoutText = data && data["stdout"] ? data["stdout"] : ""
            root.handleProviderConfigWatch(stdoutText)
        }
    }

    Timer {
        id: updateCheckTimer

        repeat: false
        running: false
        triggeredOnStart: false
        onTriggered: root.checkForWidgetUpdate()
    }

    Timer {
        id: updateCommandTimeoutTimer

        repeat: false
        onTriggered: root.handleUpdateCommandTimeout()
    }

    Plasma5Support.DataSource {
        id: updateSource

        engine: "executable"

        onNewData: function(sourceName, data) {
            var rawStdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stdoutText = SafeText.cliJsonText(rawStdoutText)
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            if (stdoutText === null) {
                stdoutText = ""
                stderrText = i18n("Widget updater response exceeded the supported size.")
            }
            root.handleUpdateData(sourceName, stdoutText, stderrText)
        }
    }

    Plasma5Support.DataSource {
        id: notificationSource

        engine: "executable"

        onNewData: function(sourceName, data) {
            notificationSource.disconnectSource(sourceName)
        }
    }

    compactRepresentation: Components.CompactRepresentation {
        applet: root
    }

    fullRepresentation: Components.FullRepresentation {
        applet: root
    }
}
