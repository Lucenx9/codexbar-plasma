#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POT_FILE="${ROOT_DIR}/po/codexbar-plasma.pot"
UPDATE_SCRIPT="${ROOT_DIR}/scripts/update_translations.sh"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected i18n catalog fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

if [[ ! -x "$UPDATE_SCRIPT" ]]; then
  echo "scripts/update_translations.sh must exist and be executable" >&2
  exit 1
fi

if [[ ! -f "$POT_FILE" ]]; then
  echo "po/codexbar-plasma.pot must exist; run make translations" >&2
  exit 1
fi

"$UPDATE_SCRIPT" --check

require_in_file "$POT_FILE" "Project-Id-Version: codexbar-plasma"
require_in_file "$POT_FILE" "Report-Msgid-Bugs-To: https://github.com/Lucenx9/codexbar-plasma/issues"
require_in_file "$POT_FILE" "msgid \"Overview\""
require_in_file "$POT_FILE" "msgid \"Widget update check failed.\""
require_in_file "$POT_FILE" "msgid \"%1 hour\""
require_in_file "$POT_FILE" "msgid_plural \"%1 hours\""

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/fakebin"
printf '%s\n' 'existing catalog' > "$fixture_dir/catalog.pot"
cat > "$fixture_dir/fakebin/xgettext" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'partial catalog'
exit 1
SH
chmod +x "$fixture_dir/fakebin/xgettext"
if PATH="$fixture_dir/fakebin:$PATH" \
  "$UPDATE_SCRIPT" --output "$fixture_dir/catalog.pot" >/dev/null 2>&1; then
  echo "translation update must fail when xgettext fails" >&2
  exit 1
fi
if [[ "$(cat "$fixture_dir/catalog.pot")" != "existing catalog" ]]; then
  echo "a failed translation update must preserve the existing catalog" >&2
  exit 1
fi

echo "i18n catalog checks passed."
