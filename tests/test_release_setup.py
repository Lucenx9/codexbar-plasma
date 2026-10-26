"""Exercise standalone setup with isolated downloads, installs and CLI effects."""
import hashlib
import fcntl
import json
import os
import pty
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import tempfile
import termios
import time
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/update-widget.sh"
BOOTSTRAP = ROOT / "setup.sh"
README = ROOT / "README.md"


class ReleaseSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # An explicit PATH prevents a developer's real CLI from affecting tests.
        for tool in ("bash", "dirname", "uname", "jq", "sort", "head", "tail", "grep", "wc",
                     "python3", "sha256sum", "timeout", "mktemp", "rm", "flock", "mkdir"):
            (self.bin / tool).symlink_to(shutil.which(tool))
        self.env = {"PATH": str(self.bin), "HOME": str(self.root / "home"),
                    "XDG_DATA_HOME": str(self.root / "data with spaces"), "FIXTURE": str(self.root)}
        self.installed = Path(self.env["XDG_DATA_HOME"]) / "plasma/plasmoids/app.codexbar.plasma"
        shutil.copyfile(SCRIPT, self.root / "update-widget.sh")
        shutil.copyfile(BOOTSTRAP, self.root / "setup.sh")
        self.fake("id", 'printf "%s\\n" "${TEST_UID:-1000}"')
        self.fake("systemctl", 'echo restart >> "$FIXTURE/calls"')
        self.fake("curl", '''
printf '%s\\n' "$@" >> "$FIXTURE/downloads"
output=""
for arg in "$@"; do
  [[ "$arg" == https://* ]] && url="$arg"
done
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift; fi
  shift
done
case "$url" in
  */latest) file=release.json ;;
  */main/setup.sh) file=setup.sh ;;
  */main/scripts/update-widget.sh) file=update-widget.sh ;;
  *.sha256) file=codexbar-plasma.plasmoid.sha256 ;;
  *.plasmoid) file=codexbar-plasma.plasmoid ;;
  *) exit 1 ;;
esac
python3 - "$FIXTURE/$file" "$output" <<'INNER'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
if sys.argv[2]:
    pathlib.Path(sys.argv[2]).write_bytes(raw)
else:
    sys.stdout.buffer.write(raw)
INNER
''')
        self.fake("kpackagetool6", '''
echo "$*" >> "$FIXTURE/calls"
[[ "${FAIL_INSTALL:-}" != 1 ]] || exit 1
python3 - "$4" <<'INNER'
import os, pathlib, sys, zipfile
root = pathlib.Path(os.environ["XDG_DATA_HOME"]) / "plasma/plasmoids/app.codexbar.plasma"
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(root)
INNER
''')
        self.package()

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def package(self, version="9.9.9", plugin_id="app.codexbar.plasma"):
        package = self.root / "codexbar-plasma.plasmoid"
        with zipfile.ZipFile(package, "w") as archive:
            archive.writestr("metadata.json", json.dumps({"KPackageStructure": "Plasma/Applet",
                              "KPlugin": {"Id": plugin_id, "Version": version}}))
            archive.writestr("scripts/manage-cli.py", '''import json, os, pathlib
with (pathlib.Path(os.environ["FIXTURE"]) / "calls").open("a") as stream:
    stream.write("managed-cli\\n")
print(os.environ.get("CLI_OUTPUT", json.dumps({"status": os.environ.get("CLI_STATUS", "ready")})))
''')
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        checksum = self.root / (package.name + ".sha256")
        checksum.write_text(f"{digest}  {package.name}\n")
        self.release = {"tag_name": "v9.9.9", "draft": False, "prerelease": False,
                        "immutable": True, "assets": []}
        for path in (package, checksum):
            self.release["assets"].append({"name": path.name, "state": "uploaded",
                "size": path.stat().st_size, "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest(),
                "browser_download_url": "https://github.com/Lucenx9/codexbar-plasma/releases/download/v9.9.9/" + path.name})
        self.save_release()

    def save_release(self):
        (self.root / "release.json").write_text(json.dumps(self.release))

    def run_setup(self, *args, input_answers=None, unset=(), **env):
        # Copy only the script: setup must not depend on checkout metadata/files.
        standalone = self.root / "downloaded.sh"
        shutil.copyfile(SCRIPT, standalone)
        command = [str(self.bin / "bash"), str(standalone), "--setup", *args]
        run_env = {key: value for key, value in {**self.env, **env}.items()
                   if key not in unset}
        if input_answers is None:
            return subprocess.run(command, env=run_env, text=True,
                                  input="", capture_output=True, timeout=30)
        master, slave = pty.openpty()
        try:
            os.write(master, input_answers.encode())
            return subprocess.run(command, env=run_env, text=True,
                                  stdin=slave, capture_output=True, timeout=30)
        finally:
            os.close(master)
            os.close(slave)

    def calls(self):
        path = self.root / "calls"
        return path.read_text() if path.exists() else ""

    def run_bootstrap(self, *args):
        return subprocess.run([str(self.bin / "bash"), "-s", "--", *args],
                              env=self.env, input=BOOTSTRAP.read_text(), text=True,
                              start_new_session=True, capture_output=True, timeout=30)

    def run_readme_unattended(self):
        command = re.search(r"For unattended or scripted setup.*?```sh\n(.*?)\n```",
                            README.read_text(), re.S).group(1)
        return subprocess.run([shutil.which("sh"), "-c", command], env=self.env,
                              text=True, input="", start_new_session=True,
                              capture_output=True, timeout=30)

    def run_readme(self, *args, input_answers=None, shell=None):
        command = re.search(r"### Quick install from a terminal.*?```sh\n(.*?)\n```",
                            README.read_text(), re.S).group(1)
        if args:
            # Keep args on the piped bootstrap Bash, including inside a pipefail wrapper.
            if "| bash'" in command:
                command = command.replace(
                    "| bash'", "| bash -s -- " + shlex.join(args) + "'", 1)
            else:
                command += " -s -- " + shlex.join(args)
        invocation = [shell or str(self.bin / "bash"), "-c", command]
        if input_answers is None:
            return subprocess.run(invocation, env=self.env, text=True, input="",
                                  start_new_session=True, capture_output=True, timeout=30)
        master, slave = pty.openpty()

        def acquire_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        try:
            os.write(master, input_answers.encode())
            return subprocess.run(invocation, env=self.env, text=True, stdin=slave,
                                  preexec_fn=acquire_terminal, capture_output=True, timeout=30)
        finally:
            os.close(master)
            os.close(slave)

    def test_fresh_install_and_rerun(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(" -i ", self.calls())
        self.assertIn("widget installed", result.stderr)
        self.assertIn("Installed widget version: 9.9.9", result.stderr)
        stages = ["Checking the latest stable widget release",
                  "Latest stable widget release: v9.9.9",
                  "Downloading widget v9.9.9", "Verifying download integrity",
                  "Waiting for the widget installation lock", "Installing widget v9.9.9",
                  "widget installed"]
        positions = [result.stderr.index(stage) for stage in stages]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn("restart Plasma", result.stderr)
        self.assertIn("Install and select managed CLI", result.stdout)
        self.assertNotIn("restart", self.calls())
        before = self.calls()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget is current", result.stderr)
        self.assertIn("Installed widget version: 9.9.9", result.stderr)
        self.assertNotIn("Downloading widget", result.stderr)
        self.assertNotIn("Installing widget", result.stderr)
        self.assertEqual(before, self.calls())

    def test_stdin_bootstrap_runs_setup_without_checkout_path(self):
        result = subprocess.run([str(self.bin / "bash"), "-s", "--", "--setup", "--no-input"],
                                env=self.env, input=SCRIPT.read_text(), text=True,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("BASH_SOURCE", result.stderr)
        self.assertIn("widget installed", result.stderr)
        self.assertIn(" -i ", self.calls())

    def test_readme_command_prompts_from_the_terminal(self):
        # The exact README pipeline must recover its controlling terminal even
        # though the consumer Bash reads the bootstrap from a pipe.
        result = self.run_readme(input_answers="y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Install or reuse the private official CodexBar CLI?", result.stderr)
        self.assertIn("managed-cli", self.calls())
        # Without a terminal the same command stays non-interactive.
        (self.root / "calls").write_text("")
        result = self.run_readme()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("managed-cli", self.calls())
        self.assertNotIn("/dev/tty", result.stderr)

    def test_readme_pipeline_runs_from_sh(self):
        result = self.run_readme(shell=shutil.which("sh"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget installed", result.stderr)
        self.assertNotIn("managed-cli", self.calls())

    def test_readme_unattended_command_runs_from_sh(self):
        result = self.run_readme_unattended()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget installed", result.stderr)
        self.assertNotIn("managed-cli", self.calls())
        self.assertNotIn("[y/N]", result.stderr)

    def test_unattended_command_propagates_empty_download_failure(self):
        for status in (6, 22, 28, 63):
            with self.subTest(status=status):
                self.fake("curl", f'printf "%s\\n" "curl: ({status}) synthetic download failure" >&2\nexit {status}')
                result = self.run_readme_unattended()
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertIn("synthetic download failure", result.stderr)
                self.assertEqual(self.calls(), "")
                self.assertFalse(self.installed.exists())

    def test_readme_bootstrap_download_is_bounded(self):
        result = self.run_readme()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (self.root / "downloads").read_text().splitlines()
        bootstrap_url = "https://raw.githubusercontent.com/Lucenx9/codexbar-plasma/main/setup.sh"
        first_request = arguments[:arguments.index(bootstrap_url)]
        for flag, value in (("-m", "30"), ("--max-filesize", "65536")):
            self.assertEqual(first_request[first_request.index(flag) + 1], value)

    def test_unattended_command_propagates_installer_failure(self):
        (self.root / "update-widget.sh").write_text("exit 7\n# codexbar-plasma-updater-end\n")
        result = self.run_readme_unattended()
        self.assertEqual(result.returncode, 7)

    def test_headless_bootstrap_in_posix_mode_skips_prompts(self):
        self.env["POSIXLY_CORRECT"] = "1"
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget installed", result.stderr)
        self.assertNotIn("managed-cli", self.calls())
        self.assertNotIn("/dev/tty", result.stderr)

    def test_downloaded_bootstrap_keeps_terminal_stdin(self):
        master, slave = pty.openpty()
        try:
            os.write(master, b"y\n")
            result = subprocess.run([str(self.bin / "bash"), str(self.root / "setup.sh")],
                                    env=self.env, text=True, stdin=slave,
                                    start_new_session=True, capture_output=True, timeout=30)
        finally:
            os.close(master)
            os.close(slave)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("managed-cli", self.calls())

    def test_readme_pipeline_keeps_restart_consent(self):
        self.installed.mkdir(parents=True)
        metadata = self.installed / "metadata.json"
        for answer, restart in (("\n", False), ("y\n", True)):
            with self.subTest(answer=answer):
                metadata.write_text(json.dumps({"KPackageStructure": "Plasma/Applet",
                    "KPlugin": {"Id": "app.codexbar.plasma", "Version": "1.0.0"}}))
                self.fake("codexbar", "exit 0")
                (self.root / "calls").write_text("")
                result = self.run_readme(input_answers=answer)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Restart Plasma panels and desktop", result.stderr)
                self.assertEqual("restart" in self.calls(), restart)

    def test_bootstrap_no_input_ignores_available_terminal(self):
        result = self.run_readme("--no-input", input_answers="y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("[y/N]", result.stderr)
        self.assertNotIn("managed-cli", self.calls())
        self.assertNotIn("restart", self.calls())

    def test_bootstrap_with_cli_is_explicit_without_a_terminal(self):
        result = self.run_bootstrap("--no-input", "--with-cli")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("managed-cli", self.calls())
        self.assertNotIn("[y/N]", result.stderr)

    def test_bootstrap_rejects_unknown_options_before_download(self):
        for option in ("--check", "--install", "--metadata", "--release-json"):
            with self.subTest(option=option):
                result = self.run_bootstrap(option)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Unsupported setup option", result.stderr)
                self.assertFalse((self.root / "downloads").exists())
                self.assertEqual(self.calls(), "")

    def test_bootstrap_help_does_not_download(self):
        for option in ("-h", "--help"):
            with self.subTest(option=option):
                result = self.run_bootstrap(option)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("--no-input", result.stdout)
                self.assertFalse((self.root / "downloads").exists())

    def test_bootstrap_does_not_execute_a_failed_download(self):
        self.fake("curl", '''
printf '%s\\n' 'echo executed >> "$FIXTURE/calls"' '# codexbar-plasma-updater-end'
exit 22
''')
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not download the installer", result.stderr)
        self.assertEqual(self.calls(), "")

    def test_bootstrap_rejects_empty_and_incomplete_downloads(self):
        for body in ("", 'echo executed >> "$FIXTURE/calls"\n'):
            with self.subTest(body=body):
                (self.root / "update-widget.sh").write_text(body)
                result = self.run_bootstrap()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Installer download is incomplete", result.stderr)
                self.assertEqual(self.calls(), "")

    def test_truncated_bootstrap_does_not_start_downloads(self):
        truncated = BOOTSTRAP.read_text().rsplit("}", 1)[0]
        result = subprocess.run([str(self.bin / "bash"), "-s"], env=self.env,
                                input=truncated, text=True, start_new_session=True,
                                capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "downloads").exists())
        self.assertEqual(self.calls(), "")

    def test_bootstrap_preserves_installer_exit_status(self):
        (self.root / "update-widget.sh").write_text("exit 7\n# codexbar-plasma-updater-end\n")
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 7)

    def test_bootstrap_fetch_is_bounded_and_https_only(self):
        result = self.run_bootstrap("--no-input")
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (self.root / "downloads").read_text().splitlines()
        for flag, value in (("--connect-timeout", "10"), ("--max-time", "30"),
                            ("--max-filesize", "65536"), ("--max-redirs", "5"),
                            ("--proto", "=https"), ("--proto-redir", "=https")):
            self.assertEqual(arguments[arguments.index(flag) + 1], value)

    def test_readme_pipeline_keeps_curl_failure_visible(self):
        self.fake("curl", 'printf "%s\\n" "curl: (22) synthetic download failure" >&2\nexit 22')
        result = self.run_readme()
        self.assertEqual(result.returncode, 22, result.stderr)
        self.assertIn("synthetic download failure", result.stderr)
        self.assertEqual(self.calls(), "")
        self.assertFalse(self.installed.exists())

    def test_readme_scripted_fetch_is_bounded_and_https_only(self):
        result = self.run_readme_unattended()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (self.root / "downloads").read_text().splitlines()
        # First fetch is the bootstrap; later lines are the updater fetch.
        setup_url = "https://raw.githubusercontent.com/Lucenx9/codexbar-plasma/main/setup.sh"
        end = arguments.index(setup_url) + 1
        bootstrap_args = arguments[:end]
        for flag, value in (("--connect-timeout", "10"), ("--max-time", "30"),
                            ("--max-filesize", "65536"), ("--max-redirs", "5"),
                            ("--proto", "=https"), ("--proto-redir", "=https")):
            self.assertEqual(bootstrap_args[bootstrap_args.index(flag) + 1], value)

    def test_upgrade_never_restarts_without_consent(self):
        self.installed.mkdir(parents=True)
        (self.installed / "metadata.json").write_text(json.dumps({
            "KPackageStructure": "Plasma/Applet",
            "KPlugin": {"Id": "app.codexbar.plasma", "Version": "1.0.0"}}))
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(" -u ", self.calls())
        self.assertNotIn(" -i ", self.calls())
        self.assertNotIn("restart", self.calls())
        self.assertIn("Log out and back in", result.stdout)

    def test_restart_requires_explicit_interactive_consent(self):
        self.fake("codexbar", "exit 0")
        for answer, restart in (("\n", False), ("y\n", True), ("n\n", False)):
            with self.subTest(answer=answer):
                self.installed.mkdir(parents=True, exist_ok=True)
                (self.installed / "metadata.json").write_text(json.dumps({
                    "KPackageStructure": "Plasma/Applet",
                    "KPlugin": {"Id": "app.codexbar.plasma", "Version": "1.0.0"}}))
                (self.root / "calls").write_text("")
                result = self.run_setup(input_answers=answer)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("restart" in self.calls(), restart)

    def test_cli_prompt_and_no_input(self):
        result = self.run_setup(input_answers="y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("managed-cli", self.calls())
        (self.root / "calls").write_text("")
        result = self.run_setup("--no-input", input_answers="y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), "")

    def test_missing_dependency_stops_before_install(self):
        (self.bin / "kpackagetool6").unlink()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing required commands: kpackagetool6", result.stderr)
        self.assertEqual(self.calls(), "")

    def test_all_missing_dependencies_are_reported_before_download(self):
        for tool in ("dirname", "uname", "id", "jq", "kpackagetool6", "python3"):
            (self.bin / tool).unlink()
        self.fake("curl", 'echo download >> "$FIXTURE/calls"; exit 99')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing required commands: uname id jq kpackagetool6 python3", result.stderr)
        self.assertIn("distribution packages", result.stderr)
        self.assertNotIn("command not found", result.stderr)
        self.assertNotIn("Setup requires Linux", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.calls(), "")
        self.assertFalse(Path(self.env["XDG_DATA_HOME"]).exists())

    def test_standalone_setup_does_not_need_dirname(self):
        (self.bin / "dirname").unlink()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget installed", result.stderr)
        self.assertNotIn("command not found", result.stderr)

    def test_update_modes_keep_json_without_setup_progress(self):
        metadata = self.root / "local.json"
        metadata.write_text(json.dumps({"KPlugin": {"Version": "0.0.0"}}))
        for mode, expected in (("--check", "available"), ("--install", "installed")):
            with self.subTest(mode=mode):
                result = subprocess.run([str(self.bin / "bash"), str(SCRIPT), mode,
                                         "--metadata", str(metadata)], env=self.env,
                                        input="", text=True, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["status"], expected)
                self.assertEqual(result.stderr, "")

    def test_checkout_update_compares_the_installed_package(self):
        metadata = self.root / "checkout.json"
        self.installed.mkdir(parents=True)
        for checkout, installed, expected in (("0.1.0", "10.0.0", "current"),
                                               ("0.1.0", "9.9.9", "current"),
                                               ("10.0.0", "1.0.0", "installed")):
            with self.subTest(checkout=checkout, installed=installed):
                metadata.write_text(json.dumps({"KPlugin": {"Version": checkout}}))
                (self.installed / "metadata.json").write_text(json.dumps({
                    "KPackageStructure": "Plasma/Applet",
                    "KPlugin": {"Id": "app.codexbar.plasma", "Version": installed}}))
                (self.root / "calls").write_text("")
                result = subprocess.run([str(self.bin / "bash"), str(SCRIPT), "--install",
                                         "--metadata", str(metadata)], env=self.env,
                                        text=True, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["status"], expected)
                self.assertEqual(json.loads((self.installed / "metadata.json").read_text())
                                 ["KPlugin"]["Version"], installed if expected == "current" else "9.9.9")
                if expected == "current":
                    self.assertEqual(self.calls(), "")

    def test_checkout_update_waits_for_an_install_before_reading_metadata(self):
        metadata = self.root / "checkout.json"
        metadata.write_text(json.dumps({"KPlugin": {"Version": "0.1.0"}}))
        self.installed.mkdir(parents=True)
        installed_metadata = self.installed / "metadata.json"
        installed_metadata.write_text("partial installation")
        lock_dir = Path(self.env["XDG_DATA_HOME"]) / "codexbar-plasma"
        lock_dir.mkdir()
        waiting = self.root / "lock-waiting"
        (self.bin / "flock").unlink()
        self.fake("flock", 'echo waiting > "$FIXTURE/lock-waiting"\nexec '
                  + shlex.quote(shutil.which("flock")) + ' "$@"')
        curl = self.bin / "curl"
        curl.write_text(curl.read_text() + '''
python3 - <<'INNER'
import fcntl, os, pathlib
path = pathlib.Path(os.environ["XDG_DATA_HOME"]) / "codexbar-plasma/widget-update.lock"
with path.open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
INNER
''')
        with (lock_dir / "widget-update.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen([str(self.bin / "bash"), str(SCRIPT), "--install",
                                        "--metadata", str(metadata)], env=self.env,
                                       text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not waiting.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                waited = waiting.exists()
                installed_metadata.write_text(json.dumps({"KPackageStructure": "Plasma/Applet",
                    "KPlugin": {"Id": "app.codexbar.plasma", "Version": "9.9.9"}}))
                fcntl.flock(lock, fcntl.LOCK_UN)
                stdout, stderr = process.communicate(timeout=10)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
        self.assertTrue(waited, stderr)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(json.loads(stdout)["status"], "current")
        self.assertEqual(self.calls(), "")

    def test_checkout_update_rechecks_the_installed_package_after_download(self):
        metadata = self.root / "checkout.json"
        metadata.write_text(json.dumps({"KPlugin": {"Version": "0.1.0"}}))
        self.installed.mkdir(parents=True)
        (self.installed / "metadata.json").write_text(json.dumps({
            "KPackageStructure": "Plasma/Applet",
            "KPlugin": {"Id": "app.codexbar.plasma", "Version": "1.0.0"}}))
        curl = self.bin / "curl"
        curl.write_text(curl.read_text() + '''
if [[ "$url" == *.plasmoid ]]; then
  python3 - <<'INNER'
import json, os, pathlib
metadata = pathlib.Path(os.environ["XDG_DATA_HOME"]) / "plasma/plasmoids/app.codexbar.plasma/metadata.json"
value = json.loads(metadata.read_text())
value["KPlugin"]["Version"] = "10.0.0"
metadata.write_text(json.dumps(value))
INNER
fi
''')
        result = subprocess.run([str(self.bin / "bash"), str(SCRIPT), "--install",
                                 "--metadata", str(metadata)], env=self.env,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "current")
        self.assertEqual(json.loads(result.stdout)["localVersion"], "10.0.0")
        self.assertEqual(self.calls(), "")

    def test_update_mode_missing_jq_still_returns_json(self):
        (self.bin / "jq").unlink()
        result = subprocess.run([str(self.bin / "bash"), str(SCRIPT), "--check"],
                                env=self.env, input="", text=True,
                                capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["errorCode"], "missing_tool")
        self.assertEqual(result.stderr, "")

    def test_update_install_missing_dependency_still_returns_json(self):
        (self.bin / "kpackagetool6").unlink()
        result = subprocess.run([str(self.bin / "bash"), str(SCRIPT), "--install"],
                                env=self.env, input="", text=True,
                                capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        reply = json.loads(result.stdout)
        self.assertEqual(reply["errorCode"], "missing_tool")
        self.assertEqual(reply["errorDetail"], "kpackagetool6")
        self.assertEqual(result.stderr, "")

    def test_invalid_release_version_is_not_printed_in_progress(self):
        self.release["tag_name"] = "v9.9.9\x1b[31m"
        self.save_release()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("\x1b", result.stderr + result.stdout)
        self.assertNotIn("Latest stable widget release:", result.stderr)
        self.assertEqual(self.calls(), "")

    def test_invalid_existing_metadata_is_preserved(self):
        self.installed.mkdir(parents=True)
        metadata = self.installed / "metadata.json"
        metadata.write_text("invalid")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(metadata.read_text(), "invalid")
        self.assertEqual(self.calls(), "")

    def test_wrong_existing_applet_identity_never_runs_its_cli_helper(self):
        for metadata in (
            {"KPackageStructure": "Plasma/Applet",
             "KPlugin": {"Id": "another.applet", "Version": "9.9.9"}},
            {"KPackageStructure": "Other/Package",
             "KPlugin": {"Id": "app.codexbar.plasma", "Version": "9.9.9"}},
        ):
            with self.subTest(metadata=metadata):
                self.installed.mkdir(parents=True, exist_ok=True)
                (self.installed / "metadata.json").write_text(json.dumps(metadata))
                result = self.run_setup("--with-cli")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("wrong applet identity", result.stderr)
                self.assertEqual(self.calls(), "")

    def test_install_failure_does_not_fall_back_or_install_cli(self):
        result = self.run_setup("--with-cli", FAIL_INSTALL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls().splitlines()), 1)

    def test_failed_upgrade_restores_the_entire_previous_package(self):
        for failure, installed_helper in (("exit 1", False), ("exit 124", False),
                                          ("exit 0", False), ("exit 1", True)):
            with self.subTest(failure=failure, installed_helper=installed_helper):
                self.installed.mkdir(parents=True, exist_ok=True)
                metadata = self.installed / "metadata.json"
                metadata.write_text(json.dumps({"KPackageStructure": "Plasma/Applet",
                    "KPlugin": {"Id": "app.codexbar.plasma", "Version": "1.0.0"}}))
                previous = metadata.read_bytes()
                script = self.installed / "scripts/update-widget.sh"
                script.parent.mkdir(exist_ok=True)
                script.write_text("#!/bin/sh\n# previous updater\n")
                if installed_helper:
                    shutil.copyfile(SCRIPT, script)
                script.chmod(0o755)
                previous_script = script.read_bytes()
                self.fake("kpackagetool6", '''
echo "$*" >> "$FIXTURE/calls"
python3 - <<'INNER'
import os, pathlib, shutil
root = pathlib.Path(os.environ["XDG_DATA_HOME"]) / "plasma/plasmoids/app.codexbar.plasma"
shutil.rmtree(root)
root.mkdir()
(root / "partial").write_text("incomplete update")
INNER
''' + failure)
                if installed_helper:
                    result = subprocess.run([str(self.bin / "bash"), str(script), "--install",
                                             "--release-json", str(self.root / "release.json")],
                                            env=self.env, text=True, capture_output=True, timeout=30)
                else:
                    result = self.run_setup("--with-cli")
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertTrue(metadata.is_file(), "Failed upgrade deleted the old widget metadata")
                self.assertEqual(metadata.read_bytes(), previous)
                self.assertEqual(script.read_bytes(), previous_script)
                self.assertEqual(script.stat().st_mode & 0o777, 0o755)
                self.assertFalse((self.installed / "partial").exists())
                self.assertNotIn("managed-cli", self.calls())
                self.assertEqual(list(self.installed.parent.glob(".codexbar-update-*")), [])

    def test_failed_first_install_removes_partial_package_and_can_retry(self):
        original_tool = (self.bin / "kpackagetool6").read_text()
        self.fake("kpackagetool6", '''
python3 - <<'INNER'
import os, pathlib
root = pathlib.Path(os.environ["XDG_DATA_HOME"]) / "plasma/plasmoids/app.codexbar.plasma"
root.mkdir(parents=True)
(root / "partial").write_text("incomplete installation")
INNER
exit 1
''')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.installed.exists())
        (self.bin / "kpackagetool6").write_text(original_tool)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-i", self.calls())

    def test_existing_cli_is_preserved(self):
        self.fake("codexbar", 'echo "unexpected CLI invocation" >> "$FIXTURE/calls"')
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Found codexbar on PATH", result.stdout)
        self.assertNotIn("CLI invocation", self.calls())
        self.assertNotIn("managed-cli", self.calls())

    def test_explicit_private_cli_and_failure(self):
        result = self.run_setup("--with-cli")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("managed-cli", self.calls())
        self.assertIn("Use managed CLI, then Apply", result.stdout)
        self.assertIn("Private CLI is ready. Select it in widget settings", result.stdout)
        self.assertGreater(result.stdout.index("Add Widgets"), result.stdout.index("Private CLI is ready"))
        result = self.run_setup("--with-cli", CLI_STATUS="unverified")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Widget is installed, but CLI setup failed", result.stderr)

    def test_malformed_cli_reply_preserves_widget_and_reports_recovery(self):
        for reply in ("garbage", "null", '"ready"', '{"status": []}', '{}'):
            with self.subTest(reply=reply):
                result = self.run_setup("--with-cli", CLI_OUTPUT=reply)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Widget is installed, but CLI setup failed", result.stderr)
                self.assertIn("Retry in General -> Managed CLI", result.stderr)
                self.assertNotIn("jq:", result.stderr)
                self.assertEqual(json.loads((self.installed / "metadata.json").read_text())
                                 ["KPlugin"]["Version"], "9.9.9")

    def test_refuses_root_before_download(self):
        result = self.run_setup(TEST_UID="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without sudo", result.stderr)
        self.assertEqual(self.calls(), "")

    def test_setup_without_home_reports_the_data_directory(self):
        cases = ({"unset": ("HOME", "XDG_DATA_HOME")},
                 {"unset": ("HOME",), "XDG_DATA_HOME": "relative"})
        for extra in cases:
            with self.subTest(extra=extra):
                result = self.run_setup("--no-input", **extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Setup requires HOME or an absolute XDG_DATA_HOME",
                              result.stderr)
                self.assertNotIn("unbound variable", result.stderr)
                self.assertEqual(self.calls(), "")

    def test_concurrent_fresh_install_reports_current_after_lock(self):
        # Another setup run installs the release after this run chose
        # fresh-install mode but before it reaches the post-lock recheck.
        # The recheck must read the installed metadata, not this run's
        # synthetic 0.0.0 stub, or the second install runs redundantly.
        self.fake("curl", '''
output=""
for arg in "$@"; do
  [[ "$arg" == https://* ]] && url="$arg"
done
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift; fi
  shift
done
case "$url" in
  */latest) file=release.json ;;
  */main/scripts/update-widget.sh) file=update-widget.sh ;;
  *.sha256) file=codexbar-plasma.plasmoid.sha256 ;;
  *.plasmoid) file=codexbar-plasma.plasmoid ;;
  *) exit 1 ;;
esac
if [[ "$file" == codexbar-plasma.plasmoid ]]; then
  winner="$XDG_DATA_HOME/plasma/plasmoids/app.codexbar.plasma"
  mkdir -p "$winner"
  printf '%s' '{"KPackageStructure":"Plasma/Applet","KPlugin":{"Id":"app.codexbar.plasma","Version":"9.9.9"}}' > "$winner/metadata.json"
fi
python3 - "$FIXTURE/$file" "$output" <<'INNER'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
if sys.argv[2]:
    pathlib.Path(sys.argv[2]).write_bytes(raw)
else:
    sys.stdout.buffer.write(raw)
INNER
''')
        result = self.run_setup("--no-input")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget is current", result.stderr)
        self.assertEqual(self.calls(), "")

    def test_untrusted_packages_never_install(self):
        for fault in ("mutable", "digest", "id", "version", "tag"):
            with self.subTest(fault=fault):
                self.package(plugin_id="wrong" if fault == "id" else "app.codexbar.plasma",
                             version="0.0.1" if fault == "version" else "9.9.9")
                if fault == "mutable":
                    self.release["immutable"] = False
                if fault == "digest":
                    self.release["assets"][0]["digest"] = "sha256:" + "0" * 64
                if fault == "tag":
                    self.release["assets"][0]["browser_download_url"] = self.release["assets"][0]["browser_download_url"].replace("v9.9.9", "v8.8.8")
                self.save_release()
                result = self.run_setup("--with-cli")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), "")


if __name__ == "__main__":
    unittest.main()
