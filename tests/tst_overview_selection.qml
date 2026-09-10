import QtQuick
import QtTest

// Overview provider checkboxes must recognize CLI aliases and mixed-case IDs,
// matching the runtime normalization in main.qml and the panel selection.
// The settings roster keeps raw CLI spellings (e.g. groqcloud), while the
// stored selection and the runtime roster use canonical keys (e.g. groq).
TestCase {
    id: testCase
    name: "OverviewSelection"
    when: windowShown

    function i18n(text, value) {
        return value === undefined ? text : String(text).replace("%1", value);
    }
    function i18np(singular, plural, count) {
        return String(count === 1 ? singular : plural).replace("%1", count);
    }

    function createPage(properties) {
        var component = Qt.createComponent("../contents/ui/configPopup.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Overview selection checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        var page = createTemporaryObject(component, testCase, Object.assign({
            width: 620,
            height: 760
        }, properties || {}));
        verify(page !== null);
        var controller = findChild(page, "providerRosterController");
        verify(controller !== null);
        controller.active = false;
        return page;
    }

    function setRoster(page, providerIDs) {
        var controller = findChild(page, "providerRosterController");
        verify(controller !== null);
        controller.active = false;
        controller.enabledProviderRoster = providerIDs.map(function (providerID) {
            return {
                provider: providerID,
                displayName: providerID
            };
        });
        page.cfg_providerOrder = "";
    }

    function test_selectionRecognizesAliasesAndMixedCase() {
        failOnWarning(/^(?!QProcess: Destroyed while process \("\/bin\/sh"\) is still running\.$).*/);
        var page = createPage({
            cfg_overviewProviderIDs: "groq"
        });
        if (!page)
            return;
        setRoster(page, ["groqcloud", "codex"]);
        verify(page.overviewProviderSelected("groq"));
        verify(page.overviewProviderSelected("groqcloud"));
        verify(page.overviewProviderSelected("GROQCLOUD"));
        verify(!page.overviewProviderSelected("codex"));

        page.cfg_overviewProviderIDs = "groqcloud";
        verify(page.overviewProviderSelected("groq"));
        compare(page.parseOverviewProviderIDs("groqcloud,Codex").join(","), "groq,codex");

        page.cfg_overviewProviderIDs = "Codex";
        verify(page.overviewProviderSelected("codex"));
        verify(page.overviewProviderSelected("CODEX"));
    }

    function test_toggleNormalizesAliasesAndKeepsAbsentSelection() {
        failOnWarning(/^(?!QProcess: Destroyed while process \("\/bin\/sh"\) is still running\.$).*/);
        var page = createPage({
            cfg_overviewProviderIDs: "__none__"
        });
        if (!page)
            return;
        setRoster(page, ["groqcloud", "codex", "claude"]);

        page.toggleOverviewProvider("GROQCLOUD", true);
        compare(page.cfg_overviewProviderIDs, "groq");
        verify(page.overviewProviderSelected("groqcloud"));

        page.toggleOverviewProvider("groqcloud", false);
        compare(page.cfg_overviewProviderIDs, "__none__");

        page.cfg_overviewProviderIDs = "codex,opencode";
        page.toggleOverviewProvider("codex", false);
        compare(page.cfg_overviewProviderIDs, "opencode");
    }

    function test_parseRejectsJunkAndCapsAtThree() {
        failOnWarning(/^(?!QProcess: Destroyed while process \("\/bin\/sh"\) is still running\.$).*/);
        var page = createPage({});
        if (!page)
            return;
        compare(page.parseOverviewProviderIDs("constructor,prototype").length, 0);
        compare(page.parseOverviewProviderIDs(new Array(600).join("x")).length, 0);
        compare(page.parseOverviewProviderIDs("codex,codex,CODEX").join(","), "codex");
        compare(page.parseOverviewProviderIDs("codex,claude,gemini,cursor").join(","), "codex,claude,gemini");

        setRoster(page, ["codex", "claude", "gemini", "cursor"]);
        page.cfg_overviewProviderIDs = "";
        compare(page.resolvedOverviewProviderIDs().join(","), "codex,claude,gemini");
        page.cfg_overviewProviderIDs = "codex,claude,gemini";
        page.toggleOverviewProvider("cursor", true);
        compare(page.cfg_overviewProviderIDs, "codex,claude,gemini");
        page.toggleOverviewProvider("", true);
        compare(page.cfg_overviewProviderIDs, "codex,claude,gemini");
    }
}
