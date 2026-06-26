# Auto Update and Theme Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add conservative GitHub Release update checks, available-update notifications, opt-in automatic widget installation, and static theme-boundary checks.

**Architecture:** A local `scripts/update-widget.sh` helper handles network, version comparison, download, and optional install. QML only schedules checks, interprets JSON status, sends notifications, and invokes install mode when explicitly enabled. Static shell tests protect updater safety and generic UI theme rules while leaving provider identity colors hardcoded.

**Tech Stack:** Bash, `curl`, `jq`, `kpackagetool6`, KDE Plasma QML, Plasma executable DataSource, existing `make check` shell tests.

---

### Task 1: Add Failing Static Coverage

**Files:**
- Modify: `scripts/test_feature_parity.sh`
- Create: `scripts/test_update_widget.sh`
- Create: `scripts/test_theme_boundaries.sh`
- Modify: `Makefile`

- [ ] **Step 1: Add feature parity assertions**

Add checks for the new config keys, settings labels, QML update functions, README text, and Makefile targets:

```sh
require_in_file "$CONFIG_XML" "updateChecksEnabled"
require_in_file "$CONFIG_XML" "updateNotificationsEnabled"
require_in_file "$CONFIG_XML" "autoUpdateEnabled"
require_in_file "$CONFIG_XML" "autoUpdateIntervalHours"
require_in_file "$CONFIG_XML" "autoUpdateLastCheck"
require_in_file "$GENERAL_QML" "Check for widget updates"
require_in_file "$GENERAL_QML" "Notify when a widget update is available"
require_in_file "$GENERAL_QML" "Install widget updates automatically"
require_in_file "$GENERAL_QML" "Update check interval:"
require_in_file "$MAIN_QML" "property bool updateChecksEnabled"
require_in_file "$MAIN_QML" "function buildUpdateCommand(installMode)"
require_in_file "$MAIN_QML" "function processUpdateCheck(payload)"
require_in_file "$MAIN_QML" "function notifyAvailableUpdate(version, url)"
require_in_file "$MAKEFILE" "scripts/test_update_widget.sh"
require_in_file "$MAKEFILE" "scripts/test_theme_boundaries.sh"
require_in_file "$MAKEFILE" "update:"
require_in_file "$README_MD" "Check for widget updates"
```

- [ ] **Step 2: Add updater safety test**

Create `scripts/test_update_widget.sh` with static assertions:

```sh
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="${ROOT_DIR}/scripts/update-widget.sh"
MAKEFILE="${ROOT_DIR}/Makefile"

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

test -x "$UPDATER" || { echo "scripts/update-widget.sh must exist and be executable" >&2; exit 1; }
require_in_file "$UPDATER" "REPO_OWNER=\"Lucenx9\""
require_in_file "$UPDATER" "REPO_NAME=\"codexbar-plasma\""
require_in_file "$UPDATER" "ASSET_NAME=\"codexbar-plasma.plasmoid\""
require_in_file "$UPDATER" "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
require_in_file "$UPDATER" "browser_download_url"
require_in_file "$UPDATER" "kpackagetool6 -t Plasma/Applet -u"
require_in_file "$UPDATER" "systemctl --user restart plasma-plasmashell.service"
require_in_file "$UPDATER" "--check"
require_in_file "$UPDATER" "--install"
require_in_file "$UPDATER" "mktemp -d"
require_in_file "$UPDATER" "trap cleanup EXIT"
require_in_file "$UPDATER" "jq -r"
require_in_file "$UPDATER" "curl --fail --location --show-error --silent"
reject_in_file "$UPDATER" "curl "
reject_in_file "$UPDATER" "| sh"
reject_in_file "$UPDATER" "| bash"
reject_in_file "$UPDATER" "eval "
require_in_file "$MAKEFILE" "scripts/update-widget.sh --install"

echo "Widget updater checks passed."
```

- [ ] **Step 3: Add theme boundary test**

Create `scripts/test_theme_boundaries.sh` with focused static checks:

```sh
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected theme fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$MAIN_QML" "function providerColor(value)"
require_in_file "$PROVIDERS_QML" "function providerColor(value)"
require_in_file "$MAIN_QML" "function contrastTextColor(color)"
require_in_file "$MAIN_QML" "Kirigami.Theme.textColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.highlightColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.highlightedTextColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.negativeTextColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.neutralTextColor"

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
allowed_files = {
    root / "contents/ui/main.qml",
    root / "contents/ui/configProviders.qml",
}
provider_icons = root / "contents/icons/providers"
patterns = [
    re.compile(r'Qt\.rgba\('),
    re.compile(r'#[0-9A-Fa-f]{3,8}'),
    re.compile(r'"(?:black|white)"'),
]

def allowed_qml(path, text, index):
    before = text[:index]
    function_name = None
    for match in re.finditer(r'\n    function ([A-Za-z0-9_]+)\(', before):
        function_name = match.group(1)
    return function_name in {"providerColor", "contrastTextColor", "withAlpha"}

for path in sorted((root / "contents/ui").glob("*.qml")):
    text = path.read_text(encoding="utf-8")
    for pattern in patterns:
        for match in pattern.finditer(text):
            if path in allowed_files and allowed_qml(path, text, match.start()):
                continue
            token = match.group(0)
            if token == '"transparent"':
                continue
            print(f"unexpected hardcoded generic UI color in {path.relative_to(root)}: {token}", file=sys.stderr)
            sys.exit(1)

for path in provider_icons.glob("*"):
    if path.is_file():
        continue

print("Theme boundary checks passed.")
PY
```

- [ ] **Step 4: Wire tests into Makefile**

Add both scripts to `check` before `test_qml_hardening.sh`.

- [ ] **Step 5: Verify red**

Run:

```sh
scripts/test_feature_parity.sh
```

Expected: FAIL on missing update config/settings/script fragments.

Run:

```sh
scripts/test_update_widget.sh
```

Expected: FAIL because `scripts/update-widget.sh` does not exist.

Run:

```sh
scripts/test_theme_boundaries.sh
```

Expected: PASS or FAIL only on existing hardcoded generic UI colors; any failure must be inspected before changing theme code.

### Task 2: Implement Local Updater Helper

**Files:**
- Create: `scripts/update-widget.sh`
- Modify: `Makefile`

- [ ] **Step 1: Create helper script**

Implement `scripts/update-widget.sh` with:

```sh
#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Lucenx9"
REPO_NAME="codexbar-plasma"
ASSET_NAME="codexbar-plasma.plasmoid"
API_VERSION="2026-03-10"
MODE="check"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
```

Complete the script with argument parsing for `--check`, `--install`, `--metadata`, and `--release-json`.

- [ ] **Step 2: Add required helper functions**

Add shell functions:

```sh
require_command() { command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"; }
fail() { jq -n --arg status "error" --arg message "$1" '{status:$status,message:$message}'; exit 1; }
json_string() { jq -rn --arg value "$1" '$value'; }
normalize_version() { printf '%s\n' "${1#v}"; }
version_gt() { [[ "$(printf '%s\n%s\n' "$(normalize_version "$1")" "$(normalize_version "$2")" | sort -V | tail -n1)" == "$(normalize_version "$1")" && "$(normalize_version "$1")" != "$(normalize_version "$2")" ]]; }
```

- [ ] **Step 3: Read local and release metadata**

Read local version from `metadata.json`:

```sh
local_version="$(jq -r '.KPlugin.Version // empty' "$metadata_path")"
```

Fetch release JSON unless `--release-json` is supplied:

```sh
release_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
curl --fail --location --show-error --silent \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: ${API_VERSION}" \
  "$release_url" > "$release_json"
```

- [ ] **Step 4: Select the release asset**

Extract:

```sh
remote_version="$(jq -r '.tag_name // empty' "$release_json")"
asset_url="$(jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .browser_download_url' "$release_json" | head -n1)"
is_draft="$(jq -r '.draft // false' "$release_json")"
is_prerelease="$(jq -r '.prerelease // false' "$release_json")"
```

Return JSON no-op for draft/prerelease, same version, older version, or missing asset.

- [ ] **Step 5: Implement install mode**

For `--install`, download asset to a temp dir and run:

```sh
kpackagetool6 -t Plasma/Applet -u "$package_path"
systemctl --user restart plasma-plasmashell.service
```

Return JSON:

```json
{"status":"installed","localVersion":"0.1.0","remoteVersion":"v0.2.0","assetUrl":"..."}
```

- [ ] **Step 6: Make executable and wire make target**

Run:

```sh
chmod +x scripts/update-widget.sh
```

Add:

```make
update:
	scripts/update-widget.sh --install
```

- [ ] **Step 7: Verify updater tests green**

Run:

```sh
scripts/test_update_widget.sh
```

Expected: PASS.

### Task 3: Add Plasma Settings and Runtime Update Flow

**Files:**
- Modify: `contents/config/main.xml`
- Modify: `contents/ui/configGeneral.qml`
- Modify: `contents/ui/main.qml`
- Modify: `scripts/test_feature_parity.sh`

- [ ] **Step 1: Add config schema entries**

Add to `contents/config/main.xml`:

```xml
<entry name="updateChecksEnabled" type="Bool">
  <label>Check for widget updates.</label>
  <default>true</default>
</entry>
<entry name="updateNotificationsEnabled" type="Bool">
  <label>Notify when widget updates are available.</label>
  <default>true</default>
</entry>
<entry name="autoUpdateEnabled" type="Bool">
  <label>Install widget updates automatically.</label>
  <default>false</default>
</entry>
<entry name="autoUpdateIntervalHours" type="Int">
  <label>Widget update check interval in hours.</label>
  <default>24</default>
  <min>1</min>
  <max>168</max>
</entry>
<entry name="autoUpdateLastCheck" type="String">
  <label>Last widget update check timestamp.</label>
  <default></default>
</entry>
```

- [ ] **Step 2: Add General settings controls**

Add aliases and controls in `configGeneral.qml`:

```qml
property alias cfg_updateChecksEnabled: updateChecksEnabledCheck.checked
property bool cfg_updateChecksEnabledDefault
property alias cfg_updateNotificationsEnabled: updateNotificationsEnabledCheck.checked
property bool cfg_updateNotificationsEnabledDefault
property alias cfg_autoUpdateEnabled: autoUpdateEnabledCheck.checked
property bool cfg_autoUpdateEnabledDefault
property alias cfg_autoUpdateIntervalHours: autoUpdateIntervalHoursSpin.value
property int cfg_autoUpdateIntervalHoursDefault
property string cfg_autoUpdateLastCheck
property string cfg_autoUpdateLastCheckDefault
```

Controls:

```qml
Controls.CheckBox { id: updateChecksEnabledCheck; text: i18n("Check for widget updates") }
Controls.CheckBox { id: updateNotificationsEnabledCheck; text: i18n("Notify when a widget update is available"); enabled: updateChecksEnabledCheck.checked }
Controls.CheckBox { id: autoUpdateEnabledCheck; text: i18n("Install widget updates automatically"); enabled: updateChecksEnabledCheck.checked }
Controls.SpinBox { id: autoUpdateIntervalHoursSpin; Kirigami.FormData.label: i18n("Update check interval:"); from: 1; to: 168; enabled: updateChecksEnabledCheck.checked }
```

- [ ] **Step 3: Add runtime properties**

Add to `main.qml`:

```qml
property bool updateChecksEnabled: Plasmoid.configuration.updateChecksEnabled !== false
property bool updateNotificationsEnabled: Plasmoid.configuration.updateNotificationsEnabled !== false
property bool autoUpdateEnabled: Plasmoid.configuration.autoUpdateEnabled === true
property int autoUpdateIntervalHours: isFinite(Number(Plasmoid.configuration.autoUpdateIntervalHours)) ? Math.max(1, Math.min(168, Number(Plasmoid.configuration.autoUpdateIntervalHours))) : 24
property string autoUpdateLastCheck: Plasmoid.configuration.autoUpdateLastCheck || ""
property string connectedUpdateCommandSource: ""
property string updateStatusText: ""
property string updateErrorText: ""
property string lastNotifiedUpdateVersion: ""
```

- [ ] **Step 4: Add command builder and check logic**

Add functions:

```qml
function updateScriptPath() {
    return Qt.resolvedUrl("../../scripts/update-widget.sh").toString().replace(/^file:\/\//, "")
}

function buildUpdateCommand(installMode) {
    var script = updateScriptPath()
    return shellQuote(script) + (installMode ? " --install" : " --check")
}

function checkForWidgetUpdate() {
    if (!updateChecksEnabled || connectedUpdateCommandSource.length > 0) {
        return
    }
    connectedUpdateCommandSource = commandWithRunNonce(buildUpdateCommand(autoUpdateEnabled))
    updateSource.connectSource(connectedUpdateCommandSource)
}
```

- [ ] **Step 5: Add DataSource and response processing**

Add `updateSource` executable DataSource and `processUpdateCheck(payload)`.

Expected behavior:

- `status === "available"` and `autoUpdateEnabled === false`: call `notifyAvailableUpdate(version, url)` once per version.
- `status === "installed"`: set status text and do not send repeated notification.
- `status === "current"` or `status === "skipped"`: update quiet status.
- `status === "error"` or parse failure: update `updateErrorText`, no notification spam.

- [ ] **Step 6: Add update timer**

Add Timer:

```qml
Timer {
    id: updateCheckTimer
    interval: root.autoUpdateIntervalHours * 60 * 60 * 1000
    repeat: true
    running: root.updateChecksEnabled
    triggeredOnStart: true
    onTriggered: root.checkForWidgetUpdate()
}
```

- [ ] **Step 7: Verify feature parity green**

Run:

```sh
scripts/test_feature_parity.sh
```

Expected: PASS.

### Task 4: Theme Boundary Audit

**Files:**
- Modify: `contents/ui/main.qml` only if `scripts/test_theme_boundaries.sh` identifies generic UI hardcoded colors.
- Modify: `contents/ui/configProviders.qml` only if generic UI colors outside `providerColor()` are identified.

- [ ] **Step 1: Run theme test**

Run:

```sh
scripts/test_theme_boundaries.sh
```

Expected: PASS after allowed provider identity colors and contrast helper are excluded.

- [ ] **Step 2: Fix only generic UI violations**

If the test reports a generic UI color, replace it with `Kirigami.Theme.*` or `withAlpha(Kirigami.Theme.textColor, alpha)`.

- [ ] **Step 3: Verify no provider identity colors changed**

Run:

```sh
git diff -- contents/ui/main.qml contents/ui/configProviders.qml | rg -n "providerColor|case \"|Qt\\.rgba" || true
```

Expected: no provider identity color map changes unless the diff is only test-related context.

### Task 5: Docs and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-06-26-auto-update-theme-design.md` only if implementation materially differs.

- [ ] **Step 1: Update README**

Document:

- update checks are enabled by default.
- available update notifications can be disabled.
- automatic install is opt-in.
- manual update is `make update` or `scripts/update-widget.sh --install`.
- KDE Store/Discover/KNewStuff should be preferred if the widget is later published there.

- [ ] **Step 2: Run full checks**

Run:

```sh
make check
make package
```

Expected: both exit 0.

- [ ] **Step 3: Runtime verify**

Run:

```sh
./install.sh
journalctl --user -u plasma-plasmashell.service --since '2 minutes ago' --no-pager \
  | rg -n 'app\.codexbar|CodexBar|ReferenceError|TypeError|SyntaxError|file://.*/app.codexbar'
```

Expected: install exits 0; no CodexBar QML errors. Unrelated logs from other plasmoids are not blockers.

- [ ] **Step 4: Commit and push**

Commit implementation:

```sh
git add Makefile README.md contents/config/main.xml contents/ui/configGeneral.qml contents/ui/main.qml scripts/test_feature_parity.sh scripts/test_update_widget.sh scripts/test_theme_boundaries.sh scripts/update-widget.sh docs/superpowers/plans/2026-06-26-auto-update-theme.md docs/superpowers/specs/2026-06-26-auto-update-theme-design.md
git commit -m "Add widget update checks"
git push
```
