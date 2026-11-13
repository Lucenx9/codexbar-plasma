import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../contents/ui/components" as Components

TestCase {
    id: testCase
    name: "AnalysisAssistant"
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
        property string lastQuestion: ""

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
        function generateAiInsight(question) {
            generateCalls++;
            lastQuestion = question;
        }
        function performAction() {
        }
    }

    Component {
        id: assistantComponent
        Components.AnalysisAssistant { width: 480; applet: mockApplet }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (var child of item.children) {
            var result = find(child, name)
            if (result) return result
        }
        return null
    }
    function init() {
        mockApplet.aiInsightsEnabled = true
        mockApplet.aiInsightsBusy = false
        mockApplet.aiInsightsConfigured = true
        mockApplet.aiInsightsCacheState = "current"
        mockApplet.generateCalls = 0
    }
    function test_disclosureDoesNotGenerate() {
        var subject = createTemporaryObject(assistantComponent, testCase)
        verify(subject !== null)
        verify(!subject.answerExpanded)
        var toggle = find(subject, "analysisAssistantToggle")
        toggle.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space)
        verify(subject.answerExpanded)
        compare(mockApplet.generateCalls, 0)
        compare(find(subject, "aiInsightsSummary").text, cacheSummary)
    }
    function test_explicitQuestionAndBusyGuard() {
        var subject = createTemporaryObject(assistantComponent, testCase, {answerExpanded: true})
        verify(subject !== null)
        var question = find(subject, "analysisQuestion")
        question.currentIndex = 2
        find(subject, "aiInsightsGenerateButton").requested()
        compare(mockApplet.generateCalls, 1)
        compare(mockApplet.lastQuestion, "headroom")
        mockApplet.aiInsightsBusy = true
        verify(!subject.canGenerate)
        verify(!question.enabled)
    }
    function test_disabledAndForeignCacheDoNotPresentAnswers() {
        var subject = createTemporaryObject(assistantComponent, testCase, {answerExpanded: true})
        mockApplet.aiInsightsCacheState = "otherContext"
        verify(!subject.showsAnswer)
        mockApplet.aiInsightsEnabled = false
        verify(!subject.canGenerate)
        compare(mockApplet.generateCalls, 0)
    }
    function test_untrustedAnswerStaysPlain() {
        var subject = createTemporaryObject(assistantComponent, testCase, {answerExpanded: true})
        var label = find(subject, "aiInsightsSummary")
        compare(label.textFormat, Text.PlainText)
        subject.width = 260
        waitForRendering(subject)
        verify(label.width <= subject.width)
    }
}
