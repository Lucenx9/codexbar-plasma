import QtQuick
import QtTest
import "../contents/ui/config/ProviderDescriptor.js" as ProviderDescriptor

TestCase {
    id: testCase
    name: "ProviderDescriptorField"
    when: windowShown
    width: 620
    height: 250
    visible: true

    function i18n(text) { return text; }

    Component { id: spyComponent; SignalSpy {} }

    function field(kind, selectedIndex) {
        return ProviderDescriptor.normalize({schemaVersion: 1, fields: [{
            id: "setting", kind: kind, title: "Setting", description: "Choose <literal> & value",
            value: kind === "boolean" ? false : kind === "enum" ? (selectedIndex === 1 ? "b" : "a") : 0,
            options: [{id: "a", title: "Alpha"}, {id: "b", title: "Beta"}],
            writeCommand: kind === "secret"
                ? ["codexbar", "config", "set-api-key", "--stdin"]
                : ["codexbar", "config", "set", "--value", "{value}"]
        }]}).fields[0];
    }

    function createField(kind) {
        var component = Qt.createComponent("../contents/ui/config/ProviderDescriptorField.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Descriptor controls need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var item = createTemporaryObject(component, testCase, {
            modelData: field(kind, 0), providerAvailable: true, writePending: false,
            secondaryTextOpacity: 0.7, width: 620
        });
        verify(item !== null);
        wait(0);
        return item;
    }

    function spy(item, signalName) {
        return createTemporaryObject(spyComponent, testCase, {target: item, signalName: signalName});
    }

    function activate(control) {
        verify(control.visible && control.enabled);
        control.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
    }

    function test_textAndNumberWrites_data() {
        return [{tag: "text", kind: "text"}, {tag: "number", kind: "number"}];
    }

    function test_textAndNumberWrites(data) {
        var item = createField(data.kind);
        if (!item) return;
        var input = findChild(item, "descriptorTextField");
        compare(input.text, "0");
        var requests = spy(item, "writeRequested");
        input.text = "42";
        activate(findChild(item, "descriptorTextSaveButton"));
        compare(requests.count, 1);
        compare(requests.signalArguments[0][0], item.modelData);
        compare(requests.signalArguments[0][1], "42");
    }

    function test_secretOnlyRequestsPrompt() {
        var item = createField("secret");
        if (!item) return;
        var prompt = spy(item, "secretPromptRequested");
        var writes = spy(item, "writeRequested");
        activate(findChild(item, "descriptorSecretButton"));
        compare(prompt.count, 1);
        compare(prompt.signalArguments[0].length, 1);
        compare(prompt.signalArguments[0][0], item.modelData);
        compare(writes.count, 0);
    }

    function test_enumWriteResultRestoresBinding_data() {
        return [{tag: "saved", selectedIndex: 1}, {tag: "failed", selectedIndex: 0}];
    }

    function test_enumWriteResultRestoresBinding(data) {
        var item = createField("enum");
        if (!item) return;
        var box = findChild(item, "descriptorEnumBox");
        var save = findChild(item, "descriptorEnumSaveButton");
        var requests = spy(item, "enumWriteRequested");
        item.enumWriteRequested.connect(function() { item.writePending = true; });
        compare(box.currentIndex, 0);
        box.currentIndex = 1;
        compare(requests.count, 0);
        activate(save);
        compare(requests.count, 1);
        compare(requests.signalArguments[0][1], 1);
        compare(box.restoreBindingAfterWrite, true);
        verify(!box.enabled && !save.enabled);
        item.modelData = field("enum", data.selectedIndex);
        item.writePending = false;
        compare(box.currentIndex, data.selectedIndex);
        compare(box.restoreBindingAfterWrite, false);
        item.modelData = field("enum", 1 - data.selectedIndex);
        compare(box.currentIndex, 1 - data.selectedIndex);
    }

    function test_rejectedEnumRequestKeepsChoiceForRetry() {
        var item = createField("enum");
        if (!item) return;
        var box = findChild(item, "descriptorEnumBox");
        var requests = spy(item, "enumWriteRequested");
        box.currentIndex = 1;
        activate(findChild(item, "descriptorEnumSaveButton"));
        compare(requests.count, 1);
        compare(item.writePending, false);
        compare(box.restoreBindingAfterWrite, false);
        compare(box.currentIndex, 1);
        activate(findChild(item, "descriptorEnumSaveButton"));
        compare(requests.count, 2);
        compare(requests.signalArguments[1][1], 1);
    }

    function test_booleanRequestsNewValueAndKeepsSavedValueBinding() {
        var item = createField("boolean");
        if (!item) return;
        var box = findChild(item, "descriptorBooleanBox");
        var requests = spy(item, "writeRequested");
        compare(box.checked, false);
        activate(box);
        compare(requests.count, 1);
        compare(requests.signalArguments[0][1], "true");
        compare(box.checked, false);
        var next = field("boolean", 0);
        next.value = true;
        item.modelData = next;
        compare(box.checked, true);
    }

    function test_pendingAndMissingProviderDisableControls_data() {
        return [
            {tag: "secret", kind: "secret", names: ["descriptorSecretButton"]},
            {tag: "text", kind: "text", names: ["descriptorTextField", "descriptorTextSaveButton"]},
            {tag: "number", kind: "number", names: ["descriptorTextField", "descriptorTextSaveButton"]},
            {tag: "enum", kind: "enum", names: ["descriptorEnumBox", "descriptorEnumSaveButton"]},
            {tag: "boolean", kind: "boolean", names: ["descriptorBooleanBox"]}
        ];
    }

    function test_pendingAndMissingProviderDisableControls(data) {
        var item = createField(data.kind);
        if (!item) return;
        for (var i = 0; i < data.names.length; i++) {
            var control = findChild(item, data.names[i]);
            verify(control.visible && control.enabled);
            item.writePending = true;
            verify(!control.enabled);
            item.writePending = false;
            verify(control.enabled);
            item.providerAvailable = false;
            verify(!control.enabled);
            item.providerAvailable = true;
            verify(control.enabled);
        }
    }
}
