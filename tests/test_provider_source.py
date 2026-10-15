"""Execute provider source writes and lifecycle handlers without optional KDE modules."""
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

QML = r'''import QtQuick
import QtTest
import "SOURCE_URL/config/ProviderSource.js" as ProviderSource
import "SOURCE_URL/config/ProviderConfigProtocol.js" as ProviderConfigProtocol
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/config/ProviderDescriptor.js" as ProviderDescriptor
TestCase {
    name: "ProviderSourceWrites"
    Component {
        id: harness
        QtObject {
            id: page
            property string commandPath: "codexbar"
            property bool providerSourceSetupSupported: true
            property bool fireworksSingleKeySetupSupported: false
            property bool commandCodeFalApiKeySetupSupported: false
            property int configCommandTimeoutMs: 60000
            property int configSecretPromptTimeoutMs: 60000
            property real configSecretPromptDialogTimeoutSeconds: 30
            property real configSecretPromptDialogKillAfterSeconds: 1
            property real configSecretCommandTimeoutSeconds: 20
            property real configSecretCommandKillAfterSeconds: 1
            property int commandRunSerial: 0
            property var commands: ({})
            property var pending: ({})
            property var pendingDesired: ({})
            property var providerFieldPending: ({})
            property var providerDiagnosticLoading: ({})
            property bool loading: false
            property bool reloadDeferredBySourceWrite: false
            property bool providerDescriptorsUnavailable: false
            property var providers: [{provider: "codex", enabled: false}, {provider: "future", enabled: true}]
            property string selectedProviderID: "codex"
            property string errorText: ""
            property string statusText: ""
            property string cfg_source: "web"
            property int revisions: 0
            property int writes: 0
            property int diagnosticsCleared: 0
            property QtObject providerSourceBox: QtObject { property int currentIndex: 1 }
            property QtObject configSource: QtObject {
                function connectSource(source) {}
                function disconnectSource(source) {}
            }
            SOURCE_FUNCTIONS
            function i18n(text, first, second) {
                return text.replace("%1", first).replace("%2", second);
            }
            function providerCliArgument(provider) { return provider; }
            function displayNameForProvider(provider) { return provider; }
            function providerTitle(provider) { return provider; }
            function providerMapKey(provider) { return provider; }
            function updateProviderEnabled(provider, enabled) { writes++; }
            function bumpProviderConfigRevision() { revisions++; }
            function setProviderDiagnostic(provider, value) { diagnosticsCleared++; }
            function setProviderDiagnosticLoading(provider, value) {}
            function setProviderDiagnosticError(provider, value) {}
            function providerConfigRevisionValue() { return revisions; }
            function shellQuote(value) { return Guards.shellQuote(value); }
        }
    }
    function start(page, mode) {
        page.setProviderSource("codex", mode);
        compare(Object.keys(page.commands).length, 1);
        return Object.keys(page.commands)[0];
    }
    function test_successAndClearingPreserveGlobalOverride() {
        for (var mode of ["api", "auto"]) {
            var page = createTemporaryObject(harness, this);
            var source = start(page, mode);
            verify(page.pending.codex);
            compare(page.pendingDesired.codex, false);
            page.setProviderSource("codex", "web");
            compare(Object.keys(page.commands).length, 1);
            page.handleData(source, JSON.stringify({provider: "codex", enabled: false, source: mode}), "noise", 0);
            compare(page.revisions, 1);
            compare(page.writes, 1);
            compare(page.diagnosticsCleared, 1);
            compare(page.cfg_source, "web");
            compare(page.providerSourceBox.currentIndex, -1);
            verify(!page.pending.codex);
            page.handleData(source, JSON.stringify({provider: "codex", enabled: true, source: "web"}), "", 0);
            compare(page.revisions, 1);
        }
    }
    function test_failuresAndCancellationDoNotCommit_data() {
        return [
            {tag: "unsupported", stdout: JSON.stringify([{error: {message: "Unsupported source"}}]), code: 1},
            {tag: "malformed", stdout: "broken", code: 0},
            {tag: "empty", stdout: "", code: 0},
            {tag: "wrongProvider", stdout: JSON.stringify({provider: "future", enabled: false, source: "api"}), code: 0},
            {tag: "wrongMode", stdout: JSON.stringify({provider: "codex", enabled: false, source: "auto"}), code: 0},
            {tag: "cancelled", stdout: JSON.stringify({cancelled: true}), code: 0},
            {tag: "timeoutExit", stdout: "", code: 124}
        ];
    }
    function test_failuresAndCancellationDoNotCommit(data) {
        var page = createTemporaryObject(harness, this);
        var source = start(page, "api");
        page.handleData(source, data.stdout, "", data.code);
        verify(!page.pending.codex);
        compare(page.revisions, 0);
        compare(page.writes, 0);
        compare(page.statusText, "");
        compare(page.providerSourceBox.currentIndex, 1);
        compare(page.cfg_source, "web");
        compare(page.errorText.length > 0, data.tag !== "cancelled");
    }
    function test_reloadRetainsCapabilitiesUntilVersionResult() {
        var page = createTemporaryObject(harness, this);
        page.handleCliVersionResult("CodexBar 0.76.0", 0);
        page.reload();
        verify(page.fireworksSingleKeySetupSupported);
        verify(page.commandCodeFalApiKeySetupSupported);
        verify(page.providerSourceSetupSupported);
        page.handleCliVersionResult("CodexBar 0.72.0", 0);
        verify(page.fireworksSingleKeySetupSupported);
        verify(!page.commandCodeFalApiKeySetupSupported);
        verify(!page.providerSourceSetupSupported);
        page.handleCliVersionResult("unknown", 1);
        verify(!page.fireworksSingleKeySetupSupported);
    }
    function test_apiKeyPromptKeepsCurrentEnablement() {
        var page = createTemporaryObject(harness, this);
        page.setApiKey("codex");
        verify(page.isPending("codex"));
        verify(!page.visualEnabled("codex", false));
        page.setApiKey("future");
        verify(page.isPending("future"));
        verify(page.visualEnabled("future", true));
    }
    function test_gateAndUnknownProvider() {
        var page = createTemporaryObject(harness, this);
        for (var version of ["CodexBar 0.72.0", "CodexBar 0.73.0-rc1", "unknown"]) {
            page.handleCliVersionResult(version, 0);
            page.setProviderSource("codex", "auto");
            compare(Object.keys(page.commands).length, 0);
        }
        page.handleCliVersionResult("CodexBar 0.74.0", 1);
        verify(!page.providerSourceSetupSupported);
        verify(!page.commandCodeFalApiKeySetupSupported);
        page.handleCliVersionResult("CodexBar 0.73.0", 0);
        verify(page.providerSourceSetupSupported);
        verify(!page.commandCodeFalApiKeySetupSupported);
        page.handleCliVersionResult("CodexBar 0.75.0-rc1", 0);
        verify(!page.commandCodeFalApiKeySetupSupported);
        page.handleCliVersionResult("CodexBar 0.75.0", 1);
        verify(!page.commandCodeFalApiKeySetupSupported);
        page.handleCliVersionResult("CodexBar 0.75.0", 0);
        verify(page.commandCodeFalApiKeySetupSupported);
        page.setProviderSource("missing", "auto");
        compare(Object.keys(page.commands).length, 0);
        page.setProviderSource("future", "api");
        compare(Object.keys(page.commands).length, 1);
    }
    function test_timeoutAndCommandRetirementIgnoreLateReplies() {
        var page = createTemporaryObject(harness, this);
        var source = start(page, "api");
        page.expireConfigCommands(Date.now() + 61000);
        verify(!page.pending.codex);
        verify(page.errorText.indexOf("timed out") >= 0);
        var newer = start(page, "auto");
        var result = JSON.stringify({provider: "codex", enabled: false, source: "api"});
        page.handleData(source, result, "", 0);
        verify(page.pending.codex);
        compare(page.revisions, 0);
        page.retireAllConfigCommands();
        page.commandPath = "other-cli";
        page.handleData(newer, result, "", 0);
        compare(page.revisions, 0);
        verify(!page.pending.codex);
    }
    function test_selectionChangeDoesNotResetAnotherProvidersChoice() {
        var page = createTemporaryObject(harness, this);
        var source = start(page, "api");
        page.selectedProviderID = "future";
        page.providerSourceBox.currentIndex = 4;
        page.handleData(source, JSON.stringify({provider: "codex", enabled: false, source: "api"}), "", 0);
        compare(page.revisions, 1);
        compare(page.providerSourceBox.currentIndex, 4);
    }
    function test_writeRetiresOldSourceDiagnostics() {
        var page = createTemporaryObject(harness, this);
        page.commands = {"old-diagnostic": {kind: "diagnose", provider: "codex",
            commandPathSignature: "codexbar", deadlineMs: Date.now() + 60000}};
        start(page, "api");
        verify(page.commands["old-diagnostic"] === undefined);
        page.handleData("old-diagnostic", "{}", "", 0);
        verify(page.pending.codex);
        compare(page.revisions, 0);
    }
    function test_descriptorPendingBlocksOnlyItsProvidersSource() {
        var page = createTemporaryObject(harness, this);
        page.providerFieldPending = {'codex::"key"': true, 'future::"action"': true};
        page.setProviderSource("codex", "api");
        compare(Object.keys(page.commands).length, 0);
        verify(!page.pending.codex);
        page.providerFieldPending = {'future::"action"': true};
        start(page, "api");
        verify(page.pending.codex);
    }
    function test_reloadAndSourceWritesCannotOverlap() {
        var page = createTemporaryObject(harness, this);
        page.reload();
        verify(page.loading);
        compare(Object.keys(page.commands).length, 2);
        // Version can complete before the retained provider list refresh.
        page.handleCliVersionResult("CodexBar 0.73.0", 0);
        verify(page.providerSourceSetupSupported);
        page.setProviderSource("codex", "web");
        compare(Object.keys(page.commands).length, 2);
        verify(!page.pending.codex);
        page.retireAllConfigCommands();
        var source = start(page, "web");
        page.reload();
        compare(Object.keys(page.commands).length, 1);
        verify(page.commands[source] !== undefined);
        verify(!page.loading);
        page.handleData(source, JSON.stringify([{error: {message: "Unsupported source"}}]), "", 1);
        compare(page.errorText, "codex: Unsupported source");
    }
    function sourceResult(mode) {
        return JSON.stringify({provider: "codex", enabled: false, source: mode});
    }
    function textField(provider) {
        return {id: "name", kind: "text", title: "Name",
            writeCommand: ["codexbar", "config", "set", "--provider", provider, "{value}"]};
    }
    function test_reloadRequestedDuringSourceWriteRunsAfterIt() {
        var page = createTemporaryObject(harness, this);
        var source = start(page, "api");
        // Another provider's descriptor write finished and asked for a roster refresh.
        page.reload(true);
        compare(Object.keys(page.commands).length, 1);
        page.handleData(source, sourceResult("api"), "", 0);
        compare(CommandLedger.sourcesOfKind(page.commands, "list").length, 1);
        compare(CommandLedger.sourcesOfKind(page.commands, "version").length, 1);
        verify(page.loading);
        compare(page.statusText, "codex setting saved");
        verify(!page.reloadDeferredBySourceWrite);
    }
    function rosterResult() {
        return JSON.stringify([{provider: "codex", enabled: false}, {provider: "future", enabled: true}]);
    }
    function finishList(page) {
        var lists = CommandLedger.sourcesOfKind(page.commands, "list");
        compare(lists.length, 1);
        page.handleData(lists[0], rosterResult(), "", 0);
        verify(!page.loading);
    }
    function test_deferredReloadKeepsSourceWriteError() {
        var page = createTemporaryObject(harness, this);
        var source = start(page, "api");
        page.reload(true);
        page.handleData(source, JSON.stringify([{error: {message: "Unsupported source"}}]), "", 1);
        compare(CommandLedger.sourcesOfKind(page.commands, "list").length, 1);
        compare(page.errorText, "codex: Unsupported source");
        // A successful roster refresh must not clear the write's error.
        finishList(page);
        compare(page.errorText, "codex: Unsupported source");
        // The retained error belongs to that one refresh, not to later reloads.
        page.reload(true);
        compare(page.errorText, "");
        finishList(page);
        compare(page.errorText, "");
    }
    function test_deferredReloadRunsAfterSourceWriteTimeout() {
        var page = createTemporaryObject(harness, this);
        start(page, "api");
        page.reload(true);
        page.expireConfigCommands(Date.now() + 61000);
        compare(CommandLedger.sourcesOfKind(page.commands, "list").length, 1);
        verify(page.errorText.indexOf("timed out") >= 0);
        finishList(page);
        verify(page.errorText.indexOf("timed out") >= 0);
    }
    function test_deferredReloadWaitsForEverySourceWrite() {
        var page = createTemporaryObject(harness, this);
        var codex = start(page, "api");
        page.setProviderSource("future", "web");
        var future = Object.keys(page.commands).filter(function(name) { return name !== codex; })[0];
        page.reload(true);
        page.handleData(codex, sourceResult("api"), "", 0);
        compare(CommandLedger.sourcesOfKind(page.commands, "list").length, 0);
        page.handleData(future, JSON.stringify({provider: "future", enabled: true, source: "web"}), "", 0);
        compare(CommandLedger.sourcesOfKind(page.commands, "list").length, 1);
    }
    function test_sourceWriteWithoutDeferredReloadDoesNotReload() {
        var page = createTemporaryObject(harness, this);
        var source = start(page, "api");
        page.handleData(source, sourceResult("api"), "", 0);
        compare(Object.keys(page.commands).length, 0);
        verify(!page.loading);
    }
    function test_sourceWriteBlocksOnlyItsProvidersDescriptorWrites() {
        var page = createTemporaryObject(harness, this);
        start(page, "api");
        page.writeDescriptorField("codex", textField("codex"), "abc");
        page.promptDescriptorSecret("codex", {id: "apiKey", title: "API key", kind: "secret",
            writeCommand: ["codexbar", "config", "set-api-key", "--provider", "codex", "--stdin"]});
        page.runDescriptorAction("codex", {id: "login", command: ["codexbar", "config", "action", "login"]});
        compare(Object.keys(page.commands).length, 1);
        compare(Object.keys(page.providerFieldPending).length, 0);
        page.writeDescriptorField("future", textField("future"), "abc");
        compare(Object.keys(page.commands).length, 2);
        verify(page.isFieldPending("future", "name"));
    }
}
'''

class ProviderSourceTests(unittest.TestCase):
    def test_source_writes_and_lifecycle(self):
        source = (ROOT / "contents/ui/configProviders.qml").read_text()
        surface = Surface("providers", ROOT)
        names = ("setProviderSource", "handleSetSourceResult", "setApiKey", "visualEnabled",
                 "retireProviderDiagnostic", "invalidateProviderDiagnostic",
                 "providerCommandFailureText", "handleCliVersionResult", "handleData",
                 "applySetSourceResult", "runReloadDeferredBySourceWrite",
                 "providerByID", "markPending", "isPending", "runCommand", "copyObject",
                 "hasOwnKey", "expireConfigCommands", "handleConfigCommandTimeout",
                 "retireAllConfigCommands", "reload", "disconnectCommandsByKind",
                 "runProviderListCommand", "runCliVersionCommand", "writeDescriptorField",
                 "promptDescriptorSecret", "runDescriptorAction", "isFieldPending",
                 "markFieldPending", "descriptorPendingKey", "descriptorPendingFieldKey",
                 "handleListResult", "shouldRetryProviderListWithoutDescriptors",
                 "descriptorListUnsupportedMessage", "firstSelectableProvider")
        functions = []
        for name in names:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-source-test-") as temporary:
            fixture = Path(temporary) / "tst_provider_source.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

if __name__ == "__main__":
    unittest.main()
