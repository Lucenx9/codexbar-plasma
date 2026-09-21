import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
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
        id: richTextReaderComponent
        TextEdit { textFormat: TextEdit.RichText }
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

    Component {
        id: inlineMessageComponent
        Components.PlainInlineMessage {}
    }

    Component {
        id: placeholderMessageComponent
        Components.PlainPlaceholderMessage {}
    }

    // Mirrors the styled mnemonic label so the suite can observe it: the
    // attached value is only readable from inside the check box's own scope.
    Component {
        id: checkBoxLabelProbeComponent
        Components.PlainCheckBox {
            property string probedLabel: Kirigami.MnemonicData.label
        }
    }

    Component {
        id: controlsLabelComponent
        Components.PlainControlsLabel {}
    }

    Component {
        id: plasmaLabelComponent
        Components.PlainPlasmaLabel {}
    }

    Component {
        id: headingComponent
        Components.PlainHeading {}
    }

    function test_buttonUsesActiveStyleLabelPath() {
        var button = createTemporaryObject(buttonComponent, this, { plainText: activeMarkup })
        var expectedText = button.contentItem === null
            ? SafeText.plainTextAsMnemonicLabel(activeMarkup)
            : SafeText.plainTextAsMnemonicRichText(activeMarkup)

        compare(button.text, expectedText)
    }

    function test_otherAbstractButtonsEscapeMarkup() {
        var checkBox = createTemporaryObject(checkBoxComponent, this, { plainText: activeMarkup })
        var itemDelegate = createTemporaryObject(itemDelegateComponent, this, { plainText: activeMarkup })

        compare(checkBox.text, SafeText.plainTextAsRichText(activeMarkup))
        compare(itemDelegate.text, SafeText.plainTextAsMnemonicRichText(activeMarkup))
    }

    function test_checkBoxPreservesVisibleText_data() {
        return [
            {tag: "plain", label: "Codex"},
            {tag: "special-characters", label: "Research & Development <example>"},
            {tag: "literal-entities", label: "&lt;example&gt; && team"},
            {tag: "markup", label: activeMarkup},
            {tag: "empty", label: ""}
        ]
    }

    function test_checkBoxPreservesVisibleText(data) {
        var checkBox = createTemporaryObject(checkBoxComponent, this, {plainText: data.label})
        verify(checkBox.contentItem !== null)
        // Read the styled label after mnemonic processing, then decode its
        // rich text exactly once to compare the visible characters.
        var reader = createTemporaryObject(richTextReaderComponent, this, {
            text: checkBox.contentItem.text
        })
        compare(reader.getText(0, reader.length), data.label)
        compare(checkBox.Accessible.name, data.label)
    }

    // KDE styles read the mnemonic label instead of text, so hostile input
    // must arrive there escaped while the accessible name stays literal.
    function test_checkBoxMnemonicLabelEscapesMarkup() {
        var checkBox = createTemporaryObject(checkBoxLabelProbeComponent, this, { plainText: activeMarkup })

        compare(checkBox.probedLabel, SafeText.plainTextAsMnemonicRichText(activeMarkup))
        compare(checkBox.Accessible.name, activeMarkup)
    }

    // Inline and placeholder messages render rich text, so untrusted bodies
    // must arrive pre-escaped while accessible names stay literal.
    function test_inlineMessageEscapesMarkup() {
        var message = createTemporaryObject(inlineMessageComponent, this, { plainText: activeMarkup })

        compare(message.text, SafeText.plainTextAsRichText(activeMarkup))
        compare(message.Accessible.name, activeMarkup)
    }

    function test_placeholderMessageEscapesMarkup() {
        var holder = createTemporaryObject(placeholderMessageComponent, this, {
            plainText: activeMarkup, plainExplanation: activeMarkup
        })

        compare(holder.text, SafeText.plainTextAsRichText(activeMarkup))
        compare(holder.explanation, SafeText.plainTextAsRichText(activeMarkup))
        compare(holder.Accessible.name, activeMarkup)
    }

    // The label wrappers exist to keep untrusted text out of rich-text
    // rendering: hostile input must stay literal plain text.
    function test_plainLabelsStayPlainText() {
        var controlsLabel = createTemporaryObject(controlsLabelComponent, this, { text: activeMarkup })
        var plasmaLabel = createTemporaryObject(plasmaLabelComponent, this, { text: activeMarkup })
        var heading = createTemporaryObject(headingComponent, this, { text: activeMarkup })

        compare(controlsLabel.textFormat, Text.PlainText)
        compare(plasmaLabel.textFormat, Text.PlainText)
        compare(heading.textFormat, Text.PlainText)
        compare(controlsLabel.text, activeMarkup)
        compare(plasmaLabel.text, activeMarkup)
        compare(heading.text, activeMarkup)
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
