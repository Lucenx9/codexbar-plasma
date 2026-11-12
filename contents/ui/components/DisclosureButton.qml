import QtQuick
import org.kde.kirigami as Kirigami

// Flat disclosure shared by the popup and settings. The arrow
// carries the state instead of a pressed-looking checked background, while
// assistive technology still receives the toggle state of a checkable button.
PlainButton {
    id: disclosure

    property bool expanded: false
    property bool alignWithForm: false

    flat: true
    icon.name: expanded ? "arrow-down" : (mirrored ? "arrow-left" : "arrow-right")
    Accessible.checkable: true
    Accessible.checked: expanded

    // Only settings forms need to align with neighbouring check boxes.
    // Popup controls must keep their hit area and focus frame inside the viewport.
    transform: Translate {
        x: disclosure.alignWithForm
            ? (disclosure.mirrored ? Kirigami.Units.smallSpacing : -Kirigami.Units.smallSpacing) : 0
    }
}
