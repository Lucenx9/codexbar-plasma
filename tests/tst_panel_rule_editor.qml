import QtQuick
import QtTest
import "../contents/ui/PanelRules.js" as PanelRules

TestCase {
    id: testCase
    name: "PanelRuleEditor"
    when: windowShown
    width: 520
    height: 180
    visible: true
    property var holder

    QtObject {
        id: configPage
        property string storedRules: "{}"
        readonly property var panelVisibilityRules: PanelRules.normalizedRules(storedRules)
        function setPanelVisibilityRule(elementID, patch) {
            storedRules = PanelRules.updatedRules(storedRules, elementID, patch);
        }
    }

    function init() {
        configPage.storedRules = "{}";
    }

    function cleanup() {
        if (holder)
            holder.destroy();
    }

    function test_keyboardEditingAndDefaultsStaySynchronized() {
        try {
            holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component editor: Component { Components.PanelRuleEditor { function i18n(text) { return text } } } }', testCase, Qt.resolvedUrl("PanelRuleEditorTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.kirigami" is not installed/.test(String(error))) {
                skip("Panel rule editor checks need the optional KDE QML modules");
                return;
            }
            throw error;
        }
        var editor = createTemporaryObject(holder.editor, testCase, {
            configPage: configPage,
            elementID: "text",
            width: 480
        });
        verify(editor !== null);
        var condition = findChild(editor, "textVisibilityCondition");
        var threshold = findChild(editor, "textVisibilityThreshold");
        verify(condition !== null && threshold !== null);
        condition.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(configPage.panelVisibilityRules.text.condition, "usageAtLeast");
        tryCompare(threshold, "visible", true);
        compare(threshold.value, 80);
        threshold.forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(configPage.panelVisibilityRules.text.usedPercent, 81);

        configPage.storedRules = '{"text":{"condition":"resetWithin","resetMinutes":15}}';
        tryCompare(condition, "currentIndex", 2);
        compare(threshold.value, 15);
        compare(threshold.to, 10080);
        configPage.storedRules = "{}";
        tryCompare(condition, "currentIndex", 0);
        verify(!threshold.visible);
        compare(configPage.panelVisibilityRules.meters.condition, "always");
    }

    function test_unreadableThresholdTextKeepsTheRule_data() {
        return [
            {tag: "cleared-minutes", rules: '{"text":{"condition":"resetWithin","resetMinutes":60}}', field: "resetMinutes", value: 60, keys: [Qt.Key_Backspace]},
            {tag: "cleared-percent", rules: '{"text":{"condition":"usageAtLeast","usedPercent":80}}', field: "usedPercent", value: 80, keys: [Qt.Key_Backspace]},
            {tag: "retyped", rules: '{"text":{"condition":"resetWithin","resetMinutes":60}}', field: "resetMinutes", value: 90, keys: [Qt.Key_9, Qt.Key_0]},
            // A grouping locale cannot regroup five digits above the maximum.
            {tag: "above-maximum", rules: '{"text":{"condition":"resetWithin","resetMinutes":60}}', field: "resetMinutes", value: 10080, keys: [Qt.Key_1, Qt.Key_2, Qt.Key_0, Qt.Key_0, Qt.Key_0], locale: "en_US"},
            {tag: "above-maximum-de", rules: '{"text":{"condition":"resetWithin","resetMinutes":60}}', field: "resetMinutes", value: 10080, keys: [Qt.Key_9, Qt.Key_9, Qt.Key_9, Qt.Key_9, Qt.Key_9], locale: "de_DE"}
        ];
    }

    // Clearing or mistyping the threshold must not save the minimum, which
    // turns "Usage at least" into always and "Reset within" into one minute.
    function test_unreadableThresholdTextKeepsTheRule(data) {
        if (!holder) {
            try {
                holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component editor: Component { Components.PanelRuleEditor { function i18n(text) { return text } } } }', testCase, Qt.resolvedUrl("PanelRuleEditorTest.qml"));
            } catch (error) {
                if (/module "org\.kde\.kirigami" is not installed/.test(String(error))) {
                    skip("Panel rule editor checks need the optional KDE QML modules");
                    return;
                }
                throw error;
            }
        }
        configPage.storedRules = data.rules;
        var editor = createTemporaryObject(holder.editor, testCase, {
            configPage: configPage,
            elementID: "text",
            width: 480
        });
        var threshold = findChild(editor, "textVisibilityThreshold");
        tryCompare(threshold, "visible", true);
        if (data.locale)
            threshold.locale = Qt.locale(data.locale);
        threshold.contentItem.forceActiveFocus(Qt.TabFocusReason);
        threshold.contentItem.selectAll();
        for (var i = 0; i < data.keys.length; i++)
            keyClick(data.keys[i]);
        keyClick(Qt.Key_Return);
        compare(configPage.panelVisibilityRules.text[data.field], data.value);
        compare(threshold.value, data.value);
        compare(threshold.valueFromText("", threshold.locale), data.value);
        compare(threshold.valueFromText("invalid", threshold.locale), data.value);
    }

    function test_interactiveEditsFollowExternalRuleChanges() {
        if (!holder) {
            try {
                holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component editor: Component { Components.PanelRuleEditor { function i18n(text) { return text } } } }', testCase, Qt.resolvedUrl("PanelRuleEditorTest.qml"));
            } catch (error) {
                if (/module "org\.kde\.kirigami" is not installed/.test(String(error))) {
                    skip("Panel rule editor checks need the optional KDE QML modules");
                    return;
                }
                throw error;
            }
        }
        var editor = createTemporaryObject(holder.editor, testCase, {
            configPage: configPage,
            elementID: "text",
            width: 480
        });
        verify(editor !== null);
        var condition = findChild(editor, "textVisibilityCondition");
        var threshold = findChild(editor, "textVisibilityThreshold");
        verify(condition !== null && threshold !== null);
        // Interactive edits write the control values imperatively, severing
        // the declarative bindings, then emit their interaction signals. Both
        // controls must still follow external rule changes afterwards, such as
        // the restore-defaults action on the General settings page.
        condition.currentIndex = 1;
        condition.activated(1);
        compare(configPage.panelVisibilityRules.text.condition, "usageAtLeast");
        tryCompare(threshold, "visible", true);
        threshold.value = 90;
        threshold.valueModified();
        compare(configPage.panelVisibilityRules.text.usedPercent, 90);
        configPage.storedRules = '{"text":{"condition":"resetWithin","resetMinutes":15}}';
        tryCompare(condition, "currentIndex", 2);
        tryCompare(threshold, "value", 15);
        configPage.storedRules = "{}";
        tryCompare(condition, "currentIndex", 0);
        tryCompare(threshold, "visible", false);
    }
}
