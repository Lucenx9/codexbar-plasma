import QtQuick
import QtQuick.Window
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
import "ProviderOrder.js" as ProviderOrder
import "SafeText.js" as SafeText
import "ThemeContrast.js" as ThemeContrast
import "config" as ProviderConfig
import "credential" as Credential
import "config/ProviderConfigProtocol.js" as ProviderConfigProtocol
import "config/ProviderDescriptor.js" as ProviderDescriptor
import "config/ProviderList.js" as ProviderList
import "config/ProviderOperations.js" as ProviderOperations
import "config/ProviderSource.js" as ProviderSource
import "config/ProviderCredentials.js" as ProviderCredentials
import "config/ProviderCapabilities.js" as ProviderCapabilities

KCM.SimpleKCM {
    id: page

    // Read the configured command path so this page can call the same CLI the
    // widget uses. The provider list/toggles below persist immediately through
    // `codexbar config enable/disable`, independent of the KCM Apply cycle.
    property string cfg_commandPath
    property string cfg_commandPathDefault: "codexbar"
    property string cfg_provider
    property string cfg_providerDefault: ""
    property string cfg_providerOrder
    property string cfg_providerOrderDefault: ""
    property string cfg_source
    property string cfg_sourceDefault: ""
    property int cfg_refreshInterval
    property int cfg_refreshIntervalDefault: 300
    property bool cfg_includeStatus
    property bool cfg_includeStatusDefault: false
    property bool cfg_usageBarsShowUsed
    property bool cfg_usageBarsShowUsedDefault: true
    property bool cfg_showProviderChangelogs
    property bool cfg_showProviderChangelogsDefault: false
    property bool cfg_showProviderInPanel
    property bool cfg_showProviderInPanelDefault: false
    property bool cfg_showPercentInPanel
    property bool cfg_showPercentInPanelDefault: false
    property bool cfg_showMultiProviderInPanel
    property bool cfg_showMultiProviderInPanelDefault: true
    property bool cfg_showCreditsInPanel
    property bool cfg_showCreditsInPanelDefault: false
    property int cfg_providerConfigRevision
    property int cfg_providerConfigRevisionDefault: 0

    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()

    property var providers: []
    property string filterText: ""
    readonly property string filterScope: ["all", "enabled", "disabled"][providerFilterBar.currentIndex] || "all"
    property bool loading: false
    // Survives dismissing the error banner, so an empty failed list keeps its
    // recovery placeholder instead of claiming the CLI reported no providers.
    property bool providerListFailed: false
    property string errorText: ""
    property string statusText: ""
    property bool providerDescriptorsUnavailable: false
    property bool fireworksSingleKeySetupSupported: false
    property bool sonioxApiKeySetupSupported: false
    property bool abliterationChatboxKeySetupSupported: false
    property bool munitoApiKeySetupSupported: false
    property bool commandCodeFalApiKeySetupSupported: false
    property bool providerSourceSetupSupported: false
    property string credentialCliVersion: ""
    readonly property url credentialScriptUrl: Qt.resolvedUrl("../../scripts/provider-auth.py")
    property var operationState: ProviderOperations.initialState()
    // running command source -> descriptor { kind, provider, desiredEnabled, fieldID, actionID }
    property var commands: ({})
    property int commandRunSerial: 0
    readonly property int configCommandTimeoutMs: 60000
    // Shell-side bound for provider diagnostics, as on the Diagnostics page:
    // 50s plus 5s kill grace stays below configCommandTimeoutMs, so a hung
    // fetch cannot outlive the dialog after the QML deadline retires it.
    readonly property int providerDiagnosticTimeoutSeconds: 50
    readonly property int providerDiagnosticKillAfterSeconds: 5
    readonly property int configSecretCommandTimeoutSeconds: 60
    readonly property int configSecretCommandKillAfterSeconds: 5
    // Bound kdialog itself because disconnecting its shell can orphan it.
    // Keep a long input window separate from the short CLI timeout.
    readonly property int configSecretPromptDialogTimeoutSeconds: 870
    readonly property int configSecretPromptDialogKillAfterSeconds: 5
    // A late submission still gets the full CLI timeout and kill grace.
    // Allow five seconds for startup and result delivery before disconnecting.
    readonly property int configSecretPromptTimeoutMs:
        (configSecretPromptDialogTimeoutSeconds + configSecretPromptDialogKillAfterSeconds
         + configSecretCommandTimeoutSeconds + configSecretCommandKillAfterSeconds) * 1000 + 5000
    // Mirrors the popup de-emphasis step in main.qml. 0.7 is the lowest value
    // where Kirigami.Theme.textColor still clears WCAG AA 4.5:1 on Breeze Light.
    readonly property real secondaryTextOpacity: 0.7
    property var providerDiagnostics: ({})
    property var providerDiagnosticErrors: ({})
    property string selectedProviderID: ""
    property var savedProviderSources: ({})
    property string providerSourceDraft: ""
    property bool providerSourcesFailed: false
    readonly property bool providerSourcesLoading: CommandLedger.hasKind(commands, "sources")
    readonly property string selectedProviderSavedSource: ProviderSource.savedMode(savedProviderSources, selectedProviderID)
    property var providerListFocus: null

    readonly property var visibleProviders: ProviderList.filteredProviders(providers, filterText, filterScope)
    readonly property var providerSettingsGroups: ProviderOrder.settingsGroups(
        visibleProviders, cfg_providerOrder)
    readonly property var visibleEnabledProviders: providerSettingsGroups.enabled
    readonly property var visibleDisabledProviders: providerSettingsGroups.disabled
    readonly property int enabledCount: ProviderList.filteredProviders(providers, "", "enabled").length
    readonly property var selectedProvider: providerByID(selectedProviderID)
    // Widget-owned URL rows sit in the header toolbar. Descriptor actions,
    // including open* ones, keep their plain-text button: their titles are
    // untrusted CLI text and the toolbar's button/menu paths render rich text.
    readonly property var selectedProviderActionRows: providerActionRows(selectedProvider)
    readonly property var selectedProviderLinkRows: selectedProviderActionRows.filter(function(row) { return providerLinkKind(row) !== "" })
    readonly property var selectedProviderCommandRows: selectedProviderActionRows.filter(function(row) { return providerLinkKind(row) === "" })
    readonly property var selectedProviderSourceModes: ProviderSource.availableModes(
        selectedProvider ? selectedProvider.authentication : null)

    // Qt.callLater coalesces this with the reload the cfg_commandPathChanged
    // handler queues when Plasma injects the stored command path during page
    // creation, so opening the page spawns one CLI list command, not two.
    Component.onCompleted: Qt.callLater(reload)
    onCfg_commandPathChanged: handleCommandPathChanged()
    onSelectedProviderIDChanged: {
        providerSourceDraft = ""
        syncProviderSourceSelection()
        cancelDeviceLogin()
    }
    onSelectedProviderSourceModesChanged: {
        if (selectedProviderSourceModes.indexOf(providerSourceDraft) < 0) providerSourceDraft = ""
        syncProviderSourceSelection()
    }
    onSelectedProviderSavedSourceChanged: {
        if (providerSourceDraft === selectedProviderSavedSource) providerSourceDraft = ""
        syncProviderSourceSelection()
    }
    Component.onDestruction: retireAllConfigCommands()

    function handleCommandPathChanged() {
        retireAllConfigCommands()
        providers = []
        providerDiagnostics = ({})
        providerDiagnosticErrors = ({})
        savedProviderSources = ({})
        providerSourceDraft = ""
        providerSourcesFailed = false
        selectedProviderID = ""
        providerDescriptorsUnavailable = false
        applyProviderCapabilities(ProviderCapabilities.versionCapabilities("", 1))
        credentialCliVersion = ""
        Qt.callLater(reload)
    }

    function reload(preserveMessages, retainedErrorText) {
        var decision = ProviderOperations.reloadRequested(operationState,
            hasCredentialWrite() || CommandLedger.hasKind(commands, "setSource"), preserveMessages, retainedErrorText)
        operationState = decision.state
        if (!decision.reload) {
            return
        }
        disconnectCommandsByKind("list")
        disconnectCommandsByKind("version")
        if (commandPath.length === 0) {
            errorText = i18n("Set the codexbar command path in Diagnostics.")
            providers = []
            providerListFailed = true
            loading = false
            return
        }
        loading = true
        errorText = decision.retainedErrorText
        if (!decision.preserveMessages) {
            statusText = ""
        }
        runProviderListCommand(true, errorText)
        runCliVersionCommand()
        runProviderSourcesCommand()
    }

    function syncProviderSourceSelection() {
        if (providerSourceBox) {
            providerSourceBox.currentIndex = selectedProviderSourceModes.indexOf(
                providerSourceDraft || selectedProviderSavedSource)
        }
    }

    function runProviderSourcesCommand() {
        disconnectCommandsByKind("sources")
        providerSourcesFailed = false
        runCommand([shellQuote(commandPath), "config dump --format json --json-only"].join(" "), {
            kind: "sources",
            providerConfigRevision: providerConfigRevisionValue(),
            timeoutMs: configCommandTimeoutMs
        })
    }

    function handleProviderSourcesResult(descriptor, stdoutText, stderrText, exitCode) {
        if (!ProviderConfigProtocol.providerListResultIsCurrent(descriptor, providerConfigRevisionValue())) {
            runProviderSourcesCommand()
            return
        }
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "command")
        var sources = result.outcome === "success" ? ProviderSource.savedSources(result.value) : null
        providerSourcesFailed = sources === null
        if (sources !== null) {
            savedProviderSources = sources
        }
        syncProviderSourceSelection()
    }

    function boundedCliMessage(value) {
        return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
    }

    // Localizes the classified command result. The precedence decision itself
    // lives in ProviderConfigProtocol.response; only the words live here.
    function providerCommandFailureText(result, context) {
        // A process without an exit status explains no more than missing data.
        if (result.outcome === "exitCodeError" && isFinite(result.exitCode)) {
            return i18n("codexbar exited with code %1", Number(result.exitCode))
        }
        switch (result.outcome) {
        case "tooLarge":
            return i18n("codexbar response exceeded the supported size.")
        case "invalidJson":
            if (context === "list") {
                return i18n("Could not parse codexbar provider JSON: %1", result.message)
            }
            if (context === "diagnostic") {
                return i18n("Could not parse codexbar diagnostics: %1", result.message)
            }
            return i18n("Could not parse codexbar response: %1", result.message)
        case "stderrError":
            return result.message
        case "envelopeError":
        case "statusError":
            return result.message.length > 0
                ? result.message
                : i18n("codexbar command failed.")
        case "timeout":
            return i18n("codexbar command timed out. Try again.")
        default:
            if (context === "diagnostic" && (result.outcome === "empty" || result.outcome === "invalidPayload")) {
                return i18n("codexbar did not return diagnostics.")
            }
            if (context === "command") {
                return i18n("codexbar did not return command data.")
            }
            return i18n("codexbar did not return provider data.")
        }
    }

    // retainedErrorText is an earlier write's error that a successful roster
    // refresh must leave visible instead of clearing.
    function runProviderListCommand(includeDescriptors, retainedErrorText) {
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
            retainedErrorText: retainedErrorText ? String(retainedErrorText) : "",
            providerConfigRevision: providerConfigRevisionValue(),
            timeoutMs: configCommandTimeoutMs
        })
    }

    function runCliVersionCommand() {
        runCommand([shellQuote(commandPath), "--version"].join(" "), {
            kind: "version",
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
        var item = providerByID(providerID)
        if (item && item.authentication && item.authentication.supportsConfigAPIKey !== true) {
            return
        }
        errorText = ""
        statusText = ""
        markPending(providerID, true, item ? item.enabled : false)
        var cliProviderID = providerCliArgument(providerID)

        var prompt = apiKeyPrompt(providerID)
        var script = [
            "if ! command -v kdialog >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"kdialog is required to prompt for API keys.\"}}'; exit 1; fi",
            "if ! command -v timeout >/dev/null 2>&1 || ! timeout --kill-after=1s 1s true >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"GNU timeout is required to save API keys safely.\"}}'; exit 1; fi",
            "key=$(timeout --kill-after=\"${7}s\" \"${6}s\" kdialog --password \"$1\" 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$key\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$key\" | timeout --kill-after=\"${5}s\" \"${4}s\" \"$2\" config set-api-key --provider \"$3\" --stdin --format json --json-only"
        ].join("; ")
        var command = [
            "sh", "-c", shellQuote(script), "_", shellQuote(prompt),
            shellQuote(commandPath), shellQuote(cliProviderID),
            shellQuote(configSecretCommandTimeoutSeconds),
            shellQuote(configSecretCommandKillAfterSeconds),
            shellQuote(configSecretPromptDialogTimeoutSeconds),
            shellQuote(configSecretPromptDialogKillAfterSeconds)
        ].join(" ")
        runCommand(command, {
            kind: "setApiKey",
            provider: providerID,
            timeoutMs: configSecretPromptTimeoutMs
        })
    }

    function hasCredentialWrite() {
        var sources = CommandLedger.sourcesOfKind(commands, "credential")
        for (var i = 0; i < sources.length; i++) {
            if (CommandLedger.find(commands, sources[i]).action !== "login") return true
        }
        return false
    }

    function credentialWriteAllowed(providerID) {
        return !loading && commandPath.length > 0 && providerByID(providerID)
            && !isPending(providerID) && !hasPendingFields(providerID)
            && !CommandLedger.hasKind(commands, "version")
    }

    function setCookie(providerID) {
        if (!credentialWriteAllowed(providerID)
                || !ProviderCredentials.supportsCookie(providerID, credentialCliVersion, providerByID(providerID).authentication)) return
        promptDescriptorSecret(providerID, {id: "cookieHeader", kind: "secret", title: i18n("Cookie header"),
            writeCommand: ["codexbar", "config", "set-cookie", "--provider", providerCliArgument(providerID), "--stdin"]})
    }

    function clearCredentials(providerID) {
        if (!credentialWriteAllowed(providerID) || !ProviderCredentials.supportsClear(credentialCliVersion)) return
        startCredentialCommand(providerID, "clear-credential")
    }

    function startDeviceLogin(providerID) {
        if (!credentialWriteAllowed(providerID) || !ProviderCredentials.supportsLogin(providerID, credentialCliVersion)) return
        startCredentialCommand(providerID, "login")
    }

    function startCredentialCommand(providerID, action) {
        var command = ProviderCredentials.helperCommand(credentialScriptUrl, commandPath, action, providerCliArgument(providerID))
        if (!command) return
        var requestID = ""
        if (action === "login") {
            requestID = Date.now().toString(16) + Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2)
            command += " --request " + shellQuote(requestID) + " --supervised --title " + shellQuote(i18n("Sign in to GitHub Copilot"))
                + " --message " + shellQuote(i18n("Open this address in your browser:\n%1\n\nEnter this code:\n%2\n\nThe code expires in %3 seconds. Press OK after entering it to continue waiting in settings. Use Cancel sign-in in settings to cancel.", "%1", "%2", "%3"))
        }
        retireProviderDiagnostic(providerID)
        errorText = ""
        statusText = ""
        markPending(providerID, true, providerByID(providerID).enabled)
        runCommand(command, {kind: "credential", action: action, provider: providerID, requestID: requestID,
            timeoutMs: action === "login" ? 970000 : configCommandTimeoutMs})
    }

    function deviceLoginActive() {
        var sources = CommandLedger.sourcesOfKind(commands, "credential")
        for (var i = 0; i < sources.length; i++) {
            if (CommandLedger.find(commands, sources[i]).action === "login") return true
        }
        return false
    }

    function cancelDeviceLogin() {
        var sources = CommandLedger.sourcesOfKind(commands, "credential")
        for (var i = 0; i < sources.length; i++) {
            var source = sources[i]
            var descriptor = CommandLedger.find(commands, source)
            if (descriptor.action !== "login") continue
            commands = CommandLedger.closed(commands, source)
            cancelCredentialRequest(descriptor)
            configSource.disconnectSource(source)
            markPending(descriptor.provider, false)
            statusText = i18n("Sign-in cancelled.")
        }
        runReloadDeferredBySourceWrite()
    }

    function cancelCredentialRequest(descriptor) {
        if (descriptor.kind !== "credential" || descriptor.action !== "login" || !descriptor.requestID) return
        var command = ProviderCredentials.helperCommand(credentialScriptUrl,
            descriptor.commandPathSignature, "cancel-login", "copilot")
            + " --request " + shellQuote(descriptor.requestID)
        return Credential.LoginCancellation.run(Guards.boundedShellCommand(command, 5, 1, true))
    }

    function handleCredentialResult(descriptor, stdoutText, exitCode) {
        markPending(descriptor.provider, false)
        var result = ProviderCredentials.result(stdoutText, exitCode, providerCliArgument(descriptor.provider), descriptor.action)
        if (result.status === "ok") {
            if (descriptor.action !== "clear-credential") {
                updateProviderEnabled(descriptor.provider, descriptor.action === "login" || result.enabled)
            }
            invalidateProviderDiagnostic(descriptor.provider)
            bumpProviderConfigRevision()
            errorText = ""
            statusText = descriptor.action === "login" ? i18n("Copilot sign-in completed.")
                : descriptor.action === "set-cookie" ? i18n("%1 cookie saved", displayNameForProvider(descriptor.provider))
                : i18n("%1 stored credentials cleared", displayNameForProvider(descriptor.provider))
            reload(true)
        } else if (result.status === "cancelled") {
            statusText = i18n("Operation cancelled.")
        } else {
            errorText = result.status === "expired" ? i18n("Sign-in expired. Try again.")
                : result.status === "conflict" ? i18n("CodexBar configuration changed during sign-in. Try again.")
                : result.status === "unavailable" ? i18n("Credential setup could not start. Check python3, kdialog and GNU timeout.")
                : i18n("%1 command failed. Try again.", displayNameForProvider(descriptor.provider))
        }
        runReloadDeferredBySourceWrite()
    }

    function setProviderSource(providerID, mode) {
        if (loading || providerSourcesLoading || !providerSourceSetupSupported || !providerByID(providerID) || isPending(providerID)
                || hasPendingFields(providerID)) {
            return
        }
        var plan = ProviderSource.planWrite(commandPath, providerCliArgument(providerID), mode,
            providerByID(providerID).authentication)
        if (!plan.ok) {
            return
        }
        // A diagnostic started before this write can describe the old source.
        retireProviderDiagnostic(providerID)
        errorText = ""
        statusText = ""
        markPending(providerID, true, providerByID(providerID).enabled)
        runCommand(plan.commandLine, {
            kind: "setSource",
            provider: providerID,
            sourceMode: mode,
            timeoutMs: configCommandTimeoutMs
        })
    }

    function loadProviderSettings(providerID) {
        if (commandPath.length === 0 || providerID.length === 0 || isPending(providerID)
                || providerDiagnosticLoadingFor(providerID)) {
            return
        }
        setProviderDiagnosticLoading(providerID, true)
        setProviderDiagnosticError(providerID, "")
        var cliProviderID = providerCliArgument(providerID)
        var command = Guards.boundedShellCommand([
            shellQuote(commandPath),
            "diagnose --provider",
            shellQuote(cliProviderID),
            "--format json --redact"
        ].join(" "), providerDiagnosticTimeoutSeconds, providerDiagnosticKillAfterSeconds)
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
                cancelCredentialRequest(commands[sourceName])
                configSource.disconnectSource(sourceName)
            }
        }
        commands = ({})
        operationState = ProviderOperations.initialState()
        loading = false
    }

    function runReloadDeferredBySourceWrite() {
        var decision = ProviderOperations.deferredReload(operationState,
            hasCredentialWrite() || CommandLedger.hasKind(commands, "setSource"), errorText)
        operationState = decision.state
        if (decision.reload) {
            reload(decision.preserveMessages, decision.retainedErrorText)
        }
    }

    function runCommand(command, descriptor) {
        commandRunSerial += 1
        var nextDescriptor = copyObject(descriptor)
        nextDescriptor.commandPathSignature = commandPath
        // Fail closed like CommandLedger.descriptor: an entry without a usable
        // deadline is skipped by hasTimedConfigCommands and expireConfigCommands,
        // so it would hold its provider's pending state until the page reopens.
        var timeoutMs = Number(nextDescriptor.timeoutMs)
        if (!isFinite(timeoutMs) || timeoutMs <= 0) {
            timeoutMs = configCommandTimeoutMs
        }
        nextDescriptor.deadlineMs = Date.now() + timeoutMs
        // Retiring a DataSource does not stop the CLI or its descendants.
        var bounded = descriptor.kind === "credential" && descriptor.action === "login"
            ? Guards.supervisedShellCommand(command, timeoutMs / 1000, 3)
            : Guards.boundedShellCommand(command, timeoutMs / 1000 + 2, 1, true)
        var sourceName = CommandLedger.withRunNonce(bounded, commandRunSerial, Date.now() + "-" + Math.random())
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
        if (descriptor.kind === "sources") {
            providerSourcesFailed = true
        } else if (descriptor.kind === "list") {
            loading = false
            providerListFailed = true
            errorText = i18n("Loading providers timed out. Try again.")
        } else if (descriptor.kind === "version") {
            applyProviderCapabilities(ProviderCapabilities.versionCapabilities("", 1))
            credentialCliVersion = ""
        } else if (descriptor.kind === "diagnose") {
            setProviderDiagnosticLoading(descriptor.provider, false)
            setProviderDiagnosticError(descriptor.provider, i18n("Loading provider diagnostics timed out. Try again."))
        } else if (descriptor.kind === "toggle") {
            markPending(descriptor.provider, false)
            errorText = i18n("%1 command timed out. Try again.", displayNameForProvider(descriptor.provider))
        } else if (descriptor.kind === "credential") {
            cancelCredentialRequest(descriptor)
            markPending(descriptor.provider, false)
            errorText = i18n("%1 command timed out. Try again.", displayNameForProvider(descriptor.provider))
            runReloadDeferredBySourceWrite()
        } else if (descriptor.kind === "setApiKey" || descriptor.kind === "setSource") {
            markPending(descriptor.provider, false)
            errorText = i18n("%1 command timed out. Try again.", displayNameForProvider(descriptor.provider))
            if (descriptor.kind === "setSource") {
                runReloadDeferredBySourceWrite()
            }
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

        if (descriptor.kind === "credential") {
            handleCredentialResult(descriptor, stdoutText, exitCode)
        } else if (descriptor.kind === "list") {
            handleListResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "version") {
            handleCliVersionResult(stdoutText, exitCode)
        } else if (descriptor.kind === "sources") {
            handleProviderSourcesResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "toggle") {
            handleToggleResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "setApiKey") {
            handleSetApiKeyResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "setSource") {
            handleSetSourceResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "descriptorField") {
            handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "descriptorAction") {
            handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "diagnose") {
            handleDiagnoseResult(descriptor, stdoutText, stderrText, exitCode)
        }
    }

    function applyProviderCapabilities(value) {
        fireworksSingleKeySetupSupported = value.fireworks
        sonioxApiKeySetupSupported = value.soniox
        abliterationChatboxKeySetupSupported = value.abliterationChatbox
        munitoApiKeySetupSupported = value.munito
        commandCodeFalApiKeySetupSupported = value.commandCodeFal
        providerSourceSetupSupported = value.source
    }

    function handleCliVersionResult(stdoutText, exitCode) {
        credentialCliVersion = Guards.exitCode(exitCode) === 0
            && ProviderConfigProtocol.cliVersionAtLeast(stdoutText, 0, 0, 0) ? stdoutText : ""
        applyProviderCapabilities(ProviderCapabilities.versionCapabilities(stdoutText, exitCode))
    }

    function handleSetSourceResult(descriptor, stdoutText, stderrText, exitCode) {
        applySetSourceResult(descriptor, stdoutText, stderrText, exitCode)
        runReloadDeferredBySourceWrite()
    }

    function applySetSourceResult(descriptor, stdoutText, stderrText, exitCode) {
        markPending(descriptor.provider, false)
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "command")
        if (result.outcome === "cancelled") {
            return
        }
        if (result.outcome !== "success") {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider),
                providerCommandFailureText(result, "command"))
            return
        }
        if (!ProviderSource.resultMatches(result.value,
                providerCliArgument(descriptor.provider), descriptor.sourceMode)) {
            errorText = i18n("codexbar did not return command data.")
            return
        }
        updateProviderEnabled(descriptor.provider, result.value.enabled)
        invalidateProviderDiagnostic(descriptor.provider)
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 setting saved", displayNameForProvider(descriptor.provider))
        savedProviderSources = ProviderSource.withSavedMode(savedProviderSources, descriptor.provider, descriptor.sourceMode)
        if (selectedProviderID === descriptor.provider) {
            providerSourceDraft = ""
            syncProviderSourceSelection()
        }
    }

    function handleListResult(descriptor, stdoutText, stderrText, exitCode) {
        if (!ProviderConfigProtocol.providerListResultIsCurrent(
                descriptor, providerConfigRevisionValue())) {
            reload(true, descriptor.retainedErrorText)
            return
        }
        if (descriptor.includeDescriptors === true && shouldRetryProviderListWithoutDescriptors(stdoutText, stderrText)) {
            providerDescriptorsUnavailable = true
            runProviderListCommand(false, descriptor.retainedErrorText)
            return
        }
        loading = false
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "list", function(identifier) {
            return page.providerTitle(identifier)
        })
        if (result.outcome !== "success") {
            providerListFailed = true
            errorText = providerCommandFailureText(result, "list")
            return
        }
        var next = result.value
        providerListFailed = false
        providers = next
        if (!providerByID(selectedProviderID)) {
            selectedProviderID = firstSelectableProvider(next)
        }
        if (descriptor.includeDescriptors === true) {
            providerDescriptorsUnavailable = !ProviderConfigProtocol
                .providerListHasSupportedDescriptors(next)
        }
        // reload() already restored the retained error; anything newer came from
        // a write that failed while this list was in flight.
    }

    function shouldRetryProviderListWithoutDescriptors(stdoutText, stderrText) {
        return descriptorListUnsupportedMessage(stdoutText, stderrText).length > 0
    }

    function descriptorListUnsupportedMessage(stdoutText, stderrText) {
        return ProviderConfigProtocol.descriptorUnsupportedMessage(stdoutText, stderrText)
    }

    function handleToggleResult(descriptor, stdoutText, stderrText, exitCode) {
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "command")
        if (result.outcome !== "success") {
            markPending(descriptor.provider, false)
            errorText = result.outcome === "invalidJson"
                ? providerCommandFailureText(result, "command")
                : i18n("%1: %2", displayNameForProvider(descriptor.provider), providerCommandFailureText(result, "command"))
            return
        }
        var payload = result.value
        // Trust the enabled value the CLI reports back; fall back to desired.
        var newEnabled = descriptor.desiredEnabled
        if (payload && !Array.isArray(payload) && payload.enabled !== undefined) {
            newEnabled = payload.enabled === true
        }
        updateProviderEnabled(descriptor.provider, newEnabled)
        markPending(descriptor.provider, false)
        invalidateProviderDiagnostic(descriptor.provider)
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 saved", displayNameForProvider(descriptor.provider))
    }

    function handleSetApiKeyResult(descriptor, stdoutText, stderrText, exitCode) {
        markPending(descriptor.provider, false)
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "setApiKey")
        if (result.outcome === "cancelled") {
            statusText = ""
            errorText = ""
            return
        }
        if (result.outcome !== "success") {
            errorText = result.outcome === "invalidJson"
                ? providerCommandFailureText(result, "command")
                : i18n("%1: %2", displayNameForProvider(descriptor.provider), providerCommandFailureText(result, "command"))
            return
        }
        var payload = result.value
        if (payload && !Array.isArray(payload) && payload.enabled !== undefined) {
            updateProviderEnabled(descriptor.provider, payload.enabled === true)
        } else {
            updateProviderEnabled(descriptor.provider, true)
        }
        invalidateProviderDiagnostic(descriptor.provider)
        bumpProviderConfigRevision()
        errorText = ""
        statusText = providerKey(descriptor.provider) === "chatbox"
            ? i18n("%1 license key saved", displayNameForProvider(descriptor.provider))
            : i18n("%1 API key saved", displayNameForProvider(descriptor.provider))
    }

    function handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode) {
        markFieldPending(descriptor.provider, descriptor.fieldID, false)
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "command")
        if (result.outcome === "cancelled") {
            return
        }
        if (result.outcome !== "success") {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider),
                providerCommandFailureText(result, "command"))
            return
        }
        if (result.value && !Array.isArray(result.value) && result.value.enabled !== undefined) {
            updateProviderEnabled(descriptor.provider, result.value.enabled === true)
        }
        invalidateProviderDiagnostic(descriptor.provider)
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 setting saved", displayNameForProvider(descriptor.provider))
        page.reload(true)
    }

    function handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode) {
        markFieldPending(descriptor.provider, descriptor.actionID, false)
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "command")
        if (result.outcome === "cancelled") {
            return
        }
        if (result.outcome !== "success") {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider),
                providerCommandFailureText(result, "command"))
            return
        }
        if (result.value && !Array.isArray(result.value) && result.value.url) {
            var url = String(result.value.url).trim()
            var safeUrl = ProviderDescriptor.safeHttpsUrl(url)
            if (safeUrl.length > 0) {
                Qt.openUrlExternally(safeUrl)
            } else {
                errorText = i18n("%1 returned an unsupported URL.", displayNameForProvider(descriptor.provider))
                return
            }
        }
        invalidateProviderDiagnostic(descriptor.provider)
        bumpProviderConfigRevision()
        errorText = ""
        statusText = i18n("%1 action completed", displayNameForProvider(descriptor.provider))
        page.reload(true)
    }

    function retireProviderDiagnostic(providerID) {
        for (var sourceName in commands) {
            if (hasOwnKey(commands, sourceName) && commands[sourceName].kind === "diagnose"
                    && commands[sourceName].provider === providerID) {
                configSource.disconnectSource(sourceName)
                commands = CommandLedger.closed(commands, sourceName)
            }
        }
        setProviderDiagnosticLoading(providerID, false)
    }

    function invalidateProviderDiagnostic(providerID) {
        retireProviderDiagnostic(providerID)
        setProviderDiagnostic(providerID, null)
        setProviderDiagnosticError(providerID, "")
    }

    function handleDiagnoseResult(descriptor, stdoutText, stderrText, exitCode) {
        setProviderDiagnosticLoading(descriptor.provider, false)
        var result = ProviderConfigProtocol.response(stdoutText, stderrText, exitCode, "diagnostic")
        if (result.outcome !== "success") {
            setProviderDiagnosticError(descriptor.provider, providerCommandFailureText(result, "diagnostic"))
            return
        }

        setProviderDiagnostic(descriptor.provider, result.value)
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
        return ProviderOperations.isDiagnosticPending(operationState, providerMapKey(providerID))
    }

    function setProviderDiagnosticLoading(providerID, value) {
        operationState = ProviderOperations.diagnosticPendingChanged(
            operationState, providerMapKey(providerID), value)
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
        return ProviderOperations.isProviderPending(operationState, providerMapKey(providerID))
    }

    function visualEnabled(providerID, fallback) {
        return ProviderOperations.enabledValue(operationState, providerMapKey(providerID), fallback)
    }

    function markPending(providerID, value, desiredEnabled) {
        operationState = ProviderOperations.providerPendingChanged(
            operationState, providerMapKey(providerID), value, desiredEnabled)
    }

    function clearProviderFilters() {
        providerFilterBar.setCurrentIndex(0)
        searchField.clear()
        searchField.forceActiveFocus(Qt.ShortcutFocusReason)
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
                enabled: !isPending(item.provider) && !isFieldPending(item.provider, actions[i].id)
            })
        }
        if (supportsApiKeySetup(item.provider) && !descriptorHasField(item, "apiKey")) {
            rows.push({ title: providerKey(item.provider) === "chatbox" ? i18n("Set license key…") : i18n("Set API key…"), icon: "document-encrypt", action: "set-api-key", enabled: !isPending(item.provider) && !loading
                && !CommandLedger.hasKind(commands, "version") })
        }
        var canWrite = !loading && !isPending(item.provider) && !hasPendingFields(item.provider)
            && !CommandLedger.hasKind(commands, "version")
        if (ProviderCredentials.supportsCookie(item.provider, credentialCliVersion, item.authentication)) {
            rows.push({title: i18n("Set cookie…"), icon: "document-encrypt", action: "set-cookie", enabled: canWrite})
        }
        if (ProviderCredentials.supportsLogin(item.provider, credentialCliVersion)) {
            rows.push({title: i18n("Sign in with GitHub…"), icon: "dialog-password", action: "device-login", enabled: canWrite})
            if (deviceLoginActive()) {
                rows.push({title: i18n("Cancel sign-in"), icon: "dialog-cancel", action: "cancel-login", enabled: true})
            }
        }
        // The destructive action follows every setup action.
        if (ProviderCredentials.supportsClear(credentialCliVersion)) {
            rows.push({title: i18n("Clear stored credentials…"), icon: "edit-clear", action: "clear-credential", enabled: canWrite})
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

    function providerLinkKind(row) {
        return row && row.url ? row.action : ""
    }

    function providerLinkRow(kind) {
        var rows = selectedProviderLinkRows
        for (var i = 0; i < rows.length; i++) {
            if (providerLinkKind(rows[i]) === kind)
                return rows[i]
        }
        return null
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
        rows.push({ label: i18n("CodexBar default"), value: item.defaultEnabled ? i18n("Enabled") : i18n("Disabled") })
        rows.push({
            label: providerKey(item.provider) === "chatbox" ? i18n("License key setup") : i18n("API key setup"),
            value: supportsApiKeySetup(item.provider) ? i18n("Supported") : i18n("Use provider login/source")
        })
        if (providerKey(item.provider) === "soniox" || providerKey(item.provider) === "chatbox") {
            appendSettingsRow(rows, i18n("Key guidance"), apiKeyPrompt(item.provider))
        }
        var authentication = item.authentication
        if (authentication) {
            appendSettingsRow(rows, i18n("Environment variables"), authentication.environmentVariables.join(", "))
            if (authentication.tokenAccounts) {
                appendSettingsRow(rows, i18n("Token accounts"), authentication.tokenAccounts.title)
                appendSettingsRow(rows, i18n("Account setup"), authentication.tokenAccounts.setupHint)
            }
            appendSettingsRow(rows, i18n("CLI sign-in"), authentication.loginCommand)
        }

        if (diagnostic) {
            appendSettingsRow(rows, i18n("Source"), diagnostic.source)
            appendSettingsRow(rows, i18n("Fetch error"), diagnostic.fetchError)
            appendSettingsRow(rows, i18n("Source mode"), diagnostic.sourceMode)
            appendSettingsRow(rows, i18n("Auth modes"), diagnostic.authModes)
            rows.push({ label: i18n("Auth configured"), value: diagnostic.authConfigured ? i18n("Yes") : i18n("No") })
            rows.push({ label: i18n("Fetch attempts"), value: diagnostic.fetchAttemptOutcomes || String(diagnostic.fetchAttempts) })
            appendSettingsRow(rows, i18n("Settings keys"), diagnostic.settingsKeys)
        } else {
            rows.push({ label: i18n("Provider diagnostics"), value: i18n("Inspect redacted settings to view source and authentication details") })
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
            var keyVariable = {soniox: "SONIOX_ORG_API_KEY", abliteration: "ABLITERATION_API_KEY",
                chatbox: "CHATBOX_LICENSE_KEY"}[providerKey(providerID)] || "API_KEY"
            lines.push("printf '%s' \"$" + keyVariable + "\" | " + shellQuote(commandPath) + " config set-api-key --provider " + shellQuote(cliProviderID) + " --stdin --format json --json-only")
        }
        if (item.authentication && item.authentication.loginCommand.length > 0) {
            lines.push(shellQuote(commandPath) + " config login --provider copilot")
        }
        return lines.join("\n")
    }

    function performProviderAction(row) {
        if (!row || !selectedProvider) {
            return
        }
        if (row.action === "set-cookie") {
            setCookie(selectedProvider.provider)
            return
        }
        if (row.action === "clear-credential") {
            clearCredentialDialog.providerID = selectedProvider.provider
            clearCredentialDialog.commandSignature = commandPath
            clearCredentialDialog.open()
            return
        }
        if (row.action === "device-login") {
            startDeviceLogin(selectedProvider.provider)
            return
        }
        if (row.action === "cancel-login") {
            cancelDeviceLogin()
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
        if (!field || !field.writeCommand || field.writeCommand.length === 0 || isPending(providerID)
                || isFieldPending(providerID, field.id)) {
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
        if (!field || !field.writeCommand || field.writeCommand.length === 0 || isPending(providerID)
                || isFieldPending(providerID, field.id)) {
            return
        }
        var cookie = field.writeCommand[2] === "set-cookie"
        if (cookie && (!credentialWriteAllowed(providerID)
                || !ProviderCredentials.supportsCookie(providerID, credentialCliVersion, providerByID(providerID).authentication))) return
        var plan = ProviderDescriptor.planSecretPrompt(field, commandPath)
        if (!plan.ok) {
            errorText = i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        if (cookie) {
            retireProviderDiagnostic(providerID)
            markPending(providerID, true, providerByID(providerID).enabled)
            plan.commandLine = ProviderCredentials.helperCommand(credentialScriptUrl, commandPath, "set-cookie", providerCliArgument(providerID))
        } else {
            markFieldPending(providerID, field.id, true)
        }
        var prompt = i18n("%1 for %2", field.title, displayNameForProvider(providerID))
        var boundedDialogCommand = "timeout --kill-after="
            + shellQuote(configSecretPromptDialogKillAfterSeconds + "s") + " "
            + shellQuote(configSecretPromptDialogTimeoutSeconds + "s") + " "
            + "kdialog --password \"$1\""
        var boundedCommandLine = "timeout --kill-after="
            + shellQuote(configSecretCommandKillAfterSeconds + "s") + " "
            + shellQuote(configSecretCommandTimeoutSeconds + "s") + " "
            + plan.commandLine
        var script = [
            "if ! command -v kdialog >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"kdialog is required to prompt for secrets.\"}}'; exit 1; fi",
            "if ! command -v timeout >/dev/null 2>&1 || ! timeout --kill-after=1s 1s true >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"GNU timeout is required to save secrets safely.\"}}'; exit 1; fi",
            "value=$(" + boundedDialogCommand + " 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$value\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$value\" | " + boundedCommandLine
        ].join("; ")
        var command = ["sh", "-c", shellQuote(script), "_", shellQuote(prompt)].join(" ")
        runCommand(command, {
            kind: cookie ? "credential" : "descriptorField",
            action: cookie ? "set-cookie" : "",
            provider: providerID,
            fieldID: field.id,
            timeoutMs: configSecretPromptTimeoutMs
        })
    }

    function runDescriptorAction(providerID, action) {
        if (!action || !action.command || action.command.length === 0 || isPending(providerID)
                || isFieldPending(providerID, action.id)) {
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
        return ProviderOperations.fieldPending(operationState, providerMapKey(providerID), fieldID)
    }

    function markFieldPending(providerID, fieldID, value) {
        operationState = ProviderOperations.fieldPendingChanged(
            operationState, providerMapKey(providerID), fieldID, value)
    }

    function hasPendingFields(providerID) {
        return ProviderOperations.hasFieldOperations(operationState, providerMapKey(providerID))
    }

    function apiKeyPrompt(providerID) {
        var name = displayNameForProvider(providerID)
        if (providerKey(providerID) === "soniox") {
            return i18n("Organization API key for %1. Project keys are not supported.", name)
        }
        if (providerKey(providerID) === "chatbox") {
            return i18n("License key for %1. This key can authorize AI requests.", name)
        }
        return i18n("API key for %1", name)
    }

    function supportsApiKeySetup(providerID) {
        var item = providerByID(providerID)
        return ProviderCapabilities.supportsApiKey(providerKey(providerID), item ? item.authentication : null, {
            fireworks: fireworksSingleKeySetupSupported,
            soniox: sonioxApiKeySetupSupported,
            abliterationChatbox: abliterationChatboxKeySetupSupported,
            munito: munitoApiKeySetupSupported,
            commandCodeFal: commandCodeFalApiKeySetupSupported
        })
    }

    function sourceModeLabel(mode) {
        if (mode === "auto") return i18n("Automatic")
        if (mode === "web") return i18n("Web")
        return {api: "API", cli: "CLI", oauth: "OAuth"}[mode] || ""
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

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function providerReadableColor(value, background) {
        return ThemeContrast.readableAccentColor(
            providerColor(value),
            background || Kirigami.Theme.backgroundColor,
            Kirigami.Theme.textColor)
    }

    function providerTitle(value) {
        return providerNames.titleForKey(providerKey(value))
    }

    Timer {
        id: configCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: page.hasTimedConfigCommands()
        triggeredOnStart: false
        onTriggered: page.expireConfigCommands(Date.now())
    }

    Controls.Dialog {
        id: clearCredentialDialog
        property string providerID: ""
        property string commandSignature: ""
        title: i18n("Clear stored credentials?")
        width: Math.min(page.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 26)
        modal: true
        standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
        onAccepted: {
            if (commandSignature === page.commandPath) page.clearCredentials(providerID)
        }
        contentItem: Components.PlainControlsLabel {
            text: i18n("Remove the API key and manual cookie stored by CodexBar for %1? Token accounts, environment variables, source settings and enablement are unchanged.", page.displayNameForProvider(clearCredentialDialog.providerID))
            wrapMode: Text.WordWrap
        }
    }

    Components.ProviderNames {
        id: providerNames
    }

    Plasma5Support.DataSource {
        id: configSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var rawStdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stdoutText = SafeText.cliJsonText(rawStdoutText)
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            var exitCode = Guards.exitCode(data ? data["exit code"] : undefined)
            if (stdoutText === null) {
                stdoutText = ""
                stderrText = i18n("codexbar response exceeded the supported size.")
                exitCode = 1
            }
            disconnectSource(sourceName)
            page.handleData(sourceName, stdoutText, stderrText, exitCode)
        }
    }

    Kirigami.Action {
        id: clearProviderFiltersAction
        text: i18n("Clear filters")
        icon.name: "edit-clear"
        onTriggered: page.clearProviderFilters()
    }

    Kirigami.Action {
        id: reloadProvidersAction
        text: i18n("Reload")
        icon.name: "view-refresh"
        enabled: reloadProvidersButton.enabled
        onTriggered: page.reload()
    }

    // Unlike FormLayout, a plain ColumnLayout does not reveal focused controls
    // in its enclosing ScrollablePage. Keep provider rows and their switches visible.
    function revealFocusedProviderControl() {
        var control = page.Window.activeFocusItem
        var ancestor = control
        while (ancestor && ancestor !== providerContent) {
            ancestor = ancestor.parent
        }
        if (!ancestor) {
            return
        }
        var listAncestor = control
        while (listAncestor && listAncestor !== providerListContent)
            listAncestor = listAncestor.parent
        var listFlickable = providerListScroll.contentItem as Flickable
        if (listAncestor && listFlickable) {
            var listPosition = providerListContent.mapFromItem(control, 0, 0)
            if (listPosition.y < listFlickable.contentY)
                listFlickable.contentY = listPosition.y
            else if (listPosition.y + control.height > listFlickable.contentY + listFlickable.height)
                listFlickable.contentY = listPosition.y + control.height - listFlickable.height
        }
        var position = page.flickable.contentItem.mapFromItem(control, 0, 0)
        page.ensureVisible(control, position.x - control.x, position.y - control.y)
    }

    Connections {
        target: page.Window
        enabled: page.visible

        function onActiveFocusItemChanged() {
            page.revealFocusedProviderControl()
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
                objectName: "providerSearchField"
                Layout.fillWidth: true
                placeholderText: i18n("Search providers")
                maximumLength: 256
                Accessible.name: placeholderText
                onTextChanged: page.filterText = text
            }

            Controls.ToolButton {
                id: reloadProvidersButton

                icon.name: "view-refresh"
                text: i18n("Reload")
                display: Controls.AbstractButton.IconOnly
                enabled: !page.loading && !CommandLedger.hasKind(page.commands, "setSource")
                Accessible.name: i18n("Reload provider list")

                Components.PlainToolTip {
                    parent: reloadProvidersButton
                    plainText: reloadProvidersButton.Accessible.name
                    visible: reloadProvidersButton.hovered || reloadProvidersButton.visualFocus
                    delay: Kirigami.Units.toolTipDelay
                }

                onClicked: page.reload()
            }
        }

        Controls.TabBar {
            id: providerFilterBar
            objectName: "providerFilterBar"

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: page.providers.length > 0
            currentIndex: 0

            Controls.TabButton {
                baselineOffset: 0
                text: i18n("All providers")
            }
            Controls.TabButton {
                baselineOffset: 0
                text: i18nc("Provider group, plural", "Enabled")
            }
            Controls.TabButton {
                baselineOffset: 0
                text: i18nc("Provider group, plural", "Disabled")
            }
        }

        Components.PlainControlsLabel {
            objectName: "providerImmediateChangesMessage"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            font: Kirigami.Theme.smallFont
            opacity: page.secondaryTextOpacity
            wrapMode: Text.WordWrap
            visible: page.providers.length > 0
            text: i18n("CodexBar saves provider changes immediately. Apply and Cancel affect widget settings only.")
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
        id: providerContent

        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        GridLayout {
            id: providerPanes
            Layout.fillWidth: true
            columns: page.width >= Kirigami.Units.gridUnit * 42 ? 2 : 1
            // Side by side, both panes fill the visible page so the list uses
            // the window height instead of leaving empty space below it. The
            // panes are the first content item, so only the viewport is read.
            readonly property real paneHeight: columns === 2
                ? Math.max(Kirigami.Units.gridUnit * 20,
                    page.flickable.height - page.topPadding - page.bottomPadding)
                : Kirigami.Units.gridUnit * 20
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing

            Controls.ScrollView {
                id: providerListScroll
                objectName: "providerListScroll"
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                // Without a details pane, empty and failure states center on the page.
                Layout.maximumWidth: providerPanes.columns === 2 && selectedProviderSurface.visible
                    ? Kirigami.Units.gridUnit * 18 : Infinity
                // Expanded details may outgrow the viewport; the list follows
                // them so both panes still end together while the page scrolls.
                Layout.preferredHeight: providerPanes.columns === 2 && selectedProviderSurface.visible
                    ? Math.max(providerPanes.paneHeight,
                        selectedProviderSurface.implicitHeight + Kirigami.Units.smallSpacing)
                    : providerPanes.paneHeight
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: providerListContent
                    width: providerListScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                        visible: page.loading && page.providers.length === 0

                        Controls.BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.visible
                        }
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
                            Layout.alignment: Qt.AlignBaseline
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Components.PlainControlsLabel {
                            Layout.alignment: Qt.AlignBaseline
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: page.filterText.trim().length > 0 || page.filterScope !== "all"
                                ? i18np("%1 matching provider", "%1 matching providers", page.visibleProviders.length)
                                : i18np("%1 provider enabled", "%1 providers enabled", page.enabledCount)
                            font: Kirigami.Theme.smallFont
                            opacity: page.secondaryTextOpacity
                            elide: Text.ElideRight
                        }
                    }

                    Components.PlainPlaceholderMessage {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit * 2
                        visible: !page.loading && page.providers.length === 0
                            && !page.providerListFailed && page.errorText.length === 0
                        icon.name: "view-list-details"
                        plainText: i18n("No providers reported")
                        plainExplanation: i18n("codexbar did not return any providers.")
                    }

                    Components.PlainPlaceholderMessage {
                        objectName: "providerListFailedMessage"
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit * 2
                        visible: !page.loading && page.providers.length === 0 && page.providerListFailed
                        icon.name: "dialog-error"
                        plainText: i18n("Could not load CodexBar provider configuration.")
                        helpfulAction: reloadProvidersAction
                    }

                    Components.PlainPlaceholderMessage {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit * 2
                        visible: page.providers.length > 0 && page.visibleProviders.length === 0
                        icon.name: "search"
                        plainText: i18n("No matching providers")
                        plainExplanation: i18n("Try another search or choose a different filter.")
                        helpfulAction: clearProviderFiltersAction
                    }

                    Components.PlainControlsLabel {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        Layout.rightMargin: Kirigami.Units.smallSpacing
                        visible: page.filterScope === "all" && page.visibleEnabledProviders.length > 0
                        text: i18nc("Provider group, plural", "Enabled")
                        font: Kirigami.Theme.smallFont
                        opacity: page.secondaryTextOpacity
                    }

                    Repeater {
                        model: page.visibleEnabledProviders

                        delegate: Components.ProviderConfigRow {
                            configPage: page
                        }
                    }

                    Components.PlainControlsLabel {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        Layout.rightMargin: Kirigami.Units.smallSpacing
                        Layout.topMargin: page.visibleEnabledProviders.length > 0 ? Kirigami.Units.largeSpacing : 0
                        visible: page.filterScope === "all" && page.visibleDisabledProviders.length > 0
                        text: i18nc("Provider group, plural", "Disabled")
                        font: Kirigami.Theme.smallFont
                        opacity: page.secondaryTextOpacity
                    }

                    Repeater {
                        model: page.visibleDisabledProviders

                        delegate: Components.ProviderConfigRow {
                            configPage: page
                        }
                    }
                }
            }
            Item {
                id: selectedProviderSurface
                objectName: "selectedProviderSurface"
                Layout.alignment: Qt.AlignTop
                Layout.minimumWidth: 0
                Layout.preferredWidth: Kirigami.Units.gridUnit * 26
                // A readable measure: controls and help text stop growing on wide windows.
                Layout.maximumWidth: Kirigami.Units.gridUnit * 44

                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                implicitHeight: Math.max(selectedProviderContent.implicitHeight + Kirigami.Units.largeSpacing * 2,
                    providerPanes.columns === 2 ? providerPanes.paneHeight - Kirigami.Units.smallSpacing : 0)
                visible: page.selectedProvider !== null

                ColumnLayout {
                    id: selectedProviderContent

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        id: selectedProviderHeader

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            readonly property color accent: page.selectedProvider
                                ? page.providerReadableColor(
                                    page.selectedProvider.provider,
                                    Kirigami.Theme.backgroundColor)
                                : Kirigami.Theme.textColor

                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing * 2
                            Layout.preferredHeight: Layout.preferredWidth
                            radius: Kirigami.Units.cornerRadius
                            color: page.withAlpha(accent, 0.12)

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: Kirigami.Units.iconSizes.medium
                                height: Kirigami.Units.iconSizes.medium
                                source: page.selectedProvider ? page.providerIconSource(page.selectedProvider.provider) : ""
                                fallback: "view-statistics"
                                isMask: true
                                color: parent.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            // The provider identity keeps its text; links overflow first.
                            Layout.minimumWidth: Math.min(implicitWidth, Kirigami.Units.gridUnit * 10)
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            Components.PlainHeading {
                                text: page.selectedProvider ? page.selectedProvider.displayName : ""
                                level: 2
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Components.PlainControlsLabel {
                                text: page.selectedProvider
                                    ? (page.selectedProvider.enabled ? i18n("%1 - enabled", page.selectedProvider.provider) : i18n("%1 - disabled", page.selectedProvider.provider))
                                    : ""
                                opacity: page.secondaryTextOpacity
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        // Links leave the settings, so they read as quiet toolbar
                        // buttons and collapse into an overflow menu when narrow.
                        Kirigami.ActionToolBar {
                            id: providerLinkToolBar
                            objectName: "providerLinkToolBar"

                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            Layout.preferredWidth: maximumContentWidth
                            Layout.maximumWidth: maximumContentWidth
                            alignment: Qt.AlignRight
                            visible: page.selectedProviderLinkRows.length > 0
                            actions: [
                                Kirigami.Action {
                                    readonly property var row: page.providerLinkRow("docs")
                                    text: row ? row.title : ""
                                    enabled: row !== null && row.enabled
                                    icon.name: "help-contents"
                                    visible: row !== null
                                    onTriggered: page.performProviderAction(row)
                                },
                                Kirigami.Action {
                                    readonly property var row: page.providerLinkRow("dashboard")
                                    text: row ? row.title : ""
                                    enabled: row !== null && row.enabled
                                    icon.name: "view-statistics"
                                    visible: row !== null
                                    onTriggered: page.performProviderAction(row)
                                },
                                Kirigami.Action {
                                    readonly property var row: page.providerLinkRow("login")
                                    text: row ? row.title : ""
                                    enabled: row !== null && row.enabled
                                    icon.name: "internet-services"
                                    visible: row !== null
                                    onTriggered: page.performProviderAction(row)
                                }
                            ]
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                    }

                    Flow {
                        id: providerCommandActions
                        objectName: "providerCommandActions"
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: page.selectedProviderCommandRows.length > 0

                        Repeater {
                            model: page.selectedProviderCommandRows

                            delegate: Controls.Button {
                                required property var modelData

                                text: SafeText.plainButtonText(modelData.title, contentItem !== null)
                                Accessible.name: modelData.title
                                icon.name: modelData.icon
                                enabled: modelData.enabled
                                onClicked: page.performProviderAction(modelData)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: providerCommandActions.visible ? Kirigami.Units.largeSpacing : 0
                        spacing: Kirigami.Units.smallSpacing
                        visible: page.providerSourceSetupSupported && page.selectedProviderSourceModes.length > 0

                        Components.PlainControlsLabel {
                            text: i18n("Source mode")
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Components.PlainComboBox {
                                id: providerSourceBox
                                Accessible.description: i18n("Some sources are unavailable on Linux. The source override in Diagnostics takes precedence.")
                                Components.PlainToolTip {
                                    parent: providerSourceBox
                                    plainText: providerSourceBox.Accessible.description
                                    visible: providerSourceBox.hovered || providerSourceBox.visualFocus
                                    delay: Kirigami.Units.toolTipDelay
                                }
                                objectName: "providerSourceBox"
                                Layout.fillWidth: true
                                model: page.selectedProviderSourceModes.map(function(mode) { return page.sourceModeLabel(mode) })
                                onModelChanged: page.syncProviderSourceSelection()
                                currentIndex: -1
                                onActivated: index => {
                                    var mode = page.selectedProviderSourceModes[index]
                                    page.providerSourceDraft = mode === page.selectedProviderSavedSource ? "" : mode
                                }
                                displayText: currentIndex < 0
                                    ? (page.providerSourcesLoading ? i18n("Loading saved source…") : i18n("Choose a source"))
                                    : currentText
                                Accessible.name: i18n("Source mode")
                                enabled: page.selectedProvider !== null
                                    && !page.loading
                                    && !page.isPending(page.selectedProvider.provider)
                                    && !page.hasPendingFields(page.selectedProvider.provider)
                            }

                            Controls.Button {
                                objectName: "providerSourceSaveButton"
                                text: i18n("Save")
                                icon.name: "document-save"
                                enabled: page.selectedProvider !== null
                                    && !page.loading
                                    && !page.providerSourcesLoading
                                    && providerSourceBox.currentIndex >= 0
                                    && page.selectedProviderSourceModes[providerSourceBox.currentIndex] !== page.selectedProviderSavedSource
                                    && !page.isPending(page.selectedProvider.provider)
                                    && !page.hasPendingFields(page.selectedProvider.provider)
                                onClicked: if (page.selectedProvider) page.setProviderSource(
                                    page.selectedProvider.provider,
                                    page.selectedProviderSourceModes[providerSourceBox.currentIndex])
                            }
                        }

                        Components.PlainControlsLabel {
                            Layout.fillWidth: true
                            text: page.providerSourcesFailed
                                ? i18n("Could not read the saved source. Reload to try again.")
                                : page.selectedProviderSourceModes.indexOf(page.selectedProviderSavedSource) < 0
                                    && !page.providerSourcesLoading
                                    ? i18n("The saved source is not recognized. Choose a source and save to replace it.")
                                    : i18n("Select Save to store this source. Apply is not needed. Automatic restores the provider default.")
                            opacity: page.secondaryTextOpacity
                            font: Kirigami.Theme.smallFont
                            wrapMode: Text.WordWrap
                        }
                    }


                    Flow {
                        id: providerSettingsActions

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Components.DisclosureButton {
                            id: providerSettingsToggle
                            objectName: "providerSettingsToggle"

                            plainText: i18n("Settings and diagnostics")
                            expanded: false
                            onClicked: expanded = !expanded
                        }

                        Controls.BusyIndicator {
                            running: page.selectedProvider !== null
                                && page.providerDiagnosticLoadingFor(page.selectedProvider.provider)
                            visible: running
                            width: Kirigami.Units.iconSizes.small
                            height: Kirigami.Units.iconSizes.small
                        }

                        Controls.Button {
                            text: i18n("Inspect redacted settings")
                            icon.name: "view-refresh"
                            visible: providerSettingsToggle.expanded
                            enabled: page.selectedProvider
                                && !page.isPending(page.selectedProvider.provider)
                                && !page.providerDiagnosticLoadingFor(page.selectedProvider.provider)
                            onClicked: if (page.selectedProvider) page.loadProviderSettings(page.selectedProvider.provider)
                        }
                    }

                    ColumnLayout {
                        id: providerSettingsDetails

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: providerSettingsToggle.expanded

                        Components.PlainControlsLabel {
                            Layout.fillWidth: true
                            text: page.providerDescriptorsUnavailable && page.providerSourceSetupSupported
                                ? i18n("This CodexBar version does not support editing other options for this provider.")
                                : page.providerDescriptorsUnavailable
                                ? i18n("This CodexBar version does not expose editable provider options. Enable/disable, supported API key setup, provider links, and redacted diagnostics remain available.")
                                : i18n("Editable provider options come from CodexBar. Redacted source and authentication details are available on request.")
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
                                // next diagnostic error still shows up. Collapsing the
                                // parent details is not a dismissal of the error.
                                if (!visible && providerSettingsToggle.expanded
                                        && plainText.length > 0 && page.selectedProvider) {
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
                                text: i18n("Provider options")
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Repeater {
                                model: page.descriptorFieldRows(page.selectedProvider)

                                delegate: ProviderConfig.ProviderDescriptorField {
                                    providerAvailable: page.selectedProvider !== null
                                    writePending: page.selectedProvider !== null
                                        && (page.isPending(page.selectedProvider.provider)
                                            || page.isFieldPending(page.selectedProvider.provider, modelData.id))
                                    secondaryTextOpacity: page.secondaryTextOpacity
                                    onWriteRequested: function(field, value) {
                                        if (page.selectedProvider)
                                            page.writeDescriptorField(page.selectedProvider.provider, field, value)
                                    }
                                    onEnumWriteRequested: function(field, optionIndex) {
                                        if (page.selectedProvider)
                                            page.writeDescriptorField(page.selectedProvider.provider, field,
                                                page.optionIDAt(field.options, optionIndex))
                                    }
                                    onSecretPromptRequested: function(field) {
                                        if (page.selectedProvider)
                                            page.promptDescriptorSecret(page.selectedProvider.provider, field)
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: page.providerSettingsRows(page.selectedProvider)

                            delegate: GridLayout {
                                id: settingsRow
                                columns: selectedProviderSurface.width < Kirigami.Units.gridUnit * 24 ? 1 : 2
                                required property var modelData

                                Layout.fillWidth: true
                                // Stacked, the label binds to its value and a
                                // wider gap separates the pairs.
                                Layout.bottomMargin: columns === 1 ? Kirigami.Units.smallSpacing : 0
                                rowSpacing: 0
                                columnSpacing: Kirigami.Units.smallSpacing

                                Components.PlainControlsLabel {
                                    objectName: "providerSettingLabel"
                                    text: modelData.label
                                    opacity: page.secondaryTextOpacity
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                                    Layout.minimumWidth: settingsRow.columns === 2 ? Kirigami.Units.gridUnit * 8 : 0
                                    Layout.maximumWidth: settingsRow.columns === 2 ? Kirigami.Units.gridUnit * 8 : Infinity
                                    Layout.fillWidth: settingsRow.columns === 1
                                    Layout.alignment: Qt.AlignTop
                                    wrapMode: Text.Wrap
                                }

                                Components.PlainControlsLabel {
                                    objectName: "providerSettingValue"
                                    text: modelData.value
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Components.DisclosureButton {
                            id: providerCliCommandsToggle

                            plainText: i18n("CLI commands")
                            expanded: false
                            onClicked: expanded = !expanded
                            Layout.alignment: Qt.AlignLeft
                        }

                        Controls.ScrollView {
                            id: providerCliCommandsView

                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                            visible: providerCliCommandsToggle.expanded

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
            }

        }
    }
}
