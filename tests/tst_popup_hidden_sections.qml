import QtQuick
import QtTest
import "../contents/ui/PopupHiddenSections.js" as Sections

TestCase {
    name: "PopupHiddenSections"

    function test_titleIdentityAndUnhideableInput() {
        var key = Sections.sectionKey({title: "Budgets", rows: []});
        verify(/^v1:[0-9a-f]{32}$/.test(key));
        compare(Sections.sectionKey({title: " Budgets ", rows: [{value: "new"}]}), key);
        verify(Sections.sectionKey({title: "Models"}) !== key);
        [null, [], {}, {title: 1}, {title: "  "}, {title: "x".repeat(3841)}].forEach(function(value) {
            compare(Sections.sectionKey(value), "");
        });
        verify(Sections.sectionKey({title: "予算 & <b>"}).length > 0);
    }

    function test_untrustedStorage() {
        [null, 42, "", "{", "{}", "[" + " ".repeat(16400) + "]"].forEach(function(raw) {
            compare(Sections.parse(raw), []);
        });
        var key = Sections.sectionKey({title: "Budgets"});
        compare(Sections.parse(JSON.stringify([
            {provider: "codex", section: key, title: "must not survive"},
            {provider: "codex", section: key},
            {provider: "__proto__", section: key},
            {provider: "", section: key},
            {provider: 3, section: key},
            {provider: "codex", section: "Budgets"},
            {provider: "codex", section: key + "\n"},
            {provider: "codex"}, null, [], "bad"
        ])), [{provider: "codex", section: key}]);
    }

    function test_persistenceFilteringAndRestoration() {
        var budget = {title: "Budgets", rows: [{value: "25"}]};
        var models = {title: "Models"};
        var untitled = {title: ""};
        var key = Sections.sectionKey(budget);
        var before = [];
        var hidden = Sections.hidden(before, "codex", key);
        compare(before, []);
        hidden = Sections.hidden(hidden, "claude", key);
        hidden = Sections.hidden(hidden, "codex", Sections.sectionKey(models));
        compare(Sections.hidden(hidden, "codex", key), hidden);
        compare(Sections.hidden(hidden, "codex", "bad"), hidden);
        var stored = Sections.serialize(hidden);
        verify(stored.indexOf("Budgets") < 0);
        hidden = Sections.parse(stored);
        compare(Sections.providers(hidden), ["codex", "claude"]);
        var reordered = [models, untitled, {title: "Budgets", rows: [{value: "99"}]}, budget];
        compare(Sections.visibleSections(reordered, hidden, "codex"), [untitled]);
        compare(Sections.hiddenSections(reordered, hidden, "codex"), [models, reordered[2]]);
        compare(Sections.visibleSections(reordered, hidden, "gemini"), reordered);
        compare(reordered.length, 4);
        var renamed = {title: "New budgets"};
        compare(Sections.visibleSections([renamed], hidden, "codex"), [renamed]);
        var restored = Sections.restored(hidden, "codex", key);
        compare(Sections.visibleSections(reordered, restored, "codex"), [untitled, reordered[2], budget]);
        compare(Sections.restoredProvider(hidden, "codex"), [{provider: "claude", section: key}]);
        compare(Sections.serialize(Sections.restoredProvider(restored, "claude")).indexOf("claude"), -1);
        compare(Sections.serialize([]), "");
        compare(Sections.visibleSections(null, hidden, "codex"), []);
        compare(Sections.hiddenSections(null, hidden, "codex"), []);
    }

    function test_capacityPreservesExistingChoices() {
        var entries = [];
        var key = Sections.sectionKey({title: "Budgets"});
        for (var i = 0; i < Sections.maximumEntries; i++)
            entries = Sections.hidden(entries, "provider" + i, key);
        compare(Sections.hidden(entries, "newprovider", key), entries);
        var oversized = entries.concat([{provider: "newprovider", section: key}]);
        compare(Sections.parse(JSON.stringify(oversized)), entries);
        var restored = Sections.restoredProvider(entries, "provider0");
        compare(Sections.hidden(restored, "newprovider", key).length, Sections.maximumEntries);
    }
}
