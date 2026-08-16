import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

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
    readonly property real maximumValue: chartMaximum(points)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    function chartMaximum(items) {
        var maximum = 0
        for (var i = 0; i < items.length; i++) {
            var value = pointValue(items[i])
            if (value > maximum) {
                maximum = value
            }
        }
        return maximum
    }

    function pointValue(point) {
        var value = point && point.value !== undefined ? Number(point.value) : 0
        return isFinite(value) ? Math.max(0, value) : 0
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
        return maximumValue > 0 ? Math.min(1, Math.max(0, value) / maximumValue) : 0
    }

    function indexAt(positionX) {
        if (points.length === 0 || plot.width <= 0) {
            return -1
        }
        if (kind === "line" && points.length > 1) {
            return Math.max(0, Math.min(points.length - 1,
                Math.round(positionX * (points.length - 1) / plot.width)))
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

        PlasmaComponents.Label {
            text: chart.hasActivePoint ? chart.pointLabel(chart.points[chart.activeIndex]) : ""
            textFormat: Text.PlainText
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            text: chart.hasActivePoint ? chart.pointDisplayValue(chart.points[chart.activeIndex]) : ""
            textFormat: Text.PlainText
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
            function onMaximumValueChanged() { plot.requestPaint() }
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

            var baseline = height - 1
            context.fillStyle = chart.applet.canvasColor(Kirigami.Theme.textColor, 0.12)
            context.fillRect(0, baseline, width, 1)
            if (chart.points.length === 0 || chart.maximumValue <= 0) {
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
                    var lineX = chart.points.length === 1 ? width / 2 : width * lineIndex / (chart.points.length - 1)
                    var lineY = baseline - (height - 3) * chart.chartFraction(chart.pointValue(chart.points[lineIndex]))
                    if (lineIndex === 0) {
                        context.moveTo(lineX, lineY)
                    } else {
                        context.lineTo(lineX, lineY)
                    }
                }
                context.stroke()
                for (var dotIndex = 0; dotIndex < chart.points.length; dotIndex++) {
                    var dotX = chart.points.length === 1 ? width / 2 : width * dotIndex / (chart.points.length - 1)
                    var dotY = baseline - (height - 3) * chart.chartFraction(chart.pointValue(chart.points[dotIndex]))
                    context.beginPath()
                    context.arc(dotX, dotY, dotIndex === chart.activeIndex ? 3.5 : 1.5, 0, Math.PI * 2)
                    context.fill()
                }
                return
            }

            var geometry = chart.applet.chartBarGeometry(width, chart.points.length)
            var normalFill = chart.applet.buildChartBarGradient(context, chart.accent, baseline, 0.78, 0.36)
            var activeFill = chart.applet.buildChartBarGradient(context, chart.accent, baseline, 1, 0.7)
            for (var barIndex = 0; barIndex < chart.points.length; barIndex++) {
                var fraction = chart.chartFraction(chart.pointValue(chart.points[barIndex]))
                var barHeight = fraction > 0 ? Math.max(2, (height - 3) * fraction) : 1
                context.fillStyle = barIndex === chart.activeIndex ? activeFill : normalFill
                chart.applet.paintRoundedTopBar(
                    context,
                    barIndex * geometry.step,
                    baseline,
                    geometry.barWidth,
                    barHeight,
                    Kirigami.Units.smallSpacing / 2)
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

        PlasmaComponents.Label {
            text: chart.points.length > 0 ? chart.pointLabel(chart.points[0]) : ""
            textFormat: Text.PlainText
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            text: chart.points.length > 1 ? chart.pointLabel(chart.points[chart.points.length - 1]) : ""
            textFormat: Text.PlainText
            opacity: chart.applet.secondaryTextOpacity
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}
