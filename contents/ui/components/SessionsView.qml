import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components

ColumnLayout {
    id: view
    objectName: "sessionsView"

    required property var applet
    readonly property alias labels: sessionLabels
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

    Components.SessionLabels {
        id: sessionLabels
        applet: view.applet
    }

    function copySessionValue(text, valueKey) {
        if (view.applet.privacyMode || text.length === 0) {
            return
        }
        clipboardBuffer.text = text
        clipboardBuffer.selectAll()
        clipboardBuffer.copy()
        clipboardBuffer.deselect()
        copiedValueKey = valueKey
        copiedTimer.restart()
    }

    // The CLI's stable ID is deliberately discarded at the trust boundary, and
    // every remaining display field may collide or change during a refresh.
    // Clear this ephemeral feedback when the snapshot changes rather than
    // attributing it to a different card.
    Connections {
        target: view.applet

        function onPrivacyModeChanged() {
            view.copiedValueKey = ""
            clipboardBuffer.text = ""
        }

        function onSessionsChanged() {
            view.copiedValueKey = ""
            // Ages are relative to the scan that produced them.
            view.sessionClockMs = Date.now()
        }
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
        id: sessionsHeaderRow

        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            Components.PlainHeading {
                text: i18n("Sessions")
                level: 2
                type: Kirigami.Heading.Type.Primary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Components.PlainPlasmaLabel {
                id: sessionsMetaLabel

                text: [view.applet.sessionsLastUpdatedText,
                    i18np("%1 local session", "%1 local sessions", view.applet.sessions.length)]
                    .filter(function(part) { return part.length > 0 })
                    .join(" \u00b7 ")
                font: Kirigami.Theme.smallFont
                opacity: view.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight

                HoverHandler {
                    id: sessionsMetaLabelHover
                }

                PlainToolTip {
                    parent: sessionsMetaLabel
                    visible: sessionsMetaLabel.truncated && sessionsMetaLabelHover.hovered
                    plainText: sessionsMetaLabel.text
                }
            }
        }

        Components.RefreshButton {
            Layout.alignment: Qt.AlignTop
            busy: view.applet.sessionsLoading
            label: i18n("Refresh sessions")
            onRequested: view.applet.refreshSessions()
        }
    }

    PlasmaComponents.ScrollView {
        id: sessionsBodyScroll
        objectName: "sessionsBodyScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        contentWidth: availableWidth
        clip: true
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.max(0, parent.width - Kirigami.Units.smallSpacing)
            height: view.applet.sessions.length > 0
                ? implicitHeight : Math.max(implicitHeight, sessionsBodyScroll.availableHeight)
            spacing: Kirigami.Units.smallSpacing

            Components.PlainInlineMessage {
                visible: view.applet.sessionsErrorText.length > 0
                plainText: view.applet.privateErrorText(view.applet.sessionsErrorText)
                type: Kirigami.MessageType.Error
                Layout.fillWidth: true
            }

            Item {
                visible: view.applet.sessions.length === 0
                    && (view.applet.sessionsLoading || view.applet.sessionsErrorText.length > 0)
                implicitHeight: sessionsBusyIndicator.visible ? sessionsBusyIndicator.implicitHeight : 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                Controls.BusyIndicator {
                    id: sessionsBusyIndicator
                    anchors.centerIn: parent
                    running: parent.visible && view.applet.sessionsLoading
                    visible: running
                }
            }

            Item {
                visible: !view.applet.sessionsLoading
                    && view.applet.sessions.length === 0
                    && view.applet.sessionsErrorText.length === 0
                implicitHeight: emptySessionsPlaceholder.implicitHeight
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Keep the native placeholder together while this item fills the view.
                Components.PlainPlaceholderMessage {
                    id: emptySessionsPlaceholder

                    anchors.centerIn: parent
                    width: parent.width
                    plainText: i18n("No local agent sessions found")
                    plainExplanation: i18n("Sessions appear after a supported local CLI starts recording them.")
                    icon.name: "system-run-symbolic"
                    type: Kirigami.PlaceholderMessage.Type.Informational
                }
            }

            // A count model rebinds cards without losing hover or keyboard
            // focus when a rescan returns the same number of sessions.
            Repeater {
                model: view.applet.presentedSessions.length

                delegate: Rectangle {
                    id: sessionCard

                    required property int index
                    // A count model's modelData is the card's index.
                    required property var modelData
                    readonly property var session: view.applet.presentedSessions[modelData]

                    readonly property bool activeSession: session.state === "active"
                        || session.state === "running" || session.state === "working"
                    readonly property string title: sessionLabels.sessionTitle(session, index)
                    readonly property string subtitle: sessionLabels.sessionSubtitle(
                        session, view.applet.sessionHostsVary)
                    readonly property string titleCopyKey: "title:" + index
                    readonly property color accent: session.provider.length > 0
                        ? view.applet.providerReadableColor(
                            session.provider,
                            Kirigami.Theme.backgroundColor)
                        : view.applet.readableAccentColor(
                            Kirigami.Theme.highlightColor,
                            Kirigami.Theme.backgroundColor)

                    Layout.fillWidth: true
                    Layout.preferredHeight: sessionRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: view.applet.nestedSurfaceRadius
                    // The card reveals its copy action on hover, so the
                    // surface confirms the hover the same way overview rows do.
                    color: view.applet.withAlpha(Kirigami.Theme.textColor,
                        sessionCardHover.hovered ? 0.075 : 0.035)

                    Behavior on color {
                        ColorAnimation {
                            duration: Kirigami.Units.shortDuration
                        }
                    }

                    Accessible.role: Accessible.ListItem
                    Accessible.name: title
                    Accessible.description: subtitle

                    HoverHandler {
                        id: sessionCardHover
                    }

                    RowLayout {
                        id: sessionRow

                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Item {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: sessionTitleValue.implicitHeight
                            Layout.alignment: Qt.AlignTop

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: sessionCard.session.provider.length > 0
                                    ? view.applet.providerIconSource(sessionCard.session.provider)
                                    : "system-run-symbolic"
                                fallback: "system-run-symbolic"
                                isMask: view.applet.providerIconIsMask(sessionCard.session.provider)
                                color: sessionCard.accent
                                width: Kirigami.Units.iconSizes.smallMedium
                                height: width
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Item {
                                id: sessionTitleRow

                                Layout.fillWidth: true
                                implicitHeight: Math.max(sessionTitleValue.implicitHeight,
                                    sessionStateLabel.implicitHeight)

                                Components.CopyableValue {
                                    id: sessionTitleValue

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - sessionStateLabel.width
                                        - Kirigami.Units.smallSpacing)
                                    text: sessionCard.title
                                    fontWeight: Font.DemiBold
                                    copyAccessibleName: i18n("Copy session name")
                                    copyEnabled: !view.applet.privacyMode
                                    copyRevealed: sessionCardHover.hovered
                                    copied: view.copiedValueKey === sessionCard.titleCopyKey
                                    onCopyRequested: function(text) {
                                        view.copySessionValue(text, sessionCard.titleCopyKey)
                                    }
                                }

                                Components.PlainPlasmaLabel {
                                    id: sessionStateLabel

                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width * 0.4)
                                    text: sessionLabels.sessionStateText(sessionCard.session.state)
                                    color: sessionCard.activeSession
                                        ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                                    opacity: sessionCard.activeSession ? 1 : view.applet.secondaryTextOpacity
                                    font.weight: sessionCard.activeSession ? Font.DemiBold : Font.Normal
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight

                                    HoverHandler { id: sessionStateHover }

                                    PlainToolTip {
                                        parent: sessionStateLabel
                                        visible: sessionStateLabel.truncated && sessionStateHover.hovered
                                        plainText: sessionStateLabel.text
                                    }
                                }
                            }

                            Components.PlainPlasmaLabel {
                                id: sessionNameLabel

                                visible: sessionCard.session.sessionName.length > 0
                                    && sessionCard.session.sessionName !== sessionCard.title
                                text: sessionCard.session.sessionName
                                opacity: view.applet.valueTextOpacity
                                Layout.fillWidth: true
                                elide: Text.ElideRight

                                HoverHandler {
                                    id: sessionNameLabelHover
                                }

                                PlainToolTip {
                                    parent: sessionNameLabel
                                    visible: sessionNameLabel.truncated && sessionNameLabelHover.hovered
                                    plainText: sessionNameLabel.text
                                }
                            }

                            // Age competes only with metadata, leaving the title
                            // the space beside its shorter state on the line above.
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: Math.max(sessionSubtitleLabel.implicitHeight,
                                    sessionActivityLabel.implicitHeight)

                                Components.PlainPlasmaLabel {
                                    id: sessionSubtitleLabel

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - sessionActivityLabel.width
                                        - Kirigami.Units.smallSpacing)
                                    visible: sessionCard.subtitle.length > 0
                                    text: sessionCard.subtitle
                                    opacity: view.applet.secondaryTextOpacity
                                    font: Kirigami.Theme.smallFont
                                    elide: Text.ElideRight

                                    HoverHandler { id: sessionSubtitleLabelHover }

                                    PlainToolTip {
                                        parent: sessionSubtitleLabel
                                        visible: sessionSubtitleLabel.truncated && sessionSubtitleLabelHover.hovered
                                        plainText: sessionSubtitleLabel.text
                                    }
                                }

                                Components.PlainPlasmaLabel {
                                    id: sessionActivityLabel

                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width * 0.5)
                                    text: sessionLabels.sessionActivityText(sessionCard.session, view.sessionClockMs)
                                    opacity: view.applet.secondaryTextOpacity
                                    font: Kirigami.Theme.smallFont
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight

                                    HoverHandler { id: sessionActivityHover }

                                    PlainToolTip {
                                        parent: sessionActivityLabel
                                        visible: sessionActivityLabel.truncated && sessionActivityHover.hovered
                                        plainText: sessionActivityLabel.text
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
