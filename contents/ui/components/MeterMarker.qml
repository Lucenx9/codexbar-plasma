import QtQuick
import org.kde.kirigami as Kirigami

// Every marker drawn on the meter shares one geometry so pace and quota
// thresholds read as the same kind of annotation. The inset matters: a
// marker that spans the track edge to edge looks like a gap in the accent
// fill rather than a tick placed on top of it. A background sliver on each
// side keeps the tick legible on the fill, such as a red pace marker over
// a terracotta bar, while the fill still shows above and below it.
Rectangle {
    id: meterMarker

    required property real percent
    property color markerColor
    // Repeater delegates exist briefly before they are parented.
    readonly property real trackWidth: parent ? parent.width : 0
    readonly property real trackHeight: parent ? parent.height : 0
    readonly property real inset: Math.max(1, Math.round(trackHeight / 7))
    readonly property real knockout: 1

    visible: percent > 0 && percent < 100
    // Whole pixels keep a 2px tick crisp instead of smearing it across 4.
    x: Math.round(Math.max(0, Math.min(trackWidth - width, trackWidth * percent / 100 - width / 2)))
    y: inset
    width: Math.max(2, Math.round(trackHeight / 3.5)) + knockout * 2
    height: Math.max(0, trackHeight - inset * 2)
    radius: width / 2
    color: Kirigami.Theme.backgroundColor

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: meterMarker.knockout
        anchors.rightMargin: meterMarker.knockout
        radius: width / 2
        color: meterMarker.markerColor
    }
}
