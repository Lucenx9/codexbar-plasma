import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ChartScale.js" as ChartScale
import "../CostChart.mjs" as CostChart
import "../ChartLines.mjs" as ChartLines
import "../ProviderNormalizer.mjs" as Normalizer

ColumnLayout {
    id: chart

    required property var applet
    required property var points
    property var lineSeries: null
    property var axisLabels: []
    readonly property bool hasLineSeries: kind === "line" && lineSeries !== null
    readonly property real axisWidth: axisLabels.length === 3
        ? Math.min(Kirigami.Units.gridUnit * 6, Math.max(
            Math.ceil(chartReadoutFontMetrics.advanceWidth(axisLabels[0])),
            Math.ceil(chartReadoutFontMetrics.advanceWidth(axisLabels[1])),
            Math.ceil(chartReadoutFontMetrics.advanceWidth(axisLabels[2])))) + Kirigami.Units.smallSpacing * 2 : 0
    onLineSeriesChanged: plot.requestPaint()
    property var seriesColors: ({})
    onSeriesColorsChanged: plot.requestPaint()
    required property color accent
    property string kind: "bar"
    property string accessibleTitle: ""
    property string valueSuffix: ""
    property bool showPeak: false
    readonly property int peakIndex: showPeak ? ChartScale.maximumIndex(points) : -1
    // Owners that plot a long range can raise this; the default keeps the
    // inline provider detail charts at their existing size.
    property real plotHeight: Kirigami.Units.gridUnit * 3
    property int selectedIndex: -1
    property int hoveredIndex: -1
    readonly property int activeIndex: hoveredIndex >= 0 ? hoveredIndex : selectedIndex
    // The readout holds the last inspected point so it survives the fade-out.
    // Binding its text to hasActivePoint would empty the row on the same signal
    // that starts the fade, leaving the common hover-exit path still blinking.
    // Bounds are rechecked on read: a shorter points array may strand this.
    property int readoutIndex: -1
    readonly property bool readoutValid: readoutIndex >= 0 && readoutIndex < pointCount
    readonly property int pointCount: points && typeof points.length === "number" ? points.length : 0
    readonly property bool hasActivePoint: activeIndex >= 0 && activeIndex < pointCount
    readonly property var valueDomain: hasLineSeries ? ChartLines.domain(lineSeries) : ChartScale.domain(points)
    readonly property real lineMarkerInset: 3.5
    readonly property color guideColor: Kirigami.Theme.textColor
    readonly property color lineBackdrop: Kirigami.Theme.backgroundColor

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    // Bounds are rechecked inline rather than through hasActivePoint: a
    // binding that depends on activeIndex is still stale while this handler,
    // fired by the same change, is running.
    onActiveIndexChanged: if (activeIndex >= 0 && activeIndex < pointCount) {
        readoutIndex = activeIndex
    }

    function pointValue(point) {
        return ChartScale.pointValue(point)
    }

    // Calendar keys use the locale's short date; other labels stay as sent.
    function pointLabel(point) {
        var label = point && point.label ? String(point.label) : ""
        var date = Normalizer.calendarKeyLocalDate(label)
        return date ? date.toLocaleDateString(Qt.locale(), Locale.ShortFormat) : label
    }

    function pointDisplayValue(point) {
        if (!point) {
            return ""
        }
        if (point.value === null) return i18n("Unavailable")
        if (point.displayValue !== undefined && point.displayValue !== null) {
            return String(point.displayValue)
        }
        var text = String(pointValue(point))
        return valueSuffix.length > 0 ? text + " " + valueSuffix : text
    }

    function pointInspectionText(index) {
        if (index < 0 || index >= pointCount) return ""
        var lines = [i18n("%1: %2", pointLabel(points[index]), pointDisplayValue(points[index]))]
        if (hasLineSeries) {
            lineSeries.forEach(function(series) {
                lines.push(i18n("%1: %2", series.label || series.provider,
                    chart.pointDisplayValue(series.points[index])))
            })
        }
        return lines.join("\n")
    }

    function traceRun(context, run) {
        context.beginPath()
        context.moveTo(run[0].x, run[0].y)
        for (var i = 1; i < run.length; i++) {
            context.bezierCurveTo(run[i].c1.x, run[i].c1.y,
                run[i].c2.x, run[i].c2.y, run[i].x, run[i].y)
        }
    }

    function paintProviderLines(context, width, height) {
        var projected = lineSeries.map(function(series) {
            return {color: chart.seriesColors[series.provider] || chart.accent,
                runs: ChartLines.paths(series.points, {width: width, height: height,
                    maximum: chart.valueDomain.maximum, inset: chart.lineMarkerInset})}
        })
        var baseline = CostChart.chartLineY(height, 0, lineMarkerInset)
        for (var fill of projected) {
            context.fillStyle = applet.canvasColor(fill.color, 0.07)
            for (var area of fill.runs) {
                if (area.length < 2) continue
                traceRun(context, area)
                context.lineTo(area[area.length - 1].x, baseline)
                context.lineTo(area[0].x, baseline)
                context.closePath()
                context.fill()
            }
        }
        context.lineCap = "round"
        context.lineJoin = "round"
        for (var stroke of projected) {
            for (var run of stroke.runs) {
                traceRun(context, run)
                // Restore the surface used for accent contrast underneath each
                // line, including where several translucent fills overlap.
                context.lineWidth = 6
                context.strokeStyle = applet.canvasColor(lineBackdrop, 1)
                context.stroke()
                context.lineWidth = 2
                context.strokeStyle = applet.canvasColor(stroke.color, 1)
                context.stroke()
            }
        }
        context.lineWidth = 4
        for (var marker of projected) {
            context.fillStyle = applet.canvasColor(marker.color, 1)
            for (var dots of marker.runs) {
                for (var point of dots) {
                    if (point.index !== activeIndex && dots.length > 1) continue
                    context.beginPath()
                    context.arc(point.x, point.y, point.index === activeIndex ? lineMarkerInset : 2, 0, Math.PI * 2)
                    context.strokeStyle = applet.canvasColor(lineBackdrop, 1)
                    context.stroke()
                    context.fill()
                }
            }
        }
    }

    function chartFraction(value) {
        return ChartScale.fraction(value, valueDomain)
    }

    function barGradient(context, baseline, topOpacity, bottomOpacity) {
        var gradient = context.createLinearGradient(0, 0, 0, Math.max(1, baseline))
        gradient.addColorStop(0, chart.applet.canvasColor(chart.accent, topOpacity))
        gradient.addColorStop(1, chart.applet.canvasColor(chart.accent, bottomOpacity))
        return gradient
    }

    function indexAt(positionX) {
        if (pointCount === 0 || plot.width <= 0) {
            return -1
        }
        if (kind === "line" && pointCount > 1) {
            return CostChart.chartLineIndexAt(
                plot.width, pointCount, positionX, chart.lineMarkerInset)
        }
        return Math.max(0, Math.min(pointCount - 1,
            Math.floor(positionX * pointCount / plot.width)))
    }

    function focusPlot(reason) {
        plotFocus.forceActiveFocus(reason)
    }

    function moveSelection(delta) {
        if (pointCount === 0) {
            return
        }
        var next = selectedIndex >= 0 ? selectedIndex + delta : (delta < 0 ? pointCount - 1 : 0)
        selectedIndex = Math.max(0, Math.min(pointCount - 1, next))
        plot.requestPaint()
    }

    FontMetrics {
        id: chartReadoutFontMetrics

        font: Kirigami.Theme.smallFont
    }

    RowLayout {
        id: chartReadout
        // Fading keeps the row from blinking as the pointer enters and leaves
        // the plot; the reserved height keeps the chart from shifting either way.
        opacity: chart.hasActivePoint || chart.peakIndex >= 0 ? 1 : 0
        Layout.fillWidth: true
        Layout.preferredHeight: chartReadoutFontMetrics.height
        spacing: Kirigami.Units.smallSpacing

        HoverHandler { id: chartReadoutHover }

        PlainToolTip {
            visible: chartReadoutHover.hovered
                && (chartPointLabel.truncated || chartPointValue.truncated)
                && (chart.hasActivePoint || chart.peakIndex >= 0)
            plainText: i18n("%1: %2", chartPointLabel.text, chartPointValue.text)
        }

        Behavior on opacity {
            enabled: !plotFocus.activeFocus
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }

        PlainPlasmaLabel {
            id: chartPointLabel
            objectName: "chartPointLabel"

            text: chart.hasLineSeries && !chart.hasActivePoint ? chart.accessibleTitle
                : chart.hasActivePoint && chart.readoutValid
                ? chart.pointLabel(chart.points[chart.readoutIndex])
                : chart.peakIndex >= 0 ? i18n("Peak daily usage")
                : chart.readoutValid ? chart.pointLabel(chart.points[chart.readoutIndex]) : ""
            // The retained text outlives the fade, and a zero opacity does not
            // take an item out of the accessibility tree the way visibility
            // would. Without this a screen reader could still announce the last
            // point while the plot itself says to use the arrow keys.
            Accessible.ignored: !chart.hasActivePoint && chart.peakIndex < 0
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlainPlasmaLabel {
            id: chartPointValue
            objectName: "chartPointValue"
            font.features: { "tnum": 1 }

            text: chart.hasLineSeries && !chart.hasActivePoint ? ""
                : chart.hasActivePoint && chart.readoutValid
                ? chart.pointDisplayValue(chart.points[chart.readoutIndex])
                : chart.peakIndex >= 0 ? chart.pointDisplayValue(chart.points[chart.peakIndex])
                : chart.readoutValid ? chart.pointDisplayValue(chart.points[chart.readoutIndex]) : ""
            Accessible.ignored: !chart.hasActivePoint && chart.peakIndex < 0
            font.weight: Font.DemiBold
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            Layout.maximumWidth: chart.width / 2
            elide: Text.ElideRight
        }
    }

    Canvas {
        id: plot

        Layout.fillWidth: true
        Layout.preferredHeight: chart.plotHeight
        Layout.leftMargin: chart.axisWidth

        Repeater {
            model: chart.axisLabels
            delegate: PlainPlasmaLabel {
                required property int index
                required property var modelData
                text: modelData
                width: Math.max(0, chart.axisWidth - Kirigami.Units.smallSpacing * 2)
                x: chart.LayoutMirroring.enabled ? plot.width + Kirigami.Units.smallSpacing * 2 : -chart.axisWidth
                y: Math.max(0, Math.min(plot.height - implicitHeight,
                    CostChart.chartLineY(plot.height, 1 - index / 2, chart.lineMarkerInset) - implicitHeight / 2))
                horizontalAlignment: Text.AlignRight
                font: Kirigami.Theme.smallFont
                opacity: chart.applet.secondaryTextOpacity
                elide: Text.ElideRight
            }
        }

        // Qt's visualFocus distinguishes keyboard entry from mouse selection.
        Controls.Control {
            id: plotFocus

            anchors.fill: parent
            activeFocusOnTab: true
            background: Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                color: "transparent"
                radius: Kirigami.Units.cornerRadius / 2
                border.width: plotFocus.visualFocus ? 1 : 0
                border.color: Kirigami.Theme.focusColor
            }

            Accessible.role: Accessible.Graphic
            Accessible.name: chart.accessibleTitle
            Accessible.description: chart.hasActivePoint
                ? chart.pointInspectionText(chart.activeIndex)
                : i18n("Use the arrow keys to inspect chart points")

            Keys.onPressed: function(event) {
                switch (event.key) {
                case Qt.Key_Escape:
                    if (chart.selectedIndex < 0) return
                    chart.selectedIndex = -1
                    event.accepted = true
                    break
                case Qt.Key_Left:
                    chart.moveSelection(-1)
                    event.accepted = true
                    break
                case Qt.Key_Right:
                    chart.moveSelection(1)
                    event.accepted = true
                    break
                case Qt.Key_Home:
                    chart.selectedIndex = chart.pointCount > 0 ? 0 : -1
                    event.accepted = true
                    break
                case Qt.Key_End:
                    chart.selectedIndex = chart.pointCount - 1
                    event.accepted = true
                    break
                default:
                    return
                }
                chart.hoveredIndex = -1
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        Connections {
            target: chart
            function onPointsChanged() {
                if (chart.selectedIndex >= chart.pointCount) {
                    chart.selectedIndex = chart.pointCount - 1
                }
                if (chart.hoveredIndex >= chart.pointCount) {
                    chart.hoveredIndex = chart.pointCount - 1
                }
                plot.requestPaint()
            }
            function onValueDomainChanged() { plot.requestPaint() }
            function onAccentChanged() { plot.requestPaint() }
            function onKindChanged() { plot.requestPaint() }
            function onSelectedIndexChanged() { plot.requestPaint() }
            function onHoveredIndexChanged() { plot.requestPaint() }
            function onGuideColorChanged() { plot.requestPaint() }
            function onLineBackdropChanged() { plot.requestPaint() }
        }

        onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0 || chart.pointCount === 0) {
                return
            }

            var baseline = ChartScale.barGeometry(height, 0, chart.valueDomain).baseline
            if (chart.kind === "line" && (chart.valueDomain.minimum < 0 || chart.hasLineSeries)) {
                baseline = CostChart.chartLineY(height,
                    chart.chartFraction(0), chart.lineMarkerInset)
            }
            context.fillStyle = chart.applet.canvasColor(chart.guideColor, 0.12)
            if (!chart.hasLineSeries) context.fillRect(0, baseline, width, 1)
            // Keep inspection visible for zero points and flat zero series,
            // where changing a bar's fill cannot identify the active position.
            if (chart.hasActivePoint) {
                var guideX
                if (chart.kind === "line") {
                    guideX = CostChart.chartLineX(
                        width, chart.pointCount, chart.activeIndex, chart.lineMarkerInset)
                } else {
                    var guideBars = CostChart.chartBarGeometry(width, chart.pointCount)
                    guideX = guideBars.offset + chart.activeIndex * guideBars.step
                        + guideBars.barWidth / 2
                }
                context.fillStyle = chart.applet.canvasColor(chart.guideColor, 0.35)
                context.fillRect(Math.max(0, Math.min(width - 1, Math.round(guideX))), 0, 1, height)
            }
            if (chart.pointCount === 0 || (!chart.hasLineSeries && chart.valueDomain.minimum === chart.valueDomain.maximum)) {
                return
            }

            if ((chart.kind === "bar" || chart.kind === "bars") && chart.valueDomain.maximum > 0) {
                var peakBar = ChartScale.barGeometry(height, chart.valueDomain.maximum, chart.valueDomain)
                var peakY = Math.round(peakBar.baseline - peakBar.height)
                if (baseline - peakY >= Kirigami.Units.gridUnit) {
                    context.fillStyle = chart.applet.canvasColor(chart.guideColor, 0.08)
                    context.fillRect(0, peakY, width, 1)
                }
            }

            if (chart.hasLineSeries) {
                context.fillStyle = chart.applet.canvasColor(chart.guideColor, 0.08)
                for (var fraction of [0, 0.5, 1]) {
                    var guideY = CostChart.chartLineY(height, fraction, chart.lineMarkerInset)
                    context.fillRect(0, guideY, width, 1)
                }
                chart.paintProviderLines(context, width, height)
                return
            }

            if (chart.kind === "line") {
                context.strokeStyle = chart.applet.canvasColor(chart.accent, 0.9)
                context.fillStyle = chart.applet.canvasColor(chart.accent, 1)
                context.lineWidth = 2
                context.lineCap = "round"
                context.lineJoin = "round"
                context.beginPath()
                for (var lineIndex = 0; lineIndex < chart.pointCount; lineIndex++) {
                    var lineX = CostChart.chartLineX(
                        width, chart.pointCount, lineIndex, chart.lineMarkerInset)
                    var lineY = CostChart.chartLineY(height,
                        chart.chartFraction(chart.pointValue(chart.points[lineIndex])), chart.lineMarkerInset)
                    if (lineIndex === 0) {
                        context.moveTo(lineX, lineY)
                    } else {
                        context.lineTo(lineX, lineY)
                    }
                }
                context.stroke()
                for (var dotIndex = 0; dotIndex < chart.pointCount; dotIndex++) {
                    var dotX = CostChart.chartLineX(
                        width, chart.pointCount, dotIndex, chart.lineMarkerInset)
                    var dotY = CostChart.chartLineY(height,
                        chart.chartFraction(chart.pointValue(chart.points[dotIndex])), chart.lineMarkerInset)
                    context.beginPath()
                    context.arc(dotX, dotY,
                        dotIndex === chart.activeIndex ? chart.lineMarkerInset : 1.5,
                        0, Math.PI * 2)
                    context.fill()
                }
                return
            }

            var geometry = CostChart.chartBarGeometry(width, chart.pointCount)
            var normalFill = chart.barGradient(context, baseline, 0.78, 0.36)
            var activeFill = chart.barGradient(context, baseline, 1, 0.7)
            for (var barIndex = 0; barIndex < chart.pointCount; barIndex++) {
                var bar = ChartScale.barGeometry(height,
                    chart.pointValue(chart.points[barIndex]), chart.valueDomain)
                context.save()
                if (bar.negative) {
                    context.translate(0, baseline * 2)
                    context.scale(1, -1)
                }
                context.fillStyle = barIndex === chart.activeIndex ? activeFill : normalFill
                CostChart.paintRoundedTopBar(context,
                    {x: geometry.offset + barIndex * geometry.step, baseline: baseline,
                        width: geometry.barWidth, height: bar.height}, Kirigami.Units.smallSpacing / 2)
                context.restore()
            }
        }

        MouseArea {
            id: plotMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) {
                chart.hoveredIndex = chart.indexAt(mouse.x)
            }
            onExited: chart.hoveredIndex = -1
            onClicked: function(mouse) {
                // An already focused control receives no new focus-in event.
                plotFocus.focusReason = Qt.MouseFocusReason
                plotFocus.forceActiveFocus(Qt.MouseFocusReason)
                chart.selectedIndex = chart.indexAt(mouse.x)
            }
        }

        PlainToolTip {
            parent: plot
            visible: !chart.hasLineSeries && chart.hasActivePoint
                && (chartPointLabel.truncated || chartPointValue.truncated)
                && (plotMouse.containsMouse || plotFocus.activeFocus)
            plainText: chart.hasActivePoint
                ? chart.pointInspectionText(chart.activeIndex) : ""
        }

        // A clipped child stays inside the plot and its scroll viewport. Unlike
        // an overlay tooltip, it cannot float over navigation after scrolling.
        Rectangle {
            id: linePreview
            objectName: "chartLinePreview"
            readonly property real rowHeight: Math.max(Kirigami.Units.iconSizes.small, previewFont.height)
            readonly property int rowCapacity: Math.max(0, Math.floor((plot.height
                - Kirigami.Units.smallSpacing * 2) / (rowHeight + previewRows.spacing)) - 2)
            readonly property var providers: chart.lineSeries || []
            readonly property var inspectedPoint: chart.hoveredIndex >= 0 && chart.hoveredIndex < chart.pointCount
                ? chart.points[chart.hoveredIndex] : null
            readonly property bool hasOmittedRows: providers.length > rowCapacity
            readonly property var visibleProviders: providers.slice(0,
                Math.max(0, rowCapacity - (hasOmittedRows ? 1 : 0)))
            readonly property var placement: CostChart.chartPreviewGeometry(plot.width,
                CostChart.chartLineX(plot.width, chart.pointCount, chart.hoveredIndex, chart.lineMarkerInset),
                previewRows.implicitWidth + Kirigami.Units.smallSpacing * 2,
                Kirigami.Units.largeSpacing)
            visible: chart.hasLineSeries && chart.hoveredIndex >= 0 && plotMouse.containsMouse
            width: placement.width
            height: Math.min(plot.height, previewRows.implicitHeight + Kirigami.Units.smallSpacing * 2)
            x: placement.x
            y: 0
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            radius: Kirigami.Units.cornerRadius
            clip: true
            Accessible.ignored: true
            FontMetrics { id: previewFont; font: Kirigami.Theme.smallFont }
            ColumnLayout {
                id: previewRows
                x: Kirigami.Units.smallSpacing
                y: Kirigami.Units.smallSpacing
                width: Math.max(0, linePreview.width - Kirigami.Units.smallSpacing * 2)
                spacing: Kirigami.Units.smallSpacing / 2

                PlainPlasmaLabel {
                    text: chart.pointLabel(linePreview.inspectedPoint)
                    font: Kirigami.Theme.smallFont
                    opacity: chart.applet.secondaryTextOpacity
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
                Repeater {
                    model: linePreview.visibleProviders
                    delegate: RowLayout {
                        id: previewProvider
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            objectName: "chartPreviewProviderIcon"
                            source: previewProvider.modelData.iconSource || "view-statistics"
                            fallback: "view-statistics"
                            isMask: previewProvider.modelData.iconIsMask === true
                            color: chart.seriesColors[previewProvider.modelData.provider] || chart.accent
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            Accessible.ignored: true
                        }
                        PlainPlasmaLabel {
                            text: previewProvider.modelData.label || previewProvider.modelData.provider
                            font: Kirigami.Theme.smallFont
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            Accessible.ignored: true
                        }
                        PlainPlasmaLabel {
                            text: chart.pointDisplayValue(previewProvider.modelData.points
                                ? previewProvider.modelData.points[chart.hoveredIndex] : null)
                            font: Kirigami.Theme.smallFont
                            Layout.maximumWidth: previewRows.width / 2
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            Accessible.ignored: true
                        }
                    }
                }
                PlainPlasmaLabel {
                    visible: linePreview.hasOmittedRows
                    text: "…"
                    font: Kirigami.Theme.smallFont
                    Accessible.ignored: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlainPlasmaLabel {
                        text: i18n("Total")
                        font: Kirigami.Theme.smallFont
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }
                    PlainPlasmaLabel {
                        objectName: "chartPreviewTotal"
                        text: chart.pointDisplayValue(linePreview.inspectedPoint)
                        font: Kirigami.Theme.smallFont
                        Layout.maximumWidth: previewRows.width / 2
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }
                }
            }
        }
    }

    RowLayout {
        visible: chart.pointCount > 0
        Layout.fillWidth: true
        Layout.leftMargin: chart.axisWidth
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            text: chart.pointCount > 0 ? chart.pointLabel(chart.points[0]) : ""
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlainPlasmaLabel {
            text: chart.pointCount > 1 ? chart.pointLabel(chart.points[chart.pointCount - 1]) : ""
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}
