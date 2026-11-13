import QtQuick
import QtQuick.Controls as Controls
import "../SafeText.mjs" as SafeText

Controls.Button {
    property string plainText: ""

    text: SafeText.plainButtonText(plainText, contentItem !== null)
    Accessible.name: plainText
}
