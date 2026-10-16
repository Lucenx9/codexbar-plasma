#!/usr/bin/env bash

# Parse the complete bootstrap before executing a streamed download.
{
  set -euo pipefail

  no_input=false
  for argument in "$@"; do
    case "$argument" in
      --no-input) no_input=true ;;
      --with-cli) ;;
      -h|--help)
        printf '%s\n' 'usage: bash setup.sh [--with-cli] [--no-input]' \
          'Installs the latest stable widget release for the current user.' \
          '--with-cli also installs/reuses the private CLI; select it in widget settings.' \
          '--no-input skips optional prompts and never restarts Plasma.'
        exit 0
        ;;
      *) printf '%s\n' 'Unsupported setup option. Use --help for supported options.' >&2; exit 2 ;;
    esac
  done

  for required_command in curl bash; do
    command -v "$required_command" >/dev/null 2>&1 || {
      printf 'Missing required command: %s\n' "$required_command" >&2
      exit 127
    }
  done

  if ! installer=$(curl --fail --location --show-error --silent \
    --connect-timeout 10 --max-time 30 --max-filesize 65536 --max-redirs 5 \
    --proto '=https' --proto-redir '=https' \
    https://raw.githubusercontent.com/Lucenx9/codexbar-plasma/main/scripts/update-widget.sh); then
    printf '%s\n' 'Could not download the installer; setup stopped.' >&2
    exit 1
  fi
  if [[ "$installer" != *$'\n# codexbar-plasma-updater-end' ]]; then
    printf '%s\n' 'Installer download is incomplete; setup stopped.' >&2
    exit 1
  fi

  if [[ "$no_input" == true ]]; then
    exec bash -c "$installer" codexbar-setup --setup "$@" </dev/null
  elif [[ -t 0 ]]; then
    exec bash -c "$installer" codexbar-setup --setup "$@"
  elif { true </dev/tty; } 2>/dev/null; then
    exec bash -c "$installer" codexbar-setup --setup "$@" </dev/tty
  else
    exec bash -c "$installer" codexbar-setup --setup "$@" </dev/null
  fi
}
