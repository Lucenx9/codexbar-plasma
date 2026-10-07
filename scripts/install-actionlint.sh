#!/usr/bin/env bash
set -euo pipefail

# Update both values from the release's checksums.txt when bumping.
ACTIONLINT_VERSION=1.7.12
ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
actionlint_dir="$(mktemp -d)"
trap 'rm -rf "$actionlint_dir"' EXIT
curl -fsSL --retry 3 -o "${actionlint_dir}/actionlint.tar.gz" \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
printf '%s  %s\n' "$ACTIONLINT_SHA256" "${actionlint_dir}/actionlint.tar.gz" \
  | sha256sum --check --strict -
tar -xzf "${actionlint_dir}/actionlint.tar.gz" -C /usr/local/bin actionlint
