import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components" as Components
import "../SafeText.js" as SafeText

// Render one normalized CLI field. The settings page owns validation, prompts,
// command execution and persistence; signals carry requests without credentials.
ColumnLayout {
    id: fieldRoot
    required property var modelData
    required property bool providerAvailable
    required property bool writePending
    required property real secondaryTextOpacity

    signal writeRequested(var field, string value)
    signal enumWriteRequested(var field, int optionIndex)
    signal secretPromptRequested(var field)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: fieldRoot.modelData.kind === "secret"

        Components.PlainControlsLabel {
            text: fieldRoot.modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Components.PlainControlsLabel {
            text: fieldRoot.modelData.redactedValue.length > 0 ? fieldRoot.modelData.redactedValue : i18n("Not configured")
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Controls.Button {
            objectName: "descriptorSecretButton"
            text: i18n("Set…")
            Accessible.name: i18n("Set %1", fieldRoot.modelData.title)
            icon.name: "password-show-off"
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
            onClicked: if (fieldRoot.providerAvailable) fieldRoot.secretPromptRequested(fieldRoot.modelData)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: fieldRoot.modelData.kind === "text" || fieldRoot.modelData.kind === "number"

        Components.PlainControlsLabel {
            text: fieldRoot.modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Controls.TextField {
            id: descriptorTextField
            objectName: "descriptorTextField"
            Layout.fillWidth: true
            text: fieldRoot.modelData.valueText
            placeholderText: SafeText.plainTextAsRichText(fieldRoot.modelData.description)
            Accessible.name: fieldRoot.modelData.title
            Accessible.description: fieldRoot.modelData.description
            inputMethodHints: fieldRoot.modelData.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
        }

        Controls.Button {
            objectName: "descriptorTextSaveButton"
            text: i18n("Save")
            Accessible.name: i18n("Save %1", fieldRoot.modelData.title)
            icon.name: "document-save"
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
            onClicked: if (fieldRoot.providerAvailable) fieldRoot.writeRequested(fieldRoot.modelData, descriptorTextField.text)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: fieldRoot.modelData.kind === "enum"

        Components.PlainControlsLabel {
            text: fieldRoot.modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Components.PlainComboBox {
            id: descriptorEnumBox
            objectName: "descriptorEnumBox"

            property bool restoreBindingAfterWrite: false
            readonly property bool descriptorWritePending: fieldRoot.writePending

            Layout.fillWidth: true
            model: fieldRoot.modelData.options
            textRole: "title"
            Accessible.name: fieldRoot.modelData.title
            valueRole: "id"
            currentIndex: fieldRoot.modelData.selectedOptionIndex
            enabled: fieldRoot.providerAvailable
                && fieldRoot.modelData.options.length > 0
                && !descriptorWritePending
            onDescriptorWritePendingChanged: {
                if (descriptorWritePending || !restoreBindingAfterWrite) {
                    return
                }
                restoreBindingAfterWrite = false
                currentIndex = Qt.binding(function() {
                    return fieldRoot.modelData.selectedOptionIndex
                })
            }
        }

        Controls.Button {
            id: descriptorEnumSaveButton
            objectName: "descriptorEnumSaveButton"

            text: i18n("Save")
            Accessible.name: i18n("Save %1", fieldRoot.modelData.title)
            icon.name: "document-save"
            enabled: fieldRoot.providerAvailable
                && descriptorEnumBox.currentIndex >= 0
                && !fieldRoot.writePending
            onClicked: {
                if (!fieldRoot.providerAvailable) {
                    return
                }
                fieldRoot.enumWriteRequested(fieldRoot.modelData, descriptorEnumBox.currentIndex)
                // A rejected plan never enters the pending state,
                // so it keeps the user's choice available to retry.
                // A started write restores the binding only when its
                // result clears the pending state.
                descriptorEnumBox.restoreBindingAfterWrite =
                    descriptorEnumBox.descriptorWritePending
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: fieldRoot.modelData.kind === "boolean"

        Components.PlainControlsLabel {
            text: fieldRoot.modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Components.PlainCheckBox {
            objectName: "descriptorBooleanBox"
            checked: fieldRoot.modelData.value === true || String(fieldRoot.modelData.value).toLowerCase() === "true"
            plainText: fieldRoot.modelData.description
            Accessible.name: fieldRoot.modelData.title
            Accessible.description: fieldRoot.modelData.description
            implicitWidth: 0
            Layout.fillWidth: true
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
            onClicked: {
                if (fieldRoot.providerAvailable) {
                    fieldRoot.writeRequested(fieldRoot.modelData, checked ? "true" : "false")
                }
                // Restore the binding the click severed so the box reflects the
                // saved value (and reverts on a failed write).
                checked = Qt.binding(function() {
                    return fieldRoot.modelData.value === true || String(fieldRoot.modelData.value).toLowerCase() === "true"
                })
            }
        }
    }

    Components.PlainControlsLabel {
        Layout.fillWidth: true
        text: fieldRoot.modelData.description
        opacity: fieldRoot.secondaryTextOpacity
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        visible: fieldRoot.modelData.description.length > 0
            && fieldRoot.modelData.kind !== "boolean"
            && fieldRoot.modelData.kind !== "text"
            && fieldRoot.modelData.kind !== "number"
    }
}
