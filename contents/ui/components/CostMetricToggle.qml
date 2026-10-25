import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Two-way history metric switch. Both choices stay visible and switch with
// one click, instead of a closed combo that only repeats the current metric.
RowLayout {
    id: metricToggle

    required property var applet
    readonly property var values: ["cost", "tokens"]
    readonly property int currentIndex: applet.costHistoryShowsTokens ? 1 : 0

    signal activated(int index)

    spacing: 0
    Accessible.role: Accessible.Grouping
    Accessible.name: i18n("History metric")

    onActivated: function (index) {
        applet.setCostHistoryMetric(values[index]);
    }

    Repeater {
        model: [i18n("Cost"), i18n("Tokens")]

        delegate: PlasmaComponents.ToolButton {
            required property int index
            required property var modelData

            text: modelData
            font: Kirigami.Theme.smallFont
            checkable: true
            checked: metricToggle.currentIndex === index
            Accessible.name: modelData

            onClicked: {
                metricToggle.activated(index);
                // A click toggles checked and severs the binding; the applet
                // setting stays the single source of the checked choice.
                checked = Qt.binding(function () {
                    return metricToggle.currentIndex === index;
                });
            }
        }
    }
}
