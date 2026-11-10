"""Run the auth adapter against synthetic CLI event streams and native dialogs."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import shlex
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/lib'))
from qml_surfaces import Surface
HELPER = ROOT / "scripts/provider-auth.py"
spec = importlib.util.spec_from_file_location("provider_auth", HELPER)
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
PENDING = {"status": "authorization_pending", "verificationURI": "https://github.com/login/device",
           "userCode": "ABCD-1234", "expiresIn": 30}

CLI = r'''#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time
from pathlib import Path
root = Path(os.environ['AUTH_FIXTURE'])
root.joinpath('cli.pid').write_text(str(os.getpid()))
root.joinpath('cli.argv').write_text(json.dumps(sys.argv[1:]))
mode = os.environ.get('AUTH_MODE', 'ok')
if sys.argv[2] != 'login':
    value = sys.stdin.buffer.read()
    root.joinpath('input').write_bytes(value)
    provider = sys.argv[sys.argv.index('--provider') + 1]
    if mode.startswith('child-'):
        if mode == 'child-resistant':
            signal.signal(signal.SIGTERM, lambda *_: root.joinpath('stopping').touch())
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'],
                                 stdin=subprocess.DEVNULL,
                                 stdout=None if mode == 'child-pipe' else subprocess.DEVNULL)
        root.joinpath('child.pid').write_text(str(child.pid))
        if mode == 'child-closed-pipes':
            os.close(1)
        if mode in ('child-hang', 'child-closed-pipes', 'child-resistant'):
            time.sleep(60)
    if mode == 'refuse':
        print(json.dumps({'error': {'message': value.decode()}}))
        print(value.decode(), file=sys.stderr)
        sys.exit(1)
    if mode == 'oversize':
        print('x' * 70000)
        sys.exit(0)
    print(json.dumps({'provider': provider if mode != 'mismatch' else 'wrong',
                     'enabled': True, 'cleared': ['apiKey', 'cookieHeader'],
                     'configPath': '/private/path', 'cookie': value.decode()}))
    sys.exit(0)
if '--stdin' in sys.argv:
    value = sys.stdin.buffer.read()
    root.joinpath('input').write_bytes(value)
lines = json.loads(root.joinpath('events').read_text())
for line in lines:
    if isinstance(line, (int, float)):
        time.sleep(line)
    else:
        # Deliberately split writes across JSON boundaries.
        value = (line if isinstance(line, str) else json.dumps(line)) + '\n'
        os.write(1, value[:5].encode())
        os.write(1, value[5:].encode())
if mode == 'hang':
    time.sleep(60)
sys.exit(1 if mode == 'exit1' else 0)
'''
DIALOG = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ['AUTH_FIXTURE'])
root.joinpath('dialog.pid').write_text(str(os.getpid()))
root.joinpath('dialog.argv').write_text(json.dumps(sys.argv[1:]))
root.joinpath('dialog.text').write_text(sys.stdin.read())
mode = os.environ.get('AUTH_MODE')
if mode in ('cancel', 'dismiss', 'dialog-failure'):
    sys.exit({'cancel': 1, 'dismiss': 0, 'dialog-failure': 2}[mode])
time.sleep(60)
'''


class LoginEventTests(unittest.TestCase):
    def test_pending_projection_and_terminal_decisions(self):
        event = {**PENDING, 'private': 'discarded'}
        self.assertEqual(auth.login_event(False, None, event),
                         {'kind': 'pending', 'prompt': ('https://github.com/login/device', 'ABCD-1234', 30)})
        self.assertEqual(event['private'], 'discarded')
        self.assertEqual(auth.login_event(True, None, {'status': 'authorized'}),
                         {'kind': 'terminal', 'status': 'ok'})
        self.assertEqual(auth.login_event(False, None, {'status': 'failed',
                         'error': 'Config changed during login. Please try again.'}),
                         {'kind': 'terminal', 'status': 'conflict'})
        self.assertEqual(auth.login_event(True, None, {'status': 'failed', 'error': 'private'}),
                         {'kind': 'terminal', 'status': 'failed'})

    def test_invalid_order_and_terminal_state_reject_every_later_event(self):
        for pending, terminal, event in [(False, None, {'status': 'authorized'}),
                (True, None, PENDING), (False, None, None), (False, None, []),
                (False, None, {'status': 'future'}), (True, 'ok', PENDING),
                (True, 'failed', {'status': 'failed'})]:
            with self.subTest(pending=pending, terminal=terminal, event=event):
                self.assertEqual(auth.login_event(pending, terminal, event), {'kind': 'invalid'})

    def test_stream_framing_and_total_budget(self):
        stream = auth.LoginStream()
        self.assertEqual(list(stream.feed(b'{"status":')), [])
        self.assertTrue(stream.incomplete())
        self.assertEqual(list(stream.feed(b'"authorized"}\n{}\n ')), [{'status': 'authorized'}, {}])
        self.assertFalse(stream.incomplete())
        stream = auth.LoginStream()
        list(stream.feed(b'{}' + b' ' * (auth.MAX_BYTES - 3) + b'\n'))
        with self.assertRaises(ValueError):
            list(stream.feed(b'\n'))
        for invalid in (b'\n', b'{\n'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                list(auth.LoginStream().feed(invalid))


class ProviderAuthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codexbar-auth-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name, source in (("codexbar", CLI), ("kdialog", DIALOG)):
            path = self.root / name
            path.write_text(source)
            path.chmod(0o700)
        self.env = {**os.environ, "AUTH_FIXTURE": str(self.root), "PATH": str(self.root) + ":" + os.environ['PATH']}

    def arguments(self, action="login", provider="copilot"):
        return [sys.executable, str(HELPER), "--cli", str(self.root / "codexbar"),
                "--action", action, "--provider", provider, "--title", "Sign in",
                "--message", "Visit %1\nCode %2\nExpires in %3"]

    def run_helper(self, events=(), mode="ok", action="login", value="", request="", provider="copilot"):
        self.root.joinpath('events').write_text(json.dumps(events))
        arguments = self.arguments(action, provider) + (["--request", request] if request else [])
        result = subprocess.run(arguments, env={**self.env, "AUTH_MODE": mode},
                                input=value, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertNotIn('ABCD-1234', result.stdout)
        self.assertNotIn('github.com', result.stdout)
        self.assertNotIn('private', result.stdout)
        self.assertNotIn('synthetic-cookie', result.stdout)
        return json.loads(result.stdout)

    def assert_stopped(self, name):
        pid_file = self.root / (name + '.pid')
        if not pid_file.exists():
            return
        pid = int(pid_file.read_text())
        stat = Path(f"/proc/{pid}/stat")
        # Descendants are not waitable children of the helper. SIGKILL is
        # asynchronous, so allow the kernel to finish their termination.
        deadline = time.monotonic() + 2
        while True:
            try:
                state = stat.read_text().split(') ')[1]
            except (FileNotFoundError, ProcessLookupError):
                return
            if state.startswith('Z'):
                return
            self.assertLess(time.monotonic(), deadline, name + ' is still running')
            time.sleep(.01)

    def test_authorized_stream_shows_only_projected_event_in_private_dialog(self):
        self.assertEqual(self.run_helper([PENDING, .2, {"status": "authorized"}])['status'], 'ok')
        text = self.root.joinpath('dialog.text').read_text()
        self.assertIn('ABCD-1234', text)
        self.assertIn('https://github.com/login/device', text)
        self.assertNotIn('ABCD-1234', self.root.joinpath('dialog.argv').read_text())
        self.assertNotIn('github.com', self.root.joinpath('dialog.argv').read_text())
        self.assertEqual(json.loads(self.root.joinpath('cli.argv').read_text()),
                         ['config', 'login', '--provider', 'copilot', '--json'])
        self.assert_stopped('dialog')
        self.assert_stopped('cli')

    def test_session_import_uses_stdin_and_requires_one_successful_terminal_record(self):
        cases = [([{"status": "authorized"}], "ok", "ok"),
                 ([{"status": "authorized"}], "exit1", "failed"),
                 ([{"status": "authorized", "error": "synthetic-cookie"}], "ok", "failed"),
                 ([{"status": "failed", "error": "synthetic-cookie"}], "exit1", "failed"),
                 ([{"status": "failed", "error": "Config changed during login. Please try again."}], "exit1", "conflict"),
                 ([PENDING, {"status": "authorized"}], "ok", "failed"),
                 ([{"status": "authorized"}, {"status": "failed"}], "ok", "failed"),
                 ([{"status": "authorization_pending"}], "ok", "failed"),
                 ([None], "ok", "failed"), (["x" * 70000], "ok", "failed")]
        for events, mode, expected in cases:
            with self.subTest(events=str(events)[:100], mode=mode):
                result = self.run_helper(events, mode, action="import-session",
                                         provider="claudeplatform", value="synthetic-cookie")
                self.assertEqual(result, {"status": expected, "provider": "claudeplatform"})
                self.assertEqual(self.root.joinpath('input').read_text(), 'synthetic-cookie')
                self.assertEqual(json.loads(self.root.joinpath('cli.argv').read_text()),
                                 ['config', 'login', '--provider', 'claudeplatform', '--json', '--stdin'])
                self.assertFalse(self.root.joinpath('dialog.pid').exists())
                self.assert_stopped('cli')

    def test_session_import_rejects_other_providers_and_empty_or_oversized_input(self):
        for provider, value in [('copilot', 'synthetic-cookie'), ('claudeplatform', ''),
                                ('claudeplatform', 'x' * 65537)]:
            with self.subTest(provider=provider, size=len(value)):
                self.assertEqual(self.run_helper(action='import-session', provider=provider,
                                                 value=value)['status'], 'failed')
                self.assertFalse(self.root.joinpath('cli.pid').exists())

    def test_cancellation_stops_cli_and_never_reports_authorized(self):
        self.assertEqual(self.run_helper([PENDING, 3, {"status": "authorized"}], mode='cancel')['status'], 'cancelled')
        self.assert_stopped('cli')

    def test_dialog_ok_continues_waiting_and_dialog_failure_is_not_cancellation(self):
        events = [PENDING, .3, {"status": "authorized"}]
        self.assertEqual(self.run_helper(events, mode='dismiss')['status'], 'ok')
        self.assertEqual(self.run_helper(events, mode='dialog-failure')['status'], 'failed')
        self.assert_stopped('cli')

    def test_slow_terminal_exit_is_failure_not_expiry(self):
        self.assertEqual(self.run_helper([PENDING, {"status": "authorized"}], mode='hang')['status'], 'failed')
        self.assert_stopped('cli')

    def test_expiry_stops_cli_and_dialog(self):
        self.assertEqual(self.run_helper([{**PENDING, 'expiresIn': 1}], mode='hang')['status'], 'expired')
        self.assert_stopped('cli')
        self.assert_stopped('dialog')

    def test_offline_failure_conflict_and_exit_failure(self):
        self.assertEqual(self.run_helper([{'status':'failed', 'error':'opaque private error'}], mode='exit1')['status'], 'failed')
        self.assertEqual(self.run_helper([PENDING, {'status':'failed', 'error':'Config changed during login. Please try again.'}], mode='exit1')['status'], 'conflict')
        self.assertEqual(self.run_helper([PENDING, {'status':'authorized'}], mode='exit1')['status'], 'failed')

    def test_malformed_truncated_duplicate_and_out_of_order_streams(self):
        cases = [[], ['{'], [None], [['bad']], [{'status':'authorized'}],
                 [PENDING], [PENDING, PENDING], [PENDING, {'status':'authorized'}, {'status':'failed'}],
                 [{'status':'future'}], ['x' * 70000]]
        for events in cases:
            with self.subTest(events=str(events)[:100]):
                self.assertEqual(self.run_helper(events)['status'], 'failed')

    def test_untrusted_pending_fields(self):
        cases = [('verificationURI', v) for v in ['http://github.com/login/device', 'file:///tmp/x',
                 'https://a@github.com/login/device', 'https://github.com/login/device?token=secret',
                 'https://github.com/login/device\n', 'https://github.com:bad/login/device']]
        cases += [('userCode', v) for v in ['<b>ABCD</b>', 'ABCD\n1234', None, 'x' * 128]]
        cases += [('expiresIn', v) for v in [True, 0, -1, 901, '30', 3.5]]
        for key, value in cases:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                auth.pending_event({**PENDING, key: value})
        self.assertEqual(auth.pending_event({**PENDING, 'extra': 'secret'})[1], 'ABCD-1234')

    def test_cookie_stdin_and_clear_project_only_safe_matching_results(self):
        result = self.run_helper(action='set-cookie', value='synthetic-cookie')
        self.assertEqual(result, {'status':'ok', 'enabled':True, 'provider':'copilot'})
        self.assertEqual(self.root.joinpath('input').read_text(), 'synthetic-cookie')
        self.assertNotIn('synthetic-cookie', self.root.joinpath('cli.argv').read_text())
        self.assertIn('--stdin', self.root.joinpath('cli.argv').read_text())
        self.assertEqual(self.run_helper(action='clear-credential'), {'status':'ok', 'provider':'copilot'})
        for mode in ['refuse', 'mismatch', 'oversize']:
            self.assertEqual(self.run_helper(action='set-cookie', value='synthetic-cookie', mode=mode)['status'], 'failed')
        self.assertEqual(self.run_helper(action='set-cookie', value='')['status'], 'failed')

    def wait_dialog(self):
        deadline = time.monotonic() + 5
        while not self.root.joinpath('dialog.text').exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertTrue(self.root.joinpath('dialog.text').exists())

    def stop_fixture_process(self, name):
        path = self.root / (name + '.pid')
        if path.exists():
            try:
                os.kill(int(path.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass

    def wait_credential_child(self, marker='child.pid'):
        deadline = time.monotonic() + 5
        while not self.root.joinpath(marker).exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertTrue(self.root.joinpath(marker).exists())

    def test_repeated_signals_do_not_interrupt_credential_cleanup(self):
        self.addCleanup(self.stop_fixture_process, 'cli')
        self.addCleanup(self.stop_fixture_process, 'child')
        process = subprocess.Popen(self.arguments(action='clear-credential'),
                                   env={**self.env, 'AUTH_MODE': 'child-resistant'},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.wait_credential_child()
            process.send_signal(signal.SIGTERM)
            self.wait_credential_child('stopping')
            process.send_signal(signal.SIGINT)
            out, err = process.communicate(timeout=5)
            self.assertEqual(json.loads(out)['status'], 'failed')
            self.assertEqual(err, '')
            self.assert_stopped('cli')
            self.assert_stopped('child')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_credential_completion_stops_wrapper_descendants(self):
        self.addCleanup(self.stop_fixture_process, 'child')
        self.assertEqual(self.run_helper(action='clear-credential', mode='child-exit')['status'], 'ok')
        self.assert_stopped('child')

    def test_credential_timeout_stops_pipe_holding_descendants(self):
        self.addCleanup(self.stop_fixture_process, 'child')
        # Advance the real helper deadline without waiting 55 seconds or changing
        # production bounds. Its selector still drives the actual subprocess pipes.
        clock = time.monotonic
        with patch.dict(os.environ, {**self.env, 'AUTH_MODE': 'child-pipe'}), \
                patch.object(auth.time, 'monotonic', side_effect=lambda: clock() * 100):
            self.assertEqual(auth.credential(str(self.root / 'codexbar'), 'clear-credential', 'copilot'),
                             {'status': 'failed'})
        self.assert_stopped('child')

    def test_credential_interruption_stops_wrapper_and_descendants(self):
        for mode in ('child-hang', 'child-closed-pipes'):
            for interruption in ('signal', 'timeout-signal', 'lost-parent'):
                with self.subTest(mode=mode, interruption=interruption):
                    self.root.joinpath('child.pid').unlink(missing_ok=True)
                    arguments = self.arguments(action='clear-credential')
                    if interruption != 'signal':
                        arguments = ['timeout', '--kill-after=2s', '60s', *arguments]
                    process = subprocess.Popen(arguments,
                                               env={**self.env, 'AUTH_MODE': mode}, stdout=subprocess.PIPE,
                                               stderr=subprocess.PIPE, text=True)
                    try:
                        self.wait_credential_child()
                        if interruption == 'lost-parent':
                            process.kill()
                        else:
                            process.send_signal(signal.SIGTERM)
                        out, err = process.communicate(timeout=5)
                        self.assertEqual(json.loads(out)['status'], 'failed')
                        self.assertEqual(err, '')
                        self.assert_stopped('cli')
                        self.assert_stopped('child')
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.wait()
                        self.stop_fixture_process('cli')
                        self.stop_fixture_process('child')
                        process.stdout.close()
                        process.stderr.close()

    def test_signal_cancellation_stops_both_children(self):
        self.root.joinpath('events').write_text(json.dumps([PENDING]))
        process = subprocess.Popen(self.arguments(), env={**self.env, 'AUTH_MODE':'hang'},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.wait_dialog()
            process.send_signal(signal.SIGTERM)
            out, err = process.communicate(timeout=5)
            self.assertEqual(json.loads(out)['status'], 'cancelled')
            self.assertEqual(err, '')
            self.assert_stopped('cli')
            self.assert_stopped('dialog')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_lost_engine_timeout_parent_stops_children(self):
        self.root.joinpath('events').write_text(json.dumps([PENDING]))
        process = subprocess.Popen(['timeout', '--kill-after=3s', '20s', *self.arguments(), '--supervised'],
                                   env={**self.env, 'AUTH_MODE':'hang'}, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        try:
            self.wait_dialog()
            process.kill()  # QProcess destruction can kill timeout without forwarding a signal.
            out, err = process.communicate(timeout=5)
            self.assertEqual(json.loads(out)['status'], 'cancelled')
            self.assertEqual(err, '')
            self.assert_stopped('cli')
            self.assert_stopped('dialog')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_real_plasma_engine_cancel_and_destruction_stop_login(self):
        self.root.joinpath('events').write_text(json.dumps([PENDING]))
        qml = '''import QtQuick
import QtTest
import org.kde.plasma.plasma5support as Plasma5Support
import "GUARDS" as Guards
import "LEDGER" as Ledger
import "CREDENTIALS" as ProviderCredentials
import "CANCELLATION" as Credential
TestCase {
    name: "ProviderLoginCancellation"
    QtObject { id: observation; property QtObject request: null }
    Component {
        id: ownerFactory
        QtObject {
            property url credentialScriptUrl: "HELPER"
            property var descriptor: DESCRIPTOR
            function shellQuote(value) { return Guards.shellQuote(value); }
            function cancelCredentialRequest(descriptor) { CANCEL_FUNCTION }
            Component.onDestruction: observation.request = cancelCredentialRequest(descriptor)
        }
    }
    function test_disconnect() {
        var factory = Qt.createComponent("Engine.qml");
        if (factory.status === Component.Error && factory.errorString().indexOf("is not installed") >= 0) {
            skip("Plasma executable engine is unavailable");
            return;
        }
        compare(factory.status, Component.Ready, factory.errorString());
        var owner = createTemporaryObject(ownerFactory, this);
        var engine = createTemporaryObject(factory, owner);
        var command = Ledger.withRunNonce(Guards.supervisedShellCommand(COMMAND, 20, 3), 1, "cancel-test");
        engine.connectSource(command);
        wait(1500);
        engine.disconnectSource(command);
        owner.destroy();
        wait(1500);
        tryCompare(observation, "request", null, 8000);
    }
}
'''
        request = os.urandom(16).hex()
        command = shlex.join([*self.arguments(), '--supervised', '--request', request])
        descriptor = dict(kind='credential', action='login', requestID=request,
                          commandPathSignature=str(self.root / 'codexbar'))
        fixture = self.root / 'tst_cancel.qml'
        fixture.write_text(qml.replace('GUARDS', (ROOT / 'contents/ui/Guards.js').as_uri())
                           .replace('LEDGER', (ROOT / 'contents/ui/CommandLedger.js').as_uri())
                           .replace('CREDENTIALS', (ROOT / 'contents/ui/config/ProviderCredentials.js').as_uri())
                           .replace('CANCELLATION', (ROOT / 'contents/ui/credential').as_uri())
                           .replace('HELPER', HELPER.as_uri())
                           .replace('CANCEL_FUNCTION', Surface('providers', ROOT).function_body('cancelCredentialRequest'))
                           .replace('COMMAND', json.dumps(command)).replace('DESCRIPTOR', json.dumps(descriptor)))
        self.root.joinpath('Engine.qml').write_text('''import org.kde.plasma.plasma5support as P5Support
P5Support.DataSource { engine: "executable"; connectedSources: []; interval: 0 }
''')
        result = subprocess.run([os.environ.get('QMLTESTRUNNER', '/usr/lib/qt6/bin/qmltestrunner'),
                                 '-input', str(fixture)],
                                env={**self.env, 'AUTH_MODE': 'hang', 'QT_QPA_PLATFORM': 'offscreen',
                                     'QT_QUICK_BACKEND': 'software'},
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        if 'SKIP' in output or 'module "org.kde.plasma.plasma5support" is not installed' in output:
            if os.environ.get('QML_TEST_REQUIRE_NO_SKIPS') == '1':
                self.fail(output)
            self.skipTest('Plasma executable engine unavailable')
        self.assertEqual(result.returncode, 0, output)
        self.assertTrue(self.root.joinpath('dialog.text').exists(), output)
        self.assert_stopped('cli')
        self.assert_stopped('dialog')

    def test_cancel_before_start_prevents_cli_and_does_not_cancel_new_request(self):
        request = os.urandom(16).hex()
        result = subprocess.run([*self.arguments('cancel-login'), '--request', request],
                                env=self.env, capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout)['status'], 'cancelled')
        self.assertEqual(self.run_helper([PENDING, .2, {'status':'authorized'}],
                                         request=os.urandom(16).hex())['status'], 'ok')
        self.root.joinpath('cli.pid').unlink()
        result = subprocess.run([*self.arguments(), '--request', request], env=self.env,
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout)['status'], 'cancelled')
        self.assertFalse(self.root.joinpath('cli.pid').exists())


if __name__ == '__main__':
    unittest.main()
