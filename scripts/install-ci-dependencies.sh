#!/usr/bin/env bash
set -euo pipefail

# Run only in the disposable KDE neon CI container, as root.
export DEBIAN_FRONTEND=noninteractive
# The pinned image includes authenticated package indexes for this toolchain,
# kept as a fallback when the archive metadata is unreachable. Refresh them
# when the archive answers: once it rolls superseded packages (e.g. krb5),
# the snapshot references 404 and the install below fails.
apt-get update || true
apt-get install -y --no-install-recommends \
  make cmake git curl ca-certificates gettext jq libxml2-utils shellcheck \
  python3-pyflakes \
  qt6-base-dev-tools qt6-declarative-dev-tools qml6-module-qttest \
  plasma-workspace libplasma6 plasma5support kf6-kpackage \
  kf6-kcmutils kf6-kirigami kf6-qqc2-desktop-style \
  dbus-x11 xvfb xauth fonts-noto-core breeze breeze-icon-theme locales

locale-gen it_IT.UTF-8 fr_FR.UTF-8 de_DE.UTF-8 es_ES.UTF-8 pt_BR.UTF-8

# actionlint has no Ubuntu 24.04 package, so install the official release binary
# pinned by version and SHA-256. The checksum makes the download reproducible
# the way the digest-pinned image and the APT indexes make the rest of the job
# reproducible; an altered or truncated archive fails here instead of running.
# Update both values together from the release's checksums.txt when bumping.
ACTIONLINT_VERSION=1.7.12
ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
actionlint_dir="$(mktemp -d)"
trap 'rm -rf "$actionlint_dir"' EXIT
curl -fsSL --retry 3 -o "${actionlint_dir}/actionlint.tar.gz" \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
printf '%s  %s\n' "$ACTIONLINT_SHA256" "${actionlint_dir}/actionlint.tar.gz" \
  | sha256sum --check --strict -
tar -xzf "${actionlint_dir}/actionlint.tar.gz" -C /usr/local/bin actionlint

# Fail before the tests if packaging, linting, or preview support is absent.
command -v kpackagetool6
command -v plasmawindowed
command -v dbus-run-session
command -v actionlint
python3 -c 'import pyflakes'
