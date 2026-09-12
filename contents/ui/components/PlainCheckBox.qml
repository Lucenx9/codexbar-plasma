import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../SafeText.js" as SafeText

Controls.CheckBox {
    property string plainText: ""

    text: SafeText.plainTextAsRichText(plainText)
    // KDE styles consume mnemonic ampersands before parsing rich text. Qt
    // styles that read text directly still need the singly escaped version.
    Kirigami.MnemonicData.label: SafeText.plainTextAsMnemonicRichText(plainText)
    Accessible.name: plainText
}
