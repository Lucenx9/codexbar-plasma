"""Separate updater instances must execute their own requests in Plasma's engine."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "CommandSourceIsolation"
    function i18n(text, first, second) {
        return text.replace("%1", first === undefined ? "%1" : first)
                   .replace("%2", second === undefined ? "%2" : second);
    }
    Component { id: observation; QtObject { property var items: [] } }
    function version(subject, observed, controller) {
        switch (controller) {
        case "WidgetUpdateController": return subject.availableVersion;
        case "UsageController": return observed.items.length ? observed.items[0].version : "";
        case "CostController": return subject.costs.codex ? subject.costs.codex.historyLabel : "";
        case "IdentifiedTokensController": return subject.snapshot ? "0.62." + subject.snapshot.totalTokens : "";
        case "SessionsController": return subject.sessions.length ? subject.sessions[0].projectName : "";
        case "ProviderRosterController": return subject.enabledProviderRoster.length ? subject.enabledProviderRoster[0].displayName : "";
        default: return subject.result.version;
        }
    }
    function test_independentRequests_data() {
        return [
            {tag: "local-versions", controller: "CliUpdateController", options: {localOnly: true}, start: "checkNow"},
            {tag: "release-checks", controller: "CliUpdateController", options: {}, start: "checkNow"},
            {tag: "managed-cli", controller: "ManagedCliController", options: {}, start: "run", argument: "status"},
            {tag: "widget", controller: "WidgetUpdateController", options: {}, start: "runNow"},
            {tag: "usage", controller: "UsageController", options: {provider: "codex", refreshIntervalSec: 0}, start: "refresh", loading: "loading"},
            {tag: "cost", controller: "CostController", options: {}, start: "refresh", argument: true, loading: "loading"},
            {tag: "identified", controller: "IdentifiedTokensController", options: {collectionEnabled: true}, start: "request", argument: false, loading: "loading"},
            {tag: "sessions", controller: "SessionsController", options: {active: true}, start: "refresh", loading: "loading"},
            {tag: "roster", controller: "ProviderRosterController", options: {}, loading: "providerRosterLoading"}
        ];
    }
    function test_independentRequests(data) {
        var factory = Qt.createComponent("CONTROLLERS/" + data.controller + ".qml");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString())) {
            skip("Request isolation needs the optional KDE QML modules");
            return;
        }
        compare(factory.status, Component.Ready, factory.errorString());
        var options = Object.assign(data.loading
            ? {commandPath: "FIXTURE_PATH/" + data.tag}
            : {scriptUrl: "FIXTURES/" + data.tag}, data.options);
        var first = createTemporaryObject(factory, testCase, options);
        var second = createTemporaryObject(factory, testCase, options);
        verify(first !== null && second !== null);
        var firstObserved = createTemporaryObject(observation, testCase);
        var secondObserved = createTemporaryObject(observation, testCase);
        if (data.controller === "UsageController") {
            first.snapshotReceived.connect(function(items) { firstObserved.items = items; });
            second.snapshotReceived.connect(function(items) { secondObserved.items = items; });
        }
        if (data.start) {
            first[data.start](data.argument);
            second[data.start](data.argument);
        }
        var loading = data.loading || "busy";
        tryVerify(function() { return !first[loading] && version(first, firstObserved, data.controller).length > 0; });
        tryVerify(function() { return !second[loading] && version(second, secondObserved, data.controller).length > 0; });
        var versions = [version(first, firstObserved, data.controller), version(second, secondObserved, data.controller)];
        compare(versions.sort(), ["0.62.1", "0.62.2"]);
    }
}
'''

HELPER = '''#!/usr/bin/env python3
import fcntl
import json
from pathlib import Path
import sys
import time

with Path(__file__).with_suffix(".count").open("a+") as counter:
    fcntl.flock(counter, fcntl.LOCK_EX)
    counter.seek(0)
    number = int(counter.read() or "0") + 1
    counter.seek(0)
    counter.truncate()
    counter.write(str(number))
time.sleep(0.2)
version = "0.62." + str(number)
if "--check" in sys.argv:
    result = dict(status="available", remoteVersion=version)
elif "--action" in sys.argv:
    result = dict(status="ready", version=version,
                  path="/home/test/.local/share/codexbar-plasma/cli/current/codexbar")
elif "usage" in sys.argv:
    result = dict(provider="codex", version=version, usage=dict(primary=dict(usedPercent=0)))
elif "--identified-only" in sys.argv:
    end = int(sys.argv[sys.argv.index("--identified-end") + 1])
    days = int(sys.argv[sys.argv.index("--days") + 1])
    result = dict(schemaVersion=1, provider="codex", startUnixMs=end - end % 86400000 - (days - 1) * 86400000,
                  endUnixMs=end, records=[dict(id="a" * 64, timestampUnixMs=end, inputTokens=number,
                                             outputTokens=0, cacheReadTokens=0)],
                  conflictingIDs=[], excludedCount=0, partial=False)
elif "cost" in sys.argv:
    result = [dict(provider="codex", historyLabel=version, totals=dict(totalCost=number))]
elif "sessions" in sys.argv:
    result = [dict(provider="codex", projectName=version, state="active", source="cli")]
elif "config" in sys.argv:
    result = [dict(provider="codex", enabled=True, displayName=version)]
else:
    result = dict(status="local" if "--local-only" in sys.argv else "available",
                  version=version, path="/usr/bin/codexbar", latest="0.63.0", tag="v0.63.0")
print(json.dumps(result))
'''


class CommandSourceIsolationTests(unittest.TestCase):
    def test_real_engine_executes_each_request(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-request-isolation-") as directory:
            path = Path(directory)
            for name in ("local-versions", "release-checks", "managed-cli", "widget",
                         "usage", "cost", "identified", "sessions", "roster"):
                helper = path / name
                helper.write_text(HELPER)
                helper.chmod(0o700)
            fixture = path / "tst_isolation.qml"
            fixture.write_text(QML.replace("CONTROLLERS", (ROOT / "contents/ui/controllers").as_uri())
                               .replace("FIXTURES", path.as_uri()).replace("FIXTURE_PATH", str(path)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if "SKIP" in output:
                if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                    self.fail(output)
                self.skipTest("KDE QML modules unavailable")
            self.assertNotIn("QWARN", output)
