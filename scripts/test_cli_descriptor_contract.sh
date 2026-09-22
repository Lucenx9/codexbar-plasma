#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_MD="${ROOT_DIR}/docs/cli-provider-settings-descriptor.md"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected CLI descriptor contract fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected CLI descriptor contract fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

if [[ ! -f "$CONTRACT_MD" ]]; then
  echo "docs/cli-provider-settings-descriptor.md must document the provider settings descriptor contract" >&2
  exit 1
fi

# The proposal is prose, so its sentences are not pinned: rewording must stay
# free. What must not drift is the part Plasma enforces. The rendering bounds
# and the identifier pattern are read from the parser and required in the
# document, so changing either side alone fails here.
python3 - "$CONTRACT_MD" "${ROOT_DIR}/contents/ui/config/ProviderDescriptor.js" <<'PY_INNER'
import re
import sys
from pathlib import Path

contract = Path(sys.argv[1]).read_text(encoding="utf-8")
parser = Path(sys.argv[2]).read_text(encoding="utf-8")
flat = re.sub(r"\s+", " ", contract)

def constant(name):
    match = re.search(r"var " + name + r" = (\d+)", parser)
    if not match:
        raise SystemExit(f"ProviderDescriptor.js no longer declares {name}")
    return match.group(1)

failures = []
for name, phrase in (
    ("maximumFields", "{} fields"),
    ("maximumActions", "{} actions"),
    ("maximumOptions", "{} options"),
    ("maximumCommandTokens", "{} command tokens"),
    ("maximumTokenLength", "at most {} characters"),
    ("maximumIdentifierLength", "no longer than {} characters"),
):
    expected = phrase.format(constant(name))
    if expected not in flat:
        failures.append(f"contract must state the parser bound {name}: {expected!r}")

pattern = re.search(r"/\^(\[A-Za-z0-9\]\[A-Za-z0-9\._-\]\*)\$/", parser)
if not pattern:
    failures.append("ProviderDescriptor.js no longer validates identifiers with the documented pattern")
elif "`" + pattern.group(1) + "`" not in contract:
    failures.append(f"contract must document the identifier pattern {pattern.group(1)!r}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY_INNER

# A command descriptor was once documented as a read-only row; it runs a
# command. An absence has no executable equivalent, so this stays literal.
reject_in_file "$CONTRACT_MD" "- \`\"kind\": \"command\"\`: read-only row"

echo "CLI descriptor contract checks passed."
