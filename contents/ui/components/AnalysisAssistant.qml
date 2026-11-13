import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../AiInsights.js" as AiInsights

ColumnLayout {
    id: assistant
    objectName: "analysisAssistant"

    required property var applet
    property bool answerExpanded: false
    readonly property var cache: applet.aiInsightsCache
    readonly property bool showsAnswer: cache !== null
        && ["current", "stale"].indexOf(applet.aiInsightsCacheState) >= 0
    readonly property bool canGenerate: applet.aiInsightsEnabled && applet.aiInsightsConfigured
        && applet.aiInsightsSnapshot.sufficient && !applet.aiInsightsBusy
    readonly property var questions: [
        {value: "summary", text: i18n("Summarize usage")},
        {value: "changes", text: i18n("What changed this week?")},
        {value: "headroom", text: i18n("How much headroom remains?")},
        {value: "investigate", text: i18n("What should I investigate?")}
    ]

    function questionText(value) {
        return questions.filter(function(item) { return item.value === AiInsights.question(value) })[0].text
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        DisclosureButton {
            id: disclosure
            objectName: "analysisAssistantToggle"
            plainText: i18n("Ask the data")
            expanded: assistant.answerExpanded
            onClicked: assistant.answerExpanded = !assistant.answerExpanded
        }
        Item { Layout.fillWidth: true }
        PlainPlasmaLabel {
            text: i18n("AI Insights")
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
        }
    }

    ColumnLayout {
        visible: assistant.answerExpanded
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            text: i18n("All providers: current quotas and the last 7 complete days versus the previous 7. Independent of the chart filters.")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
        }

        RowLayout {
            visible: applet.aiInsightsEnabled && applet.aiInsightsConfigured
            Layout.fillWidth: true
            PlainComboBox {
                id: question
                objectName: "analysisQuestion"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                model: assistant.questions
                textRole: "text"
                valueRole: "value"
                Accessible.name: i18n("Analysis question")
                enabled: !applet.aiInsightsBusy
            }
            RefreshButton {
                objectName: "aiInsightsGenerateButton"
                iconName: "tools-wizard"
                label: i18n("Generate insight")
                busy: applet.aiInsightsBusy
                enabled: assistant.canGenerate || applet.aiInsightsBusy
                onRequested: applet.generateAiInsight(question.currentValue)
            }
        }

        PlainPlasmaLabel {
            visible: !assistant.canGenerate && !applet.aiInsightsBusy
            text: !applet.aiInsightsEnabled || !applet.aiInsightsConfigured
                ? i18n("Choose an AI provider and model in the AI Insights settings.")
                : i18n("Not enough current usage data for an insight yet.")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        PlainButton {
            visible: !applet.aiInsightsEnabled || !applet.aiInsightsConfigured
            plainText: i18n("Configure…")
            icon.name: "configure"
            onClicked: applet.performAction("settings")
        }

        PlainPlasmaLabel {
            visible: assistant.showsAnswer
            text: assistant.showsAnswer ? assistant.questionText(assistant.cache.question) : ""
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        PlainPlasmaLabel {
            objectName: "aiInsightsSummary"
            visible: assistant.showsAnswer
            text: assistant.showsAnswer ? assistant.cache.summary : ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Repeater {
            model: assistant.showsAnswer ? assistant.cache.highlights : []
            delegate: PlainPlasmaLabel {
                required property var modelData
                text: modelData
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }
        PlainPlasmaLabel {
            visible: assistant.showsAnswer
            text: assistant.showsAnswer
                ? i18n("Generated %1", applet.monthDayTimeText(assistant.cache.generatedAtMs))
                    + " · " + applet.aiInsightsProviderName(assistant.cache.provider)
                    + " · " + AiInsights.modelLabel(assistant.cache.model)
                    + (applet.aiInsightsCacheState === "stale" || applet.aiInsightsErrorReason.length > 0
                        ? " · " + i18n("Out of date") : "") : ""
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        PlainPlasmaLabel {
            visible: applet.aiInsightsEnabled
            text: i18n("Saved answers describe the measurements at generation time. Account names, projects, paths and prompts are never sent.")
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        PlainInlineMessage {
            objectName: "aiInsightsError"
            visible: applet.aiInsightsErrorReason.length > 0 && !applet.aiInsightsBusy
            plainText: applet.aiInsightsErrorText(applet.aiInsightsErrorReason)
            type: Kirigami.MessageType.Warning
            Layout.fillWidth: true
        }
    }
}
