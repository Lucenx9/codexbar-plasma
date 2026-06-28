#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected UI fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_block_fragment() {
  local file="$1"
  local block_id="$2"
  local needle="$3"
  if ! awk -v block_id="$block_id" -v needle="$needle" '
    index($0, block_id) { in_block = 1 }
    in_block && index($0, needle) { found = 1 }
    in_block && $0 ~ /^        }$/ { exit }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    echo "missing expected UI fragment near ${block_id} in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected stale UI fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$GENERAL_QML" "id: lastUpdateCheckLabel"
require_in_file "$GENERAL_QML" "id: lastUpdateStatusLabel"
require_block_fragment "$GENERAL_QML" "id: lastUpdateCheckLabel" "Layout.fillWidth: true"
require_block_fragment "$GENERAL_QML" "id: lastUpdateCheckLabel" "wrapMode: Text.WordWrap"
require_block_fragment "$GENERAL_QML" "id: lastUpdateStatusLabel" "Layout.fillWidth: true"
require_block_fragment "$GENERAL_QML" "id: lastUpdateStatusLabel" "wrapMode: Text.WordWrap"

require_in_file "$PROVIDERS_QML" "Provider-specific controls come from the CodexBar CLI descriptor"
reject_in_file "$PROVIDERS_QML" "Provider-specific editing stays in the CodexBar CLI until it exposes a stable settings descriptor"

python3 - "$ROOT_DIR" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
main_qml = root / "contents/ui/main.qml"
providers_qml = root / "contents/ui/configProviders.qml"


def function_body(text, name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"missing function {name}")
    brace = text.find("{", start)
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated function {name}")
    return text[brace + 1:index - 1]


def id_block(text, object_id):
    marker = f"id: {object_id}"
    marker_index = text.find(marker)
    if marker_index < 0:
        raise AssertionError(f"missing id {object_id}")
    brace = text.rfind("{", 0, marker_index)
    if brace < 0:
        raise AssertionError(f"missing object body for id {object_id}")
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated object body for id {object_id}")
    return text[brace + 1:index - 1]


def extract_switch_returns(text, name):
    body = function_body(text, name)
    values = {}
    pending = []
    for line in body.splitlines():
        stripped = line.strip()
        case_match = re.match(r'case "([^"]+)":', stripped)
        if case_match:
            pending.append(case_match.group(1))
            continue
        return_match = re.match(r'return "([^"]*)"', stripped)
        if return_match and pending:
            for provider in pending:
                values[provider] = return_match.group(1)
            pending = []
        elif stripped.startswith("default:"):
            pending = []
    return values


main_text = main_qml.read_text(encoding="utf-8")
providers_text = providers_qml.read_text(encoding="utf-8")

if "—" in main_text or "–" in main_text:
    raise AssertionError("main.qml must avoid em dash/en dash placeholders in visible UI text")

for function_name in ("providerDashboardUrl", "providerLoginUrl"):
    main_values = extract_switch_returns(main_text, function_name)
    provider_values = extract_switch_returns(providers_text, function_name)
    if main_values != provider_values:
        missing = sorted(set(main_values) - set(provider_values))
        extra = sorted(set(provider_values) - set(main_values))
        changed = sorted(
            key for key in set(main_values) & set(provider_values)
            if main_values[key] != provider_values[key]
        )
        raise AssertionError(
            f"{function_name} drift between main.qml and configProviders.qml; "
            f"missing={missing}, extra={extra}, changed={changed}"
        )

toggle_body = function_body(providers_text, "handleToggleResult")
if "stderrText.trim()" not in toggle_body or "exitCode" not in toggle_body:
    raise AssertionError("handleToggleResult must treat stderr/exit-code failures as errors")

# Overview selection is stored with the raw CLI provider IDs (e.g. groqcloud,
# alibaba-coding-plan) but matched at runtime against providerKey-normalized
# IDs (groq, alibaba). configuredOverviewProviderIDs must normalize on read so
# the custom selection is not silently ignored for aliased providers.
overview_body = function_body(main_text, "configuredOverviewProviderIDs")
if "providerKey(" not in overview_body:
    raise AssertionError(
        "configuredOverviewProviderIDs must normalize IDs via providerKey so "
        "aliased providers match runtime keys"
    )

for header_id in ("overviewHeaderRow", "providerHeaderRow"):
    header_body = id_block(main_text, header_id)
    if "Layout.rightMargin: Kirigami.Units.smallSpacing" not in header_body:
        raise AssertionError(
            f"{header_id} must align header actions with the inset scroll content"
        )

for scroll_id in ("overviewScroll", "providerScroll"):
    scroll_body = id_block(main_text, scroll_id)
    if "readonly property real contentRightInset: Kirigami.Units.smallSpacing" not in scroll_body:
        raise AssertionError(f"{scroll_id} must define a reusable right content inset")
    if "rightPadding: contentRightInset" not in scroll_body:
        raise AssertionError(f"{scroll_id} must reserve padding on the right edge")
    if "contentWidth: Math.max(0, availableWidth - contentRightInset)" not in scroll_body:
        raise AssertionError(f"{scroll_id} must keep content out from under the right inset")
    if f"width: {scroll_id}.contentWidth" not in scroll_body:
        raise AssertionError(f"{scroll_id} content column must follow the inset content width")

provider_scroll_body = id_block(main_text, "providerScroll")
if "rightPadding: contentRightInset" not in provider_scroll_body:
    raise AssertionError(
        "providerScroll must keep provider details away from the right popup edge"
    )

# Status notifications must fire on first sight, worsened severity, and changed
# same-severity stable incident keys so active incident replacements are not
# missed without letting free-form status text changes spam notifications.
status_body = function_body(main_text, "processStatusNotification")
if "worsened" not in status_body:
    raise AssertionError("processStatusNotification must gate on severity worsening")
if (
    "incidentChanged" not in status_body
    or "previousIncidentKey" not in status_body
    or "currentIncidentKey" not in status_body
    or "previousIncidentKey !== currentIncidentKey" not in status_body
):
    raise AssertionError(
        "processStatusNotification must only notify for same-severity changes "
        "when a stable status incident key is present"
    )
if "previousValue !== value" in status_body:
    raise AssertionError(
        "processStatusNotification must compare incident keys instead of full "
        "severity-bearing memo values"
    )

status_value_body = function_body(main_text, "notificationStatusValue")
if "statusIncidentKey" not in status_value_body:
    raise AssertionError("notificationStatusValue must prefer stable incident keys when present")
if 'item.statusSeverity + "|" + incidentKey' not in status_value_body:
    raise AssertionError("notificationStatusValue must include severity and stable incident key")
if ': item.status' in status_value_body:
    raise AssertionError("notificationStatusValue must not fall back to provider-controlled status text")

# autoSelectProvider must not clobber an explicit Overview selection on every
# refresh; once the user picks Overview the selection has to survive.
select_body = function_body(main_text, "updateSelectedProvider")
if "overviewSelected" not in select_body:
    raise AssertionError(
        "updateSelectedProvider must preserve an explicit Overview selection "
        "when autoSelectProvider is enabled"
    )
PY

echo "UI regression checks passed."
