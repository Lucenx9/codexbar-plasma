import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ChartScale.js" as ChartScale

ColumnLayout {
    id: chart

    required property var applet
    required property var points
    required property color accent
    property string kind: "bar"
    property string accessibleTitle: ""
    property string valueSuffix: ""
    // Owners that plot a long range can raise this; the default keeps the
    // inline provider detail charts at their existing size.
    property real plotHeight: Kirigami.Units.gridUnit * 3
    property int selectedIndex: -1
    property int hoveredIndex: -1
    readonly property int activeIndex: hoveredIndex >= 0 ? hoveredIndex : selectedIndex
    readonly property bool hasActivePoint: activeIndex >= 0 && activeIndex < points.length
    readonly property var valueDomain: ChartScale.domain(points)
    readonly property real lineMarkerInset: 3.5

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    function pointValue(point) {
        return ChartScale.pointValue(point)
    }

    function pointLabel(point) {
        return point && point.label ? String(point.label) : ""
    }

    function pointDisplayValue(point) {
        if (!point) {
            return ""
        }
        if (point.displayValue !== undefined && point.displayValue !== null) {
            return String(point.displayValue)
        }
        var text = String(pointValue(point))
        return valueSuffix.length > 0 ? text + " " + valueSuffix : text
    }

    function chartFraction(value) {
        return ChartScale.fraction(value, valueDomain)
    }

    function indexAt(positionX) {
        if (points.length === 0 || plot.width <= 0) {
            return -1
        }
        if (kind === "line" && points.length > 1) {
            return chart.applet.chartLineIndexAt(
                plot.width, points.length, positionX, chart.lineMarkerInset)
        }
        return Math.max(0, Math.min(points.length - 1,
            Math.floor(positionX * points.length / plot.width)))
    }

    function moveSelection(delta) {
        if (points.length === 0) {
            return
        }
        var next = selectedIndex >= 0 ? selectedIndex + delta : (delta < 0 ? points.length - 1 : 0)
        selectedIndex = Math.max(0, Math.min(points.length - 1, next))
        plot.requestPaint()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            text: chart.hasActivePoint ? chart.pointLabel(chart.points[chart.activeIndex]) : ""
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlainPlasmaLabel {
            text: chart.hasActivePoint ? chart.pointDisplayValue(chart.points[chart.activeIndex]) : ""
            font.weight: Font.DemiBold
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Canvas {
        id: plot

        Layout.fillWidth: true
        Layout.preferredHeight: chart.plotHeight
        activeFocusOnTab: true

        Accessible.role: Accessible.Graphic
        Accessible.name: chart.accessibleTitle
        Accessible.description: chart.hasActivePoint
            ? i18n("%1: %2", chart.pointLabel(chart.points[chart.activeIndex]),
                chart.pointDisplayValue(chart.points[chart.activeIndex]))
            : i18n("Use the arrow keys to inspect chart points")

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        Connections {
            target: chart
            function onPointsChanged() {
                if (chart.selectedIndex >= chart.points.length) {
                    chart.selectedIndex = chart.points.length - 1
                }
                if (chart.hoveredIndex >= chart.points.length) {
                    chart.hoveredIndex = chart.points.length - 1
                }
                plot.requestPaint()
            }
            function onValueDomainChanged() { plot.requestPaint() }
            function onAccentChanged() { plot.requestPaint() }
            function onKindChanged() { plot.requestPaint() }
            function onSelectedIndexChanged() { plot.requestPaint() }
            function onHoveredIndexChanged() { plot.requestPaint() }
        }

        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Left:
                chart.moveSelection(-1)
                event.accepted = true
                break
            case Qt.Key_Right:
                chart.moveSelection(1)
                event.accepted = true
                break
            case Qt.Key_Home:
                chart.selectedIndex = chart.points.length > 0 ? 0 : -1
                event.accepted = true
                break
            case Qt.Key_End:
                chart.selectedIndex = chart.points.length - 1
                event.accepted = true
                break
            }
        }

        onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) {
                return
            }

            var baseline = ChartScale.barGeometry(height, 0, chart.valueDomain).baseline
            if (chart.kind === "line" && chart.valueDomain.minimum < 0) {
                baseline = chart.applet.chartLineY(height,
                    chart.chartFraction(0), chart.lineMarkerInset)
            }
            context.fillStyle = chart.applet.canvasColor(Kirigami.Theme.textColor, 0.12)
            context.fillRect(0, baseline, width, 1)
            if (chart.points.length === 0 || chart.valueDomain.minimum === chart.valueDomain.maximum) {
                return
            }

            if (chart.kind === "line") {
                context.strokeStyle = chart.applet.canvasColor(chart.accent, 0.9)
                context.fillStyle = chart.applet.canvasColor(chart.accent, 1)
                context.lineWidth = 2
                context.lineCap = "round"
                context.lineJoin = "round"
                context.beginPath()
                for (var lineIndex = 0; lineIndex < chart.points.length; lineIndex++) {
                    var lineX = chart.applet.chartLineX(
                        width, chart.points.length, lineIndex, chart.lineMarkerInset)
                    var lineY = chart.applet.chartLineY(height,
                        chart.chartFraction(chart.pointValue(chart.points[lineIndex])), chart.lineMarkerInset)
                    if (lineIndex === 0) {
                        context.moveTo(lineX, lineY)
                    } else {
                        context.lineTo(lineX, lineY)
                    }
                }
                context.stroke()
                for (var dotIndex = 0; dotIndex < chart.points.length; dotIndex++) {
                    var dotX = chart.applet.chartLineX(
                        width, chart.points.length, dotIndex, chart.lineMarkerInset)
                    var dotY = chart.applet.chartLineY(height,
                        chart.chartFraction(chart.pointValue(chart.points[dotIndex])), chart.lineMarkerInset)
                    context.beginPath()
                    context.arc(dotX, dotY,
                        dotIndex === chart.activeIndex ? chart.lineMarkerInset : 1.5,
                        0, Math.PI * 2)
                    context.fill()
                }
                return
            }

            var geometry = chart.applet.chartBarGeometry(width, chart.points.length)
            var normalFill = chart.applet.buildChartBarGradient(context, chart.accent, baseline, 0.78, 0.36)
            var activeFill = chart.applet.buildChartBarGradient(context, chart.accent, baseline, 1, 0.7)
            for (var barIndex = 0; barIndex < chart.points.length; barIndex++) {
                var bar = ChartScale.barGeometry(height,
                    chart.pointValue(chart.points[barIndex]), chart.valueDomain)
                context.save()
                if (bar.negative) {
                    context.translate(0, baseline * 2)
                    context.scale(1, -1)
                }
                context.fillStyle = barIndex === chart.activeIndex ? activeFill : normalFill
                chart.applet.paintRoundedTopBar(
                    context,
                    geometry.offset + barIndex * geometry.step,
                    baseline,
                    geometry.barWidth,
                    bar.height,
                    Kirigami.Units.smallSpacing / 2)
                context.restore()
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) {
                chart.hoveredIndex = chart.indexAt(mouse.x)
            }
            onExited: chart.hoveredIndex = -1
            onClicked: function(mouse) {
                plot.forceActiveFocus(Qt.MouseFocusReason)
                chart.selectedIndex = chart.indexAt(mouse.x)
            }
        }
    }

    RowLayout {
        visible: chart.points.length > 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            text: chart.points.length > 0 ? chart.pointLabel(chart.points[0]) : ""
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlainPlasmaLabel {
            text: chart.points.length > 1 ? chart.pointLabel(chart.points[chart.points.length - 1]) : ""
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}
