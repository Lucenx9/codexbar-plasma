import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    id: testCase
    name: "AiInsightsView"
    when: windowShown
    visible: true
    width: 520
    height: 640

    readonly property string cacheSummary: "Codex runs out before its reset; Claude spend doubled this week while its quota stays low."
    property var holders: []

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, String(arguments[i]));
        return text;
    }

    function i18np(singular, plural, count) {
        var text = count === 1 ? singular : plural;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), String(arguments[i]));
        return text;
    }

    QtObject {
        id: mockApplet

        property bool aiInsightsEnabled: true
        property bool aiInsightsConfigured: true
        property bool aiInsightsBusy: false
        property string aiInsightsErrorReason: ""
        property string aiInsightsCacheState: "current"
        property int aiInsightsIntervalHours: 0
        property var aiInsightsSnapshot: ({sufficient: true, id: "abc", text: "{}"})
        property var aiInsightsCache: ({
                summary: testCase.cacheSummary,
                highlights: ["Codex runs out in about an hour", "Claude spend rose to $21"],
                generatedAtMs: 1000,
                contextKey: "ctx",
                provider: "ollama",
                model: "fixture-model",
                language: "en",
                snapshotId: "abc"
            })
        property double panelClockMs: 120000
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.8
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 4
        property int generateCalls: 0

        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, alpha);
        }
        function elapsedText() {
            return "2 minutes ago";
        }
        function monthDayTimeText() {
            return "Jan 1, 00:00";
        }
        function aiInsightsProviderName() {
            return "Ollama";
        }
        function aiInsightsErrorText() {
            return "Failed";
        }
        function generateAiInsight() {
            generateCalls++;
        }
        function performAction() {
        }
    }

    Component {
        id: cardComponent

        Item {
            width: 480
            height: 400
            property alias card: card

            Components.AiInsightsCard {
                id: card
                width: parent.width
                applet: mockApplet
            }
        }
    }

    Component {
        id: viewComponent

        Item {
            width: 480
            height: 600
            property alias view: view
            property int backs: 0
            property bool lastKeyboard: false

            Components.AiInsightsView {
                id: view
                anchors.fill: parent
                applet: mockApplet
                backText: "Overview"
                onBackRequested: function(keyboard) {
                    parent.backs++
                    parent.lastKeyboard = keyboard
                }
            }
        }
    }

    function create(component) {
        var holder = createTemporaryObject(component, testCase);
        verify(holder !== null);
        waitForRendering(holder);
        return holder;
    }

    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (var i = 0; i < item.children.length; i++) {
            var found = find(item.children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    function hasText(item, text) {
        if (!item || !item.visible)
            return false;
        if (item.text === text && item.width > 0)
            return true;
        for (var i = 0; i < item.children.length; i++) {
            if (hasText(item.children[i], text))
                return true;
        }
        return false;
    }

    function init() {
        mockApplet.aiInsightsEnabled = true;
        mockApplet.aiInsightsBusy = false;
        mockApplet.aiInsightsErrorReason = "";
        mockApplet.aiInsightsCacheState = "current";
        mockApplet.aiInsightsIntervalHours = 0;
        mockApplet.aiInsightsSnapshot = {sufficient: true, id: "abc", text: "{}"};
        mockApplet.generateCalls = 0;
    }

    function test_compactCardOpensWithoutGenerating() {
        var holder = create(cardComponent);
        var card = holder.card;
        var opened = 0;
        var keyboardOpen = null;
        card.openRequested.connect(function(keyboard) {
            opened++;
            keyboardOpen = keyboard;
        });
        compare(find(card, "aiInsightsSummary").maximumLineCount, 3);
        verify(!hasText(card, mockApplet.aiInsightsCache.highlights[0]), "the compact card must not list highlights");
        compare(find(card, "aiInsightsDetailsToggle"), null);
        var open = find(card, "aiInsightsOpenButton");
        verify(open.visible);
        mouseClick(open);
        compare(opened, 1);
        compare(keyboardOpen, false, "a mouse click must not ask for a focus ring");
        // Back focuses a button that was hidden, so it has no earlier focus reason.
        holder.forceActiveFocus();
        card.focusOpenButton(true);
        verify(open.activeFocus, "Back must be able to return focus to Open analysis");
        keyClick(Qt.Key_Space);
        compare(opened, 2, "Open analysis must work from the keyboard");
        compare(keyboardOpen, true);
        compare(mockApplet.generateCalls, 0, "navigation must never start a generation");
        verify(!mockApplet.aiInsightsBusy);
    }

    function test_compactCardKeepsEmptyAndBusyStates() {
        var holder = create(cardComponent);
        var card = holder.card;
        mockApplet.aiInsightsCacheState = "otherContext";
        verify(!card.showsInsight);
        verify(find(card, "aiInsightsEmptyText").visible);
        verify(find(card, "aiInsightsFirstGenerateButton").visible);
        mockApplet.aiInsightsBusy = true;
        verify(!find(card, "aiInsightsEmptyText").visible);
        verify(!find(card, "aiInsightsFirstGenerateButton").visible);
    }

    function test_viewShowsEverythingAndRestrainedContext() {
        var holder = create(viewComponent);
        var view = holder.view;
        verify(hasText(view, testCase.cacheSummary));
        compare(find(view, "aiInsightsSummary").maximumLineCount, 2147483647);
        verify(hasText(view, mockApplet.aiInsightsCache.highlights[0]));
        verify(hasText(view, mockApplet.aiInsightsCache.highlights[1]));
        verify(!find(view, "aiInsightsOpenButton").visible, "the analysis page must not link to itself");
        compare(view.contextLines, [
            "Generated Jan 1, 00:00",
            "A new insight is generated only when you ask for one.",
            "Uses only quota, pace, incident, and 7-day spend and token data. Account names, projects, and paths are never sent."
        ]);
        // Source, model, and freshness stay in the card header only.
        for (var i = 0; i < view.contextLines.length; i++) {
            verify(view.contextLines[i].indexOf("Ollama") < 0 && view.contextLines[i].indexOf("fixture-model") < 0);
        }
        // A changed snapshot hash is no evidence of changed consumption.
        mockApplet.aiInsightsSnapshot = {sufficient: true, id: "def", text: "{}"};
        compare(view.contextLines.length, 3);
        mockApplet.aiInsightsSnapshot = {sufficient: false, id: "", text: ""};
        compare(view.contextLines[1], "Not enough current usage data for an insight yet.");
        mockApplet.aiInsightsIntervalHours = 6;
        compare(view.contextLines[2], "A new insight is generated automatically at most every 6 hours.");
        compare(mockApplet.generateCalls, 0);
    }

    function test_viewGeneratesOnlyOnExplicitRequest() {
        var holder = create(viewComponent);
        var view = holder.view;
        var generate = find(view, "aiInsightsGenerateButton");
        verify(generate.visible);
        compare(mockApplet.generateCalls, 0);
        generate.requested();
        compare(mockApplet.generateCalls, 1);
    }

    function test_backAndEscapeReturn() {
        var holder = create(viewComponent);
        var view = holder.view;
        var back = find(view, "aiInsightsBackButton");
        compare(back.text, "Overview");
        compare(back.Accessible.name, "Back to Overview");
        mouseClick(back);
        compare(holder.backs, 1);
        compare(holder.lastKeyboard, false);
        view.focusBack(true);
        verify(back.activeFocus);
        keyClick(Qt.Key_Escape);
        compare(holder.backs, 2, "Escape on the Back button must return to the origin view");
        compare(holder.lastKeyboard, true);
        // Escape from focus deeper in the page reaches the page as well.
        find(view, "aiInsightsGenerateButton").children[0].forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Escape);
        compare(holder.backs, 3, "Escape inside the page must return to the origin view");
        compare(mockApplet.generateCalls, 0);
    }
}
