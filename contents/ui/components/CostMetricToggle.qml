import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Two-way history metric switch. Both choices stay visible and switch with
// one click, instead of a closed combo that only repeats the current metric.
// A shared track makes the pair read as one segmented control: alone, the
// unchecked button looked like a caption beside a single framed button.
Controls.Control {
    id: metricToggle

    required property var applet
    readonly property var values: ["cost", "tokens"]
    readonly property int currentIndex: applet.costHistoryShowsTokens ? 1 : 0

    signal activated(int index)

    function focusCurrentChoice(reason) {
        var choice = metricChoices.itemAt(currentIndex)
        if (choice) choice.forceActiveFocus(reason)
    }

    padding: Math.round(Kirigami.Units.smallSpacing / 2)
    Accessible.role: Accessible.Grouping
    Accessible.name: i18n("History metric")

    onActivated: function (index) {
        applet.setCostHistoryMetric(values[index]);
    }

    // Concentric corners: the track's radius is the buttons' plus its inset.
    background: Rectangle {
        radius: Kirigami.Units.cornerRadius + metricToggle.padding
        color: metricToggle.applet.withAlpha(Kirigami.Theme.textColor, 0.06)
    }

    contentItem: RowLayout {
        spacing: 0

        Repeater {
            id: metricChoices
            model: [i18n("Cost"), i18n("Tokens")]

            delegate: PlasmaComponents.ToolButton {
                required property int index
                required property var modelData

                text: modelData
                font: Kirigami.Theme.smallFont
                // The theme's padding hugs the checked frame around a small
                // label; widen it so the frame gets the same inner margin
                // horizontally that the label already has vertically.
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing
                checkable: true
                checked: metricToggle.currentIndex === index
                Accessible.name: modelData
                // Flat ToolButtons inherit the parent theme. Created while
                // Usage & Spend was hidden, they kept the unsynced default
                // black text after the view appeared, invisible on Breeze
                // Dark. Their own Button color set follows the scheme.
                Kirigami.Theme.inherit: false

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
}
