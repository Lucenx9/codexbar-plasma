#!/usr/bin/env bash
set -euo pipefail

# Run only in the disposable KDE neon CI container, as root.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  make cmake git ca-certificates gettext jq libxml2-utils shellcheck \
  qt6-base-dev-tools qt6-declarative-dev-tools qml6-module-qttest \
  plasma-workspace libplasma6 plasma5support kf6-kpackage \
  kf6-kcmutils kf6-kirigami kf6-qqc2-desktop-style \
  dbus-x11 xvfb xauth fonts-noto-core breeze breeze-icon-theme locales

locale-gen it_IT.UTF-8 fr_FR.UTF-8 de_DE.UTF-8 es_ES.UTF-8 pt_BR.UTF-8

# Fail before the tests if packaging or preview support is absent.
command -v kpackagetool6
command -v plasmawindowed
command -v dbus-run-session
