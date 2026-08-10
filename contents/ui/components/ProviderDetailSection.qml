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
    readonly property real maximumChartValue: chartMaximum(chartPoints)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    function chartMaximum(points) {
        var maximum = 0
        for (var i = 0; i < points.length; i++) {
            var value = Number(points[i].value)
            if (isFinite(value) && value > maximum) {
                maximum = value
            }
        }
        return maximum
    }

    function chartFraction(value) {
        var numericValue = Number(value)
        if (!isFinite(numericValue) || numericValue <= 0 || maximumChartValue <= 0) {
            return 0
        }
        return Math.min(1, numericValue / maximumChartValue)
    }

    PlasmaComponents.Label {
        visible: detailSection.sectionData.title.length > 0
        text: detailSection.sectionData.title
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
                opacity: detailSection.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            ColumnLayout {
                spacing: 0

                PlasmaComponents.Label {
                    text: modelData.value
                    opacity: detailSection.applet.valueTextOpacity
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    visible: modelData.secondaryValue.length > 0
                    text: modelData.secondaryValue
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
            opacity: detailSection.applet.secondaryTextOpacity
            font.weight: Font.DemiBold
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            visible: detailSection.chartData && detailSection.chartData.unit.length > 0
            text: detailSection.chartData ? detailSection.chartData.unit : ""
            opacity: detailSection.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Canvas {
        id: detailChart

        visible: detailSection.chartData !== null
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        Connections {
            target: detailSection
            function onChartPointsChanged() { detailChart.requestPaint() }
            function onMaximumChartValueChanged() { detailChart.requestPaint() }
            function onAccentChanged() { detailChart.requestPaint() }
        }

        onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            if (!detailSection.chartData
                    || width <= 0
                    || height <= 0) {
                return
            }

            var points = detailSection.chartPoints
            var baseline = height - 1
            context.fillStyle = detailSection.applet.canvasColor(Kirigami.Theme.textColor, 0.12)
            context.fillRect(0, baseline, width, 1)
            if (points.length === 0) {
                return
            }

            if (modelData.chart.kind === "line") {
                context.strokeStyle = detailSection.applet.canvasColor(detailSection.accent, 0.9)
                context.fillStyle = detailSection.applet.canvasColor(detailSection.accent, 1)
                context.lineWidth = 2
                context.lineCap = "round"
                context.lineJoin = "round"
                context.beginPath()
                for (var lineIndex = 0; lineIndex < points.length; lineIndex++) {
                    var lineX = points.length === 1 ? width / 2 : width * lineIndex / (points.length - 1)
                    var lineY = baseline - (height - 3) * detailSection.chartFraction(points[lineIndex].value)
                    if (lineIndex === 0) {
                        context.moveTo(lineX, lineY)
                    } else {
                        context.lineTo(lineX, lineY)
                    }
                }
                context.stroke()
                for (var dotIndex = 0; dotIndex < points.length; dotIndex++) {
                    var dotX = points.length === 1 ? width / 2 : width * dotIndex / (points.length - 1)
                    var dotY = baseline - (height - 3) * detailSection.chartFraction(points[dotIndex].value)
                    context.beginPath()
                    context.arc(dotX, dotY, 1.5, 0, Math.PI * 2)
                    context.fill()
                }
                return
            }

            var gap = Math.max(
                2,
                Math.min(4, Math.floor(width / Math.max(1, points.length * 5))))
            var barWidth = Math.max(1, (width - gap * Math.max(0, points.length - 1)) / points.length)
            context.fillStyle = detailSection.applet.buildChartBarGradient(
                context, detailSection.accent, baseline, 0.78, 0.36)
            for (var barIndex = 0; barIndex < points.length; barIndex++) {
                var fraction = detailSection.chartFraction(points[barIndex].value)
                var barHeight = fraction > 0 ? Math.max(2, (height - 3) * fraction) : 1
                detailSection.applet.paintRoundedTopBar(
                    context,
                    barIndex * (barWidth + gap),
                    baseline,
                    barWidth,
                    barHeight,
                    Kirigami.Units.smallSpacing / 2)
            }
        }
    }

    RowLayout {
        visible: detailChart.visible && detailSection.chartPoints.length > 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: detailSection.chartPoints.length > 0 ? detailSection.chartPoints[0].label : ""
            opacity: detailSection.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            text: detailSection.chartPoints.length > 1
                ? detailSection.chartPoints[detailSection.chartPoints.length - 1].label
                : ""
            opacity: detailSection.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}
