import QtQuick
import org.kde.kirigami as Kirigami

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

    // The style insets a flat button's frame. Pull it toward the leading edge
    // so the label shares the text column of neighbouring check boxes; a
    // transform also moves hit-testing and focus, unlike FormLayout margins.
    transform: Translate {
        x: disclosure.mirrored ? Kirigami.Units.smallSpacing : -Kirigami.Units.smallSpacing
    }
}
