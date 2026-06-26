#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
WORKFLOW="${ROOT_DIR}/.github/workflows/ci.yml"
MAKEFILE="${ROOT_DIR}/Makefile"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected security hardening fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_text() {
  local label="$1"
  local text="$2"
  local needle="$3"
  if ! grep -Fq -- "$needle" <<<"$text"; then
    echo "missing expected security hardening fragment in ${label}: $needle" >&2
    exit 1
  fi
}

reject_text() {
  local label="$1"
  local text="$2"
  local needle="$3"
  if grep -Fq -- "$needle" <<<"$text"; then
    echo "unexpected security-sensitive fragment in ${label}: $needle" >&2
    exit 1
  fi
}

workflow_job_block() {
  local job="$1"
  awk -v marker="  ${job}:" '
    $0 == marker { in_job = 1; print; next }
    in_job && /^  [A-Za-z0-9_-]+:/ { exit }
    in_job { print }
  ' "$WORKFLOW"
}

if ! awk '
  /^permissions:/ { in_permissions = 1; next }
  /^jobs:/ { exit }
  in_permissions && /contents: read/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$WORKFLOW"; then
  echo "missing top-level read-only workflow permissions in .github/workflows/ci.yml" >&2
  exit 1
fi

CHECK_JOB="$(workflow_job_block check)"
RELEASE_JOB="$(workflow_job_block release)"
require_text "check job" "$CHECK_JOB" "contents: read"
require_text "check job" "$CHECK_JOB" "persist-credentials: false"
reject_text "check job" "$CHECK_JOB" "contents: write"
require_text "release job" "$RELEASE_JOB" "if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')"
require_text "release job" "$RELEASE_JOB" "contents: write"
require_text "release job" "$RELEASE_JOB" "persist-credentials: false"

require_in_file "$MAIN_QML" "function hasOwnKey(item, key)"
require_in_file "$MAIN_QML" "Object.prototype.hasOwnProperty.call(item, key)"
require_in_file "$MAIN_QML" "function isUnsafeObjectKey(key)"
require_in_file "$MAIN_QML" "value === \"__proto__\" || value === \"prototype\" || value === \"constructor\""
require_in_file "$MAIN_QML" "if (name.length === 0 || isUnsafeObjectKey(name))"
require_in_file "$MAIN_QML" "if (!hasOwnKey(byName, name))"
require_in_file "$MAIN_QML" "if (!hasOwnKey(byName, modelName))"
require_in_file "$MAIN_QML" "if (!hasOwnKey(item, key) || isUnsafeObjectKey(key))"

require_in_file "$MAIN_QML" "function safeStatusUrl(providerID, url)"
require_in_file "$MAIN_QML" "function httpsUrlHost(url)"
require_in_file "$MAIN_QML" "statusUrl: safeStatusUrl(providerID, status && status.url ? status.url : \"\")"
require_in_file "$MAIN_QML" "Qt.openUrlExternally(safeStatusUrl(item.provider, item.statusUrl))"

require_in_file "$MAIN_QML" "notify-send --app-name=CodexBar --icon=view-statistics --urgency="
require_in_file "$MAIN_QML" "+ \" -- \" + shellQuote(cleanTitle)"

require_in_file "$MAKEFILE" "scripts/test_security_regressions.sh"

echo "Security regression checks passed."
