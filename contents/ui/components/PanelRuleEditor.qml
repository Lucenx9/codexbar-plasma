import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../PanelRules.js" as PanelRules

RowLayout {
    id: editor

    required property var configPage
    required property string elementID
    readonly property var rule: configPage.panelVisibilityRules[elementID]
    readonly property bool usesPercent: rule.condition === "usageAtLeast"
    readonly property bool usesMinutes: rule.condition === "resetWithin"

    spacing: Kirigami.Units.smallSpacing

    Controls.ComboBox {
        objectName: editor.elementID + "VisibilityCondition"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Accessible.name: editor.elementID === "text" ? i18n("Show panel text") : i18n("Show each provider meter")
        textRole: "text"
        valueRole: "value"
        model: [
            {
                text: i18n("Always"),
                value: "always"
            },
            {
                text: i18n("Usage at least"),
                value: "usageAtLeast"
            },
            {
                text: i18n("Reset within"),
                value: "resetWithin"
            },
            {
                text: i18n("Forecast to run out"),
                value: "runOut"
            }
        ]
        currentIndex: PanelRules.conditions.indexOf(editor.rule.condition)
        onActivated: function (index) {
            editor.configPage.setPanelVisibilityRule(editor.elementID, {
                condition: valueAt(index)
            });
        }
    }

    Controls.SpinBox {
        objectName: editor.elementID + "VisibilityThreshold"
        visible: editor.usesPercent || editor.usesMinutes
        Accessible.name: editor.usesPercent ? i18n("Minimum usage percent") : i18n("Minutes before reset")
        from: editor.usesPercent ? 0 : 1
        to: editor.usesPercent ? 100 : PanelRules.maximumResetMinutes
        value: editor.usesPercent ? editor.rule.usedPercent : editor.rule.resetMinutes
        editable: true
        onValueModified: editor.configPage.setPanelVisibilityRule(editor.elementID, editor.usesPercent ? {
            usedPercent: value
        } : {
            resetMinutes: value
        })
    }

    PlainControlsLabel {
        visible: editor.usesPercent || editor.usesMinutes
        text: editor.usesPercent ? i18n("%") : i18n("min")
    }
}
