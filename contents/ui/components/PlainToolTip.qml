import QtQuick
import QtQuick.Controls as Controls
import "../SafeText.js" as SafeText

Controls.ToolTip {
    property string plainText: ""

    text: SafeText.plainTextAsRichText(plainText)
}
