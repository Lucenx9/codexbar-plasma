import QtQuick
import QtQuick.Controls as Controls
import "../SafeText.js" as SafeText

Controls.ItemDelegate {
    property string plainText: ""

    text: SafeText.plainTextAsMnemonicRichText(plainText)
    Accessible.name: plainText
}
