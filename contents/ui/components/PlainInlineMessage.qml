import QtQuick
import org.kde.kirigami as Kirigami
import "../SafeText.mjs" as SafeText

Kirigami.InlineMessage {
    property string plainText: ""

    text: SafeText.plainTextAsRichText(plainText)
    Accessible.name: plainText
}
