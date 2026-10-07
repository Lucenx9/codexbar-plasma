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
  qt6-base-dev-tools qt6-declarative-dev-tools qml6-module-qttest qml6-module-qtquick-dialogs \
  plasma-workspace libplasma6 plasma5support kf6-kpackage \
  kf6-kcmutils kf6-kirigami kf6-qqc2-desktop-style kf6-kdeclarative \
  dbus-x11 xvfb xauth fonts-noto-core breeze breeze-icon-theme locales

locale-gen it_IT.UTF-8 fr_FR.UTF-8 de_DE.UTF-8 es_ES.UTF-8 pt_BR.UTF-8

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${script_dir}/install-actionlint.sh"

# Fail before the tests if packaging, linting, or preview support is absent.
command -v kpackagetool6
command -v plasmawindowed
command -v dbus-run-session
command -v actionlint
python3 -c 'import pyflakes'
