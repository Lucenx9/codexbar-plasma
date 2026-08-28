#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Lucenx9"
REPO_NAME="codexbar-plasma"
PLUGIN_ID="app.codexbar.plasma"
ASSET_NAME="codexbar-plasma.plasmoid"
CHECKSUM_NAME="${ASSET_NAME}.sha256"
API_VERSION="2026-03-10"
CURL_CONNECT_TIMEOUT_SECONDS=10
CURL_METADATA_MAX_TIME_SECONDS=30
CURL_CHECKSUM_MAX_TIME_SECONDS=30
CURL_ASSET_MAX_TIME_SECONDS=300
KPACKAGE_INSTALL_MAX_TIME_SECONDS=120
KPACKAGE_INSTALL_KILL_AFTER_SECONDS=10
MAX_RELEASE_ASSETS=64
MAX_RELEASE_METADATA_BYTES=1048576
MAX_CHECKSUM_BYTES=1024
MAX_PACKAGE_BYTES=16777216
MAX_PACKAGE_ENTRIES=2048
MAX_PACKAGE_EXPANDED_BYTES=67108864
MAX_PACKAGE_METADATA_BYTES=65536
MAX_REDIRECTS=5
MODE="check"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_PATH="${ROOT_DIR}/metadata.json"
RELEASE_JSON=""
TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  printf '%s\n' "usage: $0 [--check|--install] [--metadata PATH] [--release-json PATH]"
}

emit_status() {
  local status="$1"
  local message="$2"
  local local_version="${3:-}"
  local remote_version="${4:-}"
  local asset_url="${5:-}"
  local error_code="${6:-}"
  local error_detail="${7:-}"
  jq -n \
    --arg status "$status" \
    --arg message "$message" \
    --arg localVersion "$local_version" \
    --arg remoteVersion "$remote_version" \
    --arg assetUrl "$asset_url" \
    --arg errorCode "$error_code" \
    --arg errorDetail "$error_detail" \
    '{status: $status, message: $message, localVersion: $localVersion, remoteVersion: $remoteVersion, assetUrl: $assetUrl, errorCode: $errorCode, errorDetail: $errorDetail}'
}

fail() {
  local error_code="$1"
  local message="$2"
  local error_detail="${3:-}"
  emit_status "error" "$message" "" "" "" "$error_code" "$error_detail"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || fail "missing_tool" "missing required command: $1" "$1"
}

validate_asset_record() {
  local name="$1"
  local expected_url="$2"
  local maximum_size="$3"
  local label="$4"
  if ! jq -e \
    --arg name "$name" \
    --arg expectedUrl "$expected_url" \
    --argjson maximumSize "$maximum_size" '
      [.assets[] | select(type == "object" and .name == $name)] as $matches
      | ($matches | length) == 1
        and ($matches[0].browser_download_url == $expectedUrl)
        and ($matches[0].state == "uploaded")
        and ($matches[0].size as $size
          | ($size | type) == "number"
            and ($size | floor) == $size
            and $size > 0
            and $size <= $maximumSize)
        and ($matches[0].digest as $digest
          | ($digest | type) == "string"
            and ($digest | test("^sha256:[0-9a-f]{64}$")))
    ' "$RELEASE_JSON" >/dev/null; then
    fail "release_metadata_invalid" "release ${label} metadata does not match the expected contract"
  fi
}

validate_package_manifest() {
  local package_path="$1"
  local expected_version="$2"
  python3 - "$package_path" "$PLUGIN_ID" "$expected_version" \
    "$MAX_PACKAGE_ENTRIES" "$MAX_PACKAGE_EXPANDED_BYTES" "$MAX_PACKAGE_METADATA_BYTES" <<'PY'
import json
import stat
import sys
import zipfile
from pathlib import PurePosixPath

package_path, expected_id, expected_version = sys.argv[1:4]
maximum_entries, maximum_expanded_bytes, maximum_metadata_bytes = map(int, sys.argv[4:7])

try:
    with zipfile.ZipFile(package_path) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > maximum_entries:
            raise ValueError

        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError

        expanded_bytes = 0
        for entry in entries:
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in entry.filename:
                raise ValueError
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError
            expanded_bytes += entry.file_size
            if expanded_bytes > maximum_expanded_bytes:
                raise ValueError

        metadata_entries = [entry for entry in entries if entry.filename == "metadata.json"]
        if len(metadata_entries) != 1:
            raise ValueError
        metadata_entry = metadata_entries[0]
        if metadata_entry.is_dir() or metadata_entry.file_size > maximum_metadata_bytes:
            raise ValueError

        metadata = json.loads(archive.read(metadata_entry))
        if not isinstance(metadata, dict):
            raise ValueError
        plugin = metadata.get("KPlugin")
        if not isinstance(plugin, dict):
            raise ValueError
        if metadata.get("KPackageStructure") != "Plasma/Applet":
            raise ValueError
        if plugin.get("Id") != expected_id or plugin.get("Version") != expected_version:
            raise ValueError
except (KeyError, OSError, UnicodeDecodeError, ValueError, zipfile.BadZipFile):
    sys.exit(1)
PY
}

normalize_version() {
  printf '%s\n' "${1#v}"
}

version_gt() {
  local left
  local right
  local highest
  left="$(normalize_version "$1")"
  right="$(normalize_version "$2")"
  highest="$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -n1)"
  [[ "$highest" == "$left" && "$left" != "$right" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    MODE="check"
    shift
    ;;
  --install)
    MODE="install"
    shift
    ;;
  --metadata)
    [[ $# -ge 2 ]] || { usage >&2; exit 2; }
    METADATA_PATH="$2"
    shift 2
    ;;
  --release-json)
    [[ $# -ge 2 ]] || { usage >&2; exit 2; }
    RELEASE_JSON="$2"
    shift 2
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done

if [[ "$MODE" != "check" && "$MODE" != "install" ]]; then
  fail "invalid_invocation" "invalid update mode: $MODE"
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '{"status":"error","message":"missing required command: jq","localVersion":"","remoteVersion":"","assetUrl":"","errorCode":"missing_tool","errorDetail":"jq"}\n'
  exit 1
fi

require_command sort
require_command head
require_command tail
require_command grep
require_command wc
if [[ -z "$RELEASE_JSON" ]]; then
  require_command curl
fi
if [[ "$MODE" == "install" ]]; then
  require_command curl
  require_command kpackagetool6
  require_command python3
  require_command sha256sum
  require_command timeout
fi

if [[ ! -f "$METADATA_PATH" ]]; then
  fail "local_metadata_invalid" "metadata file not found: $METADATA_PATH"
fi

if ! jq -e 'type == "object" and (.KPlugin | type == "object") and (.KPlugin.Version | type == "string")' \
  "$METADATA_PATH" >/dev/null; then
  fail "local_metadata_invalid" "local widget metadata does not match the expected contract"
fi
local_version="$(jq -r '.KPlugin.Version' "$METADATA_PATH")"
if [[ ! "$local_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "local_metadata_invalid" "local widget version must use X.Y.Z"
fi

if [[ -z "$RELEASE_JSON" ]]; then
  TMP_DIR="$(mktemp -d)"
  RELEASE_JSON="${TMP_DIR}/release.json"
  release_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  curl --fail --location --show-error --silent \
    --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CURL_METADATA_MAX_TIME_SECONDS" \
    --max-filesize "$MAX_RELEASE_METADATA_BYTES" \
    --max-redirs "$MAX_REDIRECTS" \
    --proto '=https' \
    --proto-redir '=https' \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    -H "User-Agent: CodexBar-Plasma-Updater" \
    "$release_url" > "$RELEASE_JSON" \
    || fail "release_fetch_failed" "failed to fetch release metadata from GitHub"
fi

if [[ ! -f "$RELEASE_JSON" ]]; then
  fail "release_metadata_invalid" "release metadata file not found: $RELEASE_JSON"
fi
if [[ "$(wc -c < "$RELEASE_JSON")" -gt "$MAX_RELEASE_METADATA_BYTES" ]]; then
  fail "release_metadata_invalid" "release metadata exceeds the supported size"
fi

if ! jq -e --argjson maxAssets "$MAX_RELEASE_ASSETS" '
  type == "object"
  and (.tag_name | type == "string")
  and (.draft | type == "boolean")
  and (.prerelease | type == "boolean")
  and (.immutable | type == "boolean")
  and (.assets | type == "array")
  and (.assets | length <= $maxAssets)
  and (all(.assets[]; type == "object"))
' "$RELEASE_JSON" >/dev/null; then
  fail "release_metadata_invalid" "release metadata does not match the expected contract"
fi

remote_version="$(jq -r '.tag_name' "$RELEASE_JSON")"
is_draft="$(jq -r '.draft' "$RELEASE_JSON")"
is_prerelease="$(jq -r '.prerelease' "$RELEASE_JSON")"
is_immutable="$(jq -r '.immutable' "$RELEASE_JSON")"
asset_url="$(jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .browser_download_url' "$RELEASE_JSON" | head -n1)"
checksum_url="$(jq -r --arg name "$CHECKSUM_NAME" '.assets[]? | select(.name == $name) | .browser_download_url' "$RELEASE_JSON" | head -n1)"

if [[ ! "$remote_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "release_metadata_invalid" "release tag must use vX.Y.Z"
fi

if [[ "$is_draft" == "true" || "$is_prerelease" == "true" ]]; then
  emit_status "skipped" "latest release is draft or prerelease" "$local_version" "$remote_version" "$asset_url"
  exit 0
fi

if ! version_gt "$remote_version" "$local_version"; then
  emit_status "current" "widget is current" "$local_version" "$remote_version" "$asset_url"
  exit 0
fi

# The updater and metadata ship in the same package. A mutable release only
# reaches this gate when it is newer than the package running this script.
if [[ "$is_immutable" != "true" ]]; then
  fail "release_not_immutable" "newer widget releases must be immutable"
fi

expected_prefix="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/"
expected_asset_url="${expected_prefix}${remote_version}/${ASSET_NAME}"
expected_checksum_url="${expected_prefix}${remote_version}/${CHECKSUM_NAME}"
validate_asset_record "$ASSET_NAME" "$expected_asset_url" "$MAX_PACKAGE_BYTES" "asset"
validate_asset_record "$CHECKSUM_NAME" "$expected_checksum_url" "$MAX_CHECKSUM_BYTES" "checksum"
asset_size="$(jq -r --arg name "$ASSET_NAME" '.assets[] | select(.name == $name) | .size' "$RELEASE_JSON")"
asset_digest="$(jq -r --arg name "$ASSET_NAME" '.assets[] | select(.name == $name) | .digest' "$RELEASE_JSON")"
checksum_size="$(jq -r --arg name "$CHECKSUM_NAME" '.assets[] | select(.name == $name) | .size' "$RELEASE_JSON")"
checksum_digest="$(jq -r --arg name "$CHECKSUM_NAME" '.assets[] | select(.name == $name) | .digest' "$RELEASE_JSON")"

if [[ "$MODE" == "check" ]]; then
  emit_status "available" "widget update is available" "$local_version" "$remote_version" "$asset_url"
  exit 0
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="$(mktemp -d)"
fi
package_path="${TMP_DIR}/${ASSET_NAME}"
checksum_path="${TMP_DIR}/${CHECKSUM_NAME}"
curl --fail --location --show-error --silent \
  --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" \
  --max-time "$CURL_CHECKSUM_MAX_TIME_SECONDS" \
  --max-filesize "$MAX_CHECKSUM_BYTES" \
  --max-redirs "$MAX_REDIRECTS" \
  --proto '=https' \
  --proto-redir '=https' \
  -H "User-Agent: CodexBar-Plasma-Updater" \
  "$checksum_url" --output "$checksum_path" \
  || fail "release_download_failed" "failed to download release checksum"
curl --fail --location --show-error --silent \
  --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" \
  --max-time "$CURL_ASSET_MAX_TIME_SECONDS" \
  --max-filesize "$MAX_PACKAGE_BYTES" \
  --max-redirs "$MAX_REDIRECTS" \
  --proto '=https' \
  --proto-redir '=https' \
  -H "User-Agent: CodexBar-Plasma-Updater" \
  "$asset_url" --output "$package_path" \
  || fail "release_download_failed" "failed to download release asset"
actual_checksum_size="$(wc -c < "$checksum_path")"
actual_asset_size="$(wc -c < "$package_path")"
if [[ "$actual_checksum_size" != "$checksum_size" ]]; then
  fail "release_integrity_failed" "downloaded release checksum size does not match release metadata"
fi
if [[ "$actual_asset_size" != "$asset_size" ]]; then
  fail "release_integrity_failed" "downloaded release asset size does not match release metadata"
fi
actual_checksum_digest="sha256:$(sha256sum "$checksum_path")"
actual_checksum_digest="${actual_checksum_digest%% *}"
actual_asset_digest="sha256:$(sha256sum "$package_path")"
actual_asset_digest="${actual_asset_digest%% *}"
if [[ "$actual_checksum_digest" != "$checksum_digest" ]]; then
  fail "release_integrity_failed" "release checksum does not match the GitHub asset digest"
fi
if [[ "$actual_asset_digest" != "$asset_digest" ]]; then
  fail "release_integrity_failed" "release asset does not match the GitHub asset digest"
fi
if [[ "$(wc -l < "$checksum_path")" -ne 1 ]] \
  || ! grep -Eq '^[[:xdigit:]]{64}[[:space:]][ *]codexbar-plasma\.plasmoid$' "$checksum_path"; then
  fail "release_integrity_failed" "release checksum has an invalid format"
fi
(
  cd "$TMP_DIR"
  sha256sum --check --strict --status "$CHECKSUM_NAME"
) || fail "release_integrity_failed" "release checksum verification failed"
package_version="$(normalize_version "$remote_version")"
validate_package_manifest "$package_path" "$package_version" \
  || fail "package_invalid" "widget package manifest does not match the release"
timeout --kill-after="${KPACKAGE_INSTALL_KILL_AFTER_SECONDS}s" \
  "${KPACKAGE_INSTALL_MAX_TIME_SECONDS}s" \
  kpackagetool6 -t Plasma/Applet -u "$package_path" >&2 \
  || fail "package_install_failed" "failed to install widget package"

emit_status "installed" "widget update installed; restart Plasma to apply the update" "$local_version" "$remote_version" "$asset_url"
