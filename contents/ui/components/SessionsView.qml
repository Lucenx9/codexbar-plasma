import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components

ColumnLayout {
    id: view

    required property var applet
    property string copiedValueKey: ""
    property double sessionClockMs: Date.now()

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.largeSpacing

    // The age ticker only runs while the tab is visible, so the clock has to
    // catch up when the view returns; otherwise hours-old sessions render as
    // "just now" until the next tick.
    onVisibleChanged: {
        if (visible) {
            sessionClockMs = Date.now()
        }
    }

    function copySessionValue(text, valueKey) {
        if (text.length === 0) {
            return
        }
        clipboardBuffer.text = text
        clipboardBuffer.selectAll()
        clipboardBuffer.copy()
        clipboardBuffer.deselect()
        copiedValueKey = valueKey
        copiedTimer.restart()
    }

    Controls.TextField {
        id: clipboardBuffer

        visible: false
    }

    Timer {
        id: copiedTimer

        interval: 1200
        onTriggered: view.copiedValueKey = ""
    }

    Timer {
        id: sessionAgeTimer

        interval: 30000
        repeat: true
        running: view.visible && view.applet.sessions.length > 0
        onTriggered: view.sessionClockMs = Date.now()
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            PlainHeading {
                text: i18n("Sessions")
                level: 2
                type: Kirigami.Heading.Type.Primary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlainPlasmaLabel {
                text: view.applet.sessionsLastUpdatedText.length > 0
                    ? i18n("%1 - %2", view.applet.sessionsLastUpdatedText,
                        i18np("%1 local session", "%1 local sessions", view.applet.sessions.length))
                    : i18np("%1 local session", "%1 local sessions", view.applet.sessions.length)
                opacity: view.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            enabled: !view.applet.sessionsLoading
            Accessible.name: i18n("Refresh sessions")
            onClicked: view.applet.refreshSessions()
        }
    }

    Components.PlainInlineMessage {
        visible: view.applet.sessionsErrorText.length > 0
        plainText: view.applet.sessionsErrorText
        type: Kirigami.MessageType.Error
        Layout.fillWidth: true
    }

    // Mirrors SpendView: one filler item owns the leftover height so the
    // heading stays pinned to the top while sessions are still loading.
    Item {
        visible: view.applet.sessionsLoading && view.applet.sessions.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true

        Controls.BusyIndicator {
            anchors.centerIn: parent
            running: parent.visible
        }
    }

    PlainPlaceholderMessage {
        visible: !view.applet.sessionsLoading
            && view.applet.sessions.length === 0
            && view.applet.sessionsErrorText.length === 0
        plainText: i18n("No local agent sessions found.")
        plainExplanation: i18n("Sessions appear after a supported local CLI starts recording them.")
        icon.name: "system-run-symbolic"
        type: Kirigami.PlaceholderMessage.Type.Informational
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    PlasmaComponents.ScrollView {
        visible: view.applet.sessions.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.max(0, parent.width - Kirigami.Units.smallSpacing)
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: view.applet.sessions

                delegate: Rectangle {
                    id: sessionCard

                    required property int index
                    required property var modelData

                    readonly property bool activeSession: modelData.state === "active"
                    // A refresh can replace and reorder the sessions array
                    // inside the 1.2 s confirmation window, so the copied
                    // marker must key on the session identity rather than the
                    // delegate index or it lights up the wrong card.
                    readonly property string sessionCopyID: modelData.provider + ":"
                        + modelData.projectName + ":" + modelData.sessionName + ":"
                        + modelData.activityAt
                    readonly property string titleCopyKey: "title:" + sessionCopyID
                    readonly property string detailsCopyKey: "details:" + sessionCopyID
                    readonly property color accent: view.applet.providerReadableColor(
                        modelData.provider,
                        Kirigami.Theme.backgroundColor)

                    Layout.fillWidth: true
                    Layout.preferredHeight: sessionRow.implicitHeight + Kirigami.Units.largeSpacing
                    radius: view.applet.nestedSurfaceRadius
                    color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.035)
                    border.width: 1
                    // The state label already carries the accent, so the card
                    // keeps a neutral hairline: one carrier per signal.
                    border.color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.07)

                    Accessible.role: Accessible.ListItem
                    Accessible.name: view.applet.sessionTitle(modelData)
                    Accessible.description: view.applet.sessionSubtitle(modelData)

                    HoverHandler {
                        id: sessionCardHover
                    }

                    RowLayout {
                        id: sessionRow

                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing / 2
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: view.applet.providerIconSource(modelData.provider)
                            fallback: "system-run-symbolic"
                            isMask: view.applet.providerIconIsMask(modelData.provider)
                            color: sessionCard.accent
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            Layout.alignment: Qt.AlignTop
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            CopyableValue {
                                id: sessionTitleValue

                                text: view.applet.sessionTitle(modelData)
                                fontWeight: Font.DemiBold
                                copyAccessibleName: i18n("Copy session name")
                                copyRevealed: sessionCardHover.hovered
                                copied: view.copiedValueKey === sessionCard.titleCopyKey
                                onCopyRequested: function(text) {
                                    view.copySessionValue(text, sessionCard.titleCopyKey)
                                }
                            }

                            PlainPlasmaLabel {
                                visible: modelData.sessionName.length > 0
                                    && modelData.sessionName !== view.applet.sessionTitle(modelData)
                                text: modelData.sessionName
                                opacity: view.applet.valueTextOpacity
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            CopyableValue {
                                text: view.applet.sessionSubtitle(modelData)
                                textOpacity: view.applet.secondaryTextOpacity
                                pixelSize: Kirigami.Theme.smallFont.pixelSize
                                copyAccessibleName: i18n("Copy session details")
                                copyRevealed: sessionCardHover.hovered
                                copied: view.copiedValueKey === sessionCard.detailsCopyKey
                                onCopyRequested: function(text) {
                                    view.copySessionValue(text, sessionCard.detailsCopyKey)
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.alignment: Qt.AlignTop

                            PlainPlasmaLabel {
                                text: modelData.state.length > 0
                                    ? view.applet.capitalize(modelData.state)
                                    : i18n("Unknown")
                                color: sessionCard.activeSession
                                    ? sessionCard.accent
                                    : Kirigami.Theme.textColor
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignRight
                                // Share the title row's height so the state sits
                                // on the title's line instead of above it.
                                verticalAlignment: Text.AlignVCenter
                                Layout.preferredHeight: sessionTitleValue.actionSize
                                Layout.alignment: Qt.AlignRight
                            }

                            PlainPlasmaLabel {
                                text: view.applet.sessionActivityText(modelData, view.sessionClockMs)
                                opacity: view.applet.secondaryTextOpacity
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }
}
