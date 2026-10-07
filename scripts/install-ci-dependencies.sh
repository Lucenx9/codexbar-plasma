#!/usr/bin/env bash
set -euo pipefail

# Run only while building the disposable Ubuntu/Neon CI image, as root.
export DEBIAN_FRONTEND=noninteractive
# Consumers use the resulting image by digest, without refreshing APT. A build
# needs complete authenticated indexes; bound archive failures instead of
# silently building from a partial refresh.
apt-get -o APT::Update::Error-Mode=any -o Acquire::Retries=3 \
  -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update
apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 \
  -o Acquire::https::Timeout=30 install -y --no-install-recommends \
  make cmake git curl ca-certificates gettext jq libxml2-utils shellcheck \
  python3-pyflakes \
  qt6-base-dev-tools qt6-declarative-dev-tools qml6-module-qttest \
  qml6-module-qtqml qml6-module-qtqml-models qml6-module-qtqml-workerscript \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-dialogs \
  qml6-module-qtquick-layouts qml6-module-qtquick-templates qml6-module-qtquick-window \
  plasma-workspace libplasma6 plasma5support kf6-kpackage \
  kf6-kcmutils kf6-kirigami kf6-qqc2-desktop-style kf6-kdeclarative \
  libgl1-mesa-dri libegl-mesa0 libglx-mesa0 \
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
