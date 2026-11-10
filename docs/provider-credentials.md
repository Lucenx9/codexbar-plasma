# Provider credential commands

Plasma uses released official CLI writers; it never reads or edits provider
configuration or implements authentication. These actions are available in
**Providers**, independently of the proposed generic settings descriptor.

## Verified contracts

The installed `/usr/local/bin/codexbar` reported **0.83.0** on 2026-11-06.
An isolated `bwrap --unshare-all` probe hid host homes, runtime, temporary files,
network and IPC, cleared the environment, and used a temporary home/config/cache.
The official binary accepted a synthetic OpenDesign cookie over stdin, returned
`{provider, enabled, configPath}`, then cleared it with a result containing
`cleared: ["cookieHeader"]`. Offline Copilot login emitted one `failed` event
and exited 1. No signed-in authorization or quota response was measured.

Earlier probes establish version boundaries and Linux fetch behavior:

- [0.82.0 cookie and clear writers](research/2026-10-27-macos-parity-0.82.0.md#linux-cli-contract-changes)
  are rejected by 0.81.0. `set-cookie --provider <id> --stdin` enables the
  provider and selects manual-cookie mode; it preserves the source override.
  `clear-credential --provider <id>` removes both `apiKey` and `cookieHeader`;
  its `cleared` list can be empty. Enablement, sources and token accounts remain.
- [0.83.0 OpenDesign and authentication inventory](research/2026-11-01-macos-parity-0.83.0.md#linux-cli-contract-changes)
  add OpenDesign to the cookie allowlist. Advertised cookie support can restrict
  an action but cannot authorize an unverified Linux fetch.
- [0.80.0 Copilot login](research/2026-10-23-macos-parity-0.80.0.md#linux-cli-contract-changes)
  accepts only `config login --provider copilot --json`. The exact
  [0.83.0 command source](https://github.com/steipete/CodexBar/blob/348e2fa8d36ae8e452739ca07a79e83ab9d25e98/Sources/CodexBarCLI/CLIConfigLoginCommand.swift)
  emits newline-delimited `authorization_pending` (`verificationURI`,
  `userCode`, `expiresIn`), `authorized`, and `failed` events. Signals cancel
  its task; a concurrent config modification fails with a conflict instead
  of overwriting the change. Authorization stores a token account, enables
  Copilot and clears its single API key. The source emits pending once, before
  polling, and authorized only after saving configuration. Tokens are never emitted.
- [0.84.0 Console session import](research/2026-11-10-macos-parity-0.84.0.md#linux-cli-contract-changes)
  separately accepts `config login --provider claudeplatform --stdin --json`.
  Isolated Linux probes verify malformed-input rejection and a failed synthetic
  validation without a config write. Successful authenticated authorization
  remains unverified. Plasma offers **Validate and import session…** with CLI
  0.84.0 or later alongside the existing **Set cookie…** action.
  The 0.84.0 inventory still names only Copilot's login command.

The existing bounded `--version` probe gates all actions. Unknown versions,
failed probes and matching prereleases fail closed. Same-executable reloads
retain visible controls but disable writes until list/version checks finish.
Changing executables resets capabilities and retires outstanding requests.
The pure `config/ProviderCapabilities.js` module centralizes the existing
API-key version gates and legacy provider allowlist. The page still owns the
probe lifecycle and publishes its results; inventory authentication metadata
can restrict an action but cannot add an unverified writer.

## Linux cookie allowlist

CLI 0.82.0 or later: Claude, Claude Platform, Command Code, Cursor, Mistral,
Ollama, OpenCode Go, Parallel, Raycast, TinyApi, Trae CN, TypeSafe and X API.
OpenDesign additionally requires 0.83.0. These 14 providers reached their
fetch or provider-specific cookie validation under Auto in the pinned probes;
this does not establish successful authenticated usage.

The [0.84.0 probe](research/2026-11-10-macos-parity-0.84.0.md#linux-cli-contract-changes)
also verifies WorkBuddy's stdin cookie writer and Linux Web dispatch. Its
Plasma action requires CLI 0.84.0 or later, bringing the allowlist to 15 providers.
Its optional matching User-Agent has no supported writer; successful
authenticated billing was not measured.

Gemini remains excluded by product decision until its Web quota labels are
verified. Its cookie reaches a fetch only with Web; Auto selects CLI OAuth.
Helmcode, Abacus AI, DeepSeek, Alibaba and Manus remain macOS-only. Kimi and
Copilot had no available cookie fetch strategy. Other accepted cookie writers
remain unverified and cannot acquire an action from inventory metadata alone.

Credential clearing has no provider allowlist: the official CLI validates any
listed provider. Confirmation explains that token accounts and environment
variables are outside its scope. It does not sign out a Copilot token account.

## Validated Console session import

The explicit Claude Platform action is separately version-gated at 0.84.0 and
requires cookie support when inventory authentication metadata is present.
Only the exact `config login --provider claudeplatform --stdin --json` command
is allowed as a secret descriptor; generic field writers and actions reject it.
`promptDescriptorSecret` reads the cookie inside the native password-prompt
process and pipes it to the helper. The helper invokes the official login command
with stdin, drains at most 64 KiB, suppresses stderr and returns only a semantic
result. No cookie enters QML, argv, files or diagnostics.

Unlike Copilot, this command has no pending device-code event. Exactly one
`authorized` record without an error and CLI exit 0 constitutes success. Failed,
malformed, repeated or oversized records fail closed. The pinned conflict error
maps to a localized retry message; other CLI prose is discarded. Input cancellation
performs no write. Separate prompt and CLI deadlines, CLI process-group cleanup,
pending locks, executable signatures and command nonces reuse the cookie path.
Repeated termination signals cannot interrupt the helper's process-group cleanup.
Retired or timed-out replies cannot change enablement or refresh revisions.
Synthetic process and QML tests cover successful import, validation failure,
conflict, cancellation, timeout, stale replies and stdin-only secret handling.

SiliconFlow and Tripo single-key prompts also require 0.84.0, through the existing
API-key writer. Dedicated icons, brand colors, fallback names and
documentation/dashboard links remain available
without inventory metadata. SiliconFlow's regional origin and WorkBuddy's
User-Agent remain [CLI writer blockers](../TODO.md#provider-settings).

## Private native login prompt

The executable engine delivers output on exit, so `scripts/provider-auth.py`
bridges the official event stream to a native KDE text dialog. The helper has
no provider HTTP client and never reads config. The page owns request creation,
localized text, cancellation, nonces, deadlines and final configuration effects.
Inside the helper, bounded stream framing and pure event decisions are separate
from the process loop that opens the dialog and applies cancellation and expiry.

Pending events accept a bounded HTTPS `/login/device` address (including GitHub
Enterprise hosts), an eight-character device code with a hyphen, and an integer
expiry of 1–900 seconds. Invalid, repeated, truncated, oversized and out-of-order
events fail closed. A successful terminal event also requires CLI exit 0.
Raw stderr and failure prose never reach QML. A known conflict receives a
localized retry message by matching the pinned 0.83.0 error text
`Config changed during login. Please try again.`; the CLI supplies no typed
conflict code. Reworded or other errors safely remain generic.

The dialog receives the URI and code over stdin, keeping them out of arguments,
files, logs and Plasma's executable cache. It does not open a URL automatically.
Pressing OK dismisses the dialog and continues waiting in settings; the window
close button or the settings cancel action cancels. Cancellation, expiry,
settings destruction or loss of the
engine-owned timeout process stops the CLI and dialog groups, with bounded
TERM/KILL cleanup. The pending phase honors the CLI expiry; startup is bounded
to 60 seconds and final exit to five seconds, within the page's 970-second bound.
Disconnecting an executable source alone does not stop it immediately. The page
therefore sends an explicit cancellation request through an singleton-owned,
short-lived DataSource whose execution and cleanup survive page destruction. The helper checks a private
request marker every 100 ms; markers contain no credentials or events, also
cover cancellation before startup, and are removed on completion. Late markers
are pruned after 20 minutes on the next request. Each login has a different
request ID, so old cancellations cannot affect a newer login.
Cookie entry retains the existing separate input and save timeouts.
Cookie saves and credential clears run the CLI in its own process group and
retire that group on completion, timeout, or interruption, including descendants
of a CLI wrapper. The helper watches its parent while draining output and waiting
for CLI exit, so loss of the timeout owner also stops the group. Cancellation
escapes the selector's interrupted-system-call handling before cleanup runs.

Only safe completion records return to the page. Successful writes retire old
diagnostics and increment the existing configuration revision so usage refreshes.
Late replies from a cancelled or replaced request cannot commit. API-key setup
and the read-only CLI command hints remain available.

See [Development](development.md#provider-credential-commands) for tests and
[Usage](usage.md#providers-and-accounts) for user-facing behavior and requirements.
