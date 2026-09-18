"""Exercise notification delivery with synthetic transports and notify-send."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "contents/ui/controllers/NotificationDispatcher.qml"

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "NotificationDispatcher"

    function create() {
        var factory = Qt.createComponent(CONTROLLER_URL);
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("NotificationDispatcher needs the optional KDE QML modules");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase);
        verify(subject !== null);
        return subject;
    }

    TESTS
}
'''

TRANSPORT = '''property var connected: []
        property var started: []
        property bool immediate: false
        signal newData(string sourceName, var data)
        signal disconnected(string sourceName)
        function connectSource(sourceName) {
            connected = connected.concat(sourceName)
            started = started.concat(sourceName)
            if (immediate) newData(sourceName, {"exit code": 0})
        }
        function disconnectSource(sourceName) {
            if (connected.indexOf(sourceName) < 0) return
            connected = connected.filter(function(name) { return name !== sourceName })
            disconnected(sourceName)
        }'''

TRANSPORT_TESTS = '''
    function test_immediateRepliesAndRepeatedMessages() {
        var subject = create();
        subject.testSource.immediate = true;
        verify(subject.send("same", "body", "normal"));
        compare(subject.sending, false);
        compare(subject.testSource.connected, []);
        verify(subject.send("same", "body", "normal"));
        compare(subject.testSource.started.length, 2);
        verify(subject.testSource.started[0] !== subject.testSource.started[1]);
        compare(subject.sending, false);
        compare(subject.testSource.connected, []);
    }

    function test_concurrentAndLateReplies() {
        var subject = create();
        verify(subject.send("same", "body", "normal"));
        verify(subject.send("same", "body", "normal"));
        var sources = subject.testSource.started;
        compare(sources.length, 2);
        verify(sources[0] !== sources[1]);
        subject.testSource.newData(sources[0], {"exit code": 1, stderr: "synthetic failure"});
        compare(subject.sending, true);
        compare(subject.testSource.connected, [sources[1]]);
        subject.testSource.newData(sources[0], {"exit code": 0});
        compare(subject.testSource.connected, [sources[1]]);
        subject.testSource.newData(sources[1], null);
        compare(subject.sending, false);
        compare(subject.testSource.connected, []);
    }

    function test_invalidTextDoesNotStartAProcess() {
        var subject = create();
        verify(!subject.send(null, "body", "normal"));
        verify(!subject.send("title", {toString: null}, "normal"));
        compare(subject.sending, false);
        compare(subject.testSource.started, []);
    }

    function test_completionCommitsBeforeDisconnect() {
        var subject = create();
        subject.send("first", "body", "normal");
        var first = subject.testSource.started[0];
        var observed = [];
        subject.testSource.disconnected.connect(function(source) {
            observed.push(subject.sending);
            if (source === first) {
                subject.send("second", "body", "normal");
                subject.testSource.newData(first, {"exit code": 0});
            }
        });
        subject.testSource.newData(first, {"exit code": 0});
        compare(observed, [false]);
        compare(subject.sending, true);
        compare(subject.testSource.connected, [subject.testSource.started[1]]);
        subject.testSource.newData(subject.testSource.started[1], {"exit code": 0});
        compare(observed, [false, false]);
    }

    function test_realDeadlineAndRecovery() {
        var subject = create();
        subject.send("never completes", "body", "normal");
        var expiredSource = subject.testSource.started[0];
        var start = Date.now();
        tryCompare(subject, "sending", false, 13000);
        verify(Date.now() - start >= 9900);
        compare(subject.testSource.connected, []);
        subject.send("recovery", "body", "normal");
        subject.testSource.newData(expiredSource, {"exit code": 0});
        compare(subject.sending, true);
        compare(subject.testSource.connected, [subject.testSource.started[1]]);
        subject.testSource.newData(subject.testSource.started[1], {"exit code": 0});
        compare(subject.sending, false);
    }

    function test_destructionDisconnectsEveryRequest() {
        var subject = create();
        subject.send("first", "body", "normal");
        subject.send("second", "body", "normal");
        var sources = subject.testSource.started;
        var disconnected = [];
        var reentrantAccepted = [];
        subject.testSource.disconnected.connect(function(source) {
            disconnected.push(source);
            reentrantAccepted.push(subject.send("during destruction", "body", "normal"));
        });
        subject.destroy();
        tryVerify(function() { return disconnected.length === 2; });
        compare(disconnected.sort(), sources.slice().sort());
        // Reentrant sends during destruction return no source name.
        verify(!reentrantAccepted[0]);
        verify(!reentrantAccepted[1]);
    }

    function test_actionSendActivatesOnlyItsOwnSource() {
        var subject = create();
        var activated = [];
        subject.activated.connect(function(source) { activated.push(source); });
        var actionSource = subject.send("update", "body", "normal", "Open release page");
        var plainSource = subject.send("plain", "body", "normal");
        verify(actionSource.length > 0);
        verify(plainSource.length > 0);
        verify(actionSource !== plainSource);
        subject.testSource.newData(plainSource, {"exit code": 0, stdout: ""});
        compare(activated, []);
        compare(subject.testSource.connected, [actionSource]);
        subject.testSource.newData(actionSource, {"exit code": 0, stdout: "default\n"});
        compare(activated, [actionSource]);
        compare(subject.sending, false);
        compare(subject.testSource.connected, []);
        // A late replay of the retired action source must not reactivate.
        subject.testSource.newData(actionSource, {"exit code": 0, stdout: "default\n"});
        compare(activated, [actionSource]);
    }

    function test_closedActionNotificationsNeverActivate() {
        var subject = create();
        var activated = [];
        subject.activated.connect(function(source) { activated.push(source); });
        var dismissedSource = subject.send("update", "body", "normal", "Open release page");
        subject.testSource.newData(dismissedSource, {"exit code": 1, stdout: ""});
        compare(activated, []);
        compare(subject.sending, false);
        var noisySource = subject.send("update", "body", "normal", "Open release page");
        subject.testSource.newData(noisySource, {"exit code": 0, stdout: "x".repeat(4096) + "default"});
        compare(activated, []);
        compare(subject.sending, false);
    }
'''

REAL_TESTS = '''
    function test_realArgumentBoundariesAndFailures() {
        var subject = create();
        var messages = MESSAGES;
        for (var message of messages)
            verify(subject.send(message.title, message.body, message.urgency));
        tryCompare(subject, "sending", false, 5000);
        verify(subject.send("synthetic failure", "", "low"));
        tryCompare(subject, "sending", false, 5000);
        verify(subject.send("recovery", "ok", "normal"));
        tryCompare(subject, "sending", false, 5000);
    }
'''

REAL_ACTION_TESTS = '''
    function test_realActionSendActivatesThroughStdout() {
        var subject = create();
        var activated = [];
        subject.activated.connect(function(source) { activated.push(source); });
        var source = subject.send("update available", "body", "normal", "Open release page");
        verify(source.length > 0);
        tryCompare(subject, "sending", false, 5000);
        compare(activated, [source]);
    }
'''


class NotificationDispatcherTests(unittest.TestCase):
    def run_qml(self, directory, controller, tests, env=None):
        fixture = directory / "tst_notification_dispatcher.qml"
        fixture.write_text(QML.replace("CONTROLLER_URL", json.dumps(controller.as_uri()))
                           .replace("TESTS", tests))
        result = subprocess.run(
            [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software", **(env or {})},
            capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        if "SKIP" in output:
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                self.fail("The test environment must provide the KDE QML modules.\n" + output)
            self.skipTest("NotificationDispatcher needs the optional KDE QML modules")
        self.assertNotIn("QWARN", output)

    def test_transport_ordering_timeout_and_destruction(self):
        # Keep the production lifecycle and timers; substitute only DataSource
        # so synchronous cached replies and replies after retirement are explicit.
        source = CONTROLLER.read_text()
        source = source.replace('import org.kde.plasma.plasma5support as Plasma5Support\n', '')
        for module in ("CommandLedger", "NotificationCommand"):
            source = source.replace('"../' + module + '.js"',
                                    json.dumps((ROOT / "contents/ui" / (module + ".js")).as_uri()))
        source = source.replace('id: controller', 'id: controller\n    property alias testSource: notificationSource', 1)
        source = source.replace('Plasma5Support.DataSource {', 'QtObject {')
        source = source.replace('engine: "executable"', TRANSPORT)
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-order-") as temporary:
            directory = Path(temporary)
            controller = directory / "Dispatcher.qml"
            controller.write_text(source)
            self.run_qml(directory, controller, TRANSPORT_TESTS)

    def test_real_notify_send_arguments_and_failure_recovery(self):
        with tempfile.TemporaryDirectory(prefix="codexbar notification 'test-") as temporary:
            directory = Path(temporary)
            log = directory / "calls.jsonl"
            marker = directory / "injection-marker"
            executable = directory / "notify-send"
            executable.write_text('''#!/usr/bin/python3
import json
import os
import sys
with open(os.environ["NOTIFICATION_TEST_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
if any(argument.startswith("--action=") for argument in sys.argv):
    print("default")
sys.exit(1 if "synthetic failure" in sys.argv else 0)
''')
            executable.chmod(0o755)
            messages = [
                {"title": "  Codex's quota  ", "body": "  line one\nline two\t€  ", "urgency": " critical "},
                {"title": "--help", "body": "--version", "urgency": "low"},
                {"title": " \t", "body": " ", "urgency": "unexpected"},
                {"title": "same", "body": "same", "urgency": "normal"},
                {"title": "same", "body": "same", "urgency": "normal"},
                {"title": "' ; touch \"" + str(marker) + "\"; #",
                 "body": '$(touch "' + str(marker) + '") `touch "' + str(marker) + '"` $HOME \\ * ; & |',
                 "urgency": "normal; touch " + str(marker)},
            ]
            self.run_qml(directory, CONTROLLER,
                         REAL_TESTS.replace("MESSAGES", json.dumps(messages)),
                         {"PATH": str(directory) + os.pathsep + os.environ.get("PATH", ""),
                          "NOTIFICATION_TEST_LOG": str(log)})
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            expected = []
            for message in messages + [{"title": "synthetic failure", "body": "", "urgency": "low"},
                                       {"title": "recovery", "body": "ok", "urgency": "normal"}]:
                urgency = message["urgency"].strip()
                if urgency not in ("low", "normal", "critical"):
                    urgency = "normal"
                expected.append(["--app-name=CodexBar", "--icon=view-statistics", "--urgency=" + urgency,
                                 "--", message["title"].strip() or "CodexBar", message["body"].strip()])
            self.assertCountEqual(calls, expected)
            self.assertFalse(marker.exists(), "notification text must not execute shell commands")

    def test_real_action_activation_and_capability_probe(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-action-") as temporary:
            directory = Path(temporary)
            log = directory / "calls.jsonl"
            executable = directory / "notify-send"
            # The capability probe runs first and must advertise --action;
            # the action send answers with the activated default action name.
            executable.write_text('''#!/usr/bin/python3
import json
import os
import sys
with open(os.environ["NOTIFICATION_TEST_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
if "--help" in sys.argv:
    print("  -A, --action=[NAME=]Text  notification actions")
elif any(argument.startswith("--action=") for argument in sys.argv):
    print("default")
sys.exit(0)
''')
            executable.chmod(0o755)
            self.run_qml(directory, CONTROLLER, REAL_ACTION_TESTS,
                         {"PATH": str(directory) + os.pathsep + os.environ.get("PATH", ""),
                          "NOTIFICATION_TEST_LOG": str(log)})
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[0], ["--help"])
            self.assertEqual(calls[1], ["--app-name=CodexBar", "--icon=view-statistics",
                                        "--urgency=normal", "--action=default=Open release page",
                                        "--", "update available", "body"])

    def test_real_action_falls_back_without_capability(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-legacy-") as temporary:
            directory = Path(temporary)
            log = directory / "calls.jsonl"
            executable = directory / "notify-send"
            # A libnotify 0.7 notify-send has no --action: the probe must
            # route the send through the plain command instead of failing.
            executable.write_text('''#!/usr/bin/python3
import json
import os
import sys
with open(os.environ["NOTIFICATION_TEST_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(0)
''')
            executable.chmod(0o755)
            self.run_qml(directory, CONTROLLER, '''
    function test_realActionSendFallsBackToPlain() {
        var subject = create();
        var activated = [];
        subject.activated.connect(function(source) { activated.push(source); });
        verify(subject.send("update available", "body", "normal", "Open release page").length > 0);
        tryCompare(subject, "sending", false, 5000);
        compare(activated, []);
    }
''', {"PATH": str(directory) + os.pathsep + os.environ.get("PATH", ""),
      "NOTIFICATION_TEST_LOG": str(log)})
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(calls, [["--help"],
                                     ["--app-name=CodexBar", "--icon=view-statistics",
                                      "--urgency=normal", "--", "update available", "body"]])

    def test_missing_notify_send_completes_quietly(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-missing-") as temporary:
            directory = Path(temporary)
            self.run_qml(directory, CONTROLLER, '''
    function test_missingExecutable() {
        var subject = create();
        verify(subject.send("title", "body", "normal"));
        tryCompare(subject, "sending", false, 5000);
    }
''', {"PATH": str(directory)})


if __name__ == "__main__":
    unittest.main()
