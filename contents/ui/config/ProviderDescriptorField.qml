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
        visible: modelData.kind === "secret"

        Components.PlainControlsLabel {
            text: modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Components.PlainControlsLabel {
            text: modelData.redactedValue.length > 0 ? modelData.redactedValue : i18n("Not configured")
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Controls.Button {
            objectName: "descriptorSecretButton"
            text: i18n("Set…")
            icon.name: "password-show-off"
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
            onClicked: if (fieldRoot.providerAvailable) fieldRoot.secretPromptRequested(modelData)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: modelData.kind === "text" || modelData.kind === "number"

        Components.PlainControlsLabel {
            text: modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Controls.TextField {
            id: descriptorTextField
            objectName: "descriptorTextField"
            Layout.fillWidth: true
            text: modelData.valueText
            placeholderText: SafeText.plainTextAsRichText(modelData.description)
            Accessible.description: modelData.description
            inputMethodHints: modelData.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
        }

        Controls.Button {
            objectName: "descriptorTextSaveButton"
            text: i18n("Save")
            icon.name: "document-save"
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
            onClicked: if (fieldRoot.providerAvailable) fieldRoot.writeRequested(modelData, descriptorTextField.text)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: modelData.kind === "enum"

        Components.PlainControlsLabel {
            text: modelData.title
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
            model: modelData.options
            textRole: "title"
            valueRole: "id"
            currentIndex: modelData.selectedOptionIndex
            enabled: fieldRoot.providerAvailable
                && modelData.options.length > 0
                && !descriptorWritePending
            onDescriptorWritePendingChanged: {
                if (descriptorWritePending || !restoreBindingAfterWrite) {
                    return
                }
                restoreBindingAfterWrite = false
                currentIndex = Qt.binding(function() {
                    return modelData.selectedOptionIndex
                })
            }
        }

        Controls.Button {
            id: descriptorEnumSaveButton
            objectName: "descriptorEnumSaveButton"

            text: i18n("Save")
            icon.name: "document-save"
            enabled: fieldRoot.providerAvailable
                && descriptorEnumBox.currentIndex >= 0
                && !fieldRoot.writePending
            onClicked: {
                if (!fieldRoot.providerAvailable) {
                    return
                }
                fieldRoot.enumWriteRequested(modelData, descriptorEnumBox.currentIndex)
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
        visible: modelData.kind === "boolean"

        Components.PlainControlsLabel {
            text: modelData.title
            opacity: fieldRoot.secondaryTextOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            elide: Text.ElideRight
        }

        Components.PlainCheckBox {
            objectName: "descriptorBooleanBox"
            checked: modelData.value === true || String(modelData.value).toLowerCase() === "true"
            plainText: modelData.description
            implicitWidth: 0
            Layout.fillWidth: true
            enabled: fieldRoot.providerAvailable && !fieldRoot.writePending
            onClicked: {
                if (fieldRoot.providerAvailable) {
                    fieldRoot.writeRequested(modelData, checked ? "true" : "false")
                }
                // Restore the binding the click severed so the box reflects the
                // saved value (and reverts on a failed write).
                checked = Qt.binding(function() {
                    return modelData.value === true || String(modelData.value).toLowerCase() === "true"
                })
            }
        }
    }

    Components.PlainControlsLabel {
        Layout.fillWidth: true
        text: modelData.description
        opacity: fieldRoot.secondaryTextOpacity
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        visible: modelData.description.length > 0
            && modelData.kind !== "boolean"
            && modelData.kind !== "text"
            && modelData.kind !== "number"
    }
}
