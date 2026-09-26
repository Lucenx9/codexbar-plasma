import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "components" as Components
import "AiInsights.js" as AiInsights
import "CommandLedger.js" as CommandLedger

KCM.SimpleKCM {
    id: page

    readonly property Controls.ScrollView scrollView: contentItem as Controls.ScrollView

    // Reserve the themed scrollbar width even when initial overflow disappears.
    Binding {
        target: page.scrollView
        property: page.mirrored ? "leftPadding" : "rightPadding"
        value: page.scrollView.Controls.ScrollBar.vertical.implicitWidth
    }

    property alias cfg_aiInsightsEnabled: enabledCheck.checked
    property bool cfg_aiInsightsEnabledDefault: false
    property string cfg_aiInsightsProvider: "ollama"
    property string cfg_aiInsightsProviderDefault: "ollama"
    property string cfg_aiInsightsModel: ""
    property string cfg_aiInsightsModelDefault: ""
    property alias cfg_aiInsightsOllamaEndpoint: endpointField.text
    property string cfg_aiInsightsOllamaEndpointDefault: "http://localhost:11434"
    property alias cfg_aiInsightsOpenRouterZdr: zdrCheck.checked
    property bool cfg_aiInsightsOpenRouterZdrDefault: true
    property int cfg_aiInsightsIntervalHours: 0
    property int cfg_aiInsightsIntervalHoursDefault: 0

    readonly property string provider: AiInsights.safeProvider(cfg_aiInsightsProvider)
    readonly property bool cloudProvider: provider !== "ollama"
    readonly property string providerName: messages.providerName(provider)
    readonly property bool localEndpoint: AiInsights.isLocalEndpoint(cfg_aiInsightsOllamaEndpoint)
    property var availableModels: []
    property string keyStatus: ""
    property string actionText: ""
    property bool actionFailed: false
    // Helper processes: one at a time, each with a nonce and a deadline.
    property string activeSource: ""
    property string activeAction: ""
    property int commandSerial: 0
    readonly property bool busy: activeSource.length > 0
    readonly property url scriptUrl: Qt.resolvedUrl("../../scripts/ai-insights.py")
    readonly property bool cacheStored: typeof Plasmoid !== "undefined" && Plasmoid.configuration
        ? String(Plasmoid.configuration.aiInsightsCache || "").length > 0 : false
    property bool cacheCleared: false
    // Models typed for other providers during this settings session, so
    // trying another provider and switching back keeps the earlier model.
    property var modelsByProvider: ({})

    onCfg_aiInsightsModelChanged: {
        if (modelCombo.editText.trim() !== cfg_aiInsightsModel) {
            modelCombo.editText = cfg_aiInsightsModel
        }
    }
    onProviderChanged: {
        retire()
        if (availableModels.length > 0) {
            // A new model list resets the combo; keep the typed or saved model.
            // This also fires during instantiation from creation properties,
            // even when the stored provider equals the default, so an already
            // empty list is left alone instead of churning the combo.
            var model = cfg_aiInsightsModel
            availableModels = []
            modelCombo.editText = model
        }
        keyStatus = ""
        actionText = ""
        Qt.callLater(refreshKeyStatus)
    }
    // A connection test describes the address it listed. An edited address
    // is untested, so a running test is retired and its result cleared.
    onCfg_aiInsightsOllamaEndpointChanged: {
        if (activeAction === "models") {
            retire()
        }
        actionText = ""
        if (availableModels.length > 0) {
            // A new model list resets the combo; keep the typed or saved model.
            var model = cfg_aiInsightsModel
            availableModels = []
            modelCombo.editText = model
        }
    }
    onCfg_aiInsightsEnabledChanged: Qt.callLater(refreshKeyStatus)
    // The cleared flag disables Clear at once; a newly stored insight re-arms
    // the button while the page stays open.
    onCacheStoredChanged: {
        if (cacheStored) {
            cacheCleared = false
        }
    }
    Component.onCompleted: {
        // Offer the stored model as the initial picker entry, so the menu is
        // never empty on open. A connection test replaces it with the live
        // list; a provider or address change empties it until the next test.
        if (cfg_aiInsightsModel.length > 0 && availableModels.length === 0) {
            availableModels = [cfg_aiInsightsModel]
        }
        modelCombo.editText = cfg_aiInsightsModel
        Qt.callLater(refreshKeyStatus)
    }
    Component.onDestruction: retire()

    function selectProvider(value) {
        if (cfg_aiInsightsProvider === value) {
            return
        }
        // Model identifiers belong to one provider.
        var models = modelsByProvider
        models[provider] = cfg_aiInsightsModel
        modelsByProvider = models
        cfg_aiInsightsProvider = value
        cfg_aiInsightsModel = models[value] || ""
    }

    function retire() {
        var source = activeSource
        activeSource = ""
        activeAction = ""
        actionDeadline.stop()
        if (source.length > 0) {
            helperSource.disconnectSource(source)
        }
    }

    function run(action) {
        if (busy) {
            return false
        }
        var command = AiInsights.command(scriptUrl, action, {
            provider: provider,
            endpoint: cfg_aiInsightsOllamaEndpoint,
            prompt: i18n("%1 API key for CodexBar AI Insights", providerName)
        })
        if (command.length === 0) {
            return false
        }
        commandSerial += 1
        activeAction = action
        activeSource = CommandLedger.withRunNonce(command, commandSerial)
        actionDeadline.interval = action === "set-key" ? 340000 : 50000
        actionDeadline.restart()
        helperSource.connectSource(activeSource)
        return true
    }

    // A local Secret Service lookup, never a network request.
    function refreshKeyStatus() {
        if (enabledCheck.checked && cloudProvider && !busy) {
            keyStatus = ""
            run("key-status")
        }
    }

    function report(text, failed) {
        actionText = text
        actionFailed = failed
    }

    function accept(sourceName, data) {
        if (sourceName !== activeSource) {
            return
        }
        var action = activeAction
        retire()
        var stdout = data ? data["stdout"] : ""
        if (action === "key-status") {
            keyStatus = AiInsights.statusReply(stdout, ["present", "absent", "unavailable"])
        } else if (action === "set-key") {
            var saved = AiInsights.statusReply(stdout, ["saved", "cancelled", "invalid", "dialog_missing", "unavailable"])
            if (saved === "saved") {
                report(i18n("API key saved in the system wallet."), false)
            } else if (saved === "invalid") {
                report(i18n("The API key contains unsupported characters."), true)
            } else if (saved === "dialog_missing") {
                report(i18n("kdialog is required to enter an API key."), true)
            } else if (saved === "unavailable") {
                report(i18n("Could not save the API key. The system wallet is unavailable."), true)
            }
            Qt.callLater(refreshKeyStatus)
        } else if (action === "clear-key") {
            var cleared = AiInsights.statusReply(stdout, ["cleared", "unavailable"])
            report(cleared === "cleared" ? i18n("API key removed from the system wallet.")
                : i18n("Could not remove the API key. The system wallet is unavailable."), cleared !== "cleared")
            Qt.callLater(refreshKeyStatus)
        } else if (action === "models") {
            var result = AiInsights.modelsReply(stdout,
                data && data["exit code"] !== undefined ? Number(data["exit code"]) : NaN)
            // The test read the wallet itself, so its answer replaces a status
            // lookup that failed or timed out, for example on a locked wallet.
            if (result.key === "valid") {
                keyStatus = "present"
            } else if (result.reason === "missing_key") {
                keyStatus = "absent"
            } else if (result.reason === "secret_unavailable") {
                keyStatus = "unavailable"
            }
            if (result.outcome !== "ok") {
                report(messages.errorText(result.reason, provider), true)
                return
            }
            var model = cfg_aiInsightsModel
            availableModels = result.models
            // A new model list resets the combo; keep the typed or saved model.
            modelCombo.currentIndex = modelCombo.find(model)
            modelCombo.editText = model
            // The list proves access, not that a generation will succeed, so
            // never report an unlisted model as working.
            if (model.length === 0) {
                report(i18np("Connection works. %1 model available.", "Connection works. %1 models available.",
                    result.models.length), false)
            } else if (!AiInsights.modelListed(provider, model, result.models)) {
                report(i18n("Connection works, but %1 is not in the list of models usable for AI Insights. Choose a listed model.", model), true)
            } else {
                var listed = i18n("Connection works, and %1 is in the list of models usable for AI Insights.", model)
                report(provider === "openrouter" && cfg_aiInsightsOpenRouterZdr
                    ? listed + " " + i18n("Zero Data Retention routing is checked only when an insight is generated.")
                    : listed, false)
            }
        }
    }

    Components.AiInsightsMessages {
        id: messages
    }

    Plasma5Support.DataSource {
        id: helperSource

        engine: "executable"
        interval: 0
        onNewData: function(sourceName, data) {
            page.accept(sourceName, data)
        }
    }

    Timer {
        id: actionDeadline

        onTriggered: {
            var action = page.activeAction
            page.retire()
            if (action !== "key-status") {
                page.report(messages.errorText("timeout", page.provider), true)
            }
        }
    }

    // The page title already names the feature, so the form starts with
    // the switch instead of a repeated section heading.
    Kirigami.FormLayout {
        Controls.CheckBox {
            id: enabledCheck
            objectName: "aiInsightsEnabledCheck"
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Enable AI Insights")
        }

        Components.PlainControlsLabel {
            text: i18n("Shows a short AI-generated summary of your usage in Overview. Nothing is sent and no AI service is contacted while this is off.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Model")
            Kirigami.FormData.isSection: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("AI provider:")
            enabled: enabledCheck.checked
            spacing: 0

            Controls.RadioButton {
                objectName: "aiInsightsOllamaRadio"
                text: i18n("Ollama (local)")
                checked: page.provider === "ollama"
                onToggled: if (checked) page.selectProvider("ollama")
            }

            Controls.RadioButton {
                objectName: "aiInsightsOpenRouterRadio"
                text: "OpenRouter"
                checked: page.provider === "openrouter"
                onToggled: if (checked) page.selectProvider("openrouter")
            }

            Controls.RadioButton {
                objectName: "aiInsightsOpenAIRadio"
                text: "OpenAI"
                checked: page.provider === "openai"
                onToggled: if (checked) page.selectProvider("openai")
            }
        }

        Controls.TextField {
            id: endpointField
            objectName: "aiInsightsEndpointField"
            Kirigami.FormData.label: i18n("Ollama address:")
            visible: !page.cloudProvider
            enabled: enabledCheck.checked
            placeholderText: "http://localhost:11434"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        }

        // Capped like the model row: a wider row would re-center the whole
        // form each time the provider changes.
        RowLayout {
            objectName: "aiInsightsKeyRow"
            Kirigami.FormData.label: i18n("API key:")
            visible: page.cloudProvider
            enabled: enabledCheck.checked && !page.busy
            spacing: Kirigami.Units.smallSpacing
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24

            Components.PlainControlsLabel {
                objectName: "aiInsightsKeyStatus"
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                wrapMode: Text.WordWrap
                text: page.keyStatus === "present" ? i18n("Stored in the system wallet")
                    : (page.keyStatus === "absent" ? i18n("Not set")
                    : (page.keyStatus === "unavailable" ? i18n("System wallet unavailable") : ""))
                opacity: 0.7
            }

            Controls.Button {
                text: page.keyStatus === "present" ? i18n("Replace...") : i18n("Set API key...")
                icon.name: "document-encrypt"
                onClicked: page.run("set-key")
            }

            Controls.Button {
                visible: page.keyStatus === "present"
                text: i18n("Remove")
                icon.name: "edit-delete"
                onClicked: page.run("clear-key")
            }
        }

        // The model field yields width first, so a narrow dialog wraps the
        // form instead of pushing the test button past the viewport.
        RowLayout {
            Kirigami.FormData.label: i18n("Model:")
            enabled: enabledCheck.checked
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24

            Controls.ComboBox {
                id: modelCombo
                objectName: "aiInsightsModelCombo"
                editable: true
                model: page.availableModels
                implicitWidth: Kirigami.Units.gridUnit * 6
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                // The control resets its text on its own while it initializes
                // and whenever its list changes. Only a focused edit is user
                // intent; anything else restores the setting instead of
                // adopting the reset, so opening the page cannot wipe it.
                onEditTextChanged: {
                    if (!modelCombo.activeFocus) {
                        if (editText !== page.cfg_aiInsightsModel) {
                            modelCombo.editText = page.cfg_aiInsightsModel
                        }
                        return
                    }
                    var value = editText.trim()
                    if (value !== page.cfg_aiInsightsModel) {
                        page.cfg_aiInsightsModel = value
                    }
                }
                // A mouse selection can land while the popup holds focus, so
                // commit it explicitly. This fires only for user interaction.
                onActivated: {
                    var value = currentText.trim()
                    if (value.length > 0) {
                        page.cfg_aiInsightsModel = value
                    }
                }
                Accessible.name: i18n("Model")

                // OpenRouter lists hundreds of models; without a cap the list
                // covers the whole settings window. It scrolls past the cap,
                // and typing still completes a model name.
                Binding {
                    target: modelCombo.popup
                    when: modelCombo.popup !== null
                    property: "height"
                    value: Math.min(modelCombo.popup.implicitHeight, Kirigami.Units.gridUnit * 16)
                }
            }

            Controls.Button {
                objectName: "aiInsightsTestButton"
                text: i18n("Test connection")
                icon.name: "network-connect"
                enabled: !page.busy
                onClicked: {
                    page.report("", false)
                    // The button is only enabled while idle, so a refused run
                    // means the command itself is invalid (for example an
                    // oversized Ollama endpoint), not a busy helper.
                    if (!page.run("models")) {
                        page.report(messages.errorText("invalid_input", page.provider), true)
                    }
                }
            }
        }

        Components.PlainControlsLabel {
            visible: page.busy && page.activeAction !== "key-status"
            text: page.activeAction === "set-key" ? i18n("Waiting for the API key dialog...") : i18n("Checking...")
            opacity: 0.7
            Layout.fillWidth: true
        }

        Components.PlainControlsLabel {
            objectName: "aiInsightsActionText"
            visible: page.actionText.length > 0 && !page.busy
            text: page.actionText
            color: page.actionFailed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Controls.CheckBox {
            id: zdrCheck
            objectName: "aiInsightsZdrCheck"
            visible: page.provider === "openrouter"
            enabled: enabledCheck.checked
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Use only Zero Data Retention endpoints")
        }

        Components.PlainControlsLabel {
            text: {
                if (page.provider === "ollama") {
                    return page.localEndpoint
                        ? i18n("Generation uses the Ollama service on this computer. Usage statistics stay on this device.")
                        : i18n("Aggregated usage statistics are sent to the Ollama service at this address. Remote addresses must use https://.")
                }
                var sent = i18n("Only aggregated usage statistics are sent to %1: quotas, reset times, pace forecasts, and weekly spending and tokens per provider. Never account names, emails, projects, file paths, or prompts.", page.providerName)
                var billing = page.provider === "openai"
                    ? i18n("Requests are billed to your OpenAI API account. A ChatGPT subscription does not include API credits.")
                    : i18n("Requests are billed to your OpenRouter credits, at the price of the model you choose. Providers that may collect data are never used.")
                return sent + "\n\n" + billing
            }
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Generation")
            Kirigami.FormData.isSection: true
        }

        Controls.ComboBox {
            id: intervalCombo
            objectName: "aiInsightsIntervalCombo"
            Kirigami.FormData.label: i18n("Frequency:")
            enabled: enabledCheck.checked
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Only on request"), value: 0 },
                { text: i18n("Every 6 hours"), value: 6 },
                { text: i18n("Every 12 hours"), value: 12 },
                { text: i18n("Daily"), value: 24 }
            ]
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(AiInsights.intervalHours(page.cfg_aiInsightsIntervalHours)))
            onActivated: page.cfg_aiInsightsIntervalHours = currentValue
            Connections {
                target: page
                function onCfg_aiInsightsIntervalHoursChanged() {
                    intervalCombo.currentIndex = Math.max(0, intervalCombo.indexOfValue(
                        AiInsights.intervalHours(page.cfg_aiInsightsIntervalHours)))
                }
            }
        }

        Components.PlainControlsLabel {
            text: i18n("Use the button on the AI Insights card to generate on request. Automatic generation never runs more often than the chosen interval, and ordinary usage refreshes do not trigger it.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Controls.Button {
            objectName: "aiInsightsClearButton"
            Kirigami.FormData.label: i18n("Saved insight:")
            text: i18n("Clear")
            Accessible.name: i18n("Clear saved insight")
            icon.name: "edit-clear-history"
            enabled: page.cacheStored && !page.cacheCleared
            onClicked: {
                Plasmoid.configuration.aiInsightsCache = ""
                page.cacheCleared = true
            }
        }
    }
}
