import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components

// The AI Insights analysis page inside the popup. FullRepresentation owns the
// navigation; this page only asks to go back. The saved insight keeps no copy
// of the usage it was written from, so its context never cites live data.
ColumnLayout {
    id: view
    objectName: "aiInsightsView"

    required property var applet
    // The view Back returns to: "Overview" or the provider's title.
    property string backText: ""

    // `keyboard` tells the origin view whether to show its focus ring.
    signal backRequested(bool keyboard)

    function focusBack(keyboard) {
        backButton.forceActiveFocus(keyboard ? Qt.TabFocusReason : Qt.OtherFocusReason)
    }

    function scrollToTop() {
        var flickable = scroll.contentItem as Flickable
        if (flickable) {
            flickable.cancelFlick()
            flickable.contentY = 0
        }
    }

    readonly property var cache: applet.aiInsightsCache
    readonly property bool showsInsight: cache !== null && insightCard.showsInsight
    // The card header already names the service, model, age, and whether the
    // insight is out of date; this only adds what it cannot show.
    readonly property var contextLines: [
        showsInsight ? i18n("Generated %1", applet.monthDayTimeText(cache.generatedAtMs)) : "",
        // The card explains this itself when there is no insight.
        showsInsight && !applet.aiInsightsSnapshot.sufficient
            ? i18n("Not enough current usage data for an insight yet.") : "",
        applet.aiInsightsIntervalHours > 0
            ? i18np("A new insight is generated automatically at most every %1 hour.",
                "A new insight is generated automatically at most every %1 hours.",
                applet.aiInsightsIntervalHours)
            : i18n("A new insight is generated only when you ask for one."),
        i18n("Uses only quota, pace, incident, and 7-day spend and token data. Account names, projects, and paths are never sent.")
    ].filter(function(line) { return line.length > 0 })

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.largeSpacing

    // Escape steps back to the origin view instead of closing the popup.
    Keys.onEscapePressed: function(event) {
        view.backRequested(true)
        event.accepted = true
    }

    PlasmaComponents.ToolButton {
        id: backButton
        objectName: "aiInsightsBackButton"
        Layout.maximumWidth: view.width

        icon.name: "go-previous-symbolic"
        text: view.backText
        display: PlasmaComponents.AbstractButton.TextBesideIcon
        Accessible.name: i18n("Back to %1", view.backText)
        onClicked: view.backRequested(visualFocus)

        PlainToolTip {
            parent: backButton
            visible: backLabel.truncated && (backButton.hovered || backButton.visualFocus)
            plainText: backButton.Accessible.name
        }

        // The default Plasma label parses rich text and inserts mnemonic markup.
        contentItem: RowLayout {
            spacing: backButton.spacing

            Kirigami.Icon {
                source: backButton.icon.name
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
                color: backButton.icon.color
                Layout.alignment: Qt.AlignVCenter
            }

            PlainPlasmaLabel {
                id: backLabel

                text: view.backText
                font: backButton.font
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    PlasmaComponents.ScrollView {
        id: scroll
        objectName: "aiInsightsViewScroll"

        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.max(0, scroll.availableWidth - Kirigami.Units.smallSpacing)
            spacing: Kirigami.Units.largeSpacing

            Components.AiInsightsCard {
                id: insightCard

                applet: view.applet
                detailed: true
            }

            ColumnLayout {
                objectName: "aiInsightsContext"
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlainHeading {
                    text: i18n("About this insight")
                    level: 4
                    type: Kirigami.Heading.Type.Primary
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Repeater {
                    model: view.contextLines

                    delegate: PlainPlasmaLabel {
                        required property var modelData

                        text: modelData
                        opacity: applet.secondaryTextOpacity
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
