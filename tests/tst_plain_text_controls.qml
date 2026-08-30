import QtQuick
import QtTest
import "../contents/ui/components" as Components
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "PlainTextControls"

    readonly property string activeMarkup: "Status <img src=\"http://127.0.0.1/probe\"> & <test-org>"

    Component {
        id: buttonComponent
        Components.PlainButton {}
    }

    Component {
        id: checkBoxComponent
        Components.PlainCheckBox {}
    }

    Component {
        id: itemDelegateComponent
        Components.PlainItemDelegate {}
    }

    Component {
        id: toolTipComponent
        Components.PlainToolTip {}
    }

    Component {
        id: comboBoxComponent
        Components.PlainComboBox {}
    }

    function test_buttonUsesActiveStyleLabelPath() {
        var button = createTemporaryObject(buttonComponent, this, { plainText: activeMarkup })

        compare(button.text, SafeText.plainButtonText(
            activeMarkup, button.contentItem !== null))
    }

    function test_otherAbstractButtonsEscapeMarkup() {
        var checkBox = createTemporaryObject(checkBoxComponent, this, { plainText: activeMarkup })
        var itemDelegate = createTemporaryObject(itemDelegateComponent, this, { plainText: activeMarkup })

        compare(checkBox.text, SafeText.plainTextAsRichText(activeMarkup))
        compare(itemDelegate.text, SafeText.plainTextAsMnemonicRichText(activeMarkup))
    }

    function test_toolTipEscapesMarkup() {
        var toolTip = createTemporaryObject(toolTipComponent, this, { plainText: activeMarkup })

        compare(toolTip.text, SafeText.plainTextAsRichText(activeMarkup))
    }

    function test_comboBoxDelegateEscapesMarkup() {
        var comboBox = createTemporaryObject(comboBoxComponent, this, {
            model: [{ id: "unsafe", title: activeMarkup }],
            textRole: "title",
            valueRole: "id"
        })
        var optionDelegate = comboBox.delegate.createObject(comboBox, {
            index: 0,
            modelData: comboBox.model[0]
        })

        verify(optionDelegate !== null)
        compare(optionDelegate.plainText, activeMarkup)
        compare(optionDelegate.text, SafeText.plainTextAsMnemonicRichText(activeMarkup))
        optionDelegate.destroy()
    }
}
