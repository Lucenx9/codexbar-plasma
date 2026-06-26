import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.icon: "view-statistics"
    Plasmoid.title: "CodexBar"
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
    property bool usageBarsShowUsed: Plasmoid.configuration.usageBarsShowUsed === true
    property bool showQuotaWarningMarkers: Plasmoid.configuration.showQuotaWarningMarkers !== false
    property bool enableNotifications: Plasmoid.configuration.enableNotifications !== false
    property bool notifyStatusIncidents: Plasmoid.configuration.notifyStatusIncidents !== false
    property bool notifyQuotaWarnings: Plasmoid.configuration.notifyQuotaWarnings !== false
    property bool notifyLimitResets: Plasmoid.configuration.notifyLimitResets !== false
    property string menuBarDisplayMode: Plasmoid.configuration.menuBarDisplayMode || "percent"
    property bool resetTimesShowAbsolute: Plasmoid.configuration.resetTimesShowAbsolute === true
    property bool showProviderChangelogs: Plasmoid.configuration.showProviderChangelogs === true
    property bool autoSelectProvider: Plasmoid.configuration.autoSelectProvider === true
    property int providerConfigRevision: Plasmoid.configuration.providerConfigRevision || 0
    property var providers: []
    property var providerDisplayNames: ({})
    property string errorText: ""
    property string lastUpdatedText: ""
    property bool loading: false
    property string commandSource: buildCommand()
    property string connectedCommandSource: ""
    property string providerConfigCommandSource: buildProviderConfigCommand()
    property string connectedProviderConfigCommandSource: ""
    property string providerConfigWatchCommand: buildProviderConfigWatchCommand()
    property string providerConfigStamp: ""
    property int commandRunSerial: 0
    property var pendingProviderCommands: ({})
    property var fallbackProviderOrder: []
    property var fallbackProviderResults: ({})
    property var fallbackProviderSeen: ({})
    property int pendingProviderCount: 0
    property bool providerFallbackActive: false
    property string costCommandSource: buildCostCommand()
    property string connectedCostCommandSource: ""
    property var tokenCosts: ({})
    property string costErrorText: ""
    property int selectedProviderIndex: 0
    property bool selectionInitialized: false
    property var selectedAccounts: ({})
    property var accountOptions: ({})
    property var accountErrors: ({})
    property var accountLoading: ({})
    property var pendingAccountCommands: ({})
    property var notificationMemo: ({})
    property bool notificationsPrimed: false
    readonly property bool overviewAvailable: provider.length === 0 && providers.length > 1
    readonly property bool overviewSelected: overviewAvailable && selectedProviderIndex < 0
    readonly property var selectedProviderData: providers.length > 0 && selectedProviderIndex >= 0
        ? providers[Math.min(selectedProviderIndex, providers.length - 1)]
        : null

    onCommandSourceChanged: Qt.callLater(refreshNow)
    onProviderConfigRevisionChanged: Qt.callLater(refreshNow)
    onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)
    onAutoSelectProviderChanged: updateSelectedProvider()
    onEnableNotificationsChanged: resetNotificationMemo()
    onNotifyStatusIncidentsChanged: resetNotificationMemo()
    onNotifyQuotaWarningsChanged: resetNotificationMemo()
    onNotifyLimitResetsChanged: resetNotificationMemo()
    onProvidersChanged: {
        if (providers.length === 0) {
            selectedProviderIndex = 0
            selectionInitialized = false
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

        var effectiveSource = source
        if (source.length === 0 && providerKey(providerID) === "codex") {
            effectiveSource = "cli"
        }

        if (effectiveSource.length > 0) {
            parts.push("--source")
            parts.push(shellQuote(effectiveSource))
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
        return [
            "sh",
            "-lc",
            shellQuote("config=\"${XDG_CONFIG_HOME:-$HOME/.config}/codexbar/config.json\"; if [ -r \"$config\" ]; then cksum \"$config\"; else printf missing; fi")
        ].join(" ")
    }

    function buildProviderUsageCommand(providerID, codexCliFallback) {
        var parts = [
            shellQuote(commandPath),
            "usage",
            "--provider",
            shellQuote(providerCliArgument(providerID)),
            "--format",
            "json",
            "--json-only"
        ]

        var effectiveSource = source
        if (codexCliFallback && source.length === 0 && providerKey(providerID) === "codex") {
            effectiveSource = "cli"
        }

        if (effectiveSource.length > 0) {
            parts.push("--source")
            parts.push(shellQuote(effectiveSource))
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

        var parts = [
            shellQuote(commandPath),
            "cost",
            "--format",
            "json",
            "--json-only"
        ]

        if (provider.length > 0) {
            parts.push("--provider")
            parts.push(shellQuote(provider))
        }

        return parts.join(" ")
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function hasOwnKey(item, key) {
        return item ? Object.prototype.hasOwnProperty.call(item, key) : false
    }

    function isUnsafeObjectKey(key) {
        var value = String(key || "")
        return value === "__proto__" || value === "prototype" || value === "constructor"
    }

    function commandWithRunNonce(command) {
        if (command.length === 0) {
            return ""
        }
        commandRunSerial += 1
        return "CODEXBAR_PLASMA_RUN=" + commandRunSerial + " " + command
    }

    function refreshNow() {
        disconnectUsageCommands()

        if (commandSource.length === 0) {
            errorText = i18n("Set the codexbar command path in widget settings.")
            return
        }

        loading = true
        errorText = ""
        providerFallbackActive = false
        if (canUseProviderFallback()) {
            startProviderFallback()
            refreshCost()
            return
        }
        connectedCommandSource = commandWithRunNonce(commandSource)
        usageSource.connectSource(connectedCommandSource)
        refreshCost()
    }

    function disconnectUsageCommands() {
        if (connectedCommandSource.length > 0) {
            usageSource.disconnectSource(connectedCommandSource)
            connectedCommandSource = ""
        }
        if (connectedProviderConfigCommandSource.length > 0) {
            usageSource.disconnectSource(connectedProviderConfigCommandSource)
            connectedProviderConfigCommandSource = ""
        }
        for (var command in pendingProviderCommands) {
            usageSource.disconnectSource(command)
        }
        for (var accountCommand in pendingAccountCommands) {
            usageSource.disconnectSource(accountCommand)
        }
        pendingProviderCommands = ({})
        pendingAccountCommands = ({})
        accountLoading = ({})
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
        if (connectedCostCommandSource.length > 0) {
            usageSource.disconnectSource(connectedCostCommandSource)
            connectedCostCommandSource = ""
        }

        if (costCommandSource.length === 0) {
            tokenCosts = ({})
            costErrorText = ""
            return
        }

        costErrorText = ""
        connectedCostCommandSource = commandWithRunNonce(costCommandSource)
        usageSource.connectSource(connectedCostCommandSource)
    }

    function parseOutput(stdoutText, stderrText) {
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            if (canUseProviderFallback()) {
                startProviderFallback()
                return
            }
            providers = []
            errorText = stderrText.trim().length > 0 ? stderrText.trim() : i18n("codexbar did not return JSON.")
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
        for (var i = 0; i < items.length; i++) {
            if (items[i]) {
                nextProviders.push(normalizeProvider(items[i]))
            }
        }

        providers = nextProviders
        errorText = nextProviders.length === 0 ? stderrText.trim() : ""
        lastUpdatedText = i18n("Updated %1", Qt.formatDateTime(new Date(), "hh:mm"))
        loading = false
    }

    function canUseProviderFallback() {
        return source.length === 0
    }

    function startProviderFallback() {
        providerFallbackActive = true
        if (connectedCommandSource.length > 0) {
            usageSource.disconnectSource(connectedCommandSource)
            connectedCommandSource = ""
        }
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

        connectedProviderConfigCommandSource = commandWithRunNonce(providerConfigCommandSource)
        usageSource.connectSource(connectedProviderConfigCommandSource)
    }

    function parseProviderConfigOutput(stdoutText, stderrText) {
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            providers = []
            errorText = stderrText.trim().length > 0 ? stderrText.trim() : i18n("Could not load CodexBar provider configuration.")
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

        var providerIDs = []
        var displayNames = ({})
        var items = Array.isArray(payload) ? payload : []
        for (var i = 0; i < items.length; i++) {
            if (items[i] && items[i].provider) {
                var providerID = providerKey(items[i].provider)
                if (items[i].displayName && String(items[i].displayName).trim().length > 0) {
                    displayNames[providerID] = String(items[i].displayName).trim()
                }
                if (items[i].enabled === true) {
                    providerIDs.push(providerID)
                }
            }
        }

        providerDisplayNames = displayNames
        startProviderFallbackForProviders(providerIDs)
    }

    function startProviderFallbackForProviders(providerIDs) {
        for (var existingCommand in pendingProviderCommands) {
            usageSource.disconnectSource(existingCommand)
        }
        pendingProviderCommands = ({})
        fallbackProviderOrder = []
        fallbackProviderResults = ({})
        fallbackProviderSeen = ({})
        pendingProviderCount = 0

        var seenCommands = ({})
        var commands = ({})
        var commandList = []
        for (var i = 0; i < providerIDs.length; i++) {
            var providerID = providerKey(providerIDs[i])
            var baseCommand = buildProviderUsageCommand(providerID, true)
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
        for (var j = 0; j < commandList.length; j++) {
            usageSource.connectSource(commandList[j])
        }
        if (pendingProviderCount === 0) {
            providers = []
            errorText = i18n("No enabled CodexBar providers.")
            loading = false
        }
    }

    function parseProviderFallbackOutput(sourceName, stdoutText, stderrText) {
        var providerID = pendingProviderCommands[sourceName] || ""
        if (providerID.length === 0) {
            return
        }
        if (fallbackProviderSeen[providerID]) {
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
                stderrText.trim().length > 0 ? stderrText.trim() : i18n("codexbar did not return JSON."))))
        } else {
            var payload
            try {
                payload = JSON.parse(trimmed)
                var items = Array.isArray(payload) ? payload : [payload]
                for (var i = 0; i < items.length; i++) {
                    if (items[i]) {
                        if (!items[i].provider) {
                            items[i].provider = providerID
                        }
                        normalizedItems.push(normalizeProvider(items[i]))
                    }
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
        pendingProviderCount = Math.max(0, pendingProviderCount - 1)

        if (pendingProviderCount === 0) {
            finishProviderFallback()
        }
    }

    function finishProviderFallback() {
        var nextProviders = []
        for (var i = 0; i < fallbackProviderOrder.length; i++) {
            var providerID = fallbackProviderOrder[i]
            var items = fallbackProviderResults[providerID] || []
            for (var j = 0; j < items.length; j++) {
                nextProviders.push(items[j])
            }
        }

        providers = nextProviders
        errorText = nextProviders.length === 0 ? i18n("codexbar did not return JSON.") : ""
        lastUpdatedText = i18n("Updated %1", Qt.formatDateTime(new Date(), "hh:mm"))
        loading = false
        fallbackProviderSeen = ({})
        pendingProviderCount = fallbackProviderOrder.length
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
        commands[connectedCommand] = normalizedProviderID
        pendingAccountCommands = commands
        usageSource.connectSource(connectedCommand)
    }

    function parseProviderAccountsOutput(sourceName, stdoutText, stderrText) {
        var providerID = pendingAccountCommands[sourceName] || ""
        if (providerID.length === 0) {
            return
        }

        var commands = copyObject(pendingAccountCommands)
        delete commands[sourceName]
        pendingAccountCommands = commands
        setAccountLoading(providerID, false)

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            setAccountOptions(providerID, [])
            setAccountError(providerID, stderrText.trim().length > 0 ? stderrText.trim() : i18n("codexbar did not return account data."))
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            setAccountOptions(providerID, [])
            setAccountError(providerID, i18n("Could not parse codexbar account JSON: %1", error.message))
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var options = []
        var message = ""
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item) {
                continue
            }
            if (!item.provider) {
                item.provider = providerID
            }
            var normalized = normalizeProvider(item)
            if (normalized.error.length > 0 && accountLabel(normalized).length === 0) {
                message = normalized.error
                continue
            }
            options.push(normalized)
        }

        setAccountOptions(providerID, dedupeAccountOptions(options))
        setAccountError(providerID, options.length === 0 ? message : "")
    }

    function dedupeAccountOptions(items) {
        var seen = ({})
        var result = []
        for (var i = 0; i < items.length; i++) {
            var label = accountLabel(items[i])
            if (label.length === 0 || seen[label]) {
                continue
            }
            seen[label] = true
            result.push(items[i])
        }
        return result
    }

    function parseCostOutput(stdoutText, stderrText) {
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            tokenCosts = ({})
            costErrorText = stderrText.trim()
            applyTokenCosts()
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            tokenCosts = ({})
            costErrorText = i18n("Could not parse codexbar cost JSON: %1", error.message)
            applyTokenCosts()
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var nextCosts = ({})
        for (var i = 0; i < items.length; i++) {
            var cost = normalizeTokenCost(items[i])
            if (cost && cost.provider.length > 0) {
                nextCosts[cost.provider] = cost
            }
        }

        tokenCosts = nextCosts
        costErrorText = ""
        applyTokenCosts()
    }

    function normalizeTokenCost(item) {
        if (!item || !item.provider) {
            return null
        }

        var providerID = providerKey(item.provider)
        var currency = item.currencyCode || "USD"
        var windowLabel = item.historyLabel || (item.historyDays === 1 ? i18n("Today") : i18n("Last 30 days"))
        return {
            provider: providerID,
            title: i18n("Cost"),
            sessionLine: costLine(i18n("Today"), item.sessionCostUSD, item.sessionTokens, currency),
            monthLine: costLine(windowLabel, item.last30DaysCostUSD, item.last30DaysTokens, currency),
            hintLine: tokenCostHint(providerID),
            totals: normalizeCostTotals(item.totals, item.last30DaysCostUSD, item.last30DaysTokens, currency),
            models: normalizeCostModels(item.daily, currency),
            daily: normalizeCostDaily(item.daily, currency)
        }
    }

    function normalizeCostDaily(items, currency) {
        var result = []
        if (!items || !Array.isArray(items)) {
            return result
        }

        for (var i = 0; i < items.length; i++) {
            var item = items[i] || ({})
            var cost = Number(item.totalCost !== undefined ? item.totalCost : item.costUSD)
            var tokens = Number(item.totalTokens !== undefined ? item.totalTokens : item.tokens)
            var inputTokens = Number(item.inputTokens)
            var outputTokens = Number(item.outputTokens)
            var cacheReadTokens = Number(item.cacheReadTokens)
            var cacheCreationTokens = Number(item.cacheCreationTokens !== undefined ? item.cacheCreationTokens : item.cacheWriteTokens)
            if (!isFinite(tokens)) {
                tokens = sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens)
            }
            if (!isFinite(cost) && !isFinite(tokens) && !isFinite(inputTokens) && !isFinite(outputTokens)) {
                continue
            }
            result.push({
                label: String(item.date || item.day || item.dayKey || ""),
                cost: isFinite(cost) ? Math.max(0, cost) : 0,
                tokens: isFinite(tokens) ? Math.max(0, tokens) : 0,
                inputTokens: isFinite(inputTokens) ? Math.max(0, inputTokens) : 0,
                outputTokens: isFinite(outputTokens) ? Math.max(0, outputTokens) : 0,
                cacheReadTokens: isFinite(cacheReadTokens) ? Math.max(0, cacheReadTokens) : 0,
                cacheCreationTokens: isFinite(cacheCreationTokens) ? Math.max(0, cacheCreationTokens) : 0,
                currency: currency || "USD"
            })
        }

        return result.slice(Math.max(0, result.length - 30))
    }

    function normalizeCostTotals(totals, fallbackCost, fallbackTokens, currency) {
        var source = totals || ({})
        var cost = Number(source.totalCost !== undefined ? source.totalCost : fallbackCost)
        var tokens = Number(source.totalTokens !== undefined ? source.totalTokens : fallbackTokens)
        var inputTokens = Number(source.inputTokens)
        var outputTokens = Number(source.outputTokens)
        var cacheReadTokens = Number(source.cacheReadTokens)
        var cacheCreationTokens = Number(source.cacheCreationTokens !== undefined ? source.cacheCreationTokens : source.cacheWriteTokens)
        if (!isFinite(tokens)) {
            tokens = sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens)
        }
        return {
            cost: isFinite(cost) ? Math.max(0, cost) : 0,
            tokens: isFinite(tokens) ? Math.max(0, tokens) : 0,
            inputTokens: isFinite(inputTokens) ? Math.max(0, inputTokens) : 0,
            outputTokens: isFinite(outputTokens) ? Math.max(0, outputTokens) : 0,
            cacheReadTokens: isFinite(cacheReadTokens) ? Math.max(0, cacheReadTokens) : 0,
            cacheCreationTokens: isFinite(cacheCreationTokens) ? Math.max(0, cacheCreationTokens) : 0,
            currency: currency || "USD"
        }
    }

    function sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens) {
        var total = 0
        var values = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens]
        for (var i = 0; i < values.length; i++) {
            if (isFinite(Number(values[i])) && Number(values[i]) > 0) {
                total += Number(values[i])
            }
        }
        return total > 0 ? total : Number.NaN
    }

    function normalizeCostModels(items, currency) {
        var byName = ({})
        if (!items || !Array.isArray(items)) {
            return []
        }

        for (var i = 0; i < items.length; i++) {
            var breakdowns = items[i] && Array.isArray(items[i].modelBreakdowns)
                ? items[i].modelBreakdowns
                : []
            for (var j = 0; j < breakdowns.length; j++) {
                var breakdown = breakdowns[j] || ({})
                var name = String(breakdown.modelName || breakdown.model || "").trim()
                if (name.length === 0 || isUnsafeObjectKey(name)) {
                    continue
                }
                var cost = Number(breakdown.cost !== undefined ? breakdown.cost : breakdown.totalCost)
                var tokens = Number(breakdown.totalTokens !== undefined ? breakdown.totalTokens : breakdown.tokens)
                if (!isFinite(cost) && !isFinite(tokens)) {
                    continue
                }
                if (!hasOwnKey(byName, name)) {
                    byName[name] = {
                        label: name,
                        cost: 0,
                        tokens: 0,
                        currency: currency || "USD"
                    }
                }
                if (isFinite(cost)) {
                    byName[name].cost += Math.max(0, cost)
                }
                if (isFinite(tokens)) {
                    byName[name].tokens += Math.max(0, tokens)
                }
            }
        }

        var rows = []
        for (var modelName in byName) {
            if (!hasOwnKey(byName, modelName)) {
                continue
            }
            rows.push(byName[modelName])
        }
        rows.sort(function(a, b) {
            if (b.cost !== a.cost) {
                return b.cost - a.cost
            }
            return b.tokens - a.tokens
        })
        return rows.slice(0, 6)
    }

    function costSparklineMax(points) {
        var maxCost = 0
        if (!points) {
            return maxCost
        }
        for (var i = 0; i < points.length; i++) {
            maxCost = Math.max(maxCost, Number(points[i].cost) || 0)
        }
        return maxCost
    }

    function costSparklineSummary(points) {
        if (!points || points.length === 0) {
            return ""
        }
        var last = points[points.length - 1]
        var label = last.label && last.label.length > 0 ? last.label : i18n("Latest")
        return i18n("%1: %2", label, amountString(last.cost, last.currency || "USD"))
    }

    function costBreakdownRows(tokenCost) {
        if (!tokenCost || !tokenCost.totals) {
            return []
        }

        var totals = tokenCost.totals
        var rows = []
        appendTokenBreakdownRow(rows, i18n("Total tokens"), totals.tokens)
        appendTokenBreakdownRow(rows, i18n("Input"), totals.inputTokens)
        appendTokenBreakdownRow(rows, i18n("Output"), totals.outputTokens)
        appendTokenBreakdownRow(rows, i18n("Cache read"), totals.cacheReadTokens)
        appendTokenBreakdownRow(rows, i18n("Cache write"), totals.cacheCreationTokens)
        return rows
    }

    function appendTokenBreakdownRow(rows, label, tokens) {
        var value = Number(tokens)
        if (!isFinite(value) || value <= 0) {
            return
        }
        rows.push({
            label: label,
            value: tokenCountString(value)
        })
    }

    function costModelRows(tokenCost) {
        if (!tokenCost || !tokenCost.models) {
            return []
        }

        var rows = []
        for (var i = 0; i < tokenCost.models.length; i++) {
            var item = tokenCost.models[i]
            rows.push({
                label: item.label,
                value: costTokenSummary(item.cost, item.tokens, item.currency)
            })
        }
        return rows
    }

    function costDailyRows(tokenCost) {
        if (!tokenCost || !tokenCost.daily) {
            return []
        }

        var rows = []
        var first = Math.max(0, tokenCost.daily.length - 7)
        for (var i = tokenCost.daily.length - 1; i >= first; i--) {
            var item = tokenCost.daily[i]
            rows.push({
                label: item.label && item.label.length > 0 ? item.label : i18n("Latest"),
                value: costTokenSummary(item.cost, item.tokens, item.currency)
            })
        }
        return rows
    }

    function costHistoryRows(tokenCost) {
        if (!tokenCost || !tokenCost.daily || tokenCost.daily.length === 0) {
            return []
        }

        var rows = []
        var maxCost = costSparklineMax(tokenCost.daily)
        var first = Math.max(0, tokenCost.daily.length - 14)
        for (var i = tokenCost.daily.length - 1; i >= first; i--) {
            var item = tokenCost.daily[i]
            var cost = Math.max(0, Number(item.cost) || 0)
            var value = compactCostTokenSummary(cost, item.tokens, item.currency)
            rows.push({
                label: item.label && item.label.length > 0 ? item.label : i18n("Latest"),
                value: value.length > 0 ? value : amountString(0, item.currency || "USD"),
                percent: maxCost > 0 ? Math.max(3, cost * 100 / maxCost) : 0,
                isPeak: maxCost > 0 && cost === maxCost
            })
        }
        return rows
    }

    function costPeakLine(points) {
        if (!points || points.length === 0) {
            return ""
        }

        var peak = null
        for (var i = 0; i < points.length; i++) {
            var cost = Number(points[i].cost) || 0
            if (!peak || cost > peak.cost) {
                peak = {
                    label: points[i].label && points[i].label.length > 0 ? points[i].label : i18n("Latest"),
                    cost: cost,
                    currency: points[i].currency || "USD"
                }
            }
        }
        if (!peak || peak.cost <= 0) {
            return ""
        }
        return i18n("Peak: %1 · %2", peak.label, amountString(peak.cost, peak.currency))
    }

    function costAverageDailyLine(points) {
        if (!points || points.length === 0) {
            return ""
        }

        var total = 0
        var currency = "USD"
        for (var i = 0; i < points.length; i++) {
            total += Math.max(0, Number(points[i].cost) || 0)
            if (points[i].currency) {
                currency = points[i].currency
            }
        }
        if (total <= 0) {
            return ""
        }
        return i18n("Average/day: %1", amountString(total / points.length, currency))
    }

    function costPerMillionLine(tokenCost) {
        if (!tokenCost || !tokenCost.totals) {
            return ""
        }
        var cost = Number(tokenCost.totals.cost)
        var tokens = Number(tokenCost.totals.tokens)
        if (!isFinite(cost) || !isFinite(tokens) || cost <= 0 || tokens <= 0) {
            return ""
        }
        return i18n("Average: %1 / 1M tokens", amountString(cost * 1000000 / tokens, tokenCost.totals.currency || "USD"))
    }

    function costTokenSummary(cost, tokens, currency) {
        var parts = []
        if (isFinite(Number(cost)) && Number(cost) > 0) {
            parts.push(amountString(Number(cost), currency || "USD"))
        }
        if (isFinite(Number(tokens)) && Number(tokens) > 0) {
            parts.push(i18n("%1 tokens", tokenCountString(Number(tokens))))
        }
        return parts.join(" · ")
    }

    function compactCostTokenSummary(cost, tokens, currency) {
        var parts = []
        if (isFinite(Number(cost)) && Number(cost) > 0) {
            parts.push(amountString(Number(cost), currency || "USD"))
        }
        if (isFinite(Number(tokens)) && Number(tokens) > 0) {
            parts.push(tokenCountString(Number(tokens)))
        }
        return parts.join(" · ")
    }

    function applyTokenCosts() {
        if (!providers || providers.length === 0) {
            return
        }

        var nextProviders = []
        for (var i = 0; i < providers.length; i++) {
            var item = copyObject(providers[i])
            item.tokenCost = tokenCosts[item.provider] || null
            nextProviders.push(item)
        }
        providers = nextProviders
    }

    function selectedAccountForProvider(providerID) {
        var key = providerKey(providerID)
        var selected = selectedAccounts[key]
        return selected ? String(selected) : ""
    }

    function accountOptionsForProvider(providerID) {
        var key = providerKey(providerID)
        return accountOptions[key] || []
    }

    function accountErrorForProvider(providerID) {
        var key = providerKey(providerID)
        return accountErrors[key] ? String(accountErrors[key]) : ""
    }

    function accountLoadingForProvider(providerID) {
        return accountLoading[providerKey(providerID)] === true
    }

    function setAccountOptions(providerID, options) {
        var next = copyObject(accountOptions)
        next[providerKey(providerID)] = options || []
        accountOptions = next
    }

    function setAccountError(providerID, message) {
        var next = copyObject(accountErrors)
        var key = providerKey(providerID)
        if (message && String(message).trim().length > 0) {
            next[key] = String(message).trim()
        } else {
            delete next[key]
        }
        accountErrors = next
    }

    function setAccountLoading(providerID, value) {
        var next = copyObject(accountLoading)
        var key = providerKey(providerID)
        if (value) {
            next[key] = true
        } else {
            delete next[key]
        }
        accountLoading = next
    }

    function accountLabel(item) {
        if (!item) {
            return ""
        }
        if (item.account && item.account.length > 0) {
            return item.account
        }
        if (item.organization && item.organization.length > 0) {
            return item.organization
        }
        if (item.loginMethod && item.loginMethod.length > 0) {
            return item.loginMethod
        }
        return ""
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
        var key = providerKey(providerID)
        var label = String(accountLabel || "")
        var next = copyObject(selectedAccounts)
        if (label.length > 0) {
            next[key] = label
        } else {
            delete next[key]
        }
        selectedAccounts = next

        var options = accountOptionsForProvider(key)
        for (var i = 0; i < options.length; i++) {
            if (root.accountLabel(options[i]) === label) {
                replaceProviderSnapshot(key, options[i])
                return
            }
        }
        Qt.callLater(refreshNow)
    }

    function replaceProviderSnapshot(providerID, snapshot) {
        var key = providerKey(providerID)
        var nextProviders = []
        for (var i = 0; i < providers.length; i++) {
            nextProviders.push(providers[i].provider === key ? snapshot : providers[i])
        }
        providers = nextProviders
    }

    function normalizeProvider(item) {
        var usage = item.usage || ({})
        var pace = item.pace || ({})
        var rows = []
        var providerID = providerKey(item.provider || "unknown")

        var primaryRow = addWindow(rows, rateWindowLabel(providerID, "primary"), usage.primary, pace.primary, true, "primary")
        addWindow(rows, rateWindowLabel(providerID, "secondary"), usage.secondary, pace.secondary, true, "secondary")
        addWindow(rows, rateWindowLabel(providerID, "tertiary"), usage.tertiary, null, true, "tertiary")

        var extras = usage.extraRateWindows || []
        for (var i = 0; i < extras.length; i++) {
            var extra = extras[i]
            if (extra && extra.window) {
                addWindow(rows, extra.title || extra.id || i18n("Extra"), extra.window, null, extra.usageKnown !== false, "extra")
            }
        }

        var identity = usage.identity || ({})
        var error = item.error || null
        var status = item.status || null
        var severity = statusSeverity(status)
        var credits = item.credits || null
        var placeholder = providerPlaceholder(providerID, rows, usage, item, error)
        var displayName = item.displayName || item.title || providerDisplayNames[providerID] || ""

        return {
            provider: providerID,
            title: providerTitle(providerID, displayName),
            source: item.source || "",
            version: item.version || "",
            account: item.account || identity.accountEmail || usage.accountEmail || "",
            organization: identity.accountOrganization || usage.accountOrganization || "",
            loginMethod: identity.loginMethod || usage.loginMethod || "",
            rows: rows,
            primaryRow: primaryRow,
            providerCost: providerCostSection(providerID, usage.providerCost),
            resetCredits: resetCreditsSection(providerID, usage.codexResetCredits),
            tokenCost: tokenCosts[providerID] || null,
            planText: planText(providerID, usage, item),
            dashboardUrl: providerDashboardUrl(providerID),
            statusUrl: safeStatusUrl(providerID, status && status.url ? status.url : ""),
            changelogUrl: providerChangelogUrl(providerID),
            credits: credits && credits.remaining !== null && credits.remaining !== undefined && isFinite(Number(credits.remaining))
                ? Number(credits.remaining)
                : null,
            status: status ? statusText(status) : "",
            statusSeverity: severity,
            hasIncident: severity.length > 0,
            error: error && error.message ? error.message : "",
            placeholder: placeholder,
            updatedAt: usage.updatedAt || (credits ? credits.updatedAt : "")
        }
    }

    function providerPlaceholder(providerID, rows, usage, item, error) {
        if (rows && rows.length > 0) {
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

    function addWindow(rows, label, window, pace, usageKnown, lane) {
        if (!window) {
            return null
        }

        var known = usageKnown !== false
        var used = Number(window.usedPercent)
        var hasPercent = known && isFinite(used)
        var paceValue = pace && isFinite(Number(pace.expectedUsedPercent))
            ? clamp(Number(pace.expectedUsedPercent), 0, 100)
            : -1
        var row = {
            lane: lane || "",
            label: label,
            hasPercent: hasPercent,
            usedPercent: hasPercent ? clamp(used, 0, 100) : 0,
            leftPercent: hasPercent ? clamp(100 - used, 0, 100) : 0,
            pacePercent: paceValue,
            paceOnTop: !pace || pace.willLastToReset !== false,
            reset: resetText(window, resetTimesShowAbsolute),
            pace: pace && pace.summary ? pace.summary : ""
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

        if (!cost) {
            return null
        }

        var used = Number(cost.used)
        var limit = Number(cost.limit)
        var currency = cost.currencyCode || "USD"
        var period = cost.period || i18n("This month")
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
            line: i18n("%1 available", Math.round(count))
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

    function statusSeverity(status) {
        if (!status) {
            return ""
        }
        var indicator = String(status.indicator || "").toLowerCase()
        switch (indicator) {
        case "minor":
        case "maintenance":
        case "major":
        case "critical":
        case "unknown":
            return indicator
        default:
            return ""
        }
    }

    function statusBadgeColor(severity) {
        switch (String(severity || "")) {
        case "critical":
        case "major":
            return Kirigami.Theme.negativeTextColor
        case "minor":
            return Qt.rgba(245 / 255, 158 / 255, 11 / 255, 1)
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
        var warning = usageBarsShowUsed ? 80 : 20
        var critical = usageBarsShowUsed ? 95 : 5
        return [
            { percent: warning, severity: "minor" },
            { percent: critical, severity: "major" }
        ]
    }

    function resetNotificationMemo() {
        notificationMemo = ({})
        notificationsPrimed = false
        Qt.callLater(processNotifications)
    }

    function primeNotifications() {
        var nextMemo = ({})
        for (var i = 0; i < providers.length; i++) {
            var item = providers[i]
            if (!item) {
                continue
            }
            if (notifyStatusIncidents) {
                var statusValue = notificationStatusValue(item)
                if (statusValue.length > 0) {
                    nextMemo["status:" + item.provider] = statusValue
                }
            }
            if (notifyQuotaWarnings) {
                var rows = item.rows || []
                for (var j = 0; j < rows.length; j++) {
                    var level = quotaNotificationLevel(rows[j])
                    if (level.length > 0) {
                        nextMemo[quotaNotificationKey(item.provider, rows[j], j)] = level
                    }
                }
            }
            if (notifyLimitResets) {
                // Arm rows that already sit at warning-level usage so a later
                // reset fires, but never fire on this first observation.
                var resetRows = item.rows || []
                for (var k = 0; k < resetRows.length; k++) {
                    var resetRow = resetRows[k]
                    if (resetRow && resetRow.hasPercent
                        && Number(resetRow.usedPercent) >= limitResetArmThreshold) {
                        nextMemo[limitResetNotificationKey(item.provider, resetRow, k)] = "1"
                    }
                }
            }
        }
        notificationMemo = nextMemo
        notificationsPrimed = true
    }

    function processNotifications() {
        if (!enableNotifications || providers.length === 0) {
            return
        }
        if (!notificationsPrimed) {
            primeNotifications()
            return
        }

        var nextMemo = ({})
        for (var i = 0; i < providers.length; i++) {
            var item = providers[i]
            if (!item) {
                continue
            }

            if (notifyStatusIncidents) {
                processStatusNotification(item, nextMemo)
            }
            if (notifyQuotaWarnings) {
                processQuotaNotifications(item, nextMemo)
            }
            if (notifyLimitResets) {
                processLimitResetNotifications(item, nextMemo)
            }
        }
        notificationMemo = nextMemo
    }

    function processStatusNotification(item, nextMemo) {
        var key = "status:" + item.provider
        var value = notificationStatusValue(item)
        var previousValue = String(notificationMemo[key] || "")
        if (value.length > 0) {
            var previousSeverity = previousValue.length > 0 ? previousValue.split("|")[0] : ""
            var worsened = notificationRank(item.statusSeverity) > notificationRank(previousSeverity)
            if (previousValue.length === 0 || worsened || previousValue !== value) {
                sendPlasmaNotification(
                    i18n("%1 status issue", item.title),
                    item.status,
                    notificationUrgency(item.statusSeverity))
            }
            nextMemo[key] = value
        } else {
            delete nextMemo[key]
        }
    }

    function processQuotaNotifications(item, nextMemo) {
        var rows = item.rows || []
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            var key = quotaNotificationKey(item.provider, row, i)
            var level = quotaNotificationLevel(row)
            var previousLevel = String(notificationMemo[key] || "")
            if (level.length > 0 && notificationRank(level) > notificationRank(previousLevel)) {
                var body = i18n("%1 is %2% used", row.label, Math.round(row.usedPercent))
                if (row.reset && row.reset.length > 0) {
                    body += ". " + i18n("Resets %1", row.reset)
                }
                sendPlasmaNotification(
                    level === "major" ? i18n("%1 quota critical", item.title) : i18n("%1 quota warning", item.title),
                    body,
                    notificationUrgency(level))
            }
            if (level.length > 0) {
                nextMemo[key] = level
            } else {
                delete nextMemo[key]
            }
        }
    }

    // Usage at or above this percent arms a row for reset detection; once armed,
    // dropping to or below the floor fires a single "limit reset" notification.
    // Mirrors the macOS weekly-limit reset detector, scoped to limits the user
    // was actually near so routine short-window resets stay quiet.
    readonly property int limitResetArmThreshold: 80
    readonly property int limitResetFloor: 5

    function processLimitResetNotifications(item, nextMemo) {
        var rows = item.rows || []
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            if (!row || !row.hasPercent) {
                continue
            }
            var used = Number(row.usedPercent)
            if (!isFinite(used)) {
                continue
            }
            var key = limitResetNotificationKey(item.provider, row, i)
            var wasArmed = notificationMemo[key] === "1"
            if (wasArmed && used <= limitResetFloor) {
                sendPlasmaNotification(
                    i18n("%1 limit reset", item.title),
                    i18n("%1 is back to %2% used", row.label, Math.round(used)),
                    "low")
            } else if (used >= limitResetArmThreshold || (wasArmed && used > limitResetFloor)) {
                nextMemo[key] = "1"
            }
        }
    }

    function limitResetNotificationKey(providerID, row, index) {
        var lane = row && row.lane ? row.lane : ""
        var label = row && row.label ? row.label : ""
        return "reset:" + providerID + ":" + lane + ":" + label + ":" + index
    }

    function notificationStatusValue(item) {
        if (!item || !item.hasIncident || !item.statusSeverity || !item.status) {
            return ""
        }
        return item.statusSeverity + "|" + item.status
    }

    function quotaNotificationKey(providerID, row, index) {
        var lane = row && row.lane ? row.lane : ""
        var label = row && row.label ? row.label : ""
        return "quota:" + providerID + ":" + lane + ":" + label + ":" + index
    }

    function quotaNotificationLevel(row) {
        if (!row || !row.hasPercent) {
            return ""
        }
        var used = Number(row.usedPercent)
        if (!isFinite(used)) {
            return ""
        }
        if (used >= 95) {
            return "major"
        }
        if (used >= 80) {
            return "minor"
        }
        return ""
    }

    function notificationRank(severity) {
        switch (String(severity || "")) {
        case "critical":
            return 5
        case "major":
            return 4
        case "minor":
            return 3
        case "maintenance":
            return 2
        case "unknown":
            return 1
        default:
            return 0
        }
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
        notificationSource.connectSource(command)
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
        var key = String(value || "codex").toLowerCase()
        var aliases = {
            "abacusai": "abacus",
            "agy": "antigravity",
            "alibaba-coding-plan": "alibaba",
            "alibaba-token-plan": "alibabatokenplan",
            "aws-bedrock": "bedrock",
            "droid": "factory",
            "gemini-cli": "gemini",
            "groqcloud": "groq",
            "kimi-k2": "kimik2",
            "vertex": "vertexai"
        }
        return aliases[key] || key
    }

    function providerCliArgument(value) {
        switch (providerKey(value)) {
        case "abacus":
            return "abacusai"
        case "alibaba":
            return "alibaba-coding-plan"
        case "alibabatokenplan":
            return "alibaba-token-plan"
        case "azureopenai":
            return "azure-openai"
        case "bedrock":
            return "bedrock"
        case "groq":
            return "groqcloud"
        default:
            return providerKey(value)
        }
    }

    function providerTitle(value, displayName) {
        var key = providerKey(value)
        var preferred = String(displayName || "").trim()
        if (preferred.length > 0) {
            return preferred
        }

        var names = {
            "aws-bedrock": "AWS Bedrock",
            "abacus": "Abacus AI",
            "abacusai": "Abacus AI",
            "alibaba-coding-plan": "Alibaba Coding",
            "alibaba-token-plan": "Alibaba Token",
            "alibaba": "Alibaba",
            "alibabatokenplan": "Alibaba Token Plan",
            "azureopenai": "Azure OpenAI",
            "bedrock": "AWS Bedrock",
            "antigravity": "Antigravity",
            "augment": "Augment",
            "chutes": "Chutes",
            "claude": "Claude",
            "codebuff": "Codebuff",
            "commandcode": "Command Code",
            "codex": "Codex",
            "copilot": "Copilot",
            "crof": "Crof",
            "cursor": "Cursor",
            "deepgram": "Deepgram",
            "deepseek": "DeepSeek",
            "devin": "Devin",
            "doubao": "Doubao",
            "factory": "Droid",
            "gemini": "Gemini",
            "grok": "Grok",
            "groq": "Groq",
            "groqcloud": "GroqCloud",
            "jetbrains": "JetBrains AI",
            "kilo": "Kilo",
            "kimi-k2": "Kimi K2 (unofficial)",
            "kimik2": "Kimi K2 (unofficial)",
            "kiro": "Kiro",
            "litellm": "LiteLLM",
            "llmproxy": "LLM Proxy",
            "manus": "Manus",
            "mistral": "Mistral",
            "mimo": "Xiaomi MiMo",
            "moonshot": "Moonshot / Kimi API",
            "ollama": "Ollama",
            "openai": "OpenAI",
            "opencode": "OpenCode",
            "opencodego": "OpenCode Go",
            "openrouter": "OpenRouter",
            "perplexity": "Perplexity",
            "synthetic": "Synthetic",
            "t3chat": "T3 Chat",
            "venice": "Venice",
            "vertexai": "Vertex AI",
            "warp": "Warp",
            "windsurf": "Windsurf",
            "zai": "z.ai"
        }

        if (names[key]) {
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
        var key = providerKey(value)
        var aliases = {
            "aws-bedrock": "bedrock",
            "gemini": "gemini-white.png",
            "kimi-k2": "kimik2"
        }
        key = aliases[key] || key
        var fileName = key.indexOf(".") === -1 ? key + ".svg" : key
        return Qt.resolvedUrl("../icons/providers/" + fileName)
    }

    function providerIconIsMask(value) {
        return true
    }

    function providerColor(value) {
        switch (providerKey(value)) {
        case "abacus":
            return Qt.rgba(56 / 255, 189 / 255, 248 / 255, 1)
        case "alibaba":
        case "alibabatokenplan":
            return Qt.rgba(1, 106 / 255, 0, 1)
        case "amp":
            return Qt.rgba(220 / 255, 38 / 255, 38 / 255, 1)
        case "codex":
            return Qt.rgba(73 / 255, 163 / 255, 176 / 255, 1)
        case "openai":
            return Qt.rgba(15 / 255, 130 / 255, 110 / 255, 1)
        case "claude":
            return Qt.rgba(204 / 255, 124 / 255, 94 / 255, 1)
        case "gemini":
            return Qt.rgba(171 / 255, 135 / 255, 234 / 255, 1)
        case "antigravity":
            return Qt.rgba(96 / 255, 186 / 255, 126 / 255, 1)
        case "cursor":
            return Qt.rgba(0, 191 / 255, 165 / 255, 1)
        case "copilot":
            return Qt.rgba(168 / 255, 85 / 255, 247 / 255, 1)
        case "bedrock":
            return Qt.rgba(1, 0.6, 0, 1)
        case "codebuff":
            return Qt.rgba(68 / 255, 1, 0, 1)
        case "commandcode":
            return Qt.rgba(0, 0, 0, 1)
        case "crof":
            return Qt.rgba(46 / 255, 171 / 255, 148 / 255, 1)
        case "deepgram":
            return Qt.rgba(100 / 255, 103 / 255, 242 / 255, 1)
        case "deepseek":
            return Qt.rgba(82 / 255, 125 / 255, 240 / 255, 1)
        case "devin":
            return Qt.rgba(70 / 255, 180 / 255, 130 / 255, 1)
        case "doubao":
            return Qt.rgba(51 / 255, 112 / 255, 1, 1)
        case "elevenlabs":
            return Qt.rgba(235 / 255, 235 / 255, 230 / 255, 1)
        case "factory":
            return Qt.rgba(1, 107 / 255, 53 / 255, 1)
        case "grok":
            return Qt.rgba(16 / 255, 163 / 255, 127 / 255, 1)
        case "groq":
            return Qt.rgba(245 / 255, 104 / 255, 68 / 255, 1)
        case "jetbrains":
            return Qt.rgba(1, 51 / 255, 153 / 255, 1)
        case "kilo":
            return Qt.rgba(242 / 255, 112 / 255, 39 / 255, 1)
        case "kimi":
        case "minimax":
            return Qt.rgba(254 / 255, 96 / 255, 60 / 255, 1)
        case "kimik2":
            return Qt.rgba(76 / 255, 0, 1, 1)
        case "kiro":
            return Qt.rgba(1, 153 / 255, 0, 1)
        case "litellm":
            return Qt.rgba(76 / 255, 137 / 255, 240 / 255, 1)
        case "llmproxy":
            return Qt.rgba(36 / 255, 180 / 255, 126 / 255, 1)
        case "manus":
            return Qt.rgba(52 / 255, 50 / 255, 45 / 255, 1)
        case "mimo":
            return Qt.rgba(1, 105 / 255, 0, 1)
        case "mistral":
            return Qt.rgba(1, 80 / 255, 15 / 255, 1)
        case "moonshot":
            return Qt.rgba(32 / 255, 93 / 255, 235 / 255, 1)
        case "ollama":
            return Qt.rgba(136 / 255, 136 / 255, 136 / 255, 1)
        case "opencode":
        case "opencodego":
            return Qt.rgba(59 / 255, 130 / 255, 246 / 255, 1)
        case "openrouter":
            return Qt.rgba(100 / 255, 103 / 255, 242 / 255, 1)
        case "perplexity":
            return Qt.rgba(32 / 255, 178 / 255, 170 / 255, 1)
        case "poe":
            return Qt.rgba(38 / 255, 173 / 255, 97 / 255, 1)
        case "stepfun":
            return Qt.rgba(0.13, 0.59, 0.95, 1)
        case "t3chat":
            return Qt.rgba(245 / 255, 102 / 255, 71 / 255, 1)
        case "venice":
            return Qt.rgba(0.2, 0.6, 1, 1)
        case "vertexai":
            return Qt.rgba(66 / 255, 133 / 255, 244 / 255, 1)
        case "warp":
            return Qt.rgba(147 / 255, 139 / 255, 180 / 255, 1)
        case "windsurf":
            return Qt.rgba(52 / 255, 232 / 255, 187 / 255, 1)
        case "zed":
            return Qt.rgba(8 / 255, 78 / 255, 1, 1)
        case "zai":
            return Qt.rgba(232 / 255, 90 / 255, 106 / 255, 1)
        default:
            return Kirigami.Theme.highlightColor
        }
    }

    function providerDashboardUrl(providerID) {
        switch (providerKey(providerID)) {
        case "abacus":
            return "https://apps.abacus.ai/chatllm/admin/compute-points-usage"
        case "alibaba":
            return "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan"
        case "alibabatokenplan":
            return "https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan"
        case "amp":
            return "https://ampcode.com/settings#billing"
        case "augment":
            return "https://app.augmentcode.com/account/subscription"
        case "azureopenai":
            return "https://ai.azure.com"
        case "bedrock":
            return "https://console.aws.amazon.com/bedrock"
        case "chutes":
            return "https://chutes.ai"
        case "codebuff":
            return "https://www.codebuff.com/usage"
        case "commandcode":
            return "https://commandcode.ai/studio"
        case "codex":
            return "https://chatgpt.com/codex/settings/usage"
        case "claude":
            return "https://claude.ai/settings/usage"
        case "copilot":
            return "https://github.com/settings/copilot"
        case "cursor":
            return "https://cursor.com/dashboard?tab=usage"
        case "deepgram":
            return "https://console.deepgram.com/project/"
        case "deepseek":
            return "https://platform.deepseek.com/usage"
        case "devin":
            return "https://app.devin.ai"
        case "doubao":
            return "https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&advancedActiveKey=subscribe"
        case "elevenlabs":
            return "https://elevenlabs.io/app/developers/usage"
        case "factory":
            return "https://app.factory.ai/settings/billing"
        case "gemini":
            return "https://gemini.google.com"
        case "grok":
            return "https://grok.com/?_s=usage"
        case "groq":
            return "https://console.groq.com/dashboard/metrics"
        case "kilo":
            return "https://app.kilo.ai/usage"
        case "kimi":
            return "https://www.kimi.com/code/console"
        case "kiro":
            return "https://app.kiro.dev/account/usage"
        case "manus":
            return "https://manus.im"
        case "mimo":
            return "https://platform.xiaomimimo.com/#/console/balance"
        case "mistral":
            return "https://admin.mistral.ai/organization/usage"
        case "moonshot":
            return "https://platform.moonshot.ai/console/account"
        case "minimax":
            return "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3"
        case "ollama":
            return "https://ollama.com/settings"
        case "openai":
            return "https://platform.openai.com/usage"
        case "opencode":
        case "opencodego":
            return "https://opencode.ai"
        case "openrouter":
            return "https://openrouter.ai/settings/credits"
        case "perplexity":
            return "https://www.perplexity.ai/account/usage"
        case "poe":
            return "https://poe.com/api/keys"
        case "stepfun":
            return "https://platform.stepfun.com/plan-usage"
        case "t3chat":
            return "https://t3.chat/settings/customization"
        case "venice":
            return "https://venice.ai/settings/api"
        case "vertexai":
            return "https://console.cloud.google.com/vertex-ai"
        case "warp":
            return "https://docs.warp.dev/reference/cli/api-keys"
        case "windsurf":
            return "https://windsurf.com/subscription/usage"
        case "zai":
            return "https://z.ai/manage-apikey/coding-plan/personal/my-plan"
        default:
            return ""
        }
    }

    function providerDocsUrl(providerID) {
        var key = providerKey(providerID)
        var docs = {
            abacus: "abacus.md",
            alibaba: "alibaba-coding-plan.md",
            alibabatokenplan: "alibaba-token-plan.md",
            amp: "amp.md",
            antigravity: "antigravity.md",
            augment: "augment.md",
            bedrock: "bedrock.md",
            chutes: "chutes.md",
            claude: "claude.md",
            codebuff: "codebuff.md",
            commandcode: "command-code.md",
            codex: "codex.md",
            crof: "crof.md",
            cursor: "cursor.md",
            deepgram: "deepgram.md",
            deepseek: "deepseek.md",
            devin: "devin.md",
            doubao: "doubao.md",
            elevenlabs: "elevenlabs.md",
            factory: "factory.md",
            gemini: "gemini.md",
            grok: "grok.md",
            groq: "groqcloud.md",
            jetbrains: "jetbrains.md",
            kilo: "kilo.md",
            kimi: "kimi.md",
            kimik2: "kimi-k2.md",
            kiro: "kiro.md",
            litellm: "litellm.md",
            llmproxy: "llm-proxy.md",
            manus: "manus.md",
            mimo: "mimo.md",
            minimax: "minimax.md",
            moonshot: "moonshot.md",
            ollama: "ollama.md",
            opencode: "opencode.md",
            opencodego: "opencode.md",
            vertexai: "vertexai.md",
            warp: "warp.md",
            windsurf: "windsurf.md",
            zai: "zai.md"
        }
        if (!docs[key]) {
            return ""
        }
        return "https://github.com/steipete/CodexBar/blob/main/docs/" + docs[key]
    }

    function providerLoginUrl(providerID) {
        switch (providerKey(providerID)) {
        case "codex":
        case "openai":
            return "https://chatgpt.com"
        case "claude":
            return "https://claude.ai"
        case "cursor":
            return "https://cursor.com/settings"
        case "opencode":
        case "opencodego":
            return "https://opencode.ai/auth"
        case "gemini":
            return "https://aistudio.google.com"
        case "factory":
            return "https://app.factory.ai"
        case "copilot":
            return "https://github.com/login"
        case "devin":
            return "https://app.devin.ai/settings/usage"
        case "manus":
            return "https://manus.im"
        case "mimo":
            return "https://platform.xiaomimimo.com/api/v1/genLoginUrl?currentPath=%2F%23%2Fconsole%2Fbalance"
        case "perplexity":
            return "https://www.perplexity.ai"
        default:
            return ""
        }
    }

    function providerStatusUrl(providerID) {
        switch (providerKey(providerID)) {
        case "alibaba":
        case "alibabatokenplan":
            return "https://status.aliyun.com"
        case "antigravity":
        case "gemini":
            return "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history"
        case "azureopenai":
            return "https://azure.status.microsoft/en-us/status"
        case "bedrock":
        case "kiro":
            return "https://health.aws.amazon.com/health/status"
        case "codex":
        case "openai":
            return "https://status.openai.com/"
        case "claude":
            return "https://status.claude.com/"
        case "copilot":
            return "https://www.githubstatus.com/"
        case "cursor":
            return "https://status.cursor.com"
        case "deepgram":
            return "https://status.deepgram.com"
        case "deepseek":
            return "https://status.deepseek.com"
        case "elevenlabs":
            return "https://status.elevenlabs.io"
        case "factory":
            return "https://status.factory.ai"
        case "grok":
            return "https://status.x.ai"
        case "groq":
            return "https://status.groq.com"
        case "openrouter":
            return "https://status.openrouter.ai/"
        case "perplexity":
            return "https://status.perplexity.com/"
        case "vertexai":
            return "https://status.cloud.google.com"
        default:
            return ""
        }
    }

    function httpsUrlHost(url) {
        var match = String(url || "").trim().match(/^https:\/\/([^\/?#]+)/i)
        return match ? match[1].toLowerCase() : ""
    }

    function safeStatusUrl(providerID, url) {
        var fallback = providerStatusUrl(providerID)
        var fallbackHost = httpsUrlHost(fallback)
        var candidate = String(url || "").trim()
        var candidateHost = httpsUrlHost(candidate)
        if (fallbackHost.length === 0) {
            return ""
        }
        if (candidateHost.length === 0) {
            return fallback
        }
        return candidateHost === fallbackHost ? candidate : fallback
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

        rows.push({ title: i18n("Refresh"), icon: "view-refresh", action: "refresh", enabled: true })
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

    function copyObject(item) {
        var copy = ({})
        for (var key in item) {
            if (!hasOwnKey(item, key) || isUnsafeObjectKey(key)) {
                continue
            }
            copy[key] = item[key]
        }
        return copy
    }

    function hasText(value) {
        return String(value || "").trim().length > 0
    }

    function hasAdditionalSections(item) {
        return item && (item.credits !== null || item.resetCredits || item.providerCost || item.tokenCost) ? true : false
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

    function amountString(value, currency) {
        if (currency === "Quota") {
            return Math.round(value).toString()
        }
        var numeric = Number(value)
        var negative = numeric < 0
        var amount = Math.abs(numeric).toFixed(2)
        if (currency === "USD") {
            return negative ? "-$" + amount : "$" + amount
        }
        return (negative ? "-" : "") + currency + " " + amount
    }

    function costLine(label, cost, tokens, currency) {
        var costValue = isFinite(Number(cost)) ? amountString(Number(cost), currency) : "—"
        if (isFinite(Number(tokens))) {
            return i18n("%1: %2 · %3 tokens", label, costValue, tokenCountString(Number(tokens)))
        }
        return i18n("%1: %2", label, costValue)
    }

    function tokenCountString(tokens) {
        var value = Number(tokens)
        if (!isFinite(value)) {
            return "—"
        }
        var absValue = Math.abs(value)
        var sign = value < 0 ? "-" : ""
        if (absValue >= 1000000000) {
            return sign + scaledTokenCount(absValue / 1000000000) + "B"
        }
        if (absValue >= 1000000) {
            return sign + scaledTokenCount(absValue / 1000000) + "M"
        }
        if (absValue >= 1000) {
            return sign + scaledTokenCount(absValue / 1000) + "K"
        }
        return Math.round(value).toString()
    }

    function scaledTokenCount(value) {
        if (value >= 10) {
            return Number(value).toFixed(0)
        }
        var text = Number(value).toFixed(1)
        return text.replace(/\.0$/, "")
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
        if (key === "cursor" && !usageBarsShowUsed && primary && primary.leftPercent <= 0
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
        var result = []
        if (!providers) {
            return result
        }
        for (var i = 0; i < providers.length; i++) {
            if (!isOverviewErrorOnly(providers[i])) {
                result.push(providers[i])
            }
        }
        return result
    }

    function providerIndex(item) {
        if (!item || !providers) {
            return 0
        }
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].provider === item.provider) {
                return i
            }
        }
        return 0
    }

    function overviewPercent() {
        var items = overviewProviders()
        if (!items || items.length === 0) {
            return -1
        }

        var total = 0
        var count = 0
        for (var i = 0; i < items.length; i++) {
            var percent = switcherPercent(items[i])
            if (percent >= 0) {
                total += percent
                count++
            }
        }
        return count > 0 ? total / count : -1
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
        text = text
            .replace(/([A-Za-z])(\d)/g, "$1 $2")
            .replace(/(\d)([A-Za-z])/g, "$1 $2")
            .replace(/\)([A-Za-z])/g, ") $1")
            .replace(/(am|pm)\(/ig, "$1 (")
            .replace(/\s+/g, " ")
        if (/^resets\b/i.test(text)) {
            return text.replace(/^resets\s*/i, i18n("Resets "))
        }
        return i18n("Resets %1", text)
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
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

    function updateSelectedProvider() {
        if (!providers || providers.length === 0) {
            return
        }

        if (autoSelectProvider) {
            selectedProviderIndex = autoSelectedProviderIndex()
            selectionInitialized = true
            return
        }

        if (!selectionInitialized) {
            selectedProviderIndex = overviewAvailable ? -1 : 0
            selectionInitialized = true
            return
        }
        if (!overviewAvailable && selectedProviderIndex < 0) {
            selectedProviderIndex = 0
        }
        if (selectedProviderIndex >= providers.length) {
            selectedProviderIndex = Math.max(0, providers.length - 1)
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
                return i18n("%1 · %2", percentText, paceText)
            }
            return percentText.length > 0 ? percentText : paceText
        }
        if (mode === "resetTime") {
            return primaryResetText(item)
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

    function primaryResetText(item) {
        var row = switcherMetricRow(item)
        if (!row || !row.reset || row.reset.length === 0) {
            return ""
        }
        return resetLabel(row.reset)
    }

    function formatNumber(value) {
        if (Math.abs(value) >= 100) {
            return Math.round(value).toString()
        }
        return Number(value).toFixed(1)
    }

    Plasma5Support.DataSource {
        id: usageSource

        engine: "executable"
        interval: root.refreshIntervalSec > 0 ? root.refreshIntervalSec * 1000 : 0

        onNewData: function(sourceName, data) {
            var stdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stderrText = data && data["stderr"] ? data["stderr"] : ""

            if (sourceName === root.connectedCostCommandSource) {
                root.parseCostOutput(stdoutText, stderrText)
                return
            }

            if (sourceName === root.connectedProviderConfigCommandSource) {
                root.parseProviderConfigOutput(stdoutText, stderrText)
                return
            }

            if (root.pendingAccountCommands[sourceName]) {
                root.parseProviderAccountsOutput(sourceName, stdoutText, stderrText)
                return
            }

            if (root.pendingProviderCommands[sourceName]) {
                root.parseProviderFallbackOutput(sourceName, stdoutText, stderrText)
                return
            }

            if (sourceName === root.connectedCommandSource) {
                root.parseOutput(stdoutText, stderrText)
            }
        }
    }

    Plasma5Support.DataSource {
        id: providerConfigWatcher

        engine: "executable"
        interval: 2000

        onNewData: function(sourceName, data) {
            if (sourceName !== root.providerConfigWatchCommand) {
                return
            }
            var stdoutText = data && data["stdout"] ? data["stdout"] : ""
            root.handleProviderConfigWatch(stdoutText)
        }
    }

    Plasma5Support.DataSource {
        id: notificationSource

        engine: "executable"

        onNewData: function(sourceName, data) {
            notificationSource.disconnectSource(sourceName)
        }
    }

    compactRepresentation: Item {
        id: compactRoot

        readonly property bool hasProviderMeters: root.compactProviders().length > 0
        readonly property var incidentProvider: root.primaryIncidentProvider()
        readonly property string primaryText: root.compactText()
        readonly property bool showPrimaryIdentity: !hasProviderMeters || primaryText.length > 0
        readonly property int desiredWidth: Math.min(
            Kirigami.Units.gridUnit * 8.5,
            Math.max(Kirigami.Units.gridUnit * 4.8,
                compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2))

        Layout.minimumWidth: desiredWidth
        Layout.preferredWidth: desiredWidth
        Layout.maximumWidth: desiredWidth
        Layout.maximumHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2

        implicitWidth: desiredWidth
        implicitHeight: Layout.maximumHeight
        clip: true

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            id: compactRow

            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                readonly property string compactProvider: root.selectedCompactProvider() ? root.selectedCompactProvider().provider : "codex"

                visible: compactRoot.showPrimaryIdentity
                source: loading ? "view-refresh" : root.providerIconSource(compactProvider)
                isMask: !loading && root.providerIconIsMask(compactProvider)
                color: loading ? Kirigami.Theme.textColor : root.providerColor(compactProvider)
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            Rectangle {
                id: compactStatusBadge

                visible: compactRoot.incidentProvider !== null
                    && compactRoot.incidentProvider.hasIncident
                Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.5
                Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
                radius: width / 2
                color: compactRoot.incidentProvider
                    ? root.statusBadgeColor(compactRoot.incidentProvider.statusSeverity)
                    : "transparent"

                Controls.ToolTip.visible: compactStatusMouse.containsMouse
                Controls.ToolTip.text: compactRoot.incidentProvider
                    ? i18n("%1: %2", compactRoot.incidentProvider.title, compactRoot.incidentProvider.status)
                    : ""

                MouseArea {
                    id: compactStatusMouse

                    anchors.fill: parent
                    hoverEnabled: true
                }
            }

            PlasmaComponents.Label {
                visible: compactRoot.primaryText.length > 0
                text: compactRoot.primaryText
                elide: Text.ElideRight
                font.bold: true
                Layout.fillWidth: true
            }

            Repeater {
                model: root.compactProviders()

                delegate: Item {
                    id: compactMeter

                    readonly property real meter: root.switcherPercent(modelData)
                    readonly property color accent: root.providerColor(modelData.provider)

                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.15
                    Layout.preferredHeight: compactRow.height

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 0

                        Kirigami.Icon {
                            source: root.providerIconSource(modelData.provider)
                            isMask: root.providerIconIsMask(modelData.provider)
                            color: compactMeter.accent
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 9
                            Layout.preferredHeight: 9
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            radius: height / 2
                            color: root.withAlpha(compactMeter.accent, 0.28)
                            clip: true

                            Rectangle {
                                visible: compactMeter.meter >= 0
                                width: compactMeter.meter <= 0
                                    ? 0
                                    : Math.max(parent.height, parent.width * Math.max(0, Math.min(100, compactMeter.meter)) / 100)
                                height: parent.height
                                radius: parent.radius
                                color: compactMeter.accent
                            }
                        }
                    }
                }
            }
        }
    }

    fullRepresentation: Item {
        id: fullRoot

        implicitWidth: Kirigami.Units.gridUnit * 34
        implicitHeight: Kirigami.Units.gridUnit * 38
        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
        Layout.minimumHeight: Kirigami.Units.gridUnit * 28
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Flickable {
                id: providerTabsFlickable

                visible: providers.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: providerTabs.implicitWidth
                contentHeight: height
                interactive: contentWidth > width
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 3.1

                RowLayout {
                    id: providerTabs

                    height: providerTabsFlickable.height
                    spacing: 1

                    Rectangle {
                        id: overviewTab

                        readonly property bool selected: root.overviewSelected
                        readonly property real meter: root.overviewPercent()
                        readonly property color accent: Kirigami.Theme.highlightColor
                        readonly property color foreground: selected ? Kirigami.Theme.highlightedTextColor : root.withAlpha(Kirigami.Theme.textColor, 0.72)

                        visible: root.overviewAvailable
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5.7
                        Layout.preferredHeight: providerTabsFlickable.height
                        radius: Kirigami.Units.smallSpacing
                        color: selected
                            ? root.withAlpha(accent, 0.9)
                            : (overviewTabMouse.containsMouse ? root.withAlpha(Kirigami.Theme.textColor, 0.06) : "transparent")
                        border.width: selected ? 0 : 1
                        border.color: root.withAlpha(Kirigami.Theme.textColor, 0.14)

                        MouseArea {
                            id: overviewTabMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.selectedProviderIndex = -1
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: 2

                            Kirigami.Icon {
                                source: "view-grid-symbolic"
                                isMask: true
                                color: overviewTab.foreground
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                            }

                            PlasmaComponents.Label {
                                text: i18n("Overview")
                                horizontalAlignment: Text.AlignHCenter
                                font.weight: overviewTab.selected ? Font.DemiBold : Font.Normal
                                font.pixelSize: 11
                                color: overviewTab.foreground
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                visible: false
                                Layout.fillWidth: true
                                Layout.preferredHeight: 3
                                radius: height / 2
                                color: overviewTab.selected
                                    ? root.withAlpha(overviewTab.foreground, 0.28)
                                    : root.withAlpha(overviewTab.accent, 0.28)
                                clip: true

                                Rectangle {
                                    visible: overviewTab.meter >= 0
                                    width: overviewTab.meter <= 0
                                        ? 0
                                        : Math.max(parent.height, parent.width * Math.max(0, Math.min(100, overviewTab.meter)) / 100)
                                    height: parent.height
                                    radius: parent.radius
                                    color: overviewTab.selected ? overviewTab.foreground : overviewTab.accent
                                }
                            }
                        }
                    }

                    Repeater {
                        model: providers

                        delegate: Rectangle {
                            id: providerTab

                            readonly property bool selected: index === root.selectedProviderIndex
                            readonly property real meter: root.switcherPercent(modelData)
                            readonly property color accent: root.providerColor(modelData.provider)
                            readonly property color selectedAccent: Kirigami.Theme.highlightColor
                            readonly property color foreground: selected ? Kirigami.Theme.highlightedTextColor : root.withAlpha(Kirigami.Theme.textColor, 0.72)

                            Layout.preferredWidth: Math.min(
                                Kirigami.Units.gridUnit * 6.2,
                                Math.max(Kirigami.Units.gridUnit * 3.1, providerTabLabel.implicitWidth + Kirigami.Units.gridUnit))
                            Layout.preferredHeight: providerTabsFlickable.height
                            radius: Kirigami.Units.smallSpacing
                            color: selected
                                ? root.withAlpha(selectedAccent, 0.9)
                                : (providerTabMouse.containsMouse ? root.withAlpha(Kirigami.Theme.textColor, 0.06) : "transparent")
                            border.width: selected ? 0 : 1
                            border.color: root.withAlpha(Kirigami.Theme.textColor, 0.14)
                            opacity: modelData.error.length > 0 ? 0.62 : 1

                            MouseArea {
                                id: providerTabMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selectedProviderIndex = index
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: 2

                                Kirigami.Icon {
                                    source: root.providerIconSource(modelData.provider)
                                    isMask: root.providerIconIsMask(modelData.provider)
                                    color: providerTab.foreground
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                }

                                PlasmaComponents.Label {
                                    id: providerTabLabel

                                    text: modelData.title
                                    horizontalAlignment: Text.AlignHCenter
                                    font.weight: providerTab.selected ? Font.DemiBold : Font.Normal
                                    font.pixelSize: 11
                                    color: providerTab.foreground
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 2
                                    radius: height / 2
                                    opacity: providerTab.selected ? 0 : 1
                                    color: root.withAlpha(Kirigami.Theme.textColor, 0.16)
                                    clip: true

                                    Rectangle {
                                        visible: !providerTab.selected && providerTab.meter >= 0
                                        width: providerTab.meter <= 0
                                            ? 0
                                            : Math.max(parent.height, parent.width * Math.max(0, Math.min(100, providerTab.meter)) / 100)
                                        height: parent.height
                                        radius: parent.radius
                                        color: providerTab.accent
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: errorText.length > 0
                text: errorText
                color: Kirigami.Theme.negativeTextColor
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            PlasmaComponents.Label {
                visible: providers.length === 0 && errorText.length === 0
                text: loading ? i18n("Loading usage...") : i18n("No provider data.")
                opacity: 0.7
                Layout.fillWidth: true
            }

            ColumnLayout {
                visible: root.overviewSelected
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 2

                        Kirigami.Heading {
                            text: i18n("Overview")
                            level: 2
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            text: lastUpdatedText.length > 0
                                ? i18n("%1 · %2 providers", lastUpdatedText, root.overviewProviders().length)
                                : i18n("%1 providers", root.overviewProviders().length)
                            opacity: 0.62
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-refresh"
                        enabled: !loading
                        Accessible.name: i18n("Refresh")
                        onClicked: root.refreshNow()
                    }
                }

                Controls.ScrollView {
                    id: overviewScroll

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: overviewScroll.availableWidth
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            visible: root.overviewProviders().length === 0
                            text: i18n("No overview data available.")
                            opacity: 0.66
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.overviewProviders()

                            delegate: Rectangle {
                                id: overviewRow

                                readonly property color accent: root.providerColor(modelData.provider)
                                readonly property var usageRow: root.switcherMetricRow(modelData)
                                readonly property bool hasUsage: usageRow && usageRow.hasPercent
                                readonly property real shownPercent: hasUsage ? root.displayPercent(usageRow) : -1
                                readonly property string resetText: usageRow ? root.resetLabel(usageRow.reset) : ""
                                readonly property string detail: root.overviewDetailText(modelData)

                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * (detail.length > 0 ? 4.45 : 4.05)
                                radius: Kirigami.Units.smallSpacing
                                color: overviewRowMouse.containsMouse
                                    ? root.withAlpha(Kirigami.Theme.textColor, 0.06)
                                    : "transparent"
                                border.width: 1
                                border.color: root.withAlpha(accent, 0.22)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing

                                    Rectangle {
                                        Layout.preferredWidth: 3
                                        Layout.fillHeight: true
                                        radius: width / 2
                                        color: overviewRow.accent
                                    }

                                    Kirigami.Icon {
                                        source: root.providerIconSource(modelData.provider)
                                        isMask: root.providerIconIsMask(modelData.provider)
                                        color: overviewRow.accent
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.title
                                                font.weight: Font.DemiBold
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                visible: overviewRow.hasUsage
                                                text: i18n("%1% %2", Math.round(overviewRow.shownPercent), root.percentSuffix())
                                                opacity: 0.72
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            visible: overviewRow.detail.length > 0
                                            text: overviewRow.detail
                                            opacity: 0.62
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }

                                        Rectangle {
                                            visible: overviewRow.hasUsage
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 4
                                            radius: height / 2
                                            color: root.withAlpha(Kirigami.Theme.textColor, 0.14)
                                            clip: true

                                            Rectangle {
                                                width: overviewRow.shownPercent <= 0
                                                    ? 0
                                                    : Math.max(parent.height, parent.width * overviewRow.shownPercent / 100)
                                                height: parent.height
                                                radius: parent.radius
                                                color: overviewRow.accent
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            visible: overviewRow.resetText.length > 0
                                            text: overviewRow.resetText
                                            opacity: 0.56
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: overviewRowMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.selectedProviderIndex = root.providerIndex(modelData)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                visible: root.selectedProviderData !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Heading {
                                text: root.selectedProviderData ? root.selectedProviderData.title : ""
                                level: 2
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                id: providerStatusBadge

                                visible: root.selectedProviderData
                                    && root.selectedProviderData.hasIncident
                                Layout.preferredWidth: providerStatusBadgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25
                                radius: height / 2
                                color: root.selectedProviderData
                                    ? root.statusBadgeColor(root.selectedProviderData.statusSeverity)
                                    : "transparent"

                                PlasmaComponents.Label {
                                    id: providerStatusBadgeLabel

                                    anchors.centerIn: parent
                                    text: root.selectedProviderData
                                        ? root.statusBadgeText(root.selectedProviderData.statusSeverity)
                                        : ""
                                    color: root.contrastTextColor(providerStatusBadge.color)
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            PlasmaComponents.Label {
                                visible: root.selectedProviderData
                                    && root.selectedProviderData.account
                                    && root.selectedProviderData.account.length > 0
                                text: root.selectedProviderData ? root.selectedProviderData.account : ""
                                opacity: 0.62
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                            }

                            PlasmaComponents.ToolButton {
                                icon.name: "view-refresh"
                                enabled: !loading
                                Accessible.name: i18n("Refresh")
                                onClicked: root.refreshNow()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents.Label {
                                text: lastUpdatedText.length > 0 ? lastUpdatedText : i18n("Updated just now")
                                opacity: 0.62
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents.Label {
                                visible: root.selectedProviderData
                                    && root.selectedProviderData.planText
                                    && root.selectedProviderData.planText.length > 0
                                text: root.selectedProviderData ? root.selectedProviderData.planText : ""
                                opacity: 0.66
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: root.selectedProviderData
                        && (root.accountLoadingForProvider(root.selectedProviderData.provider)
                            || root.accountOptionsForProvider(root.selectedProviderData.provider).length > 0
                            || root.accountErrorForProvider(root.selectedProviderData.provider).length > 0)
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: i18n("Accounts")
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Controls.BusyIndicator {
                            running: root.selectedProviderData
                                && root.accountLoadingForProvider(root.selectedProviderData.provider)
                            visible: running
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "view-refresh"
                            enabled: root.selectedProviderData
                                && !root.accountLoadingForProvider(root.selectedProviderData.provider)
                            Accessible.name: i18n("Reload accounts")
                            onClicked: {
                                if (root.selectedProviderData) {
                                    root.loadAccounts(root.selectedProviderData.provider)
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: root.selectedProviderData
                                ? root.accountOptionsForProvider(root.selectedProviderData.provider)
                                : []

                            delegate: Controls.Button {
                                readonly property string label: root.accountLabel(modelData)
                                readonly property string subtitle: root.accountSubtitle(modelData)

                                checkable: true
                                checked: root.accountIsSelected(modelData, root.selectedProviderData)
                                text: subtitle.length > 0 ? label + " · " + subtitle : label
                                icon.name: "user-identity"
                                onClicked: root.selectAccount(modelData.provider, label)
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        visible: root.selectedProviderData
                            && root.accountErrorForProvider(root.selectedProviderData.provider).length > 0
                        text: root.selectedProviderData
                            ? root.accountErrorForProvider(root.selectedProviderData.provider)
                            : ""
                        color: Kirigami.Theme.negativeTextColor
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }

                PlasmaComponents.Label {
                    visible: root.selectedProviderData
                        && root.selectedProviderData.status
                        && root.selectedProviderData.status.length > 0
                    text: root.selectedProviderData ? root.selectedProviderData.status : ""
                    opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }

                PlasmaComponents.Label {
                    visible: root.selectedProviderData
                        && root.selectedProviderData.error
                        && root.selectedProviderData.error.length > 0
                    text: root.selectedProviderData ? root.selectedProviderData.error : ""
                    color: Kirigami.Theme.negativeTextColor
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }

                Controls.ScrollView {
                    id: providerScroll

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: providerScroll.availableWidth
                        spacing: Kirigami.Units.largeSpacing

                        PlasmaComponents.Label {
                            visible: root.providerPlaceholderText(root.selectedProviderData).length > 0
                            text: root.providerPlaceholderText(root.selectedProviderData)
                            opacity: 0.66
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.selectedProviderData ? root.selectedProviderData.rows : []

                            delegate: ColumnLayout {
                                readonly property color accent: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")
                                readonly property real shownPercent: root.displayPercent(modelData)
                                readonly property real markerPercent: root.paceMarkerPercent(modelData)

                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing / 1.5

                                PlasmaComponents.Label {
                                    text: modelData.label
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    id: usageBar

                                    visible: modelData.hasPercent
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    radius: height / 2
                                    color: root.withAlpha(Kirigami.Theme.textColor, 0.14)
                                    clip: true

                                    Rectangle {
                                        width: shownPercent <= 0
                                            ? 0
                                            : Math.max(parent.height, parent.width * shownPercent / 100)
                                        height: parent.height
                                        radius: parent.radius
                                        color: accent
                                    }

                                    Rectangle {
                                        visible: markerPercent > 0 && markerPercent < 100
                                        x: Math.max(0, Math.min(parent.width - width, parent.width * markerPercent / 100 - width / 2))
                                        y: 1
                                        width: 2
                                        height: parent.height - 2
                                        radius: width / 2
                                        color: modelData.paceOnTop
                                            ? root.withAlpha(Kirigami.Theme.positiveTextColor, 0.9)
                                            : root.withAlpha(Kirigami.Theme.negativeTextColor, 0.9)
                                    }

                                    Repeater {
                                        id: quotaWarningMarkerRepeater

                                        model: root.quotaWarningMarkers(modelData)

                                        delegate: Rectangle {
                                            readonly property real markerPercent: Number(modelData.percent) || 0

                                            visible: markerPercent > 0 && markerPercent < 100
                                            x: Math.max(0, Math.min(usageBar.width - width, usageBar.width * markerPercent / 100 - width / 2))
                                            y: 0
                                            width: 1
                                            height: usageBar.height
                                            radius: width / 2
                                            color: root.statusBadgeColor(modelData.severity)
                                            opacity: 0.72
                                        }
                                    }
                                }

                                RowLayout {
                                    visible: modelData.hasPercent || root.resetLabel(modelData.reset).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        visible: modelData.hasPercent
                                        text: i18n("%1% %2", Math.round(shownPercent), root.percentSuffix())
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    PlasmaComponents.Label {
                                        visible: root.resetLabel(modelData.reset).length > 0
                                        text: root.resetLabel(modelData.reset)
                                        opacity: 0.66
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                                    }
                                }

                                PlasmaComponents.Label {
                                    visible: modelData.pace.length > 0
                                    text: modelData.pace
                                    opacity: 0.66
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Kirigami.Separator {
                            visible: root.hasAdditionalSections(root.selectedProviderData)
                            Layout.fillWidth: true
                        }

                        ColumnLayout {
                            visible: root.selectedProviderData && root.selectedProviderData.credits !== null
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 1.5

                            Kirigami.Heading {
                                text: i18n("Credits")
                                level: 4
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: height / 2
                                color: root.withAlpha(Kirigami.Theme.textColor, 0.14)
                                clip: true

                                Rectangle {
                                    width: root.selectedProviderData && root.selectedProviderData.credits > 0
                                        ? Math.max(parent.height, parent.width * Math.min(root.selectedProviderData.credits, 1000) / 1000)
                                        : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: i18n("Remaining: %1", root.selectedProviderData ? root.formatNumber(root.selectedProviderData.credits) : "")
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        ColumnLayout {
                            id: resetCreditsSection

                            readonly property var resetCredits: root.selectedProviderData ? root.selectedProviderData.resetCredits : null

                            visible: resetCreditsSection.resetCredits ? true : false
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 1.5

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }

                            Kirigami.Heading {
                                text: resetCreditsSection.resetCredits ? resetCreditsSection.resetCredits.title : ""
                                level: 4
                                Layout.fillWidth: true
                            }

                            PlasmaComponents.Label {
                                text: resetCreditsSection.resetCredits ? resetCreditsSection.resetCredits.line : ""
                                opacity: 0.7
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            id: providerCostSection

                            readonly property var providerCost: root.selectedProviderData ? root.selectedProviderData.providerCost : null
                            readonly property color accent: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")

                            visible: providerCostSection.providerCost ? true : false
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 1.5

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }

                            Kirigami.Heading {
                                text: providerCostSection.providerCost ? providerCostSection.providerCost.title : ""
                                level: 4
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                visible: providerCostSection.providerCost && providerCostSection.providerCost.percentUsed >= 0 ? true : false
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: height / 2
                                color: root.withAlpha(Kirigami.Theme.textColor, 0.14)
                                clip: true

                                Rectangle {
                                    width: providerCostSection.providerCost && providerCostSection.providerCost.percentUsed > 0
                                        ? Math.max(parent.height, parent.width * providerCostSection.providerCost.percentUsed / 100)
                                        : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: providerCostSection.accent
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: providerCostSection.providerCost ? providerCostSection.providerCost.spendLine : ""
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    visible: providerCostSection.providerCost && providerCostSection.providerCost.percentLine.length > 0 ? true : false
                                    text: providerCostSection.providerCost ? providerCostSection.providerCost.percentLine : ""
                                    opacity: 0.66
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            PlasmaComponents.Label {
                                visible: providerCostSection.providerCost && providerCostSection.providerCost.personalSpendLine.length > 0 ? true : false
                                text: providerCostSection.providerCost ? providerCostSection.providerCost.personalSpendLine : ""
                                opacity: 0.66
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            id: tokenCostSection

                            readonly property var tokenCost: root.selectedProviderData ? root.selectedProviderData.tokenCost : null

                            visible: tokenCostSection.tokenCost ? true : false
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 1.5

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }

                            Kirigami.Heading {
                                text: i18n("Cost")
                                level: 4
                                Layout.fillWidth: true
                            }

                            PlasmaComponents.Label {
                                text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.sessionLine : ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents.Label {
                                text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.monthLine : ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Canvas {
                                id: costSparkline

                                property var points: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.daily : []
                                readonly property real maxValue: root.costSparklineMax(points)
                                readonly property color accent: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")

                                visible: points.length > 1 && maxValue > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 4

                                onPointsChanged: requestPaint()
                                onMaxValueChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    if (!points || points.length < 2 || maxValue <= 0 || width <= 0 || height <= 0) {
                                        return
                                    }

                                    var gap = Math.max(1, Math.floor(width / 180))
                                    var barWidth = Math.max(2, (width - gap * (points.length - 1)) / points.length)
                                    var baseline = height - 1

                                    ctx.fillStyle = root.canvasColor(Kirigami.Theme.textColor, 0.22)
                                    ctx.fillRect(0, baseline, width, 1)

                                    ctx.fillStyle = root.canvasColor(costSparkline.accent, 0.9)
                                    for (var i = 0; i < points.length; i++) {
                                        var value = Math.max(0, Number(points[i].cost) || 0)
                                        var barHeight = Math.max(1, (height - 3) * value / maxValue)
                                        var x = i * (barWidth + gap)
                                        ctx.fillRect(x, baseline - barHeight, barWidth, barHeight)
                                    }
                                }
                            }

                            RowLayout {
                                readonly property var daily: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.daily : null
                                visible: daily && daily.length > 1
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: daily ? root.costSparklineSummary(daily) : ""
                                    opacity: 0.62
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    text: daily
                                        ? i18np("%1 day", "%1 days", daily.length)
                                        : ""
                                    opacity: 0.62
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            ColumnLayout {
                                id: costHistoryChartSection

                                readonly property var rows: root.costHistoryRows(tokenCostSection.tokenCost)
                                readonly property string peakLine: tokenCostSection.tokenCost ? root.costPeakLine(tokenCostSection.tokenCost.daily) : ""
                                readonly property string averageLine: tokenCostSection.tokenCost ? root.costAverageDailyLine(tokenCostSection.tokenCost.daily) : ""
                                readonly property color accent: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")

                                visible: rows.length > 1
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing / 2

                                PlasmaComponents.Label {
                                    text: i18n("Cost history")
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    visible: costHistoryChartSection.peakLine.length > 0
                                        || costHistoryChartSection.averageLine.length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: costHistoryChartSection.peakLine
                                        opacity: 0.66
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    PlasmaComponents.Label {
                                        text: costHistoryChartSection.averageLine
                                        opacity: 0.66
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }

                                Repeater {
                                    model: root.costHistoryRows(tokenCostSection.tokenCost)

                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        PlasmaComponents.Label {
                                            text: modelData.label
                                            opacity: 0.66
                                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            id: costHistoryBarTrack

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            radius: height / 2
                                            color: root.withAlpha(Kirigami.Theme.textColor, 0.12)
                                            clip: true

                                            Rectangle {
                                                width: parent.width * Math.max(0, Math.min(100, modelData.percent)) / 100
                                                height: parent.height
                                                radius: parent.radius
                                                color: modelData.isPeak
                                                    ? root.withAlpha(costHistoryChartSection.accent, 1)
                                                    : root.withAlpha(costHistoryChartSection.accent, 0.72)
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            text: modelData.value
                                            opacity: modelData.isPeak ? 0.9 : 0.7
                                            font.weight: modelData.isPeak ? Font.DemiBold : Font.Normal
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                id: costDrillDownSection

                                visible: tokenCostSection.tokenCost
                                    && (root.costBreakdownRows(tokenCostSection.tokenCost).length > 0
                                        || root.costModelRows(tokenCostSection.tokenCost).length > 0
                                        || root.costDailyRows(tokenCostSection.tokenCost).length > 0)
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: i18n("Cost drill-down")
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    visible: tokenCostSection.tokenCost && root.costPerMillionLine(tokenCostSection.tokenCost).length > 0
                                    text: tokenCostSection.tokenCost ? root.costPerMillionLine(tokenCostSection.tokenCost) : ""
                                    opacity: 0.7
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                ColumnLayout {
                                    visible: root.costBreakdownRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    Repeater {
                                        model: root.costBreakdownRows(tokenCostSection.tokenCost)

                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.label
                                                opacity: 0.66
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.value
                                                opacity: 0.78
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                Kirigami.Separator {
                                    visible: root.costModelRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                }

                                ColumnLayout {
                                    visible: root.costModelRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlasmaComponents.Label {
                                        text: i18n("Models")
                                        opacity: 0.66
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Repeater {
                                        model: root.costModelRows(tokenCostSection.tokenCost)

                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.label
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.value
                                                opacity: 0.7
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                Kirigami.Separator {
                                    visible: root.costDailyRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                }

                                ColumnLayout {
                                    visible: root.costDailyRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlasmaComponents.Label {
                                        text: i18n("Recent days")
                                        opacity: 0.66
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Repeater {
                                        model: root.costDailyRows(tokenCostSection.tokenCost)

                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.label
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.value
                                                opacity: 0.7
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                visible: tokenCostSection.tokenCost && tokenCostSection.tokenCost.hintLine.length > 0 ? true : false
                                text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.hintLine : ""
                                opacity: 0.62
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        ColumnLayout {
                            visible: root.selectedProviderData !== null
                            Layout.fillWidth: true
                            spacing: 0

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: root.selectedProviderData ? root.actionRows(root.selectedProviderData) : []

                                delegate: Controls.ItemDelegate {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    icon.name: modelData.icon
                                    enabled: modelData.enabled
                                    onClicked: root.performAction(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
