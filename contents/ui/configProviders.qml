import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "components" as Components

KCM.SimpleKCM {
    id: page

    // Read the configured command path so this page can call the same CLI the
    // widget uses. The provider list/toggles below persist immediately through
    // `codexbar config enable/disable`, independent of the KCM Apply cycle.
    property string cfg_commandPath
    property string cfg_commandPathDefault
    property string cfg_provider
    property string cfg_providerDefault
    property string cfg_source
    property string cfg_sourceDefault
    property int cfg_refreshInterval
    property int cfg_refreshIntervalDefault
    property bool cfg_includeStatus
    property bool cfg_includeStatusDefault
    property bool cfg_usageBarsShowUsed
    property bool cfg_usageBarsShowUsedDefault
    property bool cfg_showProviderChangelogs
    property bool cfg_showProviderChangelogsDefault
    property bool cfg_showProviderInPanel
    property bool cfg_showProviderInPanelDefault
    property bool cfg_showPercentInPanel
    property bool cfg_showPercentInPanelDefault
    property bool cfg_showMultiProviderInPanel
    property bool cfg_showMultiProviderInPanelDefault
    property bool cfg_showCreditsInPanel
    property bool cfg_showCreditsInPanelDefault
    property int cfg_providerConfigRevision
    property int cfg_providerConfigRevisionDefault

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
    property var providerDiagnostics: ({})
    property var providerDiagnosticErrors: ({})
    property var providerDiagnosticLoading: ({})
    property string selectedProviderID: ""

    readonly property var visibleProviders: filterProviders(providers, filterText)
    readonly property int enabledCount: countEnabled(providers)
    readonly property var selectedProvider: providerByID(selectedProviderID)

    Component.onCompleted: reload()

    function reload(preserveMessages) {
        if (commandPath.length === 0) {
            errorText = i18n("Set the codexbar command path in the General page.")
            providers = []
            return
        }
        loading = true
        errorText = ""
        if (preserveMessages !== true) {
            statusText = ""
        }
        runProviderListCommand(true)
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
        runCommand(command.join(" "), { kind: "list", includeDescriptors: includeDescriptors === true })
    }

    function setEnabled(providerID, desiredEnabled) {
        if (commandPath.length === 0 || isPending(providerID)) {
            return
        }
        errorText = ""
        statusText = ""
        markPending(providerID, true, desiredEnabled)
        var command = [
            shellQuote(commandPath),
            "config",
            desiredEnabled ? "enable" : "disable",
            "--provider",
            shellQuote(providerID),
            "--format",
            "json",
            "--json-only"
        ].join(" ")
        runCommand(command, { kind: "toggle", provider: providerID, desiredEnabled: desiredEnabled })
    }

    function setApiKey(providerID) {
        if (commandPath.length === 0 || isPending(providerID)) {
            return
        }
        errorText = ""
        statusText = ""
        markPending(providerID, true, true)

        var prompt = i18n("API key for %1", displayNameForProvider(providerID))
        var script = [
            "if ! command -v kdialog >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"kdialog is required to prompt for API keys.\"}}'; exit 1; fi",
            "key=$(kdialog --password \"$1\" 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$key\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$key\" | \"$2\" config set-api-key --provider \"$3\" --stdin --format json --json-only"
        ].join("; ")
        var command = ["sh", "-lc", shellQuote(script), "_", shellQuote(prompt), shellQuote(commandPath), shellQuote(providerID)].join(" ")
        runCommand(command, { kind: "setApiKey", provider: providerID })
    }

    function loadProviderSettings(providerID) {
        if (commandPath.length === 0 || providerID.length === 0 || providerDiagnosticLoadingFor(providerID)) {
            return
        }
        setProviderDiagnosticLoading(providerID, true)
        setProviderDiagnosticError(providerID, "")
        var command = [
            shellQuote(commandPath),
            "diagnose --provider",
            shellQuote(providerID),
            "--format json --redact"
        ].join(" ")
        runCommand(command, { kind: "diagnose", provider: providerID })
    }

    function runCommand(command, descriptor) {
        var existing = copyObject(commands)
        existing[command] = descriptor
        commands = existing
        configSource.connectSource(command)
    }

    function handleData(sourceName, stdoutText, stderrText, exitCode) {
        var descriptor = commands[sourceName]
        if (!descriptor) {
            return
        }
        var withoutCommand = copyObject(commands)
        delete withoutCommand[sourceName]
        commands = withoutCommand

        if (descriptor.kind === "list") {
            handleListResult(descriptor, stdoutText, stderrText)
        } else if (descriptor.kind === "toggle") {
            handleToggleResult(descriptor, stdoutText, stderrText, exitCode)
        } else if (descriptor.kind === "setApiKey") {
            handleSetApiKeyResult(descriptor, stdoutText, stderrText)
        } else if (descriptor.kind === "descriptorField") {
            handleDescriptorFieldResult(descriptor, stdoutText, stderrText)
        } else if (descriptor.kind === "descriptorAction") {
            handleDescriptorActionResult(descriptor, stdoutText, stderrText)
        } else if (descriptor.kind === "diagnose") {
            handleDiagnoseResult(descriptor, stdoutText, stderrText)
        }
    }

    function handleListResult(descriptor, stdoutText, stderrText) {
        if (descriptor.includeDescriptors === true && shouldRetryProviderListWithoutDescriptors(stdoutText, stderrText)) {
            runProviderListCommand(false)
            return
        }
        loading = false
        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            providers = []
            errorText = stderrText.trim().length > 0
                ? stderrText.trim()
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

        var parseError = commandError(payload)
        if (parseError.length > 0) {
            providers = []
            errorText = parseError
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var next = []
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || !item.provider) {
                continue
            }
            next.push({
                provider: String(item.provider),
                displayName: item.displayName && String(item.displayName).trim().length > 0
                    ? String(item.displayName).trim()
                    : providerTitle(item.provider),
                enabled: item.enabled === true,
                defaultEnabled: item.defaultEnabled === true,
                descriptor: normalizeProviderDescriptor(item.descriptor)
            })
        }
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
        var stderrMessage = String(stderrText || "").trim()
        if (isDescriptorUnsupportedMessage(stderrMessage)) {
            return stderrMessage
        }

        var trimmed = String(stdoutText || "").trim()
        if (trimmed.length === 0) {
            return ""
        }
        try {
            var payload = JSON.parse(trimmed)
            var message = commandError(payload)
            return isDescriptorUnsupportedMessage(message) ? message : ""
        } catch (error) {
            return ""
        }
    }

    function isDescriptorUnsupportedMessage(message) {
        var text = String(message || "").toLowerCase()
        if (text.indexOf("descriptor") === -1) {
            return false
        }
        return text.indexOf("unknown option") !== -1
            || text.indexOf("unknown argument") !== -1
            || text.indexOf("unrecognized option") !== -1
            || text.indexOf("unrecognized argument") !== -1
            || text.indexOf("unexpected option") !== -1
            || text.indexOf("unexpected argument") !== -1
            || text.indexOf("unsupported option") !== -1
            || text.indexOf("unsupported argument") !== -1
            || text.indexOf("invalid option") !== -1
    }

    function handleToggleResult(descriptor, stdoutText, stderrText, exitCode) {
        var trimmed = stdoutText.trim()
        var payload = null
        if (trimmed.length > 0) {
            try {
                payload = JSON.parse(trimmed)
            } catch (error) {
                markPending(descriptor.provider, false)
                errorText = i18n("Could not parse codexbar response: %1", error.message)
                return
            }
        }

        var message = commandError(payload)
        if (message.length === 0 && stderrText.trim().length > 0) {
            message = stderrText.trim()
        }
        if (message.length === 0 && Number(exitCode) !== 0) {
            message = i18n("codexbar exited with code %1", Number(exitCode))
        }
        if (message.length === 0 && !payload) {
            message = i18n("codexbar did not return provider data.")
        }
        if (message.length > 0) {
            markPending(descriptor.provider, false)
            errorText = i18n("%1: %2", descriptor.provider, message)
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

    function handleSetApiKeyResult(descriptor, stdoutText, stderrText) {
        markPending(descriptor.provider, false)

        var trimmed = stdoutText.trim()
        var payload = null
        if (trimmed.length > 0) {
            try {
                payload = JSON.parse(trimmed)
            } catch (error) {
                errorText = i18n("Could not parse codexbar response: %1", error.message)
                return
            }
        }

        if (payload && payload.cancelled === true) {
            statusText = ""
            errorText = ""
            return
        }

        var message = commandError(payload)
        if (message.length === 0 && stderrText.trim().length > 0) {
            message = stderrText.trim()
        }
        if (message.length > 0) {
            errorText = i18n("%1: %2", descriptor.provider, message)
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

    function handleDescriptorFieldResult(descriptor, stdoutText, stderrText) {
        markFieldPending(descriptor.provider, descriptor.fieldID, false)
        var payload = parseCommandPayload(stdoutText, stderrText)
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

    function handleDescriptorActionResult(descriptor, stdoutText, stderrText) {
        markFieldPending(descriptor.provider, descriptor.actionID, false)
        var payload = parseCommandPayload(stdoutText, stderrText)
        if (payload.cancelled) {
            return
        }
        if (payload.errorMessage.length > 0) {
            errorText = i18n("%1: %2", displayNameForProvider(descriptor.provider), payload.errorMessage)
            return
        }

        if (payload.value && !Array.isArray(payload.value) && payload.value.url) {
            var url = String(payload.value.url).trim()
            if (isSafeDescriptorUrl(url)) {
                Qt.openUrlExternally(url)
            } else {
                errorText = i18n("%1 returned an unsupported URL.", displayNameForProvider(descriptor.provider))
                return
            }
        }
        errorText = ""
        statusText = i18n("%1 action completed", displayNameForProvider(descriptor.provider))
        page.reload(true)
    }

    function parseCommandPayload(stdoutText, stderrText) {
        var trimmed = stdoutText.trim()
        var payload = null
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
        if (payload && payload.cancelled === true) {
            return { value: payload, cancelled: true, errorMessage: "" }
        }
        var message = commandError(payload)
        if (message.length === 0 && stderrText.trim().length > 0) {
            message = stderrText.trim()
        }
        return { value: payload, cancelled: false, errorMessage: message }
    }

    function handleDiagnoseResult(descriptor, stdoutText, stderrText) {
        setProviderDiagnosticLoading(descriptor.provider, false)

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            setProviderDiagnosticError(
                descriptor.provider,
                stderrText.trim().length > 0 ? stderrText.trim() : i18n("codexbar did not return diagnostics."))
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            setProviderDiagnosticError(descriptor.provider, i18n("Could not parse codexbar diagnostics: %1", error.message))
            return
        }

        var message = commandError(payload)
        if (message.length > 0) {
            setProviderDiagnosticError(descriptor.provider, message)
            return
        }

        setProviderDiagnostic(descriptor.provider, normalizeProviderDiagnostic(payload))
        setProviderDiagnosticError(descriptor.provider, "")
    }

    function commandError(payload) {
        if (!payload) {
            return ""
        }
        var probe = Array.isArray(payload) ? (payload.length > 0 ? payload[0] : null) : payload
        if (probe && probe.error && probe.error.message) {
            return String(probe.error.message)
        }
        return ""
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
        if (message && message.length > 0) {
            next[key] = message
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

    function normalizeProviderDiagnostic(payload) {
        var item = Array.isArray(payload) ? (payload.length > 0 ? payload[0] : ({})) : payload
        var settings = item && item.settings ? item.settings : ({})
        var auth = item && item.auth ? item.auth : ({})
        return {
            provider: item && item.provider ? String(item.provider) : "",
            displayName: item && item.displayName ? String(item.displayName) : "",
            source: item && item.source ? String(item.source) : "",
            sourceMode: item && item.sourceMode ? String(item.sourceMode) : "",
            authConfigured: auth.configured === true,
            authModes: Array.isArray(auth.modes) ? auth.modes.join(", ") : "",
            settingsKeys: objectKeys(settings).join(", "),
            fetchAttempts: item && Array.isArray(item.fetchAttempts) ? item.fetchAttempts.length : 0
        }
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
        var copy = ({})
        for (var key in item) {
            if (!hasOwnKey(item, key) || isUnsafeObjectKey(key)) {
                continue
            }
            copy[key] = item[key]
        }
        return copy
    }

    function hasOwnKey(item, key) {
        return item ? Object.prototype.hasOwnProperty.call(item, key) : false
    }

    function isUnsafeObjectKey(key) {
        var value = String(key || "")
        return value === "__proto__" || value === "prototype" || value === "constructor"
    }

    function providerMapKey(providerID) {
        var key = providerKey(providerID)
        return isUnsafeObjectKey(key) ? "" : key
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

    function normalizeProviderDescriptor(raw) {
        if (!raw || Number(raw.schemaVersion) !== 1) {
            return { schemaVersion: 0, fields: [], actions: [] }
        }
        var fields = []
        var rawFields = Array.isArray(raw.fields) ? raw.fields : []
        for (var i = 0; i < rawFields.length; i++) {
            var field = normalizeDescriptorField(rawFields[i])
            if (field) {
                fields.push(field)
            }
        }
        var actions = []
        var rawActions = Array.isArray(raw.actions) ? raw.actions : []
        for (var j = 0; j < rawActions.length; j++) {
            var action = normalizeDescriptorAction(rawActions[j])
            if (action) {
                actions.push(action)
            }
        }
        return { schemaVersion: 1, fields: fields, actions: actions }
    }

    function normalizeDescriptorField(raw) {
        if (!raw || !raw.id || !raw.kind || !isSupportedDescriptorFieldKind(raw.kind)) {
            return null
        }
        var command = normalizeCommandTokens(raw.writeCommand)
        if (command.length === 0 || !isAllowedDescriptorCommand(command, "field")) {
            return null
        }
        return {
            id: String(raw.id),
            kind: String(raw.kind),
            title: raw.title ? String(raw.title) : providerTitle(raw.id),
            description: raw.description ? String(raw.description) : "",
            value: raw.value === undefined || raw.value === null ? "" : raw.value,
            redactedValue: raw.redactedValue ? String(raw.redactedValue) : "",
            required: raw.required === true,
            options: normalizeDescriptorOptions(raw.options),
            writeCommand: command
        }
    }

    function normalizeDescriptorAction(raw) {
        if (!raw || !raw.id || !raw.title) {
            return null
        }
        var command = normalizeCommandTokens(raw.command)
        if (command.length === 0 || !isAllowedDescriptorCommand(command, "action")) {
            return null
        }
        return {
            id: String(raw.id),
            kind: raw.kind ? String(raw.kind) : "command",
            title: String(raw.title),
            description: raw.description ? String(raw.description) : "",
            command: command
        }
    }

    function isSupportedDescriptorFieldKind(kind) {
        switch (String(kind)) {
        case "text":
        case "secret":
        case "enum":
        case "boolean":
        case "number":
            return true
        default:
            return false
        }
    }

    function normalizeDescriptorOptions(rawOptions) {
        var result = []
        if (!Array.isArray(rawOptions)) {
            return result
        }
        for (var i = 0; i < rawOptions.length; i++) {
            var option = rawOptions[i]
            if (!option || option.id === undefined || option.id === null) {
                continue
            }
            result.push({
                id: String(option.id),
                title: option.title ? String(option.title) : String(option.id)
            })
        }
        return result
    }

    function normalizeCommandTokens(tokens) {
        var result = []
        if (!Array.isArray(tokens)) {
            return result
        }
        for (var i = 0; i < tokens.length; i++) {
            var token = String(tokens[i])
            if (token.length > 0) {
                result.push(token)
            }
        }
        return result
    }

    function isAllowedDescriptorCommand(commandTokens, purpose) {
        if (!Array.isArray(commandTokens) || commandTokens.length < 3) {
            return false
        }
        if (String(commandTokens[0]) !== "codexbar" || String(commandTokens[1]) !== "config") {
            return false
        }

        var subcommand = String(commandTokens[2])
        if (purpose === "field") {
            return subcommand === "set" || subcommand === "set-api-key"
        }
        if (purpose === "action") {
            return subcommand === "action"
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
        var lines = [
            shellQuote(commandPath) + " usage --provider " + shellQuote(providerID) + " --format json --json-only",
            shellQuote(commandPath) + " diagnose --provider " + shellQuote(providerID) + " --format json --redact",
            shellQuote(commandPath) + " config " + (item.enabled ? "disable" : "enable") + " --provider " + shellQuote(providerID) + " --format json --json-only"
        ]
        if (supportsApiKeySetup(providerID)) {
            lines.push("printf '%s' \"$API_KEY\" | " + shellQuote(commandPath) + " config set-api-key --provider " + shellQuote(providerID) + " --stdin --format json --json-only")
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
        if (!isAllowedDescriptorCommand(field.writeCommand, "field")) {
            errorText = i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        markFieldPending(providerID, field.id, true)
        var command = runDescriptorCommand(field.writeCommand, ({ "{value}": value }), field.kind === "secret" ? value : null)
        runCommand(command, { kind: "descriptorField", provider: providerID, fieldID: field.id })
    }

    function promptDescriptorSecret(providerID, field) {
        if (!field || !field.writeCommand || field.writeCommand.length === 0 || isFieldPending(providerID, field.id)) {
            return
        }
        if (!isAllowedDescriptorCommand(field.writeCommand, "field")) {
            errorText = i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        markFieldPending(providerID, field.id, true)
        var prompt = i18n("%1 for %2", field.title, displayNameForProvider(providerID))
        var commandLine = commandLineFromTokens(field.writeCommand, ({}))
        var script = [
            "if ! command -v kdialog >/dev/null 2>&1; then printf '%s\\n' '{\"error\":{\"message\":\"kdialog is required to prompt for secrets.\"}}'; exit 1; fi",
            "value=$(kdialog --password \"$1\" 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$value\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$value\" | " + commandLine
        ].join("; ")
        var command = ["sh", "-lc", shellQuote(script), "_", shellQuote(prompt)].join(" ")
        runCommand(command, { kind: "descriptorField", provider: providerID, fieldID: field.id })
    }

    function runDescriptorAction(providerID, action) {
        if (!action || !action.command || action.command.length === 0 || isFieldPending(providerID, action.id)) {
            return
        }
        if (!isAllowedDescriptorCommand(action.command, "action")) {
            errorText = i18n("%1 returned an unsupported descriptor command.", displayNameForProvider(providerID))
            return
        }
        errorText = ""
        statusText = ""
        markFieldPending(providerID, action.id, true)
        var command = runDescriptorCommand(action.command, ({}), null)
        runCommand(command, { kind: "descriptorAction", provider: providerID, actionID: action.id })
    }

    function runDescriptorCommand(commandTokens, replacements, stdinValue) {
        var commandLine = commandLineFromTokens(commandTokens, replacements)
        if (stdinValue !== undefined && stdinValue !== null) {
            var script = "printf '%s' \"$1\" | " + commandLine
            return ["sh", "-lc", shellQuote(script), "_", shellQuote(stdinValue)].join(" ")
        }
        return commandLine
    }

    function commandLineFromTokens(commandTokens, replacements) {
        var parts = []
        for (var i = 0; i < commandTokens.length; i++) {
            var token = commandTokens[i]
            if (i === 0 && token === "codexbar" && commandPath.length > 0) {
                token = commandPath
            }
            parts.push(shellQuote(applyCommandTokenReplacements(token, replacements)))
        }
        return parts.join(" ")
    }

    function isSafeDescriptorUrl(url) {
        var text = String(url || "").trim().toLowerCase()
        return text.indexOf("https://") === 0
    }

    function applyCommandTokenReplacements(token, replacements) {
        var result = String(token)
        for (var key in replacements) {
            if (!hasOwnKey(replacements, key)) {
                continue
            }
            result = result.split(key).join(String(replacements[key]))
        }
        return result
    }

    function fieldOptionIndex(field) {
        if (!field || !Array.isArray(field.options)) {
            return -1
        }
        var value = String(field.value || "")
        for (var i = 0; i < field.options.length; i++) {
            if (field.options[i].id === value) {
                return i
            }
        }
        return -1
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
        var field = providerMapKey(fieldID)
        return provider.length > 0 && field.length > 0 ? provider + "::" + field : ""
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
        case "commandcode":
        case "copilot":
        case "crof":
        case "deepgram":
        case "deepseek":
        case "doubao":
        case "elevenlabs":
        case "grok":
        case "groq":
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
        var key = providerKey(providerID)
        var docs = {
            abacus: "abacus.md",
            alibaba: "alibaba-coding-plan.md",
            alibabatokenplan: "alibaba-token-plan.md",
            amp: "amp.md",
            antigravity: "antigravity.md",
            augment: "augment.md",
            azureopenai: "providers.md#azure-openai",
            bedrock: "bedrock.md",
            chutes: "chutes.md",
            claude: "claude.md",
            codebuff: "codebuff.md",
            commandcode: "command-code.md",
            codex: "codex.md",
            copilot: "copilot.md",
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
            mistral: "providers.md#mistral",
            minimax: "minimax.md",
            moonshot: "moonshot.md",
            ollama: "ollama.md",
            opencode: "opencode.md",
            opencodego: "opencode.md",
            openai: "openai.md",
            openrouter: "openrouter.md",
            perplexity: "providers.md#perplexity",
            poe: "poe.md",
            stepfun: "stepfun.md",
            synthetic: "providers.md#synthetic",
            t3chat: "providers.md#t3-chat",
            venice: "venice.md",
            vertexai: "vertexai.md",
            warp: "warp.md",
            windsurf: "windsurf.md",
            zai: "zai.md",
            zed: "zed.md"
        }
        if (!docs[key]) {
            return ""
        }
        return "https://github.com/steipete/CodexBar/blob/main/docs/" + docs[key]
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
        case "crof":
            return "https://crof.ai/dashboard"
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

    function bumpProviderConfigRevision() {
        var current = Number(Plasmoid.configuration.providerConfigRevision || cfg_providerConfigRevision || 0)
        var next = current >= 2147480000 ? 1 : current + 1
        cfg_providerConfigRevision = next
        Plasmoid.configuration.providerConfigRevision = next
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    // --- Provider visual identity (kept in sync with main.qml) ---

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

    function providerColor(value) {
        switch (providerKey(value)) {
        case "codex":
            return Qt.rgba(73 / 255, 163 / 255, 176 / 255, 1)
        case "openai":
            return Qt.rgba(0.06, 0.51, 0.43, 1)
        case "azureopenai":
            return Qt.rgba(0, 120 / 255, 212 / 255, 1)
        case "claude":
            return Qt.rgba(204 / 255, 124 / 255, 94 / 255, 1)
        case "cursor":
            return Qt.rgba(0, 191 / 255, 165 / 255, 1)
        case "opencode":
            return Qt.rgba(59 / 255, 130 / 255, 246 / 255, 1)
        case "opencodego":
            return Qt.rgba(59 / 255, 130 / 255, 246 / 255, 1)
        case "alibaba":
            return Qt.rgba(1, 106 / 255, 0, 1)
        case "alibabatokenplan":
            return Qt.rgba(1, 106 / 255, 0, 1)
        case "factory":
            return Qt.rgba(1, 107 / 255, 53 / 255, 1)
        case "gemini":
            return Qt.rgba(171 / 255, 135 / 255, 234 / 255, 1)
        case "antigravity":
            return Qt.rgba(96 / 255, 186 / 255, 126 / 255, 1)
        case "copilot":
            return Qt.rgba(168 / 255, 85 / 255, 247 / 255, 1)
        case "devin":
            return Qt.rgba(70 / 255, 180 / 255, 130 / 255, 1)
        case "minimax":
            return Qt.rgba(254 / 255, 96 / 255, 60 / 255, 1)
        case "manus":
            return Qt.rgba(52 / 255, 50 / 255, 45 / 255, 1)
        case "kimi":
            return Qt.rgba(254 / 255, 96 / 255, 60 / 255, 1)
        case "kilo":
            return Qt.rgba(242 / 255, 112 / 255, 39 / 255, 1)
        case "kiro":
            return Qt.rgba(1, 153 / 255, 0, 1)
        case "zai":
            return Qt.rgba(232 / 255, 90 / 255, 106 / 255, 1)
        case "vertexai":
            return Qt.rgba(66 / 255, 133 / 255, 244 / 255, 1)
        case "augment":
            return Qt.rgba(99 / 255, 102 / 255, 241 / 255, 1)
        case "jetbrains":
            return Qt.rgba(1, 51 / 255, 153 / 255, 1)
        case "kimik2":
            return Qt.rgba(76 / 255, 0, 1, 1)
        case "moonshot":
            return Qt.rgba(32 / 255, 93 / 255, 235 / 255, 1)
        case "amp":
            return Qt.rgba(220 / 255, 38 / 255, 38 / 255, 1)
        case "t3chat":
            return Qt.rgba(245 / 255, 102 / 255, 71 / 255, 1)
        case "ollama":
            return Qt.rgba(136 / 255, 136 / 255, 136 / 255, 1)
        case "synthetic":
            return Qt.rgba(20 / 255, 20 / 255, 20 / 255, 1)
        case "warp":
            return Qt.rgba(147 / 255, 139 / 255, 180 / 255, 1)
        case "openrouter":
            return Qt.rgba(100 / 255, 103 / 255, 242 / 255, 1)
        case "elevenlabs":
            return Qt.rgba(0.92, 0.92, 0.90, 1)
        case "windsurf":
            return Qt.rgba(52 / 255, 232 / 255, 187 / 255, 1)
        case "zed":
            return Qt.rgba(8 / 255, 78 / 255, 1, 1)
        case "perplexity":
            return Qt.rgba(32 / 255, 178 / 255, 170 / 255, 1)
        case "mimo":
            return Qt.rgba(1, 105 / 255, 0, 1)
        case "doubao":
            return Qt.rgba(51 / 255, 112 / 255, 1, 1)
        case "abacus":
            return Qt.rgba(56 / 255, 189 / 255, 248 / 255, 1)
        case "mistral":
            return Qt.rgba(1, 80 / 255, 15 / 255, 1)
        case "deepseek":
            return Qt.rgba(0.32, 0.49, 0.94, 1)
        case "codebuff":
            return Qt.rgba(68 / 255, 1, 0, 1)
        case "crof":
            return Qt.rgba(0.18, 0.67, 0.58, 1)
        case "venice":
            return Qt.rgba(0.2, 0.6, 1, 1)
        case "commandcode":
            return Qt.rgba(0, 0, 0, 1)
        case "stepfun":
            return Qt.rgba(0.13, 0.59, 0.95, 1)
        case "bedrock":
            return Qt.rgba(1, 0.6, 0, 1)
        case "grok":
            return Qt.rgba(16 / 255, 163 / 255, 127 / 255, 1)
        case "groq":
            return Qt.rgba(245 / 255, 104 / 255, 68 / 255, 1)
        case "llmproxy":
            return Qt.rgba(36 / 255, 180 / 255, 126 / 255, 1)
        case "litellm":
            return Qt.rgba(76 / 255, 137 / 255, 240 / 255, 1)
        case "deepgram":
            return Qt.rgba(100 / 255, 103 / 255, 242 / 255, 1)
        case "poe":
            return Qt.rgba(0.15, 0.68, 0.38, 1)
        case "chutes":
            return Qt.rgba(49 / 255, 132 / 255, 1, 1)
        default:
            return Kirigami.Theme.highlightColor
        }
    }

    function providerTitle(value) {
        var key = providerKey(value)
        var words = String(key).replace(/[_-]/g, " ").split(" ")
        for (var i = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
            }
        }
        return words.join(" ")
    }

    function objectKeys(item) {
        var keys = []
        if (!item) {
            return keys
        }
        for (var key in item) {
            keys.push(key)
        }
        keys.sort()
        return keys
    }

    Plasma5Support.DataSource {
        id: configSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var stdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            var exitCode = data && data["exit code"] !== undefined ? Number(data["exit code"]) : 0
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

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            type: Kirigami.MessageType.Error
            text: page.errorText
            visible: page.errorText.length > 0
            showCloseButton: true
            onVisibleChanged: if (!visible) page.errorText = ""
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            type: Kirigami.MessageType.Positive
            text: page.statusText
            visible: page.statusText.length > 0
            showCloseButton: true
            onVisibleChanged: if (!visible) page.statusText = ""
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            text: i18np("%1 provider enabled", "%1 providers enabled", page.enabledCount)
            opacity: 0.7
            visible: page.providers.length > 0
        }

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
                    isMask: true
                    color: page.selectedProvider ? page.providerColor(page.selectedProvider.provider) : Kirigami.Theme.textColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Controls.Label {
                        text: page.selectedProvider ? page.selectedProvider.displayName : ""
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Controls.Label {
                        text: page.selectedProvider
                            ? (page.selectedProvider.enabled ? i18n("%1 - enabled", page.selectedProvider.provider) : i18n("%1 - disabled", page.selectedProvider.provider))
                            : ""
                        opacity: 0.62
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

                        text: modelData.title
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

                    Controls.Label {
                        text: i18n("Provider settings")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Controls.BusyIndicator {
                        running: page.selectedProvider
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

                Controls.Label {
                    Layout.fillWidth: true
                    text: i18n("Provider-specific controls come from the CodexBar CLI descriptor. This panel also shows redacted source/auth details and exact CLI commands.")
                    opacity: 0.66
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    type: Kirigami.MessageType.Error
                    text: page.selectedProvider
                        ? page.providerDiagnosticErrorFor(page.selectedProvider.provider)
                        : ""
                    visible: text.length > 0
                    showCloseButton: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: page.descriptorFieldRows(page.selectedProvider).length > 0

                    Controls.Label {
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

                                Controls.Label {
                                    text: modelData.title
                                    opacity: 0.66
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Controls.Label {
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

                                Controls.Label {
                                    text: modelData.title
                                    opacity: 0.66
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Controls.TextField {
                                    id: descriptorTextField
                                    Layout.fillWidth: true
                                    text: String(modelData.value || "")
                                    placeholderText: modelData.description
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

                                Controls.Label {
                                    text: modelData.title
                                    opacity: 0.66
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Controls.ComboBox {
                                    id: descriptorEnumBox
                                    Layout.fillWidth: true
                                    model: modelData.options
                                    textRole: "title"
                                    valueRole: "id"
                                    currentIndex: page.fieldOptionIndex(modelData)
                                    enabled: page.selectedProvider
                                        && modelData.options.length > 0
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                }

                                Controls.Button {
                                    text: i18n("Save")
                                    icon.name: "document-save"
                                    enabled: page.selectedProvider
                                        && descriptorEnumBox.currentIndex >= 0
                                        && !page.isFieldPending(page.selectedProvider.provider, modelData.id)
                                    onClicked: if (page.selectedProvider) page.writeDescriptorField(
                                        page.selectedProvider.provider,
                                        modelData,
                                        page.optionIDAt(modelData.options, descriptorEnumBox.currentIndex))
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: modelData.kind === "boolean"

                                Controls.Label {
                                    text: modelData.title
                                    opacity: 0.66
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    elide: Text.ElideRight
                                }

                                Controls.CheckBox {
                                    checked: modelData.value === true || String(modelData.value).toLowerCase() === "true"
                                    text: modelData.description
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

                            Controls.Label {
                                Layout.fillWidth: true
                                text: modelData.description
                                opacity: 0.55
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
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: modelData.label
                            opacity: 0.66
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                            elide: Text.ElideRight
                        }

                        Controls.Label {
                            text: modelData.value
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                Controls.Label {
                    text: i18n("CLI commands")
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5

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

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 2
            visible: !page.loading && page.providers.length === 0 && page.errorText.length === 0
            icon.name: "view-list-details"
            text: i18n("No providers reported")
            explanation: i18n("codexbar did not return any providers.")
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 2
            visible: page.providers.length > 0 && page.visibleProviders.length === 0
            icon.name: "search"
            text: i18n("No matching providers")
            explanation: i18n("No provider matches \"%1\".", page.filterText)
        }

        Repeater {
            model: page.visibleProviders

            delegate: Components.ProviderConfigRow {
                configPage: page
            }
        }
    }
}
