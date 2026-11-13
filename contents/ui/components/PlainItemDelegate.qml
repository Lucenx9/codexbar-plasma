import QtQuick
import QtQuick.Controls as Controls
import "../SafeText.mjs" as SafeText

Controls.ItemDelegate {
    property string plainText: ""

    text: SafeText.plainTextAsMnemonicRichText(plainText)
    Accessible.name: plainText
}
