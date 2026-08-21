import QtQuick
import QtQuick.Controls as Controls

Controls.ComboBox {
    id: control

    delegate: PlainItemDelegate {
        required property int index
        required property var modelData

        width: control.width
        plainText: control.textAt(index)
        highlighted: control.highlightedIndex === index
    }

    Accessible.name: currentText
}
