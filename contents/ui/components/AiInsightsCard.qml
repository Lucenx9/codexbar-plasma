import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../AiInsights.js" as AiInsights

// Presentation only: main.qml owns generation, persistence, and error text.
// Generated text is untrusted and always rendered as plain text.
Rectangle {
    id: card
    objectName: "aiInsightsCard"

    required property var applet

    readonly property var cache: applet.aiInsightsCache
    readonly property string cacheState: applet.aiInsightsCacheState
    readonly property bool showsInsight: cache !== null
        && (cacheState === "current" || cacheState === "stale")
    readonly property bool stale: showsInsight
        && (cacheState === "stale" || applet.aiInsightsErrorReason.length > 0)
    readonly property bool canGenerate: applet.aiInsightsConfigured
        && applet.aiInsightsSnapshot.sufficient && !applet.aiInsightsBusy
    readonly property string emptyText: {
        if (!applet.aiInsightsConfigured)
            return i18n("Choose an AI provider and model in the AI Insights settings.")
        if (!applet.aiInsightsSnapshot.sufficient)
            return i18n("Not enough current usage data for an insight yet.")
        if (cacheState === "otherContext")
            return i18n("The saved insight belongs to other settings or another language. Generate a new one when needed.")
        return i18n("No insight generated yet.")
    }
    // Relative age, like the provider rows; an out-of-date insight says so
    // here instead of in an extra line that would lengthen the card.
    readonly property string metaText: {
        if (!showsInsight)
            return ""
        var age = applet.sessionActivityText({ activityMs: cache.generatedAtMs }, applet.panelClockMs)
        var source = i18n("%1 - %2", applet.aiInsightsProviderName(cache.provider), AiInsights.modelLabel(cache.model))
        return i18n("%1 - %2", source, stale ? i18n("Out of date, %1", age) : age)
    }
    readonly property int highlightCount: showsInsight ? cache.highlights.length : 0
    // Highlights stay one click away, so the card reads in a glance.
    property bool detailsExpanded: false

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.preferredHeight: implicitHeight
    radius: applet.roundedSurfaceRadius
    color: applet.withAlpha(Kirigami.Theme.textColor, 0.035)

    Controls.Action {
        id: configureAction

        text: i18n("Configure...")
        icon.name: "configure"
        onTriggered: applet.performAction("settings")
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        anchors.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
        // Center the generate icon on the Overview rows' chevrons.
        anchors.rightMargin: Math.max(0, Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
            + (Kirigami.Units.iconSizes.small - generateButton.implicitWidth) / 2)
        spacing: Kirigami.Units.smallSpacing

        // The header mirrors the Overview rows: an identity tile, then the
        // title column, so the card reads as part of the same list.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    + Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignTop
                radius: applet.nestedSurfaceRadius
                color: applet.withAlpha(Kirigami.Theme.highlightColor, 0.12)

                Kirigami.Icon {
                    anchors.centerIn: parent
                    // A hint bulb: the card's identity. The wand stays on the
                    // generate action.
                    source: "games-hint"
                    fallback: "tools-wizard"
                    isMask: true
                    color: Kirigami.Theme.highlightColor
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: Kirigami.Units.iconSizes.smallMedium
                    Accessible.ignored: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlainHeading {
                        text: i18n("AI Insights")
                        level: 4
                        type: Kirigami.Heading.Type.Primary
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }

                    // A quiet badge instead of "(Beta)" in the title.
                    Rectangle {
                        objectName: "aiInsightsBetaBadge"
                        implicitWidth: betaLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                        implicitHeight: betaLabel.implicitHeight + Kirigami.Units.smallSpacing / 2
                        Layout.alignment: Qt.AlignVCenter
                        radius: height / 2
                        color: applet.withAlpha(Kirigami.Theme.highlightColor, 0.14)

                        PlainPlasmaLabel {
                            id: betaLabel

                            anchors.centerIn: parent
                            text: i18n("Beta")
                            font: Kirigami.Theme.smallFont
                            opacity: applet.valueTextOpacity
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                PlainPlasmaLabel {
                    visible: card.metaText.length > 0
                    text: card.metaText
                    opacity: applet.secondaryTextOpacity
                    font: Kirigami.Theme.smallFont
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            // A distinct icon: this button calls a possibly billed AI service,
            // while the Overview refresh button only refreshes usage.
            RefreshButton {
                id: generateButton
                objectName: "aiInsightsGenerateButton"
                Layout.alignment: Qt.AlignTop
                iconName: "tools-wizard"
                visible: applet.aiInsightsConfigured && card.showsInsight
                enabled: card.canGenerate || applet.aiInsightsBusy
                busy: applet.aiInsightsBusy
                label: card.showsInsight ? i18n("Regenerate insight") : i18n("Generate insight")
                onRequested: applet.generateAiInsight()
            }
        }

        RowLayout {
            visible: applet.aiInsightsBusy && !card.showsInsight
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.BusyIndicator {
                running: parent.visible
                Accessible.name: i18n("Generating insight...")
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlainPlasmaLabel {
                text: i18n("Generating insight...")
                opacity: applet.secondaryTextOpacity
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }

        PlainPlasmaLabel {
            objectName: "aiInsightsEmptyText"
            visible: !card.showsInsight && !applet.aiInsightsBusy
            text: card.emptyText
            opacity: applet.secondaryTextOpacity
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        PlasmaComponents.Button {
            visible: !applet.aiInsightsConfigured
            action: configureAction
        }

        // First use: a labeled action instead of only the header icon.
        PlasmaComponents.Button {
            objectName: "aiInsightsFirstGenerateButton"
            visible: applet.aiInsightsConfigured && !card.showsInsight && !applet.aiInsightsBusy
                && applet.aiInsightsSnapshot.sufficient
            text: i18n("Generate insight")
            icon.name: "tools-wizard"
            onClicked: applet.generateAiInsight()
        }

        // Dims while a new insight is generated, then settles as the reply
        // replaces it. Opening the popup never animates.
        ColumnLayout {
            objectName: "aiInsightsBody"
            visible: card.showsInsight
            opacity: applet.aiInsightsBusy ? applet.secondaryTextOpacity : 1
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Behavior on opacity {
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }

            PlainPlasmaLabel {
                objectName: "aiInsightsSummary"
                text: card.showsInsight ? card.cache.summary : ""
                opacity: card.stale ? applet.valueTextOpacity : 1
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            // A disclosure, like the cost details: flat, so it never
            // outweighs the summary it expands.
            PlainButton {
                objectName: "aiInsightsDetailsToggle"
                flat: true
                visible: card.highlightCount > 0
                plainText: card.detailsExpanded ? i18n("Hide details") : i18n("Show details")
                icon.name: card.detailsExpanded ? "arrow-up" : "arrow-down"
                Accessible.checkable: true
                Accessible.checked: card.detailsExpanded
                onClicked: card.detailsExpanded = !card.detailsExpanded
            }

            Repeater {
                model: card.showsInsight && card.detailsExpanded ? card.cache.highlights : []

                // A separate bullet keeps wrapped lines aligned with the text.
                delegate: RowLayout {
                    id: highlightRow

                    required property var modelData

                    opacity: card.stale ? applet.valueTextOpacity : 1
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    // Centered on the first line of text.
                    Item {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: Kirigami.Units.smallSpacing * 1.5
                        implicitHeight: highlightText.implicitHeight / Math.max(1, highlightText.lineCount)

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.implicitWidth
                            height: width
                            radius: width / 2
                            color: Kirigami.Theme.highlightColor
                        }
                    }

                    PlainPlasmaLabel {
                        id: highlightText

                        text: highlightRow.modelData
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }
            }
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
