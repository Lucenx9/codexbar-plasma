import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "components" as Components
import "CommandLedger.js" as CommandLedger
import "Guards.js" as Guards
import "ProviderIdentity.js" as ProviderIdentity
import "SafeText.js" as SafeText
import "ThemeContrast.js" as ThemeContrast
import "config/ProviderConfigProtocol.js" as ProviderConfigProtocol
import "config/ProviderDescriptor.js" as ProviderDescriptor

KCM.SimpleKCM {
    id: page

    // Read the configured command path so this page can call the same CLI the
    // widget uses. The provider list/toggles below persist immediately through
    // `codexbar config enable/disable`, independent of the KCM Apply cycle.
    property string cfg_commandPath
    property string cfg_commandPathDefault: "codexbar"
    property string cfg_provider
    property string cfg_providerDefault: ""
    property string cfg_source
    property string cfg_sourceDefault: ""
    property int cfg_refreshInterval
    property int cfg_refreshIntervalDefault: 300
    property bool cfg_includeStatus
    property bool cfg_includeStatusDefault: false
    property bool cfg_usageBarsShowUsed
    property bool cfg_usageBarsShowUsedDefault: false
    property bool cfg_showProviderChangelogs
    property bool cfg_showProviderChangelogsDefault: false
    property bool cfg_showProviderInPanel
    property bool cfg_showProviderInPanelDefault: true
    property bool cfg_showPercentInPanel
    property bool cfg_showPercentInPanelDefault: true
    property bool cfg_showMultiProviderInPanel
    property bool cfg_showMultiProviderInPanelDefault: false
    property bool cfg_showCreditsInPanel
    property bool cfg_showCreditsInPanelDefault: false
    property int cfg_providerConfigRevision
    property int cfg_providerConfigRevisionDefault: 0

    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()

    property var providers: []
    property string filterText: ""
    property bool loading: false
    property string errorText: ""
    property string statusText: ""
    // provider id -> true while an enable/disable command is in flight
    property var pending: ({})
    // provider id -> desired enabled value while the CLI command is in flight
    property var pendingDesired: ({})
    property var providerFieldPending: ({})
    // running command source -> descriptor { kind, provider, desiredEnabled, fieldID, actionID }
    property var commands: ({})
    property int commandRunSerial: 0
    readonly property int configCommandTimeoutMs: 60000
    readonly property int configSecretCommandTimeoutSeconds: 60
    readonly property int configSecretCommandKillAfterSeconds: 5
    // Mirrors the popup de-emphasis step in main.qml. 0.7 is the lowest value
    // where Kirigami.Theme.textColor still clears WCAG AA 4.5:1 on Breeze Light.
    readonly property real secondaryTextOpacity: 0.7
    property var providerDiagnostics: ({})
    property var providerDiagnosticErrors: ({})
    property var providerDiagnosticLoading: ({})
    property string selectedProviderID: ""

    readonly property var visibleProviders: filterProviders(providers, filterText)
    readonly property int enabledCount: countEnabled(providers)
    readonly property var selectedProvider: providerByID(selectedProviderID)

    Component.onCompleted: reload()
    onCfg_commandPathChanged: handleCommandPathChanged()

    function handleCommandPathChanged() {
        retireAllConfigCommands()
        providers = []
        providerDiagnostics = ({})
        providerDiagnosticErrors = ({})
        selectedProviderID = ""
        Qt.callLater(reload)
    }

    function reload(preserveMessages) {
        disconnectCommandsByKind("list")
        if (commandPath.length === 0) {
            errorText = i18n("Set the codexbar command path in the General page.")
            providers = []
            loading = false
            return
        }
        loading = true
        errorText = ""
        if (preserveMessages !== true) {
            statusText = ""
        }
        runProviderListCommand(true)
    }

    function boundedCliMessage(value) {
        return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
    }

    // Localizes the classified command result. The precedence decision itself
    // lives in ProviderConfigProtocol.commandOutcome; only the words live here.
    function providerCommandFailureText(result) {
        switch (result.outcome) {
        case "envelopeError":
        case "stderrError":
            return result.message
        case "statusError":
            return result.message.length > 0
                ? result.message
                : i18n("codexbar command failed.")
        case "timeout":
            return i18n("codexbar command timed out. Try again.")
        case "exitCodeError":
            return i18n("codexbar exited with code %1", Number(result.exitCode))
        default:
            return i18n("codexbar did not return provider data.")
        }
    }

    function runProviderListCommand(includeDescriptors) {
        var command = [
            shellQuote(commandPath),
            "config",
            "providers"
        ]
        if (includeDescriptors) {
            command.push("--descriptors")
        }
        command.push("--format")
        command.push("json")
        command.push("--json-only")
        runCommand(command.join(" "), {
            kind: "list",
            includeDescriptors: includeDescriptors === true,
            providerConfigRevision: providerConfigRevisionValue(),
            timeoutMs: configCommandTimeoutMs
        })
    }

    function setEnabled(providerID, desiredEnabled) {
        if (commandPath.length === 0 || isPending(providerID)) {
            return
        }
        errorText = ""
        statusText = ""
        markPending(providerID, true, desiredEnabled)
        var cliProviderID = providerCliArgument(providerID)
        var command = [
            shellQuote(commandPath),
            "config",
            desiredEnabled ? "enable" : "disable",
            "--provider",
            shellQuote(cliProviderID),
            "--format",
            "json",
            "--json-only"
        ].join(" ")
        runCommand(command, {
            kind: "toggle",
            provider: providerID,
            desiredEnabled: desiredEnabled,
            timeoutMs: configCommandTimeoutMs
        })
    }

    function setApiKey(providerID) {
        if (commandPath.length === 0 || isPending(providerID)) {
            return
        }
        errorText = ""
        statusText = ""
        markPending(providerID, true, true)
        var cliProviderID = providerCliArgument(providerID)

        var prompt = i18n("API key for %1", displayNameForProvider(providerID))
        var script = [
            "if ! command -v kdialog >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"kdialog is required to prompt for API keys.\"}}'; exit 1; fi",
            "if ! command -v timeout >/dev/null 2>&1 || ! timeout --kill-after=1s 1s true >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"GNU timeout is required to save API keys safely.\"}}'; exit 1; fi",
            "key=$(kdialog --password \"$1\" 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$key\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$key\" | timeout --kill-after=\"${5}s\" \"${4}s\" \"$2\" config set-api-key --provider \"$3\" --stdin --format json --json-only"
        ].join("; ")
        var command = [
            "sh", "-c", shellQuote(script), "_", shellQuote(prompt),
            shellQuote(commandPath), shellQuote(cliProviderID),
            shellQuote(configSecretCommandTimeoutSeconds),
            shellQuote(configSecretCommandKillAfterSeconds)
        ].join(" ")
        runCommand(command, { kind: "setApiKey", provider: providerID })
    }

    function loadProviderSettings(providerID) {
        if (commandPath.length === 0 || providerID.length === 0 || providerDiagnosticLoadingFor(providerID)) {
            return
        }
        setProviderDiagnosticLoading(providerID, true)
        setProviderDiagnosticError(providerID, "")
        var cliProviderID = providerCliArgument(providerID)
        var command = [
            shellQuote(commandPath),
            "diagnose --provider",
            shellQuote(cliProviderID),
            "--format json --redact"
        ].join(" ")
        runCommand(command, {
            kind: "diagnose",
            provider: providerID,
            timeoutMs: configCommandTimeoutMs
        })
    }

    function disconnectCommandsByKind(kind) {
        var sourceNames = CommandLedger.sourcesOfKind(commands, kind)
        var remaining = commands
        for (var i = 0; i < sourceNames.length; i++) {
            var sourceName = sourceNames[i]
            configSource.disconnectSource(sourceName)
            remaining = CommandLedger.closed(remaining, sourceName)
        }
        commands = remaining
    }

    function retireAllConfigCommands() {
        for (var sourceName in commands) {
            if (hasOwnKey(commands, sourceName)) {
                configSource.disconnectSource(sourceName)
            }
        }
        commands = ({})
        pending = ({})
        pendingDesired = ({})
        providerFieldPending = ({})
        providerDiagnosticLoading = ({})
        loading = false
    }

    function runCommand(command, descriptor) {
        commandRunSerial += 1
        var sourceName = CommandLedger.withRunNonce(command, commandRunSerial)
        var nextDescriptor = copyObject(descriptor)
        nextDescriptor.commandPathSignature = commandPath
        var timeoutMs = Number(nextDescriptor.timeoutMs)
        if (isFinite(timeoutMs) && timeoutMs > 0) {
            nextDescriptor.deadlineMs = Date.now() + timeoutMs
        }
        commands = CommandLedger.opened(commands, sourceName, nextDescriptor)
        configSource.connectSource(sourceName)
    }

    function hasTimedConfigCommands() {
        return CommandLedger.hasDeadlines(commands)
    }

    function expireConfigCommands(nowMs) {
        var expired = CommandLedger.expired(commands, nowMs)
        if (expired.length === 0) {
            return
        }
        var remaining = commands
        for (var i = 0; i < expired.length; i++) {
            var sourceName = expired[i].sourceName
            configSource.disconnectSource(sourceName)
            remaining = CommandLedger.closed(remaining, sourceName)
        }
        commands = remaining
        for (var j = 0; j < expired.length; j++) {
            var descriptor = expired[j].descriptor
            handleConfigCommandTimeout(descriptor)
        }
    }

    function handleConfigCommandTimeout(descriptor) {
        if (descriptor.kind === "list") {
            loading = false
            errorText = i18n("Loading providers timed out. Try again.")
        } else if (descriptor.kind === "diagnose") {
            setProviderDiagnosticLoading(descriptor.provider, false)
            setProviderDiagnosticError(descriptor.provider, i18n("Loading provider diagnostics timed out. Try again."))
        } else if (descriptor.kind === "toggle") {
            markPending(descriptor.provider, false)
            errorText = i18n("%1 command timed out. Try again.", displayNameForProvider(descriptor.provider))
        } else if (descriptor.kind === "descriptorField" || descriptor.kind === "descriptorAction") {
            var fieldID = descriptor.kind === "descriptorField" ? descriptor.fieldID : descriptor.actionID
            markFieldPending(descriptor.provider, fieldID, false)
            errorText = i18n("%1 command timed out. Try again.", displayNameForProvider(descriptor.provider))
        }
    }

    function handleData(sourceName, stdoutText, stderrText, exitCode) {
        var descriptor = CommandLedger.find(commands, sourceName)
        if (!descriptor) {
            return
        }
        commands = CommandLedger.closed(commands, sourceName)
        if (descriptor.commandPathSignature !== commandPath) {
            return
        }

        if (descriptor.kind === "list") {
            handleListResult(descriptor, stdoutText, stderrText)
        } else if (descriptor.kind === "toggle") {
            handleToggleResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "setApiKey") {
            handleSetApiKeyResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "descriptorField") {
            handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "descriptorAction") {
            handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "diagnose") {
            handleDiagnoseResult(descriptor, stdoutText, stderrText)
        }
    }

    function handleListResult(descriptor, stdoutText, stderrText) {
        if (!ProviderConfigProtocol.providerListResultIsCurrent(
                descriptor, providerConfigRevisionValue())) {
            reload(true)
            return
        }
        if (descriptor.includeDescriptors === true && shouldRetryProviderListWithoutDescriptors(stdoutText, stderrText)) {
            runProviderListCommand(false)
            return
        }
        loading = false
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            providers = []
            errorText = stderrText.trim().length > 0
                ? boundedCliMessage(stderrText)
                : i18n("codexbar did not return provider data.")
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            providers = []
            errorText = i18n("Could not parse codexbar provider JSON: %1", error.message)
            return
        }

        var parseError = ProviderConfigProtocol.commandError(payload)
        if (parseError.length > 0) {
            providers = []
            errorText = parseError
            return
        }

        var next = ProviderConfigProtocol.normalizeProviderList(payload, function(identifier) {
            return page.providerTitle(identifier)
        })
        providers = next
        if (!providerByID(selectedProviderID)) {
            selectedProviderID = firstSelectableProvider(next)
        }
        errorText = ""
    }

    function shouldRetryProviderListWithoutDescriptors(stdoutText, stderrText) {
        return descriptorListUnsupportedMessage(stdoutText, stderrText).length > 0
    }

    function descriptorListUnsupportedMessage(stdoutText, stderrText) {
        return ProviderConfigProtocol.descriptorUnsupportedMessage(stdoutText, stderrText)
    }

    function handleToggleResult(descriptor, stdoutText, stderrText, exitCode) {
        var trimmed = stdoutText.trim()
        var payload
        if (trimmed.length > 0) {
            try {
                payload = JSON.parse(trimmed)
            } catch (error) {
                markPending(descriptor.provider, false)
                errorText = i18n("Could not parse codexbar response: %1", error.message)
                return
            }
        }

        var result = ProviderConfigProtocol.commandOutcome(payload, stderrText, exitCode)
        if (result.outcome !== "success") {
            markPending(descriptor.provider, false)
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider),
                providerCommandFailureText(result))
            return
        }

        // Trust the enabled value the CLI reports back; fall back to desired.
        var newEnabled = descriptor.desiredEnabled
        if (payload && !Array.isArray(payload) && payload.enabled !== undefined) {
            newEnabled = payload.enabled === true
        }
        updateProviderEnabled(descriptor.provider, newEnabled)
        markPending(descriptor.provider, false)
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 saved", displayNameForProvider(descriptor.provider))
    }

    function handleSetApiKeyResult(descriptor, stdoutText, stderrText, exitCode) {
        markPending(descriptor.provider, false)

        var trimmed = stdoutText.trim()
        var payload
        if (trimmed.length > 0) {
            try {
                payload = JSON.parse(trimmed)
            } catch (error) {
                errorText = i18n("Could not parse codexbar response: %1", error.message)
                return
            }
        }

        var result = ProviderConfigProtocol.commandOutcome(payload, stderrText, exitCode)
        if (result.outcome === "cancelled") {
            statusText = ""
            errorText = ""
            return
        }
        // Older CLI builds completed set-api-key with exit 0 and no JSON. Keep
        // that successful pair while requiring shaped data for every other
        // printed response.
        if (!ProviderConfigProtocol.setApiKeyOutcomeIsSuccess(result)) {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider),
                providerCommandFailureText(result))
            return
        }

        if (payload && !Array.isArray(payload) && payload.enabled !== undefined) {
            updateProviderEnabled(descriptor.provider, payload.enabled === true)
        } else {
            updateProviderEnabled(descriptor.provider, true)
        }
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 API key saved", displayNameForProvider(descriptor.provider))
    }

    function handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode) {
        markFieldPending(descriptor.provider, descriptor.fieldID, false)
        var payload = parseCommandPayload(stdoutText, stderrText, exitCode)
        if (payload.cancelled) {
            return
        }
        if (payload.errorMessage.length > 0) {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider), payload.errorMessage)
            return
        }

        if (payload.value && !Array.isArray(payload.value) && payload.value.enabled !== undefined) {
            updateProviderEnabled(descriptor.provider, payload.value.enabled === true)
        }
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 setting saved", displayNameForProvider(descriptor.provider))
        page.reload(true)
    }

    function handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode) {
        markFieldPending(descriptor.provider, descriptor.actionID, false)
        var payload = parseCommandPayload(stdoutText, stderrText, exitCode)
        if (payload.cancelled) {
            return
        }
        if (payload.errorMessage.length > 0) {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider), payload.errorMessage)
            return
        }

        if (payload.value && !Array.isArray(payload.value) && payload.value.url) {
            var url = String(payload.value.url).trim()
            var safeUrl = ProviderDescriptor.safeHttpsUrl(url)
            if (safeUrl.length > 0) {
                Qt.openUrlExternally(safeUrl)
            } else {
                errorText = i18n("%1 returned an unsupported URL.", displayNameForProvider(descriptor.provider))
                return
            }
        }
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 action completed", displayNameForProvider(descriptor.provider))
        page.reload(true)
    }

    function parseCommandPayload(stdoutText, stderrText, exitCode) {
        var trimmed = stdoutText.trim()
        var payload
        if (trimmed.length > 0) {
            try {
                payload = JSON.parse(trimmed)
            } catch (error) {
                return {
                    value: null,
                    cancelled: false,
                    errorMessage: i18n("Could not parse codexbar response: %1", error.message)
                }
            }
        }

        var result = ProviderConfigProtocol.commandOutcome(payload, stderrText, exitCode)
        if (result.outcome === "cancelled") {
            return { value: null, cancelled: true, errorMessage: "" }
        }
        if (result.outcome === "empty" || result.outcome === "invalidPayload") {
            return {
                value: null,
                cancelled: false,
                errorMessage: i18n("codexbar did not return command data.")
            }
        }
        if (result.outcome !== "success") {
            return {
                value: null,
                cancelled: false,
                errorMessage: providerCommandFailureText(result)
            }
        }
        return { value: payload, cancelled: false, errorMessage: "" }
    }

    function handleDiagnoseResult(descriptor, stdoutText, stderrText) {
        setProviderDiagnosticLoading(descriptor.provider, false)

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            setProviderDiagnosticError(
                descriptor.provider,
                stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("codexbar did not return diagnostics."))
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            setProviderDiagnosticError(descriptor.provider, i18n("Could not parse codexbar diagnostics: %1", error.message))
            return
        }

        var message = ProviderConfigProtocol.commandError(payload)
        if (message.length > 0) {
            setProviderDiagnosticError(descriptor.provider, message)
            return
        }

        setProviderDiagnostic(
            descriptor.provider,
            ProviderConfigProtocol.normalizeProviderDiagnostic(payload))
        setProviderDiagnosticError(descriptor.provider, "")
    }

    function firstSelectableProvider(list) {
        if (!list || list.length === 0) {
            return ""
        }
        for (var i = 0; i < list.length; i++) {
            if (list[i].enabled) {
                return list[i].provider
            }
        }
        return list[0].provider
    }

    function providerByID(providerID) {
        if (!providerID || providerID.length === 0) {
            return null
        }
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].provider === providerID) {
                return providers[i]
            }
        }
        return null
    }

    function providerDiagnosticFor(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && hasOwnKey(providerDiagnostics, key) ? providerDiagnostics[key] : null
    }

    function setProviderDiagnostic(providerID, diagnostic) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var next = copyObject(providerDiagnostics)
        next[key] = diagnostic
        providerDiagnostics = next
    }

    function providerDiagnosticErrorFor(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && hasOwnKey(providerDiagnosticErrors, key) ? providerDiagnosticErrors[key] : ""
    }

    function setProviderDiagnosticError(providerID, message) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var next = copyObject(providerDiagnosticErrors)
        var cleanMessage = boundedCliMessage(message)
        if (cleanMessage.length > 0) {
            next[key] = cleanMessage
        } else {
            delete next[key]
        }
        providerDiagnosticErrors = next
    }

    function providerDiagnosticLoadingFor(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && hasOwnKey(providerDiagnosticLoading, key) && providerDiagnosticLoading[key] === true
    }

    function setProviderDiagnosticLoading(providerID, value) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var next = copyObject(providerDiagnosticLoading)
        if (value) {
            next[key] = true
        } else {
            delete next[key]
        }
        providerDiagnosticLoading = next
    }


    function updateProviderEnabled(providerID, enabled) {
        var next = []
        for (var i = 0; i < providers.length; i++) {
            var item = copyObject(providers[i])
            if (item.provider === providerID) {
                item.enabled = enabled
            }
            next.push(item)
        }
        providers = next
    }

    function isPending(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && hasOwnKey(pending, key) && pending[key] === true
    }

    function visualEnabled(providerID, fallback) {
        var key = providerMapKey(providerID)
        if (key.length > 0 && hasOwnKey(pendingDesired, key)) {
            return pendingDesired[key] === true
        }
        return fallback === true
    }

    function markPending(providerID, value, desiredEnabled) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var next = copyObject(pending)
        var desired = copyObject(pendingDesired)
        if (value) {
            next[key] = true
            desired[key] = desiredEnabled === true
        } else {
            delete next[key]
            delete desired[key]
        }
        pending = next
        pendingDesired = desired
    }

    function filterProviders(list, filter) {
        var needle = String(filter || "").trim().toLowerCase()
        if (needle.length === 0) {
            return list
        }
        var result = []
        for (var i = 0; i < list.length; i++) {
            var item = list[i]
            if (String(item.displayName).toLowerCase().indexOf(needle) !== -1
                    || String(item.provider).toLowerCase().indexOf(needle) !== -1) {
                result.push(item)
            }
        }
        return result
    }

    function countEnabled(list) {
        var count = 0
        for (var i = 0; i < list.length; i++) {
            if (list[i].enabled) {
                count++
            }
        }
        return count
    }

    function copyObject(item) {
        return Guards.copyObject(item)
    }

    function hasOwnKey(item, key) {
        return Guards.hasOwnKey(item, key)
    }

    function isUnsafeObjectKey(key) {
        return Guards.isUnsafeObjectKey(key)
    }

    function providerMapKey(providerID) {
        var key = providerKey(providerID)
        return ProviderIdentity.providerMapKey(key)
    }

    function displayNameForProvider(providerID) {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].provider === providerID) {
                return providers[i].displayName
            }
        }
        return providerTitle(providerID)
    }

    function providerActionRows(item) {
        if (!item) {
            return []
        }

        var rows = []
        var actions = descriptorActionRows(item)
        for (var i = 0; i < actions.length; i++) {
            rows.push({
                title: actions[i].title,
                icon: descriptorActionIcon(actions[i]),
                action: "descriptor-action",
                descriptorAction: actions[i],
                enabled: !isFieldPending(item.provider, actions[i].id)
            })
        }
        if (supportsApiKeySetup(item.provider) && !descriptorHasField(item, "apiKey")) {
            rows.push({ title: i18n("Set API key..."), icon: "password-show-off", action: "set-api-key", enabled: !isPending(item.provider) })
        }
        var docs = providerDocsUrl(item.provider)
        if (docs.length > 0) {
            rows.push({ title: i18n("Docs"), icon: "help-contents", action: "docs", url: docs, enabled: true })
        }
        var dashboard = providerDashboardUrl(item.provider)
        if (dashboard.length > 0 && !descriptorHasAction(item, "openDashboard")) {
            rows.push({ title: i18n("Dashboard"), icon: "view-statistics", action: "dashboard", url: dashboard, enabled: true })
        }
        var login = providerLoginUrl(item.provider)
        if (login.length > 0) {
            rows.push({ title: item.enabled ? i18n("Account") : i18n("Login"), icon: "internet-services", action: "login", url: login, enabled: true })
        }
        return rows
    }

    function descriptorActionIcon(action) {
        if (!action) {
            return "run-build"
        }
        if (action.id === "openDashboard") {
            return "view-statistics"
        }
        if (action.id === "openDocs") {
            return "help-contents"
        }
        if (action.id === "openLogin") {
            return "internet-services"
        }
        return "run-build"
    }

    function providerSettingsRows(item) {
        if (!item) {
            return []
        }

        var diagnostic = providerDiagnosticFor(item.provider)
        var rows = []
        rows.push({ label: i18n("Provider id"), value: item.provider })
        rows.push({ label: i18n("State"), value: item.enabled ? i18n("Enabled") : i18n("Disabled") })
        rows.push({ label: i18n("Default"), value: item.defaultEnabled ? i18n("On by default") : i18n("Off by default") })
        rows.push({
            label: i18n("API key setup"),
            value: supportsApiKeySetup(item.provider) ? i18n("Supported") : i18n("Use provider login/source")
        })

        if (diagnostic) {
            appendSettingsRow(rows, i18n("Source"), diagnostic.source)
            appendSettingsRow(rows, i18n("Source mode"), diagnostic.sourceMode)
            appendSettingsRow(rows, i18n("Auth modes"), diagnostic.authModes)
            rows.push({ label: i18n("Auth configured"), value: diagnostic.authConfigured ? i18n("Yes") : i18n("No") })
            rows.push({ label: i18n("Fetch attempts"), value: String(diagnostic.fetchAttempts) })
            appendSettingsRow(rows, i18n("Settings keys"), diagnostic.settingsKeys)
        } else {
            rows.push({ label: i18n("Provider diagnostics"), value: i18n("Load redacted settings to inspect source/auth details") })
        }
        return rows
    }

    function descriptorFieldRows(item) {
        return item && item.descriptor && Array.isArray(item.descriptor.fields) ? item.descriptor.fields : []
    }

    function descriptorActionRows(item) {
        return item && item.descriptor && Array.isArray(item.descriptor.actions) ? item.descriptor.actions : []
    }

    function descriptorHasField(item, fieldID) {
        var fields = descriptorFieldRows(item)
        for (var i = 0; i < fields.length; i++) {
            if (fields[i].id === fieldID) {
                return true
            }
        }
        return false
    }

    function descriptorHasAction(item, actionID) {
        var actions = descriptorActionRows(item)
        for (var i = 0; i < actions.length; i++) {
            if (actions[i].id === actionID) {
                return true
            }
        }
        return false
    }

    function appendSettingsRow(rows, label, value) {
        if (value && String(value).length > 0) {
            rows.push({ label: label, value: String(value) })
        }
    }

    function providerCliCommandText(item) {
        if (!item) {
            return ""
        }

        var providerID = item.provider
        var cliProviderID = providerCliArgument(providerID)
        var lines = [
            shellQuote(commandPath) + " usage --provider " + shellQuote(cliProviderID) + " --format json --json-only",
            shellQuote(commandPath) + " diagnose --provider " + shellQuote(cliProviderID) + " --format json --redact",
            shellQuote(commandPath) + " config " + (item.enabled ? "disable" : "enable") + " --provider " + shellQuote(cliProviderID) + " --format json --json-only"
        ]
        if (supportsApiKeySetup(providerID)) {
            lines.push("printf '%s' \"$API_KEY\" | " + shellQuote(commandPath) + " config set-api-key --provider " + shellQuote(cliProviderID) + " --stdin --format json --json-only")
        }
        return lines.join("\n")
    }

    function performProviderAction(row) {
        if (!row || !selectedProvider) {
            return
        }
        if (row.action === "descriptor-action") {
            runDescriptorAction(selectedProvider.provider, row.descriptorAction)
            return
        }
        if (row.action === "set-api-key") {
            setApiKey(selectedProvider.provider)
            return
        }
        if (row.url && row.url.length > 0) {
            Qt.openUrlExternally(row.url)
        }
    }

    function writeDescriptorField(providerID, field, value) {
        if (!field || !field.writeCommand || field.writeCommand.length === 0 || isFieldPending(providerID, field.id)) {
            return
        }
        // Every value written here ends up inside a shell command line, and
        // /proc/<pid>/cmdline stays world-readable while the child runs. Piping
        // the value through `sh -c script _ "$secret"` does not fix that: the
        // secret still lands in the shell argv. Secrets must go through
        // promptDescriptorSecret, which reads the value inside the script and
        // never puts it in a command line at all.
        var plan = ProviderDescriptor.planFieldWrite(field, value, commandPath)
        if (!plan.ok) {
            errorText = plan.reason !== "secretRequiresPrompt"
                ? i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
                : i18n("%1 secrets must be set through the secure prompt.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        markFieldPending(providerID, field.id, true)
        runCommand(plan.commandLine, {
            kind: "descriptorField",
            provider: providerID,
            fieldID: field.id,
            timeoutMs: configCommandTimeoutMs
        })
    }

    function promptDescriptorSecret(providerID, field) {
        if (!field || !field.writeCommand || field.writeCommand.length === 0 || isFieldPending(providerID, field.id)) {
            return
        }
        var plan = ProviderDescriptor.planSecretPrompt(field, commandPath)
        if (!plan.ok) {
            errorText = i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        markFieldPending(providerID, field.id, true)
        var prompt = i18n("%1 for %2", field.title, displayNameForProvider(providerID))
        var boundedCommandLine = "timeout --kill-after="
            + shellQuote(configSecretCommandKillAfterSeconds + "s") + " "
            + shellQuote(configSecretCommandTimeoutSeconds + "s") + " "
            + plan.commandLine
        var script = [
            "if ! command -v kdialog >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"kdialog is required to prompt for secrets.\"}}'; exit 1; fi",
            "if ! command -v timeout >/dev/null 2>&1 || ! timeout --kill-after=1s 1s true >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"GNU timeout is required to save secrets safely.\"}}'; exit 1; fi",
            "value=$(kdialog --password \"$1\" 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$value\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$value\" | " + boundedCommandLine
        ].join("; ")
        var command = ["sh", "-c", shellQuote(script), "_", shellQuote(prompt)].join(" ")
        runCommand(command, { kind: "descriptorField", provider: providerID, fieldID: field.id })
    }

    function runDescriptorAction(providerID, action) {
        if (!action || !action.command || action.command.length === 0 || isFieldPending(providerID, action.id)) {
            return
        }
        var plan = ProviderDescriptor.planAction(action, commandPath)
        if (!plan.ok) {
            errorText = i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        markFieldPending(providerID, action.id, true)
        runCommand(plan.commandLine, {
            kind: "descriptorAction",
            provider: providerID,
            actionID: action.id,
            timeoutMs: configCommandTimeoutMs
        })
    }

    function optionIDAt(options, index) {
        if (!Array.isArray(options) || index < 0 || index >= options.length) {
            return ""
        }
        return options[index].id
    }

    function isFieldPending(providerID, fieldID) {
        var key = descriptorPendingKey(providerID, fieldID)
        return key.length > 0 && hasOwnKey(providerFieldPending, key) && providerFieldPending[key] === true
    }

    function markFieldPending(providerID, fieldID, value) {
        var key = descriptorPendingKey(providerID, fieldID)
        if (key.length === 0) {
            return
        }
        var next = copyObject(providerFieldPending)
        if (value) {
            next[key] = true
        } else {
            delete next[key]
        }
        providerFieldPending = next
    }

    function descriptorPendingKey(providerID, fieldID) {
        var provider = providerMapKey(providerID)
        var field = descriptorPendingFieldKey(fieldID)
        return provider.length > 0 && field.length > 0 ? provider + "::" + field : ""
    }

    function descriptorPendingFieldKey(fieldID) {
        var value = String(fieldID || "").trim()
        if (value.length === 0 || value.length > 128) {
            return ""
        }
        return JSON.stringify(value)
    }

    function supportsApiKeySetup(providerID) {
        switch (providerKey(providerID)) {
        case "abacus":
        case "alibaba":
        case "alibabatokenplan":
        case "amp":
        case "azureopenai":
        case "bedrock":
        case "chutes":
        case "codebuff":
        case "clawrouter":
        case "commandcode":
        case "copilot":
        case "crof":
        case "crossmodel":
        case "deepgram":
        case "deepseek":
        case "doubao":
        case "elevenlabs":
        case "grok":
        case "groq":
        case "ibmbob":
        case "kimi":
        case "kimik2":
        case "kilo":
        case "litellm":
        case "llmproxy":
        case "manus":
        case "mimo":
        case "minimax":
        case "mistral":
        case "moonshot":
        case "ollama":
        case "openai":
        case "openrouter":
        case "perplexity":
        case "poe":
        case "stepfun":
        case "venice":
        case "warp":
        case "windsurf":
        case "zai":
            return true
        default:
            return false
        }
    }

    function providerDocsUrl(providerID) {
        return ProviderIdentity.providerDocsUrl(providerID)
    }

    function providerDashboardUrl(providerID) {
        return ProviderIdentity.providerDashboardUrl(providerID)
    }

    function providerLoginUrl(providerID) {
        return ProviderIdentity.providerLoginUrl(providerID)
    }

    function providerConfigRevisionValue() {
        var current = Number(Plasmoid.configuration.providerConfigRevision || cfg_providerConfigRevision || 0)
        return isFinite(current) && current >= 0 ? Math.floor(current) : 0
    }

    function bumpProviderConfigRevision() {
        var current = providerConfigRevisionValue()
        var next = current >= 2147480000 ? 1 : current + 1
        cfg_providerConfigRevision = next
        Plasmoid.configuration.providerConfigRevision = next
    }

    function shellQuote(value) {
        return Guards.shellQuote(value)
    }

    // --- Provider visual identity (kept in sync with main.qml) ---

    function providerKey(value) {
        return ProviderIdentity.resolveProviderKey(value)
    }

    function providerCliArgument(value) {
        return ProviderIdentity.providerCliArgument(value)
    }

    function providerIconSource(value) {
        var fileName = ProviderIdentity.providerIconFileName(value)
        if (fileName.length === 0) {
            return "view-statistics"
        }
        return Qt.resolvedUrl("../icons/providers/" + fileName)
    }

    function providerColor(value) {
        var channels = ProviderIdentity.providerBrandColorChannels(value)
        if (channels.length !== 3) {
            return Kirigami.Theme.highlightColor
        }
        return Qt.rgba(channels[0], channels[1], channels[2], 1)
    }

    function providerReadableColor(value, background) {
        return ThemeContrast.readableAccentColor(
            providerColor(value),
            background || Kirigami.Theme.backgroundColor,
            Kirigami.Theme.textColor)
    }

    function providerTitle(value) {
        var key = providerKey(value)
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

    Timer {
        id: configCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: page.hasTimedConfigCommands()
        triggeredOnStart: false
        onTriggered: page.expireConfigCommands(Date.now())
    }

    Plasma5Support.DataSource {
        id: configSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var rawStdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stdoutText = SafeText.cliJsonText(rawStdoutText)
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            var exitCode = data && data["exit code"] !== undefined ? Number(data["exit code"]) : 0
            if (stdoutText === null) {
                stdoutText = ""
                stderrText = i18n("codexbar response exceeded the supported size.")
                exitCode = 1
            }
            disconnectSource(sourceName)
            page.handleData(sourceName, stdoutText, stderrText, exitCode)
        }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.SearchField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("Search providers...")
                onTextChanged: page.filterText = text
            }

            Controls.ToolButton {
                icon.name: "view-refresh"
                text: i18n("Reload")
                display: Controls.AbstractButton.IconOnly
                enabled: !page.loading
                onClicked: page.reload()

                Controls.ToolTip.text: i18n("Reload provider list")
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        Components.PlainInlineMessage {
            id: providerErrorMessage

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            type: Kirigami.MessageType.Error
            plainText: page.errorText
            visible: page.errorText.length > 0
            showCloseButton: true
            onVisibleChanged: {
                if (visible || page.errorText.length === 0) {
                    return
                }
                // Kirigami's close button hid the banner imperatively, severing
                // the visible binding; clear the text and reinstall the binding
                // so later errors still show up.
                page.errorText = ""
                visible = Qt.binding(function() { return page.errorText.length > 0 })
            }
        }

        Components.PlainInlineMessage {
            id: providerStatusMessage

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            type: Kirigami.MessageType.Positive
            plainText: page.statusText
            visible: page.statusText.length > 0
            showCloseButton: true
            onVisibleChanged: {
                if (visible || page.statusText.length === 0) {
                    return
                }
                page.statusText = ""
                visible = Qt.binding(function() { return page.statusText.length > 0 })
            }
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: page.selectedProvider !== null

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: page.selectedProvider ? page.providerIconSource(page.selectedProvider.provider) : ""
                    fallback: "view-statistics"
                    isMask: true
                    color: page.selectedProvider
                        ? page.providerReadableColor(
                            page.selectedProvider.provider,
                            Kirigami.Theme.backgroundColor)
                        : Kirigami.Theme.textColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Components.PlainControlsLabel {
                        text: page.selectedProvider ? page.selectedProvider.displayName : ""
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Components.PlainControlsLabel {
                        text: page.selectedProvider
                            ? (page.selectedProvider.enabled ? i18n("%1 - enabled", page.selectedProvider.provider) : i18n("%1 - disabled", page.selectedProvider.provider))
                            : ""
                        opacity: page.secondaryTextOpacity
                        font: Kirigami.Theme.smallFont
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: page.providerActionRows(page.selectedProvider).length > 0

                Repeater {
                    model: page.providerActionRows(page.selectedProvider)

                    delegate: Controls.Button {
                        required property var modelData

                        text: SafeText.plainTextAsMnemonicRichText(modelData.title)
                        Accessible.name: modelData.title
                        icon.name: modelData.icon
                        enabled: modelData.enabled
                        onClicked: page.performProviderAction(modelData)
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Components.PlainControlsLabel {
                        text: i18n("Provider settings")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Controls.BusyIndicator {
                        running: page.selectedProvider !== null
                            && page.providerDiagnosticLoadingFor(page.selectedProvider.provider)
                        visible: running
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    Controls.Button {
                        text: i18n("Load redacted settings")
                        icon.name: "view-refresh"
                        enabled: page.selectedProvider
                            && !page.providerDiagnosticLoadingFor(page.selectedProvider.provider)
                        onClicked: if (page.selectedProvider) page.loadProviderSettings(page.selectedProvider.provider)
                    }
                }

                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    text: i18n("Provider-specific controls come from the CodexBar CLI descriptor. This panel also shows redacted source/auth details and exact CLI commands.")
                    opacity: page.secondaryTextOpacity
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                }

                Components.PlainInlineMessage {
                    Layout.fillWidth: true
                    type: Kirigami.MessageType.Error
                    plainText: page.selectedProvider
                        ? page.providerDiagnosticErrorFor(page.selectedProvider.provider)
                        : ""
                    visible: plainText.length > 0
                    showCloseButton: true
                    onVisibleChanged: {
                        // Kirigami's close button hides the banner imperatively,
                        // severing the visible binding. Clear the stored error so
                        // the dismissal sticks, then reinstall the binding so the
                        // next diagnostic error still shows up.
                        if (!visible && plainText.length > 0 && page.selectedProvider) {
                            page.setProviderDiagnosticError(page.selectedProvider.provider, "")
                            visible = Qt.binding(function() { return plainText.length > 0 })
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: page.descriptorFieldRows(page.selectedProvider).length > 0

                    Components.PlainControlsLabel {
                        text: i18n("Provider descriptor fields")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Repeater {
                        model: page.descriptorFieldRows(page.selectedProvider)

                        delegate: ColumnLayout {
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: modelData.kind === "secret"

                                Components.PlainControlsLabel {
                                    text: modelData.title
                                    opacity: page.secondaryTextOpacity
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Components.PlainControlsLabel {
                                    text: modelData.redactedValue.length > 0 ? modelData.redactedValue : i18n("Not configured")
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Controls.Button {
                                    text: i18n("Set...")
                                    icon.name: "password-show-off"
                                    enabled: page.selectedProvider
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                    onClicked: if (page.selectedProvider) page.promptDescriptorSecret(page.selectedProvider.provider, modelData)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: modelData.kind === "text" || modelData.kind === "number"

                                Components.PlainControlsLabel {
                                    text: modelData.title
                                    opacity: page.secondaryTextOpacity
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Controls.TextField {
                                    id: descriptorTextField
                                    Layout.fillWidth: true
                                    text: modelData.valueText
                                    placeholderText: SafeText.plainTextAsRichText(modelData.description)
                                    Accessible.description: modelData.description
                                    inputMethodHints: modelData.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
                                    enabled: page.selectedProvider
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                }

                                Controls.Button {
                                    text: i18n("Save")
                                    icon.name: "document-save"
                                    enabled: page.selectedProvider
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                    onClicked: if (page.selectedProvider) page.writeDescriptorField(page.selectedProvider.provider, modelData, descriptorTextField.text)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: modelData.kind === "enum"

                                Components.PlainControlsLabel {
                                    text: modelData.title
                                    opacity: page.secondaryTextOpacity
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Components.PlainComboBox {
                                    id: descriptorEnumBox

                                    property bool restoreBindingAfterWrite: false
                                    readonly property bool descriptorWritePending: page.selectedProvider
                                        && page.isFieldPending(page.selectedProvider.provider, modelData.id)

                                    Layout.fillWidth: true
                                    model: modelData.options
                                    textRole: "title"
                                    valueRole: "id"
                                    currentIndex: modelData.selectedOptionIndex
                                    enabled: page.selectedProvider
                                        && modelData.options.length > 0
                                        && !descriptorWritePending
                                    onDescriptorWritePendingChanged: {
                                        if (descriptorWritePending || !restoreBindingAfterWrite) {
                                            return
                                        }
                                        restoreBindingAfterWrite = false
                                        currentIndex = Qt.binding(function() {
                                            return modelData.selectedOptionIndex
                                        })
                                    }
                                }

                                Controls.Button {
                                    id: descriptorEnumSaveButton

                                    text: i18n("Save")
                                    icon.name: "document-save"
                                    enabled: page.selectedProvider
                                        && descriptorEnumBox.currentIndex >= 0
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                    onClicked: {
                                        if (!page.selectedProvider) {
                                            return
                                        }
                                        page.writeDescriptorField(
                                            page.selectedProvider.provider,
                                            modelData,
                                            page.optionIDAt(modelData.options, descriptorEnumBox.currentIndex))
                                        // A rejected plan never enters the pending state,
                                        // so it keeps the user's choice available to retry.
                                        // A started write restores the binding only when its
                                        // result clears the pending state.
                                        descriptorEnumBox.restoreBindingAfterWrite =
                                            descriptorEnumBox.descriptorWritePending
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: modelData.kind === "boolean"

                                Components.PlainControlsLabel {
                                    text: modelData.title
                                    opacity: page.secondaryTextOpacity
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Components.PlainCheckBox {
                                    checked: modelData.value === true || String(modelData.value).toLowerCase() === "true"
                                    plainText: modelData.description
                                    Layout.fillWidth: true
                                    enabled: page.selectedProvider
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                    onClicked: {
                                        if (page.selectedProvider) {
                                            page.writeDescriptorField(page.selectedProvider.provider, modelData, checked ? "true" : "false")
                                        }
                                        // Restore the binding the click severed so the box reflects the
                                        // saved value (and reverts on a failed write).
                                        checked = Qt.binding(function() {
                                            return modelData.value === true || String(modelData.value).toLowerCase() === "true"
                                        })
                                    }
                                }
                            }

                            Components.PlainControlsLabel {
                                Layout.fillWidth: true
                                text: modelData.description
                                opacity: page.secondaryTextOpacity
                                font: Kirigami.Theme.smallFont
                                wrapMode: Text.WordWrap
                                visible: modelData.description.length > 0
                                    && modelData.kind !== "boolean"
                                    && modelData.kind !== "text"
                                    && modelData.kind !== "number"
                            }
                        }
                    }
                }

                Repeater {
                    model: page.providerSettingsRows(page.selectedProvider)

                    delegate: RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Components.PlainControlsLabel {
                            text: modelData.label
                            opacity: page.secondaryTextOpacity
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                            elide: Text.ElideRight
                        }

                        Components.PlainControlsLabel {
                            text: modelData.value
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                Controls.ToolButton {
                    id: providerCliCommandsToggle

                    text: i18n("CLI commands")
                    icon.name: checked ? "arrow-down" : "arrow-right"
                    display: Controls.AbstractButton.TextBesideIcon
                    checkable: true
                    checked: false
                    Layout.alignment: Qt.AlignLeft
                }

                Controls.ScrollView {
                    id: providerCliCommandsView

                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                    visible: providerCliCommandsToggle.checked

                    Controls.TextArea {
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.NoWrap
                        text: page.providerCliCommandText(page.selectedProvider)
                        font.family: "monospace"
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
            visible: page.loading && page.providers.length === 0

            Controls.BusyIndicator {
                anchors.centerIn: parent
                running: parent.visible
            }
        }

        Kirigami.Separator {
            id: providerListSeparator

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: page.providers.length > 0
        }

        RowLayout {
            id: providerListHeading

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: page.providers.length > 0

            Components.PlainControlsLabel {
                text: i18n("Providers")
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Components.PlainControlsLabel {
                text: i18np("%1 provider enabled", "%1 providers enabled", page.enabledCount)
                font: Kirigami.Theme.smallFont
                opacity: page.secondaryTextOpacity
                elide: Text.ElideRight
            }
        }

        Components.PlainPlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 2
            visible: !page.loading && page.providers.length === 0 && page.errorText.length === 0
            icon.name: "view-list-details"
            plainText: i18n("No providers reported")
            plainExplanation: i18n("codexbar did not return any providers.")
        }

        Components.PlainPlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 2
            visible: page.providers.length > 0 && page.visibleProviders.length === 0
            icon.name: "search"
            plainText: i18n("No matching providers")
            plainExplanation: i18n("No provider matches \"%1\".", page.filterText)
        }

        Repeater {
            model: page.visibleProviders

            delegate: Components.ProviderConfigRow {
                configPage: page
            }
        }
    }
}
