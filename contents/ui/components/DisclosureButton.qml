import QtQuick

// Settings disclosure matching the popup's flat details toggle. The arrow
// carries the state instead of a pressed-looking checked background, while
// assistive technology still receives the toggle state of a checkable button.
PlainButton {
    id: disclosure

    property bool expanded: false

    flat: true
    icon.name: expanded ? "arrow-down" : (mirrored ? "arrow-left" : "arrow-right")
    Accessible.checkable: true
    Accessible.checked: expanded
}
