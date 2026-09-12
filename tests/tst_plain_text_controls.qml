import QtQuick
import QtTest
import "../contents/ui/components" as Components
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "PlainTextControls"

    readonly property string activeMarkup: "Status <img src=\"http://127.0.0.1/probe\"> & <test-org>"

    Component {
        id: richTextReaderComponent
        TextEdit { textFormat: TextEdit.RichText }
    }

    function createControl(qmlType, parent, properties) {
        var holder;
        try {
            holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component control: Component { Components.' + qmlType + ' {} } }', this, Qt.resolvedUrl("PlainTextControlsTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("Plain text controls check needs optional KDE QML modules");
                return null;
            }
            throw error;
        }
        return createTemporaryObject(holder.control, parent || this, properties);
    }

    function test_buttonUsesActiveStyleLabelPath() {
        var button = createControl("PlainButton", this, { plainText: activeMarkup })
        if (!button) return;
        var expectedText = button.contentItem === null
            ? SafeText.plainTextAsMnemonicLabel(activeMarkup)
            : SafeText.plainTextAsMnemonicRichText(activeMarkup)

        compare(button.text, expectedText)
    }

    function test_otherAbstractButtonsEscapeMarkup() {
        var checkBox = createControl("PlainCheckBox", this, { plainText: activeMarkup })
        if (!checkBox) return;
        var itemDelegate = createControl("PlainItemDelegate", this, { plainText: activeMarkup })
        if (!itemDelegate) return;

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
        var checkBox = createControl("PlainCheckBox", this, {plainText: data.label})
        if (!checkBox) return;
        verify(checkBox.contentItem !== null)
        // Read the styled label after mnemonic processing, then decode its
        // rich text exactly once to compare the visible characters.
        var reader = createTemporaryObject(richTextReaderComponent, this, {
            text: checkBox.contentItem.text
        })
        compare(reader.getText(0, reader.length), data.label)
        compare(checkBox.Accessible.name, data.label)
    }

    function test_toolTipEscapesMarkup() {
        var toolTip = createControl("PlainToolTip", this, { plainText: activeMarkup })
        if (!toolTip) return;

        compare(toolTip.text, SafeText.plainTextAsRichText(activeMarkup))
    }

    function test_comboBoxDelegateEscapesMarkup() {
        var comboBox = createControl("PlainComboBox", this, {
            model: [{ id: "unsafe", title: activeMarkup }],
            textRole: "title",
            valueRole: "id"
        })
        if (!comboBox) return;
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
