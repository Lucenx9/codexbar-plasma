import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

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

    PlasmaComponents.Label {
        visible: detailSection.sectionData.title.length > 0
        text: detailSection.sectionData.title
        textFormat: Text.PlainText
        font.weight: Font.DemiBold
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    Repeater {
        model: detailSection.sectionData.rows

        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: modelData.label
                textFormat: Text.PlainText
                opacity: detailSection.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            ColumnLayout {
                spacing: 0

                PlasmaComponents.Label {
                    text: modelData.value
                    textFormat: Text.PlainText
                    opacity: detailSection.applet.valueTextOpacity
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    visible: modelData.secondaryValue.length > 0
                    text: modelData.secondaryValue
                    textFormat: Text.PlainText
                    opacity: detailSection.applet.secondaryTextOpacity
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideRight
                }
            }
        }
    }

    RowLayout {
        visible: detailSection.chartData
            && (detailSection.chartData.title.length > 0 || detailSection.chartData.unit.length > 0)
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: detailSection.chartData ? detailSection.chartData.title : ""
            textFormat: Text.PlainText
            opacity: detailSection.applet.secondaryTextOpacity
            font.weight: Font.DemiBold
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            visible: detailSection.chartData && detailSection.chartData.unit.length > 0
            text: detailSection.chartData ? detailSection.chartData.unit : ""
            textFormat: Text.PlainText
            opacity: detailSection.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
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
