"""Execute production secret-prompt scripts with isolated dialog and CLI fixtures."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/config/ProviderDescriptor.js" as ProviderDescriptor
TestCase {
    name: "SecretPromptCommands"
    property string commandPath: CLI_PATH
    property string errorText: ""
    property string statusText: ""
    property var captured: []
    SOURCE_PROPERTIES
    SOURCE_FUNCTIONS
    function i18n(text, first, second) {
        return String(text).replace("%1", first).replace("%2", second);
    }
    function displayNameForProvider(provider) { return provider; }
    function providerCliArgument(provider) { return provider; }
    function isPending(provider) { return false; }
    function isFieldPending(provider, field) { return false; }
    function markPending(provider, pending, desired) {}
    function markFieldPending(provider, field, pending) {}
    function runCommand(command, descriptor) {
        captured.push({command: command, descriptor: descriptor});
    }
    function test_generateProductionCommands() {
        var production = {deadline: configSecretPromptTimeoutMs,
            phases: configSecretPromptDialogTimeoutSeconds
                + configSecretPromptDialogKillAfterSeconds
                + configSecretCommandTimeoutSeconds + configSecretCommandKillAfterSeconds};
        configSecretPromptDialogTimeoutSeconds = 0.6;
        configSecretPromptDialogKillAfterSeconds = 0.2;
        configSecretCommandTimeoutSeconds = 0.6;
        configSecretCommandKillAfterSeconds = 0.2;
        setApiKey("codex");
        promptDescriptorSecret("codex", {id: "apiKey", title: "API key", kind: "secret",
            writeCommand: ["codexbar", "config", "set-api-key", "--provider", "codex", "--stdin"]});
        // A hostile descriptor title must survive the shell round-trip
        // verbatim: the prompt is a quoted positional argument, so command
        // substitution inside it must never execute.
        promptDescriptorSecret("codex", {id: "apiKey", title: HOSTILE_TITLE, kind: "secret",
            writeCommand: ["codexbar", "config", "set-api-key", "--provider", "codex", "--stdin"]});
        compare(errorText, "");
        compare(captured.length, 3);
        console.log("PROMPT_FIXTURE:" + JSON.stringify({production: production, commands: captured}));
    }
}
'''

PROCESS = '''import json, os, signal, sys, time
from pathlib import Path
role = Path(sys.argv[0]).name
directory = Path(os.environ["PROMPT_DIRECTORY"])
directory.joinpath(role + ".pid").write_text(str(os.getpid()))
directory.joinpath(role + ".argv").write_text(json.dumps(sys.argv[1:]))
mode = os.environ["PROMPT_MODE"]
if role == "kdialog":
    if mode == "cancel":
        sys.exit(1)
    if mode == "dialog-kill":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode.startswith("dialog-"):
        time.sleep(30)
    if mode == "late":
        time.sleep(0.45)
    print("synthetic-secret")
else:
    assert sys.stdin.read() == "synthetic-secret"
    assert "synthetic-secret" not in " ".join(sys.argv)
    directory.joinpath("received").touch()
    if mode == "cli-kill":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode.startswith("cli-"):
        time.sleep(30)
    if mode == "late":
        time.sleep(0.45)
    print(json.dumps({"ok": True}))
'''


class SecretPromptLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="codexbar prompt 'test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        for name in ("kdialog", "codexbar"):
            script = cls.directory / name
            script.write_text("#!" + sys.executable + "\n" + PROCESS)
            script.chmod(0o700)
        providers = Surface("providers", ROOT)
        page = ROOT / "contents/ui/configProviders.qml"
        source = providers.texts[page]
        providers.texts = {page: source}
        functions = []
        for name in ("setApiKey", "promptDescriptorSecret", "shellQuote"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + providers.function_body(name) + "}")
        properties = re.findall(
            r"^    readonly property int configSecret\w+:.*(?:\n[ \t]{8,}\S.*)*", source, re.MULTILINE)
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("CLI_PATH", json.dumps(str(cls.directory / "codexbar")))
        hostile = 'x"; touch "' + str(cls.directory / "PWNED") + '"; echo "y'
        qml = qml.replace("HOSTILE_TITLE", json.dumps(hostile))
        cls.hostile_prompt = hostile + " for codex"
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_PROPERTIES", "\n".join(properties).replace("readonly property int", "property real"))
        fixture = cls.directory / "tst_secret_prompt.qml"
        fixture.write_text(qml)
        result = subprocess.run(
            [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
            capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        if result.returncode:
            raise AssertionError(output)
        capture = next(line.split("PROMPT_FIXTURE:", 1)[1] for line in output.splitlines()
                       if "PROMPT_FIXTURE:" in line)
        cls.fixture = json.loads(capture)

    def test_ledger_deadline_covers_both_phases_and_disconnect_margin(self):
        production = self.fixture["production"]
        self.assertGreaterEqual(production["deadline"], production["phases"] * 1000 + 5000)

    def test_prompt_commands_carry_positional_args_and_quote_hostile_prompts(self):
        # The "_" placeholder keeps every positional stable: kdialog reads the
        # prompt from $1 and the CLI from $2/$3, so a shift would silently
        # rewire both. The recorded argv pins each position, and the hostile
        # title proves the prompt quoting survives a real shell round-trip.
        entry = next(item for item in self.fixture["commands"]
                     if item["descriptor"]["kind"] == "setApiKey")
        self.run_prompt(entry, "late")
        kdialog_argv = json.loads((self.directory / "kdialog.argv").read_text())
        self.assertEqual(kdialog_argv, ["--password", "API key for codex"])
        codexbar_argv = json.loads((self.directory / "codexbar.argv").read_text())
        self.assertEqual(codexbar_argv, ["config", "set-api-key", "--provider", "codex",
                                         "--stdin", "--format", "json", "--json-only"])
        hostile = next(item for item in self.fixture["commands"]
                       if "PWNED" in item["command"])
        for marker in self.directory.glob("*.argv"):
            marker.unlink()
        (self.directory / "PWNED").unlink(missing_ok=True)
        self.run_prompt(hostile, "late")
        self.assertFalse((self.directory / "PWNED").exists())
        hostile_argv = json.loads((self.directory / "kdialog.argv").read_text())
        self.assertEqual(hostile_argv, ["--password", self.hostile_prompt])

    def test_generated_scripts_cancel_finish_and_leave_no_running_children(self):
        for entry in self.fixture["commands"]:
            for mode in ("cancel", "dialog-term", "dialog-kill", "late", "cli-term", "cli-kill"):
                with self.subTest(kind=entry["descriptor"]["kind"], mode=mode):
                    self.run_prompt(entry, mode)

    def run_prompt(self, entry, mode):
        for marker in self.directory.glob("*.pid"):
            marker.unlink()
        (self.directory / "received").unlink(missing_ok=True)
        self.assertNotIn("synthetic-secret", entry["command"])
        process = subprocess.Popen(
            ["sh", "-c", entry["command"]], start_new_session=True,
            env={**os.environ, "PATH": str(self.directory) + os.pathsep + os.environ["PATH"],
                 "PROMPT_DIRECTORY": str(self.directory), "PROMPT_MODE": mode},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            stdout, stderr = process.communicate(timeout=5)
            if mode.startswith("cli-"):
                self.assertIn(process.returncode, (124, 137), stderr)
            else:
                self.assertEqual(process.returncode, 0, stderr)
                self.assertEqual(json.loads(stdout), {"ok": True} if mode == "late" else {"cancelled": True})
            self.assertEqual((self.directory / "received").exists(), mode == "late" or mode.startswith("cli-"))
            for marker in self.directory.glob("*.pid"):
                status = Path("/proc") / marker.read_text() / "stat"
                try:
                    state = status.read_text().rsplit(")", 1)[1].split()[0]
                except FileNotFoundError:
                    continue
                self.assertEqual(state, "Z", marker.name)
        finally:
            for marker in self.directory.glob("*.pid"):
                try:
                    os.kill(int(marker.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()


QML_WIRING = '''import QtQuick
import QtTest
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/config/ProviderDescriptor.js" as ProviderDescriptor
import "SOURCE_URL/config/ProviderConfigProtocol.js" as ProviderConfigProtocol
TestCase {
    name: "ProviderCommandWiring"
    property string commandPath: "codexbar"
    property string errorText: ""
    property string statusText: ""
    property bool loading: false
    property var providers: []
    property var providerDiagnostics: ({})
    property var providerDiagnosticErrors: ({})
    property string selectedProviderID: ""
    property bool providerDescriptorsUnavailable: false
    property bool fireworksSingleKeySetupSupported: false
    property var providerFieldPending: ({})
    property var providerDiagnosticLoading: ({})
    property var commands: ({})
    property int cfg_providerConfigRevision: 0
    property var configSource
    property var page
    // Host-provided Plasmoid singleton, stubbed under a writable name: the
    // builder renames the Plasmoid references inside the two extracted
    // revision functions to this stub.
    property var plasmoidHost: ({"configuration": ({})})
    SOURCE_PROPERTIES
    SOURCE_FUNCTIONS
    function i18n(text, first, second) {
        return String(text).replace("%1", first).replace("%2", second);
    }
    function displayNameForProvider(provider) { return provider; }
    function providerCliArgument(provider) { return provider; }
    function providerTitle(identifier) { return identifier; }
    function updateProviderEnabled(provider, value) {}
    function freshSource() {
        var backend = {connected: [], disconnected: []};
        backend.connectSource = function(name) { backend.connected.push(name); };
        backend.disconnectSource = function(name) { backend.disconnected.push(name); };
        return backend;
    }
    function freshPage() {
        var stub = {reloadCalls: 0, preserved: undefined};
        stub.reload = function(preserve) { stub.reloadCalls++; stub.preserved = preserve; };
        stub.providerTitle = function(identifier) { return identifier; };
        return stub;
    }
    // Every command must mint a distinct nonce source: without the serial the
    // list and version runs share one ledger entry and a late result lands on
    // the wrong descriptor.
    function initTestCase() {
        // A fresh page starts its serial at zero, so its first command
        // carries RUN=1: the probe observes the effect, not the property.
        configSource = freshSource();
        runCommand("probe-cmd", {kind: "probe", timeoutMs: 1000});
        compare(configSource.connected[0], "CODEXBAR_PLASMA_RUN=1 probe-cmd");
    }
    function test_runCommandsMintDistinctNonceSources() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        runCommand("list-cmd", {kind: "list", timeoutMs: 1000});
        runCommand("version-cmd", {kind: "version", timeoutMs: 1000});
        compare(commandRunSerial, 2);
        compare(configSource.connected.length, 2);
        compare(configSource.connected[0], "CODEXBAR_PLASMA_RUN=1 list-cmd");
        compare(configSource.connected[1], "CODEXBAR_PLASMA_RUN=2 version-cmd");
        compare(commands["CODEXBAR_PLASMA_RUN=1 list-cmd"].kind, "list");
        compare(commands["CODEXBAR_PLASMA_RUN=2 version-cmd"].kind, "version");
    }
    // A reload retires the in-flight list run first, so its late result finds
    // no ledger entry instead of overwriting the fresh providers.
    function test_reloadRetiresInFlightListCommand() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        runCommand("old-list", {kind: "list", timeoutMs: 60000});
        var stale = configSource.connected[0];
        reload();
        compare(configSource.disconnected.length, 1);
        compare(configSource.disconnected[0], stale);
        verify(CommandLedger.find(commands, stale) === null);
        compare(configSource.connected.length, 3);
        compare(commandRunSerial, 3);
    }
    // Descriptors are copied through Guards: the ledger must own its entry,
    // and unsafe keys must not survive the copy.
    function test_copyObjectDetachesAndDropsUnsafeKeys() {
        var original = {kind: "list"};
        var copy = copyObject(original);
        copy.kind = "version";
        compare(original.kind, "list");
        var evil = JSON.parse('{"__proto__": {"polluted": true}, "kind": "list"}');
        var clean = copyObject(evil);
        compare(clean.kind, "list");
        verify(!("polluted" in clean));
        verify(!("polluted" in {}));
    }
    // Pending keys resolve CLI aliases before mapping, so an alias and its
    // canonical id share one pending slot; unusable ids map to nothing.
    function test_providerMapKeyNormalizesAliases() {
        compare(providerMapKey("11labs"), "elevenlabs");
        compare(providerMapKey("codex"), "codex");
        compare(descriptorPendingKey("__proto__", "apiKey"), "");
    }
    // Field keys are JSON-quoted so a crafted id cannot collide with another
    // entry, and overlong ids are refused instead of keying unbounded state.
    function test_descriptorPendingKeysQuoteAndBoundLengths() {
        compare(descriptorPendingKey("codex", "apiKey"), 'codex::"apiKey"');
        compare(descriptorPendingKey("codex", "  apiKey  "), 'codex::"apiKey"');
        compare(descriptorPendingFieldKey(""), "");
        compare(descriptorPendingKey("codex", ""), "");
        var long = new Array(130).join("x");
        compare(descriptorPendingFieldKey(long), "");
        compare(descriptorPendingKey("codex", long), "");
    }
    // The icon file name is built from a provider-controlled key: unusable
    // keys fall back to the generic icon instead of reaching a URL.
    function test_providerIconSourceFallsBackForUnusableKeys() {
        compare(String(providerIconSource("../../etc/passwd")), "view-statistics");
        compare(String(providerIconSource("<b>evil</b>")), "view-statistics");
        var benign = String(providerIconSource("codex"));
        verify(benign !== "view-statistics");
        verify(benign.slice(-10) === "/codex.svg");
    }
    // A secret field must never take the direct write path: the planner
    // rejects it, nothing runs, and the value reaches no command line.
    function test_secretFieldWriteRequiresSecurePrompt() {
        configSource = freshSource();
        writeDescriptorField("codex", {id: "apiKey", kind: "secret", title: "API key",
            writeCommand: ["codexbar", "config", "set-api-key", "--provider", "codex", "--stdin"]},
            "TOPSECRET");
        compare(configSource.connected.length, 0);
        verify(errorText.length > 0);
        for (var i = 0; i < configSource.connected.length; i++) {
            verify(configSource.connected[i].indexOf("TOPSECRET") === -1);
        }
    }
    // A plain value takes the planned command with its placeholder filled.
    function test_textFieldWriteRunsPlannedCommand() {
        configSource = freshSource();
        writeDescriptorField("codex", {id: "name", kind: "text", title: "Name",
            writeCommand: ["codexbar", "config", "set", "--provider", "codex", "{value}"]}, "abc");
        compare(errorText, "");
        compare(configSource.connected.length, 1);
        verify(configSource.connected[0].indexOf("abc") !== -1);
    }
    // The prompt path is secrets-only: a plain field is rejected before any
    // dialog or command could carry its value.
    function test_promptPathRejectsNonSecretField() {
        configSource = freshSource();
        promptDescriptorSecret("codex", {id: "name", kind: "text", title: "Name",
            writeCommand: ["codexbar", "config", "set", "--provider", "codex", "{value}"]});
        compare(configSource.connected.length, 0);
        verify(errorText.length > 0);
    }
    // Only allow-listed descriptor actions run; anything else is refused
    // before it can reach the shell.
    function test_descriptorActionRunsOnlyAllowedCommands() {
        configSource = freshSource();
        runDescriptorAction("codex", {id: "openDocs",
            command: ["codexbar", "config", "action", "open-docs"]});
        compare(errorText, "");
        compare(configSource.connected.length, 1);
        verify(configSource.connected[0].indexOf("open-docs") !== -1);
        runDescriptorAction("codex", {id: "evil", command: ["rm", "-rf", "/"]});
        compare(configSource.connected.length, 1);
        verify(errorText.length > 0);
    }
    // An action result opens only an https URL. Anything else reports an
    // unsupported URL and never touches the opener; a non-string value is
    // coerced before trimming instead of throwing inside the handler.
    function test_actionResultOpensOnlyHttpsUrls() {
        configSource = freshSource();
        page = freshPage();
        handleDescriptorActionResult({provider: "codex", actionID: "a1"},
            '{"url": "javascript:alert(1)"}', "", 0);
        verify(errorText.length > 0);
        compare(page.reloadCalls, 0);
        handleDescriptorActionResult({provider: "codex", actionID: "a1"},
            '{"url": 12345}', "", 0);
        verify(errorText.length > 0);
        compare(page.reloadCalls, 0);
        handleDescriptorActionResult({provider: "codex", actionID: "a1"},
            '{"url": "https://example.com/x"}', "", 0);
        compare(errorText, "");
        verify(statusText.length > 0);
        compare(page.reloadCalls, 1);
    }
    // A fresh list selects the first enabled provider, so the page never
    // opens on an empty selection; the selection property carries it.
    function test_listResultSelectsFirstEnabledProvider() {
        providers = [];
        selectedProviderID = "";
        loading = true;
        errorText = "stale";
        page = freshPage();
        var currentRevision = providerConfigRevisionValue();
        handleListResult({includeDescriptors: false, providerConfigRevision: currentRevision},
            '[{"provider": "codex", "displayName": "Codex", "enabled": true}, {"provider": "claude", "displayName": "Claude", "enabled": false}]', "");
        compare(providers.length, 2);
        compare(providers[0].provider, "codex");
        compare(selectedProviderID, "codex");
        compare(loading, false);
        compare(errorText, "");
    }
    // An old CLI that rejects --descriptors falls back to a plain list and
    // marks descriptors unavailable, instead of leaving the page in error.
    function test_listResultRetriesWithoutDescriptorsOnOldCli() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        providerDescriptorsUnavailable = false;
        loading = true;
        var currentRevision = providerConfigRevisionValue();
        handleListResult({includeDescriptors: true, providerConfigRevision: currentRevision},
            "", "codexbar: error: unknown option '--descriptors'");
        compare(providerDescriptorsUnavailable, true);
        compare(configSource.connected.length, 1);
        verify(configSource.connected[0].indexOf("--descriptors") === -1);
        verify(configSource.connected[0].indexOf("--format") !== -1);
        verify(configSource.connected[0].indexOf("--json-only") !== -1);
    }
    // The retry decision delegates to the protocol matcher: descriptor
    // rejection retries, unrelated stderr does not.
    function test_descriptorUnsupportedMessageDelegatesToProtocol() {
        verify(descriptorListUnsupportedMessage("", "error: unknown option '--descriptors'").length > 0);
        compare(descriptorListUnsupportedMessage("", "connection refused"), "");
        compare(shouldRetryProviderListWithoutDescriptors("", "error: unknown option '--descriptors'"), true);
        compare(shouldRetryProviderListWithoutDescriptors("", "connection refused"), false);
    }
    // A diagnose reply is normalized before it is stored, so the settings
    // rows read shaped values rather than raw CLI JSON.
    function test_diagnoseResultStoresNormalizedDiagnostic() {
        providerDiagnostics = ({});
        providerDiagnosticErrors = ({});
        providerDiagnosticLoading = JSON.parse('{"codex": true}');
        handleDiagnoseResult({provider: "codex"},
            '{"provider": "codex", "source": "config.toml", "auth": {"configured": true, "modes": ["api-key"]}, "settings": {"model": {}}}', "");
        var diagnostic = providerDiagnosticFor("codex");
        verify(diagnostic !== null);
        compare(diagnostic.source, "config.toml");
        compare(diagnostic.authConfigured, true);
        compare(diagnostic.settingsKeys, "model");
        compare(providerDiagnosticErrorFor("codex"), "");
        compare(providerDiagnosticLoadingFor("codex"), false);
    }
    // An error envelope becomes a diagnostic error and stores nothing, so a
    // failed inspect never shows stale shaped data as current.
    function test_diagnoseResultSurfacesEnvelopeError() {
        providerDiagnostics = ({});
        providerDiagnosticErrors = ({});
        providerDiagnosticLoading = JSON.parse('{"codex": true}');
        handleDiagnoseResult({provider: "codex"}, '{"error": {"message": "boom"}}', "");
        verify(providerDiagnosticFor("codex") === null);
        verify(providerDiagnosticErrorFor("codex").length > 0);
        compare(providerDiagnosticLoadingFor("codex"), false);
    }
    // A successful field write unlocks the field, reports the save, and
    // reloads preserving messages; the reload keeps status text visible.
    function test_fieldResultSuccessReloadsPreservingMessages() {
        configSource = freshSource();
        providerFieldPending = ({});
        page = freshPage();
        errorText = "";
        statusText = "";
        markFieldPending("codex", "name", true);
        verify(isFieldPending("codex", "name"));
        handleDescriptorFieldResult({provider: "codex", fieldID: "name"},
            '{"ok": true}', "", 0);
        compare(isFieldPending("codex", "name"), false);
        compare(errorText, "");
        compare(statusText, "codex setting saved");
        compare(page.reloadCalls, 1);
        compare(page.preserved, true);
    }
    // The list command always requests JSON; the descriptors flag is only
    // sent on the first pass, so the fallback run stays parseable by old
    // CLI builds that reject the flag.
    function test_listCommandCarriesDescriptorsAndJsonFlags() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        runProviderListCommand(true);
        var first = configSource.connected[configSource.connected.length - 1];
        verify(first.indexOf("--descriptors") !== -1);
        verify(first.indexOf("--format") !== -1);
        verify(first.indexOf("--json-only") !== -1);
        runProviderListCommand(false);
        var fallback = configSource.connected[configSource.connected.length - 1];
        verify(fallback.indexOf("--descriptors") === -1);
        verify(fallback.indexOf("--json-only") !== -1);
    }
    // Loading settings runs a redacted diagnose for the provider, so the
    // inspect action never prints secrets into process output.
    function test_loadProviderSettingsRunsRedactedDiagnose() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        providerDiagnosticLoading = ({});
        errorText = "";
        loadProviderSettings("codex");
        compare(configSource.connected.length, 1);
        var command = configSource.connected[0];
        verify(command.indexOf("diagnose --provider") !== -1);
        verify(command.indexOf("--format json --redact") !== -1);
        verify(command.indexOf("codex") !== -1);
        compare(providerDiagnosticLoadingFor("codex"), true);
        providerDiagnosticLoading = ({});
    }
    // A missing write/action command stays silent: the guard returns before
    // the planner could report an unsupported command for a no-op row.
    function test_emptyWriteCommandsStaySilent() {
        configSource = freshSource();
        providerFieldPending = ({});
        errorText = "stale";
        writeDescriptorField("codex", {id: "name", kind: "text"}, "abc");
        promptDescriptorSecret("codex", {id: "apiKey", kind: "secret"});
        runDescriptorAction("codex", {id: "openDocs"});
        compare(configSource.connected.length, 0);
        compare(errorText, "stale");
        errorText = "";
    }
    // Field writes register under the descriptorField kind so their results
    // unlock the field instead of landing on another handler.
    function test_fieldWriteRegistersDescriptorFieldKind() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        providerFieldPending = ({});
        errorText = "";
        writeDescriptorField("codex", {id: "name", kind: "text", title: "Name",
            writeCommand: ["codexbar", "config", "set", "--provider", "codex", "{value}"]}, "abc");
        compare(configSource.connected.length, 1);
        var entry = CommandLedger.find(commands, configSource.connected[0]);
        verify(entry !== null);
        compare(entry.kind, "descriptorField");
        providerFieldPending = ({});
    }
    // Descriptor actions register under the descriptorAction kind for the
    // same routing reason as field writes.
    function test_actionRegistersDescriptorActionKind() {
        configSource = freshSource();
        commandRunSerial = 0;
        commands = ({});
        providerFieldPending = ({});
        errorText = "";
        runDescriptorAction("codex", {id: "openDocs",
            command: ["codexbar", "config", "action", "open-docs"]});
        compare(configSource.connected.length, 1);
        var entry = CommandLedger.find(commands, configSource.connected[0]);
        verify(entry !== null);
        compare(entry.kind, "descriptorAction");
        providerFieldPending = ({});
    }
    // A failed field write unlocks the field and reports the failure without
    // reloading, so the rejected value stays on screen.
    function test_fieldResultErrorReportsWithoutReload() {
        providerFieldPending = ({});
        page = freshPage();
        markFieldPending("codex", "name", true);
        handleDescriptorFieldResult({provider: "codex", fieldID: "name"},
            '{"error": {"message": "boom"}}', "", 0);
        compare(isFieldPending("codex", "name"), false);
        compare(errorText, "codex: boom");
        compare(page.reloadCalls, 0);
    }
}
'''

WIRING_FUNCTIONS = (
    "runCommand", "disconnectCommandsByKind", "reload", "runProviderListCommand",
    "runCliVersionCommand", "loadProviderSettings",
    "providerConfigRevisionValue", "bumpProviderConfigRevision",
    "copyObject", "hasOwnKey", "providerKey", "providerMapKey", "descriptorPendingKey",
    "descriptorPendingFieldKey", "providerIconSource", "shellQuote", "writeDescriptorField",
    "promptDescriptorSecret", "runDescriptorAction", "handleDescriptorActionResult",
    "handleDescriptorFieldResult", "handleListResult", "handleDiagnoseResult",
    "shouldRetryProviderListWithoutDescriptors", "descriptorListUnsupportedMessage",
    "boundedCliMessage", "providerByID", "firstSelectableProvider",
    "providerDiagnosticFor", "providerDiagnosticErrorFor", "setProviderDiagnostic",
    "setProviderDiagnosticError", "setProviderDiagnosticLoading",
    "parseCommandPayload", "providerCommandFailureText", "markFieldPending", "isFieldPending",
    "providerDiagnosticLoadingFor",
)


class ProviderCommandWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="codexbar-provider-wiring-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        providers = Surface("providers", ROOT)
        page = ROOT / "contents/ui/configProviders.qml"
        source = providers.texts[page]
        providers.texts = {page: source}
        functions = []
        for name in WIRING_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            body = providers.function_body(name)
            if name in ("providerConfigRevisionValue", "bumpProviderConfigRevision"):
                body = body.replace("Plasmoid", "plasmoidHost")
            functions.append(signature + " {" + body + "}")
        serial = re.search(r"^    property int commandRunSerial: 0$", source,
                           re.MULTILINE).group(0)
        command_timeout = re.search(r"^    readonly property int configCommandTimeoutMs: 60000$",
                                    source, re.MULTILINE).group(0).replace("readonly ", "")
        secrets = re.findall(
            r"^    readonly property int configSecret\w+:.*(?:\n[ \t]{8,}\S.*)*", source, re.MULTILINE)
        qml = QML_WIRING.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_PROPERTIES", "\n".join([serial, command_timeout] + secrets))
        fixture = cls.directory / "tst_provider_wiring.qml"
        fixture.write_text(qml)
        result = subprocess.run(
            [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
            capture_output=True, text=True, timeout=30)
        cls.output = result.stdout + result.stderr
        cls.returncode = result.returncode

    def test_provider_command_wiring(self):
        self.assertEqual(self.returncode, 0, self.output)


if __name__ == "__main__":
    unittest.main()
