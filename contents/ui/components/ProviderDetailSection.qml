import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: detailSection

    required property var applet
    required property var providerData
    required property var modelData

    readonly property var sectionData: modelData
    readonly property var chartData: sectionData.chart || null
    readonly property var chartPoints: chartData ? chartData.points : []
    readonly property color accent: applet.providerReadableColor(
        providerData ? providerData.provider : "",
        Kirigami.Theme.backgroundColor)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    PlainPlasmaLabel {
        visible: detailSection.sectionData.title.length > 0
        text: detailSection.sectionData.title
        font.weight: Font.DemiBold
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    Repeater {
        model: detailSection.sectionData.rows

        delegate: Item {
            id: detailRow

            required property var modelData

            Layout.fillWidth: true
            implicitWidth: detailLabel.implicitWidth + Kirigami.Units.smallSpacing + detailValues.implicitWidth
            implicitHeight: Math.max(detailLabel.implicitHeight, detailValues.implicitHeight)

            PlainPlasmaLabel {
                id: detailLabel

                text: modelData.label
                opacity: detailSection.applet.secondaryTextOpacity
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - detailValues.width - Kirigami.Units.smallSpacing)
                elide: Text.ElideRight
            }

            ColumnLayout {
                id: detailValues

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // The plain Item owns geometry; width-dependent layout hints recurse.
                width: Math.min(implicitWidth, detailRow.width / 2)
                spacing: 0

                PlainPlasmaLabel {
                    text: modelData.value
                    opacity: detailSection.applet.valueTextOpacity
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideRight
                }

                PlainPlasmaLabel {
                    visible: modelData.secondaryValue.length > 0
                    text: modelData.secondaryValue
                    opacity: detailSection.applet.secondaryTextOpacity
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideRight
                }
            }
        }
    }

    Item {
        id: chartHeading

        visible: detailSection.chartData
            && (detailSection.chartData.title.length > 0 || detailSection.chartData.unit.length > 0)
        Layout.fillWidth: true
        implicitWidth: chartTitle.implicitWidth + Kirigami.Units.smallSpacing + chartUnit.implicitWidth
        implicitHeight: Math.max(chartTitle.implicitHeight, chartUnit.implicitHeight)

        PlainPlasmaLabel {
            id: chartTitle

            text: detailSection.chartData ? detailSection.chartData.title : ""
            opacity: detailSection.applet.secondaryTextOpacity
            font.weight: Font.DemiBold
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - chartUnit.width
                - (chartUnit.visible ? Kirigami.Units.smallSpacing : 0))
            elide: Text.ElideRight
        }

        PlainPlasmaLabel {
            id: chartUnit

            visible: detailSection.chartData && detailSection.chartData.unit.length > 0
            text: detailSection.chartData ? detailSection.chartData.unit : ""
            opacity: detailSection.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, chartHeading.width / 2)
            elide: Text.ElideRight
        }
    }

    InteractiveChart {
        visible: detailSection.chartData !== null
        applet: detailSection.applet
        points: detailSection.chartPoints
        accent: detailSection.accent
        kind: detailSection.chartData ? detailSection.chartData.kind : "bar"
        valueSuffix: detailSection.chartData ? detailSection.chartData.unit : ""
        accessibleTitle: detailSection.chartData && detailSection.chartData.title.length > 0
            ? detailSection.chartData.title
            : i18n("Usage chart")
    }
}
