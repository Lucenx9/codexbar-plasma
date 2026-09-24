"""Exercise standalone setup with isolated downloads, installs and CLI effects."""
import hashlib
import json
import os
import pty
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/update-widget.sh"
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
        self.fake("id", 'printf "%s\\n" "${TEST_UID:-1000}"')
        self.fake("systemctl", 'echo restart >> "$FIXTURE/calls"')
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
print(json.dumps({"status": os.environ.get("CLI_STATUS", "ready")}))
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

    def run_setup(self, *args, input_answers=None, **env):
        # Copy only the script: setup must not depend on checkout metadata/files.
        standalone = self.root / "downloaded.sh"
        shutil.copyfile(SCRIPT, standalone)
        command = [str(self.bin / "bash"), str(standalone), "--setup", *args]
        if input_answers is None:
            return subprocess.run(command, env={**self.env, **env}, text=True,
                                  input="", capture_output=True, timeout=30)
        master, slave = pty.openpty()
        try:
            os.write(master, input_answers.encode())
            return subprocess.run(command, env={**self.env, **env}, text=True,
                                  stdin=slave, capture_output=True, timeout=30)
        finally:
            os.close(master)
            os.close(slave)

    def calls(self):
        path = self.root / "calls"
        return path.read_text() if path.exists() else ""

    def test_fresh_install_and_rerun(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(" -i ", self.calls())
        self.assertIn("widget installed", result.stderr)
        self.assertNotIn("restart Plasma", result.stderr)
        self.assertIn("Install and select managed CLI", result.stdout)
        self.assertNotIn("restart", self.calls())
        before = self.calls()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget is current", result.stderr)
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
        # Run the documented one-liner verbatim, with curl serving this checkout's
        # installer. Piping the script into Bash made stdin the script itself, so
        # a user at a real terminal never saw the CLI or restart prompts.
        command = re.search(r"^\(installer=\$\(curl .*\)$", README.read_text(), re.M).group(0)
        shutil.copyfile(SCRIPT, self.root / "update-widget.sh")
        master, slave = pty.openpty()
        try:
            os.write(master, b"y\n")
            result = subprocess.run([str(self.bin / "bash"), "-c", command], env=self.env, text=True,
                                    stdin=slave, capture_output=True, timeout=30)
        finally:
            os.close(master)
            os.close(slave)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Install or reuse the private official CodexBar CLI?", result.stderr)
        self.assertIn("managed-cli", self.calls())
        # Without a terminal the same command stays non-interactive.
        (self.root / "calls").write_text("")
        result = subprocess.run([str(self.bin / "bash"), "-c", command], env=self.env, text=True,
                                input="y\n", capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("managed-cli", self.calls())

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
        self.assertIn("missing required command: kpackagetool6", result.stderr)
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
        result = self.run_setup("--with-cli", CLI_STATUS="unverified")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Widget is installed, but CLI setup failed", result.stderr)

    def test_refuses_root_before_download(self):
        result = self.run_setup(TEST_UID="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without sudo", result.stderr)
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
  printf '%s' '{"KPlugin":{"Version":"9.9.9"}}' > "$winner/metadata.json"
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
