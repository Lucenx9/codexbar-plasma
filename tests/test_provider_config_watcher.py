"""Exercise cached replies during production provider-watcher reconnection."""

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

QML = '''import QtQuick
import QtTest
TestCase {
    name: "ProviderConfigWatcher"
    Component {
        id: harness
        QtObject {
            id: root
            property string providerConfigWatchCommand: "watch-current"
            property string connectedProviderConfigWatchCommand: ""
            property var accepted: []
            property QtObject providerConfigWatcher: QtObject {
                property var connected: []
                // Plasma can deliver cached source data inside connectSource.
                function connectSource(sourceName) {
                    connected = connected.concat(sourceName);
                    deliver(sourceName, {stdout: "cached"});
                }
                function disconnectSource(sourceName) {
                    connected = connected.filter(function(name) { return name !== sourceName; });
                }
                property var deliver: SOURCE_HANDLER
            }
            function handleProviderConfigWatch(stdoutText) {
                accepted = accepted.concat(stdoutText);
            }
            function reconnectProviderConfigWatcher() { SOURCE_RECONNECT }
        }
    }

    function test_cachedReplyDoesNotDisconnectWatcher_data() {
        return [{tag: "first-connection", previous: ""},
                {tag: "changed-command", previous: "watch-old"}];
    }
    function test_cachedReplyDoesNotDisconnectWatcher(data) {
        var applet = createTemporaryObject(harness, this);
        verify(applet !== null);
        applet.connectedProviderConfigWatchCommand = data.previous;
        applet.providerConfigWatcher.connected = data.previous ? [data.previous] : [];
        applet.reconnectProviderConfigWatcher();
        compare(applet.providerConfigWatcher.connected, ["watch-current"]);
        compare(applet.accepted, ["cached"]);
        applet.providerConfigWatcher.deliver("watch-old", {stdout: "retired"});
        compare(applet.providerConfigWatcher.connected, ["watch-current"]);
        compare(applet.accepted, ["cached"]);
        applet.providerConfigWatchCommand = "";
        applet.reconnectProviderConfigWatcher();
        compare(applet.providerConfigWatcher.connected, []);
        applet.providerConfigWatcher.deliver("watch-current", {stdout: "retired"});
        compare(applet.accepted, ["cached"]);
    }
}
'''


class ProviderConfigWatcherTests(unittest.TestCase):
    def test_cached_reply_during_connection(self):
        applet = Surface("applet", ROOT)
        handler = re.search(
            r"onNewData:\s*(function\(sourceName, data\)\s*\{.*\})\s*$",
            applet.id_block("providerConfigWatcher"), re.DOTALL).group(1)
        qml = QML.replace("SOURCE_HANDLER", handler).replace(
            "SOURCE_RECONNECT", applet.function_body("reconnectProviderConfigWatcher"))
        with tempfile.TemporaryDirectory(prefix="codexbar-config-watcher-") as temporary:
            fixture = Path(temporary) / "tst_provider_config_watcher.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"),
                 "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
