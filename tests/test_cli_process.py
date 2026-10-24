"""Execute the shared lifecycle with synchronous and late transport callbacks."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

TRANSPORT = '''property int interval: 0
        property var connected: []
        property var started: []
        property bool immediate: false
        signal newData(string sourceName, var data)
        signal disconnected(string sourceName)
        function connectSource(sourceName) {
            connected = connected.concat(sourceName);
            started = started.concat(sourceName);
            if (immediate) newData(sourceName, {stdout: "[]", stderr: "", "exit code": 0});
        }
        function disconnectSource(sourceName) {
            connected = connected.filter(function(value) { return value !== sourceName; });
            disconnected(sourceName);
        }'''

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "CliProcess"
    Component {
        id: observation
        QtObject { property var replies: []; property var timeouts: [] }
    }
    function create() {
        var factory = Qt.createComponent(PROCESS_URL);
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase);
        verify(subject !== null);
        var observed = createTemporaryObject(observation, testCase);
        subject.completed.connect(function(context, stdout, stderr, code) {
            observed.replies = observed.replies.concat([{context: context, stdout: stdout, stderr: stderr, code: code}]);
        });
        subject.timedOut.connect(function(context) { observed.timeouts = observed.timeouts.concat([context]); });
        return {subject: subject, observed: observed, transport: subject.testSource};
    }
    function reply(o, source, code) {
        o.transport.newData(source, {stdout: "synthetic", stderr: "diagnostic", "exit code": code});
    }
    function start(o, context, timeout) {
        verify(o.subject.start("synthetic-command", context, timeout === undefined ? 60000 : timeout));
        return o.transport.started[o.transport.started.length - 1];
    }
    function test_immediateRepliesAreRegisteredAndDisconnected() {
        var o = create();
        o.transport.immediate = true;
        start(o, {range: 7});
        compare(o.observed.replies.length, 1);
        compare(o.observed.replies[0].context, {range: 7});
        compare(o.observed.replies[0].stdout, "[]");
        compare(o.subject.busy, false);
        compare(o.transport.connected, []);
    }
    function test_processStatusAndRawStreamsReachTheDomainOwner_data() {
        return [0, 1, 124, 127, null, "0"].map(function(code, i) { return {tag: String(i), code: code}; });
    }
    function test_processStatusAndRawStreamsReachTheDomainOwner(data) {
        var o = create();
        var source = start(o, "context");
        reply(o, source, data.code);
        compare(o.observed.replies, [{context: "context", stdout: "synthetic", stderr: "diagnostic", code: data.code}]);
        compare(o.subject.busy, false);
    }
    function test_supersededAndDuplicateRepliesAreIgnored() {
        var o = create();
        var old = start(o, "old");
        var current = start(o, "new");
        verify(old !== current);
        compare(o.transport.connected, [current]);
        reply(o, old, 0);
        compare(o.observed.replies, []);
        compare(o.subject.busy, true);
        reply(o, current, 1);
        reply(o, current, 0);
        compare(o.observed.replies.length, 1);
        compare(o.observed.replies[0].context, "new");
    }
    function test_cancelIsSilentAndIdempotent() {
        var o = create();
        var source = start(o, "cancelled");
        o.subject.cancel();
        o.subject.cancel();
        reply(o, source, 0);
        compare(o.transport.connected, []);
        compare(o.subject.busy, false);
        compare(o.observed.replies, []);
        compare(o.observed.timeouts, []);
    }
    function test_invalidStartPreservesCurrentRequest() {
        var o = create();
        var source = start(o, "current");
        for (var command of ["", null, undefined, {}, 42]) verify(!o.subject.start(command, "bad", 10));
        compare(o.transport.connected, [source]);
        reply(o, source, 0);
        compare(o.observed.replies[0].context, "current");
    }
    function test_instancesAndRecreatedInstancesUseDifferentSources() {
        var first = create();
        var second = create();
        var a = start(first, null);
        var b = start(second, null);
        verify(a !== b);
        first.subject.destroy();
        wait(0);
        var third = create();
        var c = start(third, null);
        verify(a !== c && b !== c);
        reply(second, a, 0);
        compare(second.subject.busy, true);
    }
    function test_timeoutRetiresBeforeNotificationAndIgnoresLateReply_data() {
        return [{tag: "normal", timeout: 30}, {tag: "invalid", timeout: NaN}];
    }
    function test_timeoutRetiresBeforeNotificationAndIgnoresLateReply(data) {
        var o = create();
        var source = start(o, "expired", data.timeout);
        var busyAtTimeout = null;
        o.subject.timedOut.connect(function() { busyAtTimeout = o.subject.busy; });
        tryCompare(o.subject, "busy", false, 2000);
        compare(busyAtTimeout, false);
        compare(o.observed.timeouts, ["expired"]);
        compare(o.transport.connected, []);
        var next = start(o, "next");
        reply(o, source, 0);
        compare(o.subject.busy, true);
        reply(o, next, 0);
        compare(o.observed.replies.length, 1);
    }
    function test_reentrantDisconnectCannotPublishOldCompletion() {
        var o = create();
        var old = start(o, "old");
        o.transport.disconnected.connect(function(source) {
            if (source === old) {
                compare(o.subject.busy, false);
                start(o, "new");
                reply(o, old, 0);
            }
        });
        reply(o, old, 0);
        compare(o.observed.replies, []);
        compare(o.subject.busy, true);
        reply(o, o.transport.started[1], 0);
        compare(o.observed.replies[0].context, "new");
    }
    function test_reentrantDisconnectSupersedesOuterStart() {
        var o = create();
        var old = start(o, "old");
        o.transport.disconnected.connect(function(source) {
            if (source === old) start(o, "inner");
        });
        verify(!o.subject.start("outer", "outer", 60000));
        compare(o.transport.started.length, 2);
        reply(o, o.transport.started[1], 0);
        compare(o.observed.replies[0].context, "inner");
    }
    function test_cancelDuringBusyNotificationPreventsConnection() {
        var o = create();
        o.subject.busyChanged.connect(function() { if (o.subject.busy) o.subject.cancel(); });
        verify(!o.subject.start("never-connect", null, 60000));
        compare(o.transport.started, []);
        compare(o.subject.busy, false);
    }
    function test_completionCanStartNextRequest() {
        var o = create();
        var old = start(o, "old");
        o.subject.completed.connect(function(context) { if (context === "old") start(o, "next"); });
        reply(o, old, 0);
        compare(o.subject.busy, true);
        reply(o, o.transport.started[1], 0);
        compare(o.observed.replies.length, 2);
    }
    function test_destroyDisconnectsAndBlocksReentrantStart() {
        var o = create();
        start(o, null);
        var disconnected = 0;
        o.transport.disconnected.connect(function(source) {
            disconnected++;
            verify(!o.subject.start("must-not-start", null, 1));
            reply(o, source, 0);
        });
        o.subject.destroy();
        wait(0);
        compare(disconnected, 1);
        compare(o.observed.replies, []);
        compare(o.observed.timeouts, []);
    }
}
'''


class CliProcessTests(unittest.TestCase):
    def test_transport_lifecycle(self):
        source = (ROOT / "contents/ui/controllers/CliProcess.qml").read_text()
        source = source.replace('import org.kde.plasma.plasma5support as Plasma5Support\n', '')
        for module in ("CommandLedger", "Guards"):
            source = source.replace(f'"../{module}.js"', json.dumps((ROOT / f"contents/ui/{module}.js").as_uri()))
        source = source.replace('id: process', 'id: process\n    property alias testSource: commandSource', 1)
        source = source.replace('Plasma5Support.DataSource {', 'QtObject {')
        source = source.replace('engine: "executable"\n        interval: 0', TRANSPORT)
        with tempfile.TemporaryDirectory(prefix="codexbar-process-") as temporary:
            directory = Path(temporary)
            component = directory / "CliProcess.qml"
            component.write_text(source)
            fixture = directory / "tst_process.qml"
            fixture.write_text(QML.replace("PROCESS_URL", json.dumps(component.as_uri())))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)


if __name__ == "__main__":
    unittest.main()
