"""Exercise watcher ownership, cached replies, and real checksum commands."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "contents/ui/controllers/ProviderConfigWatcher.qml"
MODULE = ROOT / "contents/ui/ProviderConfigWatch.js"

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "ProviderConfigWatcher"
    property var events: []

    function create(options) {
        var factory = Qt.createComponent(CONTROLLER_URL);
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("ProviderConfigWatcher needs the optional KDE QML modules");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, Object.assign({active: false}, options || {}));
        verify(subject !== null);
        subject.stampObserved.connect(function(stamp, initial) {
            testCase.events = testCase.events.concat([{stamp: stamp, initial: initial}]);
        });
        return subject;
    }
    function init() { events = []; }

    TESTS
}
'''

CACHED_TESTS = '''
    function test_cachedRepliesAndReconnection() {
        var subject = create({command: "watch-current"});
        subject.active = true;
        compare(subject.testSource.connected, ["watch-current"]);
        compare(events, [{stamp: "123 42 /synthetic/config.json", initial: true}]);
        subject.command = "watch-new";
        compare(subject.testSource.connected, ["watch-new"]);
        compare(events.length, 1);
        subject.testSource.newData("watch-current", {stdout: "111 42 /synthetic/retired.json"});
        compare(subject.testSource.connected, ["watch-new"]);
        compare(subject.stamp, "123 42 /synthetic/config.json");
        subject.testSource.newData("watch-new", {stdout: "456 43 /synthetic/config.json\\n"});
        compare(events, [{stamp: "123 42 /synthetic/config.json", initial: true}, {stamp: "456 43 /synthetic/config.json", initial: false}]);
        subject.command = "";
        compare(subject.testSource.connected, []);
        subject.testSource.newData("watch-new", {stdout: "111 42 /synthetic/retired.json"});
        compare(subject.stamp, "456 43 /synthetic/config.json");
    }
    function test_inactiveAndMalformedRepliesKeepTheLastStamp() {
        var subject = create({command: "watch-current"});
        compare(subject.testSource.connected, []);
        subject.active = true;
        for (var data of [null, {}, {stdout: 42}, {stdout: {toString: null}},
                {stdout: " "}, {stdout: "checksum unavailable"}, {stdout: "x".repeat(8193)}]) {
            subject.testSource.newData("watch-current", data);
        }
        compare(subject.stamp, "123 42 /synthetic/config.json");
        compare(events.length, 1);
        subject.active = false;
        compare(subject.testSource.connected, []);
        subject.testSource.newData("watch-current", {stdout: "222 42 /synthetic/late.json"});
        compare(events.length, 1);
        subject.testSource.cachedReply = "789 44 /synthetic/config.json";
        subject.active = true;
        compare(events[1], {stamp: "789 44 /synthetic/config.json", initial: false});
    }
    function test_reentrantReconnectKeepsTheNewObservation() {
        var subject = create({command: "watch-current"});
        subject.stampObserved.connect(function(stamp, initial) {
            if (initial) {
                subject.testSource.cachedReply = "987 45 /synthetic/replacement.json";
                subject.command = "watch-replacement";
            }
        });
        subject.active = true;
        compare(events, [{stamp: "123 42 /synthetic/config.json", initial: true}, {stamp: "987 45 /synthetic/replacement.json", initial: false}]);
        compare(subject.stamp, "987 45 /synthetic/replacement.json");
        compare(subject.testSource.connected, ["watch-replacement"]);
        subject.testSource.newData("watch-current", {stdout: "222 42 /synthetic/late.json"});
        compare(events.length, 2);
    }
'''

REAL_TESTS = '''
    function test_realChecksumAndProcessChanges() {
        var subject = create();
        console.log("WATCH_COMMAND", JSON.stringify(subject.command));
        subject.active = true;
        tryCompare(subject, "stamp", EXPECTED_STAMP, 5000);
        compare(events, [{stamp: EXPECTED_STAMP, initial: true}]);
        subject.command = "printf missing";
        tryCompare(subject, "stamp", "missing", 5000);
        compare(events[1], {stamp: "missing", initial: false});
        subject.command = "printf '  '\\n";
        wait(250);
        compare(subject.stamp, "missing");
        compare(events.length, 2);
        subject.active = false;
        subject.command = "printf '789 44 /synthetic/config.json'";
        wait(250);
        compare(events.length, 2);
        subject.active = true;
        tryCompare(subject, "stamp", "789 44 /synthetic/config.json", 5000);
        compare(events[2], {stamp: "789 44 /synthetic/config.json", initial: false});
        subject.active = false;
    }
'''


class ProviderConfigWatcherTests(unittest.TestCase):
    def run_qml(self, directory, controller, tests, env=None):
        fixture = directory / "tst_provider_config_watcher.qml"
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
            self.skipTest("ProviderConfigWatcher needs the optional KDE QML modules")
        self.assertNotIn("QWARN", output)
        return output

    def test_cached_reply_during_connection(self):
        # Substitute only the process transport. The controller's handlers,
        # lifecycle state, command registration and observation logic are real.
        source = CONTROLLER.read_text()
        source = source.replace('import org.kde.plasma.plasma5support as Plasma5Support\n', '')
        source = source.replace('"../ProviderConfigWatch.js"', json.dumps(MODULE.as_uri()))
        source = source.replace('id: controller', 'id: controller\n    property alias testSource: watchSource', 1)
        source = source.replace('Plasma5Support.DataSource {', 'QtObject {')
        source = source.replace('engine: "executable"', '''property var connected: []
        property string cachedReply: "123 42 /synthetic/config.json"
        signal newData(string sourceName, var data)
        function connectSource(sourceName) {
            connected = connected.concat(sourceName)
            newData(sourceName, {stdout: cachedReply})
        }
        function disconnectSource(sourceName) {
            connected = connected.filter(function(name) { return name !== sourceName })
        }''')
        source = source.replace('interval: controller.pollIntervalMs', 'property int interval: controller.pollIntervalMs')
        with tempfile.TemporaryDirectory(prefix="codexbar-watcher-cached-") as temporary:
            directory = Path(temporary)
            controller = directory / "Watcher.qml"
            controller.write_text(source)
            self.run_qml(directory, controller, CACHED_TESTS)

    def test_real_process_and_config_paths(self):
        with tempfile.TemporaryDirectory(prefix="codexbar watcher 'test-") as temporary:
            directory = Path(temporary)
            explicit = directory / "explicit 'config\tname\n.json"
            explicit.write_text('{"synthetic": "first"}\n')
            expected = subprocess.check_output(["cksum", str(explicit)], text=True).strip()
            output = self.run_qml(directory, CONTROLLER,
                                  REAL_TESTS.replace("EXPECTED_STAMP", json.dumps(expected)),
                                  {"CODEXBAR_CONFIG": str(explicit)})
            command = json.loads(re.search(r'WATCH_COMMAND (".*")', output).group(1))
            xdg = directory / "xdg config"
            xdg_file = xdg / "codexbar/config.json"
            xdg_file.parent.mkdir(parents=True)
            xdg_file.write_text('{"synthetic": "xdg"}\n')
            missing = directory / "missing.json"
            for name, override, expected_path in (
                ("explicit-precedence", str(explicit), explicit),
                ("xdg", "", xdg_file),
                ("missing-explicit", str(missing), None),
            ):
                with self.subTest(name=name):
                    result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True,
                                            env={**os.environ, "CODEXBAR_CONFIG": override, "XDG_CONFIG_HOME": str(xdg)},
                                            timeout=10)
                    expected_output = subprocess.check_output(["cksum", str(expected_path)], text=True) if expected_path else "missing"
                    self.assertEqual(result.stdout, expected_output)
                    self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
