# Runtime verification and CLI probes

Use this guide to inspect an installed widget, validate CLI responses, and check
packaging. [Development](development.md) owns checkout setup and delivery;
[Smoke tests](smoke-tests.md) describes isolated graphical captures.

## Runtime verification

After extracting components/delegates or changing their sizing, install or
upgrade the widget and inspect recent logs for QML errors and recursive layouts:

```sh
./install.sh
journalctl --user -u plasma-plasmashell.service --since '2 minutes ago' --no-pager \
  | rg -n 'app\.codexbar|CodexBar|ReferenceError|TypeError|SyntaxError|Detected recursive rearrange|file://.*/app.codexbar'
```

Ignore unrelated widget logs unless they mention `app.codexbar`.
The Plasma 6.7.4 configuration loader passes every configuration key to each
settings page. On the verified KF 6.29 / Qt 6.11.2 stack, this includes defaults
and produces `Setting initial properties failed` for `cfg_*` properties absent
from that page. Check the named key against the page's ownership before treating
this warning as a failed page. Keep default initializers aligned with
`contents/config/main.xml` for loaders that do not inject them.
Do not add dummy `cfg_*` properties to silence these warnings: Plasma saves
declared properties on Apply, which can overwrite unrelated or runtime-owned
state. The ownership checks in `tests/test_ui_settings_pages.py` protect this
boundary. See KDE's [configuration contract](https://develop.kde.org/docs/plasma/widget/configuration/).

For a panel smoke check when plasma-sdk is installed:

```sh
plasmoidviewer -a "$PWD" -l topedge -f horizontal
```

Use `plasmawindowed app.codexbar.plasma` for an installed-widget check.
Restarting/replacing `plasmashell` is a final runtime check, not the edit loop.
Use `qmlprofiler` only after reproducing a performance problem, and keep traces
in ignored `dist/review/` or the OS temp directory.

## CLI response validation

`CliResponse.mjs` owns bounded JSON decoding, redacted diagnostics and exit-code
acceptance for `UsageResponse`, `AccountResponse`, `CostResponse`, and
`SessionResponse`. The response modules retain their domain normalization; QML
owners pass the actual executable-engine exit code and retain process lifecycles,
localization, cache writes and stale-reply handling. Missing or nonnumeric exit
codes fail closed. Fixtures must pass an explicit status too.

Sessions and usage's provider-roster discovery require exit 0. Usage, account
usage and cost also accept the CLI's documented fetch-failure exits 1 through 4
(unexpected, missing binary, parse, timeout) when the consumed record window
contains an identified error whose numeric `error.code` equals the exit code.
The CLI exits with its last failed fetch's code. A provider record explains the
exit with `error.kind` `provider`, `runtime` (for example, `--source web` on
Linux) or no kind (cost); the `cli` record explains it only with `args`. This
preserves healthy siblings, named failed accounts,
missing-token-account empty lists, unsupported-provider account results and
older-CLI argument diagnostics. Cost
argument errors fail the entire scan without replacing its snapshot or context;
returning to a previously successful range can still show its retained data. An
unexplained success/empty JSON payload at those exits cannot replace data. Other
nonzero exits, including widget timeouts and shell launch failures, carry no
replacement payload. Empty stdout remains a failure; the existing usage fallback may recover
it. `IdentifiedTokens.js` has its separate ledger contract and is not migrated.

Verified on 2026-10-16 with the official Linux 0.76.0 archive, SHA-256
`44be9901769d6d4d111cacae8b679aa5c585b26f77afa4f6436b0928206091fd`,
matching the [pinned release evidence](research/2026-10-15-macos-parity-0.76.0.md#probe-method).
The installed executable independently reported 0.76.0. Release probes used
`bwrap --unshare-all --clearenv`, masked host homes/runtime/temp directories,
isolated home/config/cache and a 25-second deadline, without host credentials
or network. Only supported CLI config commands enabled the synthetic Pi case.

| Command / isolated condition | Exit | Observed response |
| --- | --- | --- |
| `usage --provider codex --source oauth --format json --json-only`, no credentials | 1 | Provider error record; no stderr |
| `usage --provider claude --all-accounts --format json --json-only`, no accounts | 1 | Missing-token-accounts provider error |
| `usage --format json --json-only`, default Codex plus enabled Pi | 1 | Codex error and healthy local Pi usage in the same array |
| `cost --provider codex --format json --json-only`, empty history | 0 | Zero-valued cost snapshot |
| `cost --provider cursor --format json --json-only` / unsupported option | 1 | `args` error under provider `cli` |
| `sessions --json-v2` / unsupported option | 0 / 1 | Empty array / empty stdout and diagnostic stderr |
| `config providers --format json --json-only` | 0 | Provider records |

Direct `tst_cli_response.qml` tests cover the exit policies, consumed-record
bounds, mixed results, redaction and payload limits. The production controller
fixtures cover failed valid JSON, retention and loading release, roster rejection,
scoped usage failures, and the pre-existing nonce/timeout/stale-result behavior.

## CLI probes and packaging

Codex account selection was rechecked on 2026-10-18 with Linux CLI 0.76.0
(the installed executable matched the official binary used above). With host
homes, runtime, credentials, and network isolated by `bwrap`,
`usage --provider codex --source oauth --account synthetic-account --format json
--json-only` exits 1 with an `args` error, "codex does not support token accounts".
Replacing `--account synthetic-account` with `--all-accounts` reaches the
provider fetch and returns the expected missing-credentials error instead.
The same isolation with `usage --provider gemini --all-accounts --format json
--json-only` exits 1 with an `args` error under provider `cli`, "gemini does
not support token accounts."; `AccountResponse.js` reports it as `unsupported`.
The released [selection validation](https://github.com/steipete/CodexBar/blob/v0.76.0/Sources/CodexBarCLI/TokenAccountCLI.swift)
and [usage collector](https://github.com/steipete/CodexBar/blob/v0.76.0/Sources/CodexBarCLI/CLIUsageCommand.swift)
explain that distinction. Synthetic controller tests cover multiple returned
account records; this probe does not establish authenticated multi-account
availability or add a Linux login-switching action.

`config/ProviderSource.js` plans allowlisted source-mode writes and validates
matching provider/source result records. `config/ProviderSavedSources.js` owns
the saved-source map: it projects the normalized, redacted
`config dump --format json --json-only` reply into provider source enums only.
The dump contract was verified with Linux CLI 0.83.0: `providers[].id` identifies
providers; a known `source` selects the saved mode, and an absent `source` means
Automatic. Dump entries match the exact inventory provider ID, so retained
alias-like IDs do not collide. Malformed/unknown modes and duplicate exact IDs
stay unknown; credential fields are discarded. No raw config file is read or edited.
The Providers page owns this independent, bounded read on open/reload. It does
not fetch provider usage. Read results carry the provider-config revision;
a reply predating a completed write is discarded and reread. Selection changes
clear the draft, background reads preserve a different choice, and selecting the
confirmed mode clears the draft. Reloads keep the last confirmation visible and
block source writes until the read completes. Failed reads offer Reload without
inventing Automatic; failed writes preserve the draft and prior confirmation.

Available modes come from normalized authentication metadata, with the five legacy modes only when that metadata is
absent. The page maps combo-box indexes through that same per-provider list and
clears an unsaved selection when its mode is no longer offered. The Providers
page owns the CLI 0.73.0 capability gate, execution, deadlines, revision writes and
diagnostic invalidation; `ProviderOperations.js` owns pending state and deferred
reload decisions. `tests/tst_provider_source.qml` covers its pure boundary;
`tests/test_provider_source.py` executes the production page handlers for
clearing, failure, cancellation, timeout, command retirement, selection changes,
serialization of source writes with provider-list reloads, and exclusion while
a descriptor field or action is pending for the same provider.
`tst_provider_authentication.qml` covers malformed metadata, bounds, credential
redaction, immutable projections, legacy fallback and the Copilot command
allowlist. The `settings-providers-auth` and `settings-providers-auth-legacy`
smoke scenarios execute an API source write with the new and legacy option
orders, verify the saved selection survives a reload, check the key gate and
render the read-only hints. The `settings-providers-keys-soniox` and `settings-providers-keys-chatbox` scenarios
check all three setup gates and documentation links. Each checks its target
action and visible guidance: Soniox organization keys or Chatbox license keys.
The Chatbox scenario also checks its localized license-key label.
`test_secret_prompt_lifecycle.py` executes
each new provider prompt with synthetic dialog/CLI tools to verify the
credential travels only through stdin.

The widget expects a working `codexbar`. Probe the selected official version
when investigating a contract; keep raw account output out of logs and commits.

```sh
codexbar usage --format json --json-only
codexbar usage --provider codex --status --format json --json-only
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
codexbar config providers --format json --json-only
codexbar sessions --json-v2
```

For packaging changes, run `make package` after `make check`.
Packaging needs Python 3 and GNU gettext. It compiles `po/*.po` to
`contents/locale/<language>/LC_MESSAGES/plasma_applet_app.codexbar.plasma.mo`
and includes the catalogs in the archive. Generated `.mo` files stay out of Git.
For string extraction and catalog updates, follow [Translations](translations.md).

The `PACKAGE_FILES` list in the Makefile defines the archive contents, including
README screenshots. Publishing the resulting `dist/codexbar-plasma.plasmoid`
in a GitHub Release requires user authorization.
If a KDE Store channel is introduced, use its KNewStuff/Discover update path for
that channel. WidgetKit, Sparkle, Keychain/Full Disk Access UI, and macOS app
implementation code remain outside this standalone Plasma repository.
