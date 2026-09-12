"""Exercise session-source isolation with production QML bindings and replies."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

FUNCTIONS = (
    "buildSessionsCommand", "shellQuote", "commandWithRunNonce",
    "buildCommandDescriptor", "connectUsageCommand", "finishUsageCommandSource",
    "retireUsageCommandKind", "requestSessionsRefresh", "refreshSessionsIfStale",
    "refreshSessions", "parseSessionsOutput", "handleCommandTimeout",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/SessionRefreshPolicy.js" as SessionRefreshPolicy
import "SOURCE_URL/SafeText.js" as SafeText
TestCase {
    name: "SessionContext"
    Component {
        id: harness
        QtObject {
            id: root
            property double nowMs: 1000000
            property string commandPath: "codexbar-a"
            property bool expanded: false
            property bool sessionsSelected: true
            property var sessions: []
            property string sessionsErrorText: ""
            property string sessionsLastUpdatedText: ""
            property bool sessionsLoading: false
            property double sessionsLastFinishedAtMs: -1
            property double sessionsLastCompletedAtMs: -1
            property string sessionsLoadedCommandSource: ""
            property int sessionsStaleAfterMs: 300000
            property int sessionsCommandTimeoutMs: 60000
            property int defaultCommandTimeoutMs: 120000
            property int commandRunSerial: 0
            property var activeCommandDescriptors: ({})
            property var startedSources: []
            property var finishedSources: []

            SOURCE_BINDINGS
            SOURCE_FUNCTIONS
            SOURCE_HANDLERS

            function i18n(text) { return text; }
            function boundedCliMessage(value) { return String(value); }
            // The timer and process effects are outside this state transition.
            function scheduleSessionsRefreshCheck() {}
            property QtObject engine: QtObject {
                id: usageSource
                signal newData(string sourceName, var data)
                function connectSource(sourceName) {
                    root.startedSources = root.startedSources.concat(sourceName);
                }
                function disconnectSource(sourceName) {
                    root.finishedSources = root.finishedSources.concat(sourceName);
                }
                SOURCE_REPLY_HANDLER
            }
        }
    }

    function sessionOutput(name) {
        return JSON.stringify([{provider: "codex", projectName: name,
            sessionName: name, state: "active", source: "cli"}]);
    }

    function loadedApplet() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        wait(0);
        applet.parseSessionsOutput(sessionOutput("Workspace A"), "");
        compare(applet.sessions.length, 1);
        compare(applet.sessionsLoadedCommandSource, applet.sessionsCommandSource);
        verify(applet.sessionsLastCompletedAtMs > 0);
        return applet;
    }

    function test_sourceChangeInvalidatesTheCompletedSnapshot_data() {
        return [{tag: "hidden", visible: false}, {tag: "visible", visible: true}];
    }

    function test_sourceChangeInvalidatesTheCompletedSnapshot(data) {
        var applet = loadedApplet();
        applet.expanded = data.visible;
        applet.sessionsErrorText = "previous-source error";
        applet.commandPath = "codexbar-b";
        // Invalidation is synchronous, including while the popup is hidden.
        compare(applet.sessions.length, 0);
        compare(applet.sessionsLastUpdatedText, "");
        compare(applet.sessionsLastCompletedAtMs, -1);
        compare(applet.sessionsLoadedCommandSource, "");
        compare(applet.sessionsErrorText, "");
        if (data.visible) {
            tryCompare(applet, "sessionsLoading", true);
            compare(applet.startedSources.length, 1);
            verify(applet.startedSources[0].indexOf("codexbar-b") !== -1);
        } else {
            wait(0);
            compare(applet.startedSources.length, 0);
            compare(applet.sessionsLoading, false);
        }
    }

    function test_newSourceFailureDoesNotResurrectThePreviousSnapshot_data() {
        return [{tag: "empty-output", timeout: false}, {tag: "timeout", timeout: true}];
    }

    function test_newSourceFailureDoesNotResurrectThePreviousSnapshot(data) {
        var applet = loadedApplet();
        applet.expanded = true;
        verify(applet.refreshSessions());
        var sourceA = applet.startedSources[0];
        applet.commandPath = "codexbar-b";
        tryVerify(function() { return applet.startedSources.length === 2; });
        var sourceB = applet.startedSources[1];
        compare(CommandLedger.find(applet.activeCommandDescriptors, sourceA), null);
        verify(applet.sessionsLoading);
        // Exercise the production DataSource handler, not a parallel reply model.
        applet.engine.newData(sourceA, {stdout: sessionOutput("Late A"), stderr: ""});
        verify(applet.sessionsLoading);
        if (data.timeout) {
            applet.handleCommandTimeout(sourceB,
                CommandLedger.find(applet.activeCommandDescriptors, sourceB));
        } else {
            applet.engine.newData(sourceB, {stdout: "", stderr: "source B failed"});
        }
        compare(applet.sessions.length, 0);
        compare(applet.sessionsLastUpdatedText, "");
        compare(applet.sessionsLastCompletedAtMs, -1);
        compare(applet.sessionsLoading, false);
        verify(applet.sessionsErrorText.length > 0);
        // A response after timeout/retirement must not fill the cleared view.
        applet.engine.newData(sourceB, {stdout: sessionOutput("Late B"), stderr: ""});
        compare(applet.sessions.length, 0);
        verify(applet.refreshSessions());
        var freshSource = applet.startedSources[2];
        applet.engine.newData(freshSource, {stdout: sessionOutput("Workspace B"), stderr: ""});
        compare(applet.sessions.length, 1);
        compare(applet.sessions[0].projectName, "Workspace B");
        compare(applet.sessionsLoadedCommandSource, applet.sessionsCommandSource);
        compare(applet.sessionsErrorText, "");
    }

    function test_sameSourceFailureKeepsItsCompletedSnapshot() {
        var applet = loadedApplet();
        var completedAt = applet.sessionsLastCompletedAtMs;
        var updatedText = applet.sessionsLastUpdatedText;
        verify(applet.refreshSessions());
        applet.engine.newData(applet.startedSources[0], {stdout: "", stderr: "temporary failure"});
        compare(applet.sessions.length, 1);
        compare(applet.sessions[0].projectName, "Workspace A");
        compare(applet.sessionsLastCompletedAtMs, completedAt);
        compare(applet.sessionsLastUpdatedText, updatedText);
        compare(applet.sessionsLoadedCommandSource, applet.sessionsCommandSource);
        compare(applet.sessionsLoading, false);
        compare(applet.sessionsErrorText, "temporary failure");
    }

    function test_failedScanDoesNotRestartWhenReopening_data() {
        return [
            {tag: "empty-reply", output: "", timeout: false},
            {tag: "invalid-json", output: "{", timeout: false},
            {tag: "unsupported-payload", output: "{}", timeout: false},
            {tag: "timeout", output: "", timeout: true}
        ];
    }

    function test_failedScanDoesNotRestartWhenReopening(data) {
        var applet = createTemporaryObject(harness, this, {});
        applet.expanded = true;
        verify(applet.refreshSessionsIfStale());
        var source = applet.startedSources[0];
        applet.nowMs += applet.sessionsStaleAfterMs;
        if (data.timeout) {
            applet.handleCommandTimeout(source,
                CommandLedger.find(applet.activeCommandDescriptors, source));
        } else {
            applet.engine.newData(source, {stdout: data.output, stderr: "scan failed"});
        }
        compare(applet.sessionsLoading, false);
        compare(applet.sessionsLastCompletedAtMs, -1);
        var error = applet.sessionsErrorText;
        verify(error.length > 0);
        applet.expanded = false;
        verify(!applet.refreshSessionsIfStale());
        applet.expanded = true;
        verify(!applet.refreshSessionsIfStale());
        compare(applet.startedSources.length, 1);
        compare(applet.sessionsErrorText, error);
        var finishedAt = applet.sessionsLastFinishedAtMs;
        applet.nowMs += 1;
        applet.engine.newData(source, {stdout: sessionOutput("Late scan"), stderr: ""});
        compare(applet.sessionsLastFinishedAtMs, finishedAt);
        applet.nowMs = finishedAt + applet.sessionsStaleAfterMs - 1;
        verify(!applet.refreshSessionsIfStale());
        // Explicit retry remains available during the automatic cooldown.
        verify(applet.refreshSessions());
        compare(applet.startedSources.length, 2);
        applet.engine.newData(applet.startedSources[1], {stdout: "", stderr: "failed again"});
        applet.nowMs += applet.sessionsStaleAfterMs;
        verify(applet.refreshSessionsIfStale());
        compare(applet.startedSources.length, 3);
    }

    function test_sourceChangeClearsTheFailedAttemptCooldown() {
        var applet = createTemporaryObject(harness, this, {});
        applet.expanded = true;
        verify(applet.refreshSessionsIfStale());
        applet.engine.newData(applet.startedSources[0], {stdout: "", stderr: "scan failed"});
        verify(!applet.refreshSessionsIfStale());
        applet.commandPath = "codexbar-b";
        tryVerify(function() { return applet.startedSources.length === 2; });
        verify(applet.startedSources[1].indexOf("codexbar-b") !== -1);
        verify(applet.sessionsLoading);
    }
}
'''


class SessionContextTests(unittest.TestCase):
    def test_session_snapshots_stay_with_their_command_source(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        binding = re.search(r"^    property string sessionsCommandSource: .+$",
                            source, re.MULTILINE).group(0)
        handler = "onSessionsCommandSourceChanged: {" + applet.handler_body(
            "onSessionsCommandSourceChanged") + "}"
        engine = applet.id_block("usageSource")
        reply = re.search(r"onNewData:\s*function\([^)]*\)\s*\{", engine)
        reply_handler = reply.group(0) + Surface._match_braces(engine, reply.end() - 1) + "}"
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_BINDINGS", binding)
        qml = qml.replace("SOURCE_HANDLERS", handler)
        qml = qml.replace("SOURCE_REPLY_HANDLER", reply_handler)
        qml = qml.replace("Date.now()", "root.nowMs")
        with tempfile.TemporaryDirectory(prefix="codexbar-session-context-") as temporary:
            fixture = Path(temporary) / "tst_session_context.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
