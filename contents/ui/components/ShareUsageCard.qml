import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: card

    required property var presentation
    readonly property bool wide: width >= Kirigami.Units.gridUnit * 38
    readonly property real inset: Kirigami.Units.gridUnit * (wide ? 2.5 : 1.5)
    readonly property color ink: Kirigami.Theme.textColor
    readonly property color ruleColor: withAlpha(ink, 0.12)
    readonly property color secondaryInk: withAlpha(ink, 0.72)

    function withAlpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity)
    }

    objectName: "shareUsageCard"
    implicitHeight: content.implicitHeight + inset * 2
    color: Kirigami.Theme.backgroundColor
    radius: Kirigami.Units.gridUnit
    border.color: ruleColor

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.inset
        spacing: Kirigami.Units.gridUnit * 1.5

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: "office-chart-bar"
                color: Kirigami.Theme.highlightColor
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            PlainHeading {
                text: "CodexBar"
                type: Kirigami.Heading.Type.Primary
                level: 2
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Rectangle {
                implicitWidth: period.implicitWidth + Kirigami.Units.largeSpacing * 2
                implicitHeight: period.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: height / 2
                color: "transparent"
                border.color: card.ruleColor
                PlainPlasmaLabel {
                    id: period
                    anchors.centerIn: parent
                    text: card.presentation.period
                    color: card.secondaryInk
                    font.weight: Font.Medium
                }
            }
        }

        GridLayout {
            columns: card.wide ? 2 : 1
            columnSpacing: Kirigami.Units.gridUnit * 2
            rowSpacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                spacing: Kirigami.Units.smallSpacing
                PlainPlasmaLabel {
                    text: card.presentation.tokensTitle
                    color: card.secondaryInk
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                PlainPlasmaLabel {
                    text: card.presentation.tokens
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * (card.wide ? 5 : 3.8)
                    font.weight: Font.Medium
                    font.letterSpacing: -Kirigami.Theme.defaultFont.pixelSize * (card.wide ? 5 : 3.8) * 0.025
                    font.features: {
                        "tnum": 1
                    }
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.alignment: Qt.AlignTop
                spacing: Kirigami.Units.smallSpacing
                PlainPlasmaLabel {
                    text: card.presentation.costTitle
                    color: card.secondaryInk
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                PlainPlasmaLabel {
                    text: card.presentation.cost
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            color: card.ruleColor
            implicitHeight: 1
            Layout.fillWidth: true
        }

        GridLayout {
            columns: card.wide ? 2 : 1
            columnSpacing: Kirigami.Units.gridUnit * 2
            rowSpacing: Kirigami.Units.gridUnit * 1.5
            Layout.fillWidth: true
            Repeater {
                model: card.presentation.sections
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing
                    PlainPlasmaLabel {
                        text: modelData.title
                        color: card.secondaryInk
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                    }
                    Repeater {
                        model: modelData.rows
                        Rectangle {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: rowContent.implicitHeight + Kirigami.Units.largeSpacing * 2
                            radius: Kirigami.Units.cornerRadius * 1.5
                            color: card.withAlpha(card.ink, 0.04)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: Kirigami.Units.largeSpacing
                                width: Kirigami.Units.smallSpacing / 2
                                radius: width / 2
                                color: row.modelData.color
                            }
                            ColumnLayout {
                                id: rowContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: Kirigami.Units.largeSpacing * 2
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                anchors.topMargin: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.smallSpacing / 2
                                PlainPlasmaLabel {
                                    text: row.modelData.title
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                PlainPlasmaLabel {
                                    text: row.modelData.detail
                                    color: card.secondaryInk
                                    font.features: {
                                        "tnum": 1
                                    }
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                    PlainPlasmaLabel {
                        text: modelData.extra
                        visible: text.length > 0
                        color: card.secondaryInk
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlainPlasmaLabel {
                text: card.presentation.notice
                visible: text.length > 0
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            PlainPlasmaLabel {
                text: card.presentation.privacy
                color: card.secondaryInk
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
        Rectangle {
            color: card.ruleColor
            implicitHeight: 1
            Layout.fillWidth: true
        }
        GridLayout {
            Layout.fillWidth: true
            columns: card.wide ? 2 : 1
            rowSpacing: Kirigami.Units.smallSpacing
            PlainPlasmaLabel {
                text: card.presentation.attribution
                color: card.secondaryInk
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }
            PlainPlasmaLabel {
                text: card.presentation.created
                color: card.secondaryInk
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                horizontalAlignment: card.wide ? Text.AlignRight : Text.AlignLeft
            }
        }
    }
}
