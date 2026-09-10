import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../SafeText.js" as SafeText

Controls.ToolTip {
    property string plainText: ""

    // Controls.ToolTip opens with no delay of its own, so a pointer crossing the
    // popup or the panel flashes tooltips on its way past. Default to the Plasma
    // hover delay that every explicit call site already asks for; a tooltip that
    // confirms an action instead of labelling a control opts out with delay: 0.
    delay: Kirigami.Units.toolTipDelay
    text: SafeText.plainTextAsRichText(plainText)
}
