import QtQuick
import org.kde.kirigami as Kirigami
import "../SafeText.js" as SafeText

Kirigami.PlaceholderMessage {
    property string plainText: ""
    property string plainExplanation: ""

    text: SafeText.plainTextAsRichText(plainText)
    explanation: SafeText.plainTextAsRichText(plainExplanation)
    Accessible.name: plainText
}
