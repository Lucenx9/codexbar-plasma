import QtQuick
import QtQuick.Controls as Controls
import "../SafeText.js" as SafeText

Controls.CheckBox {
    property string plainText: ""

    text: SafeText.plainTextAsRichText(plainText)
    Accessible.name: plainText
}
