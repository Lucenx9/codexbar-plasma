#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
UPDATER="${ROOT_DIR}/scripts/update-widget.sh"
MAKEFILE="${ROOT_DIR}/Makefile"
INSTALL_SCRIPT="${ROOT_DIR}/install.sh"
WORKFLOW="${ROOT_DIR}/.github/workflows/ci.yml"
README="${ROOT_DIR}/README.md"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected updater fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected updater fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

if [[ ! -x "$UPDATER" ]]; then
  echo "scripts/update-widget.sh must exist and be executable" >&2
  exit 1
fi

require_in_file "$UPDATER" "REPO_OWNER=\"Lucenx9\""
require_in_file "$UPDATER" "REPO_NAME=\"codexbar-plasma\""
require_in_file "$UPDATER" "PLUGIN_ID=\"app.codexbar.plasma\""
require_in_file "$UPDATER" "ASSET_NAME=\"codexbar-plasma.plasmoid\""
require_in_file "$UPDATER" "CHECKSUM_NAME=\"\${ASSET_NAME}.sha256\""
require_in_file "$UPDATER" "CURL_CONNECT_TIMEOUT_SECONDS=10"
require_in_file "$UPDATER" "CURL_METADATA_MAX_TIME_SECONDS=30"
require_in_file "$UPDATER" "CURL_CHECKSUM_MAX_TIME_SECONDS=30"
require_in_file "$UPDATER" "CURL_ASSET_MAX_TIME_SECONDS=300"
require_in_file "$UPDATER" "--connect-timeout \"\$CURL_CONNECT_TIMEOUT_SECONDS\""
require_in_file "$UPDATER" "--max-time \"\$CURL_METADATA_MAX_TIME_SECONDS\""
require_in_file "$UPDATER" "--max-time \"\$CURL_ASSET_MAX_TIME_SECONDS\""
require_in_file "$UPDATER" "--max-filesize \"\$MAX_RELEASE_METADATA_BYTES\""
require_in_file "$UPDATER" "--max-filesize \"\$MAX_PACKAGE_BYTES\""
require_in_file "$UPDATER" "--max-redirs \"\$MAX_REDIRECTS\""
require_in_file "$UPDATER" "--proto '=https'"
require_in_file "$UPDATER" "--proto-redir '=https'"

python3 - "$UPDATER" "$ROOT_DIR" <<'PY'
import re
import sys
from pathlib import Path

updater_text = Path(sys.argv[1]).read_text()
root = Path(sys.argv[2])
sys.path.insert(0, str(root / "scripts/lib"))
from qml_surfaces import Surface

# Read the whole plasmoid surface: the update timer and its constants stay
# correct wherever they live once the controller is extracted from main.qml.
main_qml_text = Surface("applet", root).text


def integer_constant(text, name):
    match = re.search(rf"(?:readonly property int )?{name}(?::|=)\s*(\d+)", text)
    if not match:
        raise AssertionError(f"missing integer timeout constant: {name}")
    return int(match.group(1))


metadata_seconds = integer_constant(updater_text, "CURL_METADATA_MAX_TIME_SECONDS")
checksum_seconds = integer_constant(updater_text, "CURL_CHECKSUM_MAX_TIME_SECONDS")
asset_seconds = integer_constant(updater_text, "CURL_ASSET_MAX_TIME_SECONDS")
install_seconds = integer_constant(updater_text, "KPACKAGE_INSTALL_MAX_TIME_SECONDS")
kill_after_seconds = integer_constant(updater_text, "KPACKAGE_INSTALL_KILL_AFTER_SECONDS")
outer_seconds = integer_constant(main_qml_text, "widgetAutoUpdateTimeoutMs") / 1000
minimum_seconds = metadata_seconds + checksum_seconds + asset_seconds + install_seconds + kill_after_seconds
required_outer_seconds = minimum_seconds + 30
if outer_seconds < required_outer_seconds:
    raise AssertionError(
        "widgetAutoUpdateTimeoutMs must cover all sequential updater phases plus 30s headroom: "
        f"{outer_seconds:g}s < {required_outer_seconds}s"
    )
install_timeout = re.search(
    r'(?m)^[ \t]*timeout[ \t]+--kill-after="\$\{KPACKAGE_INSTALL_KILL_AFTER_SECONDS\}s"[ \t]*\\\n'
    r'[ \t]*"\$\{KPACKAGE_INSTALL_MAX_TIME_SECONDS\}s"[ \t]*\\\n'
    r'[ \t]*kpackagetool6\b',
    updater_text,
)
if not install_timeout:
    raise AssertionError("kpackagetool6 installation must have a hard timeout with a force-kill grace")
install_timer = re.search(
    r'updateCommandTimeoutTimer\.interval\s*=\s*autoUpdateEnabled\s*\?\s*widgetAutoUpdateTimeoutMs\s*:\s*widgetUpdateCheckTimeoutMs',
    main_qml_text,
)
if not install_timer:
    raise AssertionError("automatic installs must select widgetAutoUpdateTimeoutMs")
PY
require_in_file "$UPDATER" "https://api.github.com/repos/\${REPO_OWNER}/\${REPO_NAME}/releases/latest"
require_in_file "$UPDATER" "browser_download_url"
require_in_file "$UPDATER" "checksum_url="
require_in_file "$UPDATER" "newer widget releases must be immutable"
require_in_file "$UPDATER" "validate_asset_record \"\$ASSET_NAME\" \"\$expected_asset_url\""
require_in_file "$UPDATER" "release asset does not match the GitHub asset digest"
require_in_file "$UPDATER" "sha256sum --check --strict"
require_in_file "$UPDATER" "release checksum"
require_in_file "$UPDATER" "validate_package_manifest \"\$package_path\" \"\$package_version\""
require_in_file "$UPDATER" "kpackagetool6 -t Plasma/Applet -u"
require_in_file "$UPDATER" "--check"
require_in_file "$UPDATER" "--install"
require_in_file "$UPDATER" "mktemp -d"
require_in_file "$UPDATER" "trap cleanup EXIT"
require_in_file "$UPDATER" "jq -r"
require_in_file "$UPDATER" "curl --fail --location --show-error --silent"
require_in_file "$UPDATER" "version_gt()"
require_in_file "$UPDATER" "emit_status"
require_in_file "$UPDATER" "restart Plasma to apply the update"
reject_in_file "$UPDATER" "schedule_plasmashell_restart"
reject_in_file "$UPDATER" "systemd-run --user"
reject_in_file "$UPDATER" "systemctl --user restart plasma-plasmashell.service"
reject_in_file "$UPDATER" "| sh"
reject_in_file "$UPDATER" "| bash"
reject_in_file "$UPDATER" "eval "
require_in_file "$MAKEFILE" "scripts/update-widget.sh --install"
require_in_file "$MAKEFILE" "docs/codexbar-plasma-overview.png"
require_in_file "$MAKEFILE" "docs/codexbar-plasma-codex.png"
require_in_file "$MAKEFILE" "python3 -m zipfile -c dist/codexbar-plasma.plasmoid"
require_in_file "$MAKEFILE" "sha256sum codexbar-plasma.plasmoid > codexbar-plasma.plasmoid.sha256"
require_in_file "$MAKEFILE" "missing required command: cmake, zip, or python3"
reject_in_file "$MAKEFILE" "cmake -E tar cf dist/codexbar-plasma.plasmoid --format=zip metadata.json contents docs scripts/update-widget.sh"
require_in_surface applet "function missingUpdateScriptJson()"
require_in_surface applet "Widget updater script is missing from the installed package."
require_in_surface applet "if [ -x \" + shellQuote(scriptPath) + \" ]; then \""
require_in_surface applet "printf '%s\\\\n' \" + shellQuote(missingUpdateScriptJson())"
require_in_surface applet "return \"sh -c \" + shellQuote(updateCommand)"
require_in_surface applet "setWidgetUpdateState(i18n(\"Checking for widget updates...\"), \"\", false)"
require_in_surface applet "notifyInstalledUpdate(version)"
require_in_surface applet "Restart Plasma to apply the new widget version."
require_in_surface applet "function handleUpdateCommandTimeout()"
require_in_surface applet "id: updateCommandTimeoutTimer"
require_in_surface applet "updateCommandTimeoutTimer.restart()"
require_in_surface applet "updateCommandTimeoutTimer.stop()"
require_in_surface applet "Widget update operation timed out."
reject_in_surface applet "Widget update check timed out."
# The notified version must persist so the same update is not re-announced on
# every plasmashell restart.
require_in_surface applet "Plasmoid.configuration.lastNotifiedUpdateVersion = memoKey"
require_in_file "${ROOT_DIR}/contents/config/main.xml" "name=\"lastNotifiedUpdateVersion\""
reject_in_surface applet "return \"sh \" + shellQuote(updateScriptPath())"
reject_in_surface applet "return shellQuote(updateScriptPath()) + (installMode ? \" --install\" : \" --check\")"
require_in_surface applet "function checkForWidgetUpdate(forceCheck)"
require_in_surface applet "updateCheckDue(forceCheck)"
require_in_surface applet "checkForWidgetUpdate(true)"
require_in_file "$INSTALL_SCRIPT" "make -C \"\$ROOT_DIR\" package"
require_in_file "$INSTALL_SCRIPT" "\${ROOT_DIR}/dist/codexbar-plasma.plasmoid"
reject_in_file "$INSTALL_SCRIPT" "kpackagetool6 -t Plasma/Applet -u \"\$ROOT_DIR\""
require_in_file "$WORKFLOW" "dist/codexbar-plasma.plasmoid.sha256"
require_in_file "$README" "only immutable GitHub releases"
require_in_file "$README" "curl\`, \`jq\`, \`python3\`, \`sha256sum\`"

update_script_sample="${ROOT_DIR}/scripts/update-widget.sh"
missing_json_sample='{"status":"error","message":"Widget updater script is missing from the installed package."}'
compound_sample="if [ -x '${update_script_sample}' ]; then '${update_script_sample}' --check; else printf '%s\n' '${missing_json_sample}'; fi"
nonce_wrapped_sample="CODEXBAR_PLASMA_RUN=1 sh -c $(printf '%q' "${compound_sample}")"
if ! /bin/sh -n -c "${nonce_wrapped_sample}"; then
  echo "nonce-wrapped updater command must be valid /bin/sh syntax" >&2
  exit 1
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/fakebin"
printf '%s\n' '{"KPlugin":{"Version":"0.1.0"}}' > "$fixture_dir/metadata.json"
mkdir -p "$fixture_dir/package-src"
printf '%s\n' '{"KPackageStructure":"Plasma/Applet","KPlugin":{"Id":"app.codexbar.plasma","Version":"9.9.9"}}' \
  > "$fixture_dir/package-src/metadata.json"
(
  cd "$fixture_dir/package-src"
  python3 -m zipfile -c ../codexbar-plasma.plasmoid metadata.json
)
head -c 1048577 /dev/zero | tr '\0' ' ' > "$fixture_dir/oversized-release.json"
if "$UPDATER" --check \
  --metadata "$fixture_dir/metadata.json" \
  --release-json "$fixture_dir/oversized-release.json" \
  > "$fixture_dir/oversized-release-output.json"; then
  echo "check mode must reject oversized release metadata" >&2
  exit 1
fi
if [[ "$(jq -r '.message' "$fixture_dir/oversized-release-output.json")" != "release metadata exceeds the supported size" ]]; then
  echo "oversized release metadata must emit a bounded structured error" >&2
  exit 1
fi
(
  cd "$fixture_dir"
  sha256sum codexbar-plasma.plasmoid > codexbar-plasma.plasmoid.sha256
)
package_size="$(wc -c < "$fixture_dir/codexbar-plasma.plasmoid")"
checksum_size="$(wc -c < "$fixture_dir/codexbar-plasma.plasmoid.sha256")"
package_digest="sha256:$(sha256sum "$fixture_dir/codexbar-plasma.plasmoid")"
package_digest="${package_digest%% *}"
checksum_digest="sha256:$(sha256sum "$fixture_dir/codexbar-plasma.plasmoid.sha256")"
checksum_digest="${checksum_digest%% *}"
jq -n \
  --arg package_url "https://github.com/Lucenx9/codexbar-plasma/releases/download/v9.9.9/codexbar-plasma.plasmoid" \
  --arg checksum_url "https://github.com/Lucenx9/codexbar-plasma/releases/download/v9.9.9/codexbar-plasma.plasmoid.sha256" \
  --arg package_digest "$package_digest" \
  --arg checksum_digest "$checksum_digest" \
  --argjson package_size "$package_size" \
  --argjson checksum_size "$checksum_size" \
  '{
    tag_name: "v9.9.9",
    draft: false,
    prerelease: false,
    immutable: true,
    assets: [
      {
        name: "codexbar-plasma.plasmoid",
        state: "uploaded",
        size: $package_size,
        digest: $package_digest,
        browser_download_url: $package_url
      },
      {
        name: "codexbar-plasma.plasmoid.sha256",
        state: "uploaded",
        size: $checksum_size,
        digest: $checksum_digest,
        browser_download_url: $checksum_url
      }
    ]
  }' > "$fixture_dir/release.json"

jq '
  .assets |= map(select(.name != "codexbar-plasma.plasmoid.sha256"))
' "$fixture_dir/release.json" > "$fixture_dir/release-without-checksum.json"
if "$UPDATER" --check \
  --metadata "$fixture_dir/metadata.json" \
  --release-json "$fixture_dir/release-without-checksum.json" \
  > "$fixture_dir/missing-checksum-output.json"; then
  echo "check mode must reject a newer release without its checksum asset" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/missing-checksum-output.json")" != "error" ]]; then
  echo "a missing release checksum must emit structured error JSON" >&2
  exit 1
fi

jq '
  .assets[].browser_download_url |= sub("/v9\\.9\\.9/"; "/v8.8.8/")
' "$fixture_dir/release.json" > "$fixture_dir/cross-tag-release.json"
if "$UPDATER" --check \
  --metadata "$fixture_dir/metadata.json" \
  --release-json "$fixture_dir/cross-tag-release.json" \
  > "$fixture_dir/cross-tag-output.json"; then
  echo "check mode must reject assets that do not belong to the advertised tag" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/cross-tag-output.json")" != "error" ]]; then
  echo "cross-tag release assets must emit structured error JSON" >&2
  exit 1
fi

jq '.immutable = false' "$fixture_dir/release.json" > "$fixture_dir/mutable-release.json"
if "$UPDATER" --check \
  --metadata "$fixture_dir/metadata.json" \
  --release-json "$fixture_dir/mutable-release.json" \
  > "$fixture_dir/mutable-release-output.json"; then
  echo "check mode must reject a newer mutable release" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/mutable-release-output.json")" != "error" ]]; then
  echo "a mutable release must emit structured error JSON" >&2
  exit 1
fi

printf '%s\n' '{"KPlugin":{"Version":"0.2.20"}}' > "$fixture_dir/legacy-current-metadata.json"
jq '.tag_name = "v0.2.20" | .immutable = false | .assets = []' \
  "$fixture_dir/release.json" > "$fixture_dir/legacy-current-release.json"
legacy_current_output="$(
  "$UPDATER" --check \
    --metadata "$fixture_dir/legacy-current-metadata.json" \
    --release-json "$fixture_dir/legacy-current-release.json"
)"
if ! jq -e '.status == "current" and .localVersion == "0.2.20" and .remoteVersion == "v0.2.20"' \
  >/dev/null <<<"$legacy_current_output"; then
  echo "the current legacy mutable release must be recognized before the immutability gate" >&2
  exit 1
fi

jq '.draft = "false"' "$fixture_dir/release.json" > "$fixture_dir/wrong-type-release.json"
if "$UPDATER" --check \
  --metadata "$fixture_dir/metadata.json" \
  --release-json "$fixture_dir/wrong-type-release.json" \
  > "$fixture_dir/wrong-type-output.json"; then
  echo "check mode must reject release metadata with wrong field types" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/wrong-type-output.json")" != "error" ]]; then
  echo "wrong release metadata types must emit structured error JSON" >&2
  exit 1
fi

jq '.assets += [.assets[0]]' "$fixture_dir/release.json" > "$fixture_dir/duplicate-asset-release.json"
if "$UPDATER" --check \
  --metadata "$fixture_dir/metadata.json" \
  --release-json "$fixture_dir/duplicate-asset-release.json" \
  > "$fixture_dir/duplicate-asset-output.json"; then
  echo "check mode must reject duplicate release assets" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/duplicate-asset-output.json")" != "error" ]]; then
  echo "duplicate release assets must emit structured error JSON" >&2
  exit 1
fi

cat > "$fixture_dir/fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
protocol=""
redirect_protocol=""
maximum_size=""
maximum_redirects=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --output)
    output="$2"
    shift 2
    ;;
  --proto)
    protocol="$2"
    shift 2
    ;;
  --proto-redir)
    redirect_protocol="$2"
    shift 2
    ;;
  --max-filesize)
    maximum_size="$2"
    shift 2
    ;;
  --max-redirs)
    maximum_redirects="$2"
    shift 2
    ;;
  http://*|https://*)
    url="$1"
    shift
    ;;
  *)
    shift
    ;;
  esac
done
[[ "$protocol" == "=https" ]] || exit 3
[[ "$redirect_protocol" == "=https" ]] || exit 3
[[ "$maximum_redirects" == "5" ]] || exit 3
case "$url" in
*.sha256)
  [[ "$maximum_size" == "1024" ]] || exit 3
  cp "${TEST_UPDATE_CHECKSUM_PATH:-$TEST_UPDATE_FIXTURE/codexbar-plasma.plasmoid.sha256}" "$output"
  ;;
*.plasmoid)
  [[ "$maximum_size" == "16777216" ]] || exit 3
  cp "${TEST_UPDATE_PACKAGE_PATH:-$TEST_UPDATE_FIXTURE/codexbar-plasma.plasmoid}" "$output"
  ;;
*) exit 2 ;;
esac
SH

cat > "$fixture_dir/fakebin/timeout" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
shift 2
exec "$@"
SH

cat > "$fixture_dir/fakebin/kpackagetool6" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'Successfully upgraded package.'
printf '%s\n' "$*" > "$TEST_UPDATE_INSTALL_MARKER"
SH
chmod +x "$fixture_dir/fakebin/curl" "$fixture_dir/fakebin/timeout" "$fixture_dir/fakebin/kpackagetool6"

mkdir -p "$fixture_dir/wrong-package-src"
printf '%s\n' '{"KPackageStructure":"Plasma/Applet","KPlugin":{"Id":"app.codexbar.plasma","Version":"8.8.8"}}' \
  > "$fixture_dir/wrong-package-src/metadata.json"
(
  cd "$fixture_dir/wrong-package-src"
  python3 -m zipfile -c ../wrong-version.plasmoid metadata.json
)
wrong_package_hash="$(sha256sum "$fixture_dir/wrong-version.plasmoid")"
wrong_package_hash="${wrong_package_hash%% *}"
printf '%s  %s\n' "$wrong_package_hash" "codexbar-plasma.plasmoid" \
  > "$fixture_dir/wrong-version.plasmoid.sha256"
wrong_package_size="$(wc -c < "$fixture_dir/wrong-version.plasmoid")"
wrong_checksum_size="$(wc -c < "$fixture_dir/wrong-version.plasmoid.sha256")"
wrong_package_digest="sha256:$(sha256sum "$fixture_dir/wrong-version.plasmoid")"
wrong_package_digest="${wrong_package_digest%% *}"
wrong_checksum_digest="sha256:$(sha256sum "$fixture_dir/wrong-version.plasmoid.sha256")"
wrong_checksum_digest="${wrong_checksum_digest%% *}"
jq \
  --arg packageDigest "$wrong_package_digest" \
  --arg checksumDigest "$wrong_checksum_digest" \
  --argjson packageSize "$wrong_package_size" \
  --argjson checksumSize "$wrong_checksum_size" '
    (.assets[] | select(.name == "codexbar-plasma.plasmoid")) |=
      (.size = $packageSize | .digest = $packageDigest)
    | (.assets[] | select(.name == "codexbar-plasma.plasmoid.sha256")) |=
      (.size = $checksumSize | .digest = $checksumDigest)
  ' "$fixture_dir/release.json" > "$fixture_dir/wrong-package-release.json"
if PATH="$fixture_dir/fakebin:$PATH" \
  TEST_UPDATE_FIXTURE="$fixture_dir" \
  TEST_UPDATE_PACKAGE_PATH="$fixture_dir/wrong-version.plasmoid" \
  TEST_UPDATE_CHECKSUM_PATH="$fixture_dir/wrong-version.plasmoid.sha256" \
  TEST_UPDATE_INSTALL_MARKER="$fixture_dir/install.marker" \
    "$UPDATER" --install \
      --metadata "$fixture_dir/metadata.json" \
      --release-json "$fixture_dir/wrong-package-release.json" \
      > "$fixture_dir/wrong-package-output.json"; then
  echo "an asset whose package version differs from the release tag must be rejected" >&2
  exit 1
fi
if [[ -f "$fixture_dir/install.marker" ]]; then
  echo "package manifest validation must happen before kpackagetool6" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/wrong-package-output.json")" != "error" ]]; then
  echo "a mismatched package manifest must emit structured error JSON" >&2
  exit 1
fi

good_output="$(
  PATH="$fixture_dir/fakebin:$PATH" \
  TEST_UPDATE_FIXTURE="$fixture_dir" \
  TEST_UPDATE_INSTALL_MARKER="$fixture_dir/install.marker" \
    "$UPDATER" --install --metadata "$fixture_dir/metadata.json" --release-json "$fixture_dir/release.json"
)"
if ! jq -e '.status == "installed"' >/dev/null <<<"$good_output" \
  || [[ ! -f "$fixture_dir/install.marker" ]]; then
  echo "a release with a valid checksum must be installed" >&2
  exit 1
fi

rm -f "$fixture_dir/install.marker"
jq '
  (.assets[] | select(.name == "codexbar-plasma.plasmoid")).digest =
    "sha256:0000000000000000000000000000000000000000000000000000000000000000"
' "$fixture_dir/release.json" > "$fixture_dir/wrong-api-digest-release.json"
if PATH="$fixture_dir/fakebin:$PATH" \
  TEST_UPDATE_FIXTURE="$fixture_dir" \
  TEST_UPDATE_INSTALL_MARKER="$fixture_dir/install.marker" \
    "$UPDATER" --install \
      --metadata "$fixture_dir/metadata.json" \
      --release-json "$fixture_dir/wrong-api-digest-release.json" \
      > "$fixture_dir/wrong-api-digest-output.json"; then
  echo "a release asset that disagrees with the GitHub digest must be rejected" >&2
  exit 1
fi
if [[ -f "$fixture_dir/install.marker" ]]; then
  echo "GitHub digest verification must happen before kpackagetool6" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/wrong-api-digest-output.json")" != "error" ]]; then
  echo "a mismatched GitHub digest must emit structured error JSON" >&2
  exit 1
fi

printf '%s\n' 'tampered package bytes' > "$fixture_dir/codexbar-plasma.plasmoid"
if PATH="$fixture_dir/fakebin:$PATH" \
  TEST_UPDATE_FIXTURE="$fixture_dir" \
  TEST_UPDATE_INSTALL_MARKER="$fixture_dir/install.marker" \
    "$UPDATER" --install --metadata "$fixture_dir/metadata.json" --release-json "$fixture_dir/release.json" \
    > "$fixture_dir/tampered-output.json"; then
  echo "a release asset with a mismatched checksum must be rejected" >&2
  exit 1
fi
if [[ -f "$fixture_dir/install.marker" ]]; then
  echo "checksum verification must happen before kpackagetool6" >&2
  exit 1
fi
if [[ "$(jq -r '.status' "$fixture_dir/tampered-output.json")" != "error" ]]; then
  echo "checksum mismatch must emit structured error JSON" >&2
  exit 1
fi

echo "Widget updater checks passed."
