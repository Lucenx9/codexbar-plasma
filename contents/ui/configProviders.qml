import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

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
    // running command source -> descriptor { kind, provider, desiredEnabled }
    property var commands: ({})
    property string selectedProviderID: ""

    readonly property var visibleProviders: filterProviders(providers, filterText)
    readonly property int enabledCount: countEnabled(providers)
    readonly property var selectedProvider: providerByID(selectedProviderID)

    Component.onCompleted: reload()

    function reload() {
        if (commandPath.length === 0) {
            errorText = i18n("Set the codexbar command path in the General page.")
            providers = []
            return
        }
        loading = true
        errorText = ""
        statusText = ""
        var command = [
            shellQuote(commandPath),
            "config",
            "providers",
            "--format",
            "json",
            "--json-only"
        ].join(" ")
        runCommand(command, { kind: "list" })
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
            "key=$(kdialog --password " + shellQuote(prompt) + " 2>/dev/null)",
            "status=$?",
            "if [ \"$status\" -ne 0 ] || [ -z \"$key\" ]; then printf '%s\\n' '{\"cancelled\":true}'; exit 0; fi",
            "printf '%s' \"$key\" | " + shellQuote(commandPath) + " config set-api-key --provider " + shellQuote(providerID) + " --stdin --format json --json-only"
        ].join("; ")
        var command = ["sh", "-lc", shellQuote(script)].join(" ")
        runCommand(command, { kind: "setApiKey", provider: providerID })
    }

    function runCommand(command, descriptor) {
        var existing = copyObject(commands)
        existing[command] = descriptor
        commands = existing
        configSource.connectSource(command)
    }

    function handleData(sourceName, stdoutText, stderrText) {
        var descriptor = commands[sourceName]
        if (!descriptor) {
            return
        }
        var withoutCommand = copyObject(commands)
        delete withoutCommand[sourceName]
        commands = withoutCommand

        if (descriptor.kind === "list") {
            handleListResult(stdoutText, stderrText)
        } else if (descriptor.kind === "toggle") {
            handleToggleResult(descriptor, stdoutText, stderrText)
        } else if (descriptor.kind === "setApiKey") {
            handleSetApiKeyResult(descriptor, stdoutText, stderrText)
        }
    }

    function handleListResult(stdoutText, stderrText) {
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
                defaultEnabled: item.defaultEnabled === true
            })
        }
        providers = next
        if (!providerByID(selectedProviderID)) {
            selectedProviderID = firstSelectableProvider(next)
        }
        errorText = ""
    }

    function handleToggleResult(descriptor, stdoutText, stderrText) {
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
        return pending[providerID] === true
    }

    function visualEnabled(providerID, fallback) {
        if (pendingDesired[providerID] !== undefined) {
            return pendingDesired[providerID] === true
        }
        return fallback === true
    }

    function markPending(providerID, value, desiredEnabled) {
        var next = copyObject(pending)
        var desired = copyObject(pendingDesired)
        if (value) {
            next[providerID] = true
            desired[providerID] = desiredEnabled === true
        } else {
            delete next[providerID]
            delete desired[providerID]
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
            copy[key] = item[key]
        }
        return copy
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
        if (supportsApiKeySetup(item.provider)) {
            rows.push({ title: i18n("Set API key..."), icon: "password-show-off", action: "set-api-key", enabled: !isPending(item.provider) })
        }
        var docs = providerDocsUrl(item.provider)
        if (docs.length > 0) {
            rows.push({ title: i18n("Docs"), icon: "help-contents", action: "docs", url: docs, enabled: true })
        }
        var dashboard = providerDashboardUrl(item.provider)
        if (dashboard.length > 0) {
            rows.push({ title: i18n("Dashboard"), icon: "view-statistics", action: "dashboard", url: dashboard, enabled: true })
        }
        var login = providerLoginUrl(item.provider)
        if (login.length > 0) {
            rows.push({ title: item.enabled ? i18n("Account") : i18n("Login"), icon: "internet-services", action: "login", url: login, enabled: true })
        }
        return rows
    }

    function performProviderAction(row) {
        if (!row || !selectedProvider) {
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

    function providerDashboardUrl(providerID) {
        switch (providerKey(providerID)) {
        case "codex":
        case "openai":
            return "https://platform.openai.com/usage"
        case "claude":
            return "https://console.anthropic.com/settings/usage"
        case "cursor":
            return "https://cursor.com/dashboard?tab=usage"
        case "opencode":
        case "opencodego":
            return "https://opencode.ai"
        case "gemini":
            return "https://aistudio.google.com/usage"
        case "factory":
            return "https://app.factory.ai/settings/billing"
        case "copilot":
            return "https://github.com/settings/copilot"
        case "elevenlabs":
            return "https://elevenlabs.io/app/developers/usage"
        case "openrouter":
            return "https://openrouter.ai/activity"
        case "deepgram":
            return "https://console.deepgram.com/usage"
        case "zai":
            return "https://z.ai/manage-apikey/apikey-list"
        case "minimax":
            return "https://platform.minimaxi.com/user-center/basic-information/interface-key"
        case "mistral":
            return "https://console.mistral.ai/usage"
        case "bedrock":
            return "https://console.aws.amazon.com/costmanagement/home"
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
        case "factory":
            return Qt.rgba(1, 107 / 255, 53 / 255, 1)
        case "grok":
            return Qt.rgba(16 / 255, 163 / 255, 127 / 255, 1)
        case "groq":
            return Qt.rgba(245 / 255, 104 / 255, 68 / 255, 1)
        case "kilo":
            return Qt.rgba(242 / 255, 112 / 255, 39 / 255, 1)
        case "kimi":
        case "minimax":
            return Qt.rgba(254 / 255, 96 / 255, 60 / 255, 1)
        case "kiro":
            return Qt.rgba(1, 153 / 255, 0, 1)
        case "manus":
            return Qt.rgba(52 / 255, 50 / 255, 45 / 255, 1)
        case "vertexai":
            return Qt.rgba(66 / 255, 133 / 255, 244 / 255, 1)
        case "zai":
            return Qt.rgba(232 / 255, 90 / 255, 106 / 255, 1)
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

    Plasma5Support.DataSource {
        id: configSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var stdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            disconnectSource(sourceName)
            page.handleData(sourceName, stdoutText, stderrText)
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
                placeholderText: i18n("Search providers…")
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
                            ? (page.selectedProvider.enabled ? i18n("%1 · enabled", page.selectedProvider.provider) : i18n("%1 · disabled", page.selectedProvider.provider))
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
            explanation: i18n("No provider matches “%1”.", page.filterText)
        }

        Repeater {
            model: page.visibleProviders

            delegate: Controls.ItemDelegate {
                id: providerRow

                required property var modelData

                Layout.fillWidth: true
                hoverEnabled: true
                down: false
                highlighted: providerRow.modelData.provider === page.selectedProviderID
                onClicked: page.selectedProviderID = providerRow.modelData.provider

                contentItem: RowLayout {
                    spacing: Kirigami.Units.gridUnit

                    Kirigami.Icon {
                        source: page.providerIconSource(providerRow.modelData.provider)
                        isMask: true
                        color: page.providerColor(providerRow.modelData.provider)
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Controls.Label {
                            text: providerRow.modelData.displayName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Controls.Label {
                            text: providerRow.modelData.defaultEnabled
                                ? i18n("%1 · on by default", providerRow.modelData.provider)
                                : providerRow.modelData.provider
                            elide: Text.ElideRight
                            opacity: 0.6
                            font: Kirigami.Theme.smallFont
                            Layout.fillWidth: true
                        }
                    }

                    Controls.BusyIndicator {
                        running: page.isPending(providerRow.modelData.provider)
                        visible: running
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    Controls.Switch {
                        checked: page.visualEnabled(providerRow.modelData.provider, providerRow.modelData.enabled)
                        enabled: !page.isPending(providerRow.modelData.provider)
                        onClicked: page.setEnabled(providerRow.modelData.provider, !providerRow.modelData.enabled)
                    }
                }
            }
        }
    }
}
