import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../PanelRingGeometry.js" as RingGeometry
import "../ThemeContrast.js" as ThemeContrast

Item {
    id: rings

    required property var meters
    required property color trackColor
    property color backgroundColor: Kirigami.Theme.backgroundColor
    property color textColor: Kirigami.Theme.textColor
    property bool animationsEnabled: true
    readonly property var geometry: RingGeometry.layout(Math.min(width, height), meters.length)
    readonly property int logoSize: geometry.logoSize

    Repeater {
        model: rings.geometry.radii

        delegate: Shape {
            id: ring
            required property int index
            required property var modelData
            readonly property var meter: rings.meters[index] || ({percent: 0, color: "transparent", warning: false})
            readonly property var arc: RingGeometry.arc(meter.percent, modelData, rings.geometry.strokeWidth)

            objectName: "panelMeterRing"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1
                // Correct both neutral and warning hairlines for antialiasing.
                // Keep the empty scale thinner than the measured arc.
                strokeColor: ThemeContrast.readableAccentColor(ring.meter.warning
                    ? ThemeContrast.interpolateColor(rings.trackColor, ring.meter.color, 0.4)
                    : rings.trackColor, rings.backgroundColor, rings.textColor, 5.5)
                fillColor: "transparent"
                PathAngleArc {
                    centerX: rings.width / 2
                    centerY: rings.height / 2
                    radiusX: ring.modelData
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360
                }
            }

            ShapePath {
                strokeWidth: rings.geometry.strokeWidth
                strokeColor: ring.meter.color
                fillColor: "transparent"
                capStyle: ring.arc.rounded ? ShapePath.RoundCap : ShapePath.FlatCap
                PathAngleArc {
                    centerX: rings.width / 2
                    centerY: rings.height / 2
                    radiusX: ring.modelData
                    radiusY: radiusX
                    startAngle: ring.arc.startAngle
                    sweepAngle: ring.arc.sweepAngle

                    Behavior on sweepAngle {
                        enabled: rings.animationsEnabled
                        NumberAnimation {
                            duration: Kirigami.Units.longDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
