#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Lucenx9"
REPO_NAME="codexbar-plasma"
ASSET_NAME="codexbar-plasma.plasmoid"
API_VERSION="2026-03-10"
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
  jq -n \
    --arg status "$status" \
    --arg message "$message" \
    --arg localVersion "$local_version" \
    --arg remoteVersion "$remote_version" \
    --arg assetUrl "$asset_url" \
    '{status: $status, message: $message, localVersion: $localVersion, remoteVersion: $remoteVersion, assetUrl: $assetUrl}'
}

fail() {
  emit_status "error" "$1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
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
  fail "invalid update mode: $MODE"
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '{"status":"error","message":"missing required command: jq","localVersion":"","remoteVersion":"","assetUrl":""}\n'
  exit 1
fi

require_command sort
require_command head
if [[ -z "$RELEASE_JSON" ]]; then
  require_command curl
fi
if [[ "$MODE" == "install" ]]; then
  require_command kpackagetool6
fi

if [[ ! -f "$METADATA_PATH" ]]; then
  fail "metadata file not found: $METADATA_PATH"
fi

local_version="$(jq -r '.KPlugin.Version // empty' "$METADATA_PATH")"
if [[ -z "$local_version" || "$local_version" == "null" ]]; then
  fail "metadata does not contain KPlugin.Version"
fi

if [[ -z "$RELEASE_JSON" ]]; then
  TMP_DIR="$(mktemp -d)"
  RELEASE_JSON="${TMP_DIR}/release.json"
  release_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  curl --fail --location --show-error --silent \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    "$release_url" > "$RELEASE_JSON"
fi

if [[ ! -f "$RELEASE_JSON" ]]; then
  fail "release metadata file not found: $RELEASE_JSON"
fi

remote_version="$(jq -r '.tag_name // empty' "$RELEASE_JSON")"
is_draft="$(jq -r '.draft // false' "$RELEASE_JSON")"
is_prerelease="$(jq -r '.prerelease // false' "$RELEASE_JSON")"
asset_url="$(jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .browser_download_url' "$RELEASE_JSON" | head -n1)"

if [[ -z "$remote_version" || "$remote_version" == "null" ]]; then
  fail "release metadata does not contain tag_name"
fi

if [[ "$is_draft" == "true" || "$is_prerelease" == "true" ]]; then
  emit_status "skipped" "latest release is draft or prerelease" "$local_version" "$remote_version" "$asset_url"
  exit 0
fi

if ! version_gt "$remote_version" "$local_version"; then
  emit_status "current" "widget is current" "$local_version" "$remote_version" "$asset_url"
  exit 0
fi

if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
  emit_status "skipped" "release asset ${ASSET_NAME} not found" "$local_version" "$remote_version"
  exit 0
fi

expected_prefix="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/"
if [[ "$asset_url" != "$expected_prefix"* ]]; then
  fail "release asset URL is outside the expected GitHub release path"
fi

if [[ "$MODE" == "check" ]]; then
  emit_status "available" "widget update is available" "$local_version" "$remote_version" "$asset_url"
  exit 0
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="$(mktemp -d)"
fi
package_path="${TMP_DIR}/${ASSET_NAME}"
curl --fail --location --show-error --silent "$asset_url" --output "$package_path"
kpackagetool6 -t Plasma/Applet -u "$package_path"

emit_status "installed" "widget update installed; restart Plasma to apply the update" "$local_version" "$remote_version" "$asset_url"
