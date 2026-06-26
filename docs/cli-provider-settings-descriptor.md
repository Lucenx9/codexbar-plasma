# CLI Provider Settings Descriptor

This document defines the CLI contract Plasma needs before it can render real
provider settings or onboarding flows without duplicating macOS Swift logic in
QML.

The Plasma widget should continue to show only redacted diagnostics and CLI
command hints until the upstream `codexbar` CLI exposes this contract.

## Command

```sh
codexbar config providers --descriptors --format json --json-only
```

The command returns the normal provider list plus a provider-specific
descriptor. The descriptor is declarative: it names fields and actions, but the
CLI remains the only component that knows how to read, validate, write, import,
or redact provider settings.

## Top-level shape

```json
[
  {
    "provider": "openrouter",
    "displayName": "OpenRouter",
    "enabled": true,
    "descriptor": {
      "schemaVersion": 1,
      "fields": [],
      "actions": []
    }
  }
]
```

`schemaVersion` must be incremented for incompatible changes. Plasma should
ignore descriptors with an unknown major schema and keep showing CLI command
hints.

## Fields

Fields are settings the frontend can display or edit. Field order is display
order.

```json
{
  "id": "apiKey",
  "kind": "secret",
  "title": "API key",
  "description": "Stored by codexbar. Paste your OpenRouter API key.",
  "redactedValue": "sk-...abcd",
  "required": true,
  "writeCommand": [
    "codexbar",
    "config",
    "set",
    "--provider",
    "openrouter",
    "--field",
    "apiKey",
    "--stdin",
    "--format",
    "json",
    "--json-only"
  ]
}
```

Supported field kinds:

- `"kind": "text"`: short non-secret string, such as a base URL or workspace id.
- `"kind": "secret"`: secret input, always written through stdin.
- `"kind": "enum"`: one of a stable option list.
- `"kind": "boolean"`: checkbox/toggle.
- `"kind": "number"`: bounded numeric setting.
- `"kind": "command"`: read-only row that invokes an action instead of editing
  a value.

Enum fields include `options`:

```json
{
  "id": "sourceMode",
  "kind": "enum",
  "title": "Source",
  "value": "auto",
  "options": [
    { "id": "auto", "title": "Automatic" },
    { "id": "api", "title": "API key" },
    { "id": "web", "title": "Browser cookies" }
  ],
  "writeCommand": [
    "codexbar",
    "config",
    "set",
    "--provider",
    "amp",
    "--field",
    "sourceMode",
    "--value",
    "{value}",
    "--format",
    "json",
    "--json-only"
  ]
}
```

The CLI must validate `{value}`. Plasma must not infer valid enum values from
provider names or config files.

## Actions

Actions are provider setup flows the CLI knows how to perform.

```json
{
  "id": "refreshCookies",
  "kind": "command",
  "title": "Refresh browser cookies",
  "description": "Import browser cookies for the selected provider.",
  "command": [
    "codexbar",
    "config",
    "action",
    "--provider",
    "codex",
    "--action",
    "refreshCookies",
    "--format",
    "json",
    "--json-only"
  ]
}
```

Useful action categories:

- browser-cookie import
- manual cookie save
- API key save or clear
- OAuth/device-flow handoff
- local app/session probe
- token-account add/edit/remove
- provider diagnostics refresh
- open docs/dashboard/login URL

Actions must report structured JSON with `status`, optional `message`, and
optional refreshed `descriptor`.

## Redaction and safety

Do not expose raw secrets.

Rules for the CLI:

- Secret fields must return only `redactedValue`, never raw values.
- Writes for secrets must use stdin, not command-line arguments.
- Descriptors must not include browser cookie values, bearer tokens, API keys,
  account IDs that are not already user-visible, or raw diagnostic responses.
- Error messages should be bounded and safe to store in user config.
- Commands must be local `codexbar` commands, not remote shell snippets.

Rules for Plasma:

- Treat descriptor JSON as a contract, not as raw config.
- Render only supported field kinds.
- Use `writeCommand` and action `command` exactly as arrays of argv-like
  tokens; quote each token when using Plasma's executable data source.
- Keep secret fields write-only except for `redactedValue`.
- Fall back to current CLI command hints when a descriptor is missing,
  unsupported, or invalid.

## Plasma renderer rules

The first Plasma implementation should be deliberately small:

- Render fields in the Providers page below the redacted diagnostics summary.
- Use native controls: text field, password field, checkbox, combo box, spin box,
  and buttons.
- Disable controls while their command is in flight.
- After a successful write/action, reload `codexbar config providers
  --descriptors --format json --json-only`.
- Keep existing provider enable/disable behavior separate from descriptor
  fields.
- Do not add provider-specific QML branches for individual settings.

## Example descriptor

```json
{
  "provider": "amp",
  "displayName": "Amp",
  "enabled": true,
  "descriptor": {
    "schemaVersion": 1,
    "fields": [
      {
        "id": "sourceMode",
        "kind": "enum",
        "title": "Source",
        "value": "auto",
        "options": [
          { "id": "auto", "title": "Automatic" },
          { "id": "api", "title": "API key" },
          { "id": "web", "title": "Browser cookies" }
        ],
        "writeCommand": [
          "codexbar",
          "config",
          "set",
          "--provider",
          "amp",
          "--field",
          "sourceMode",
          "--value",
          "{value}",
          "--format",
          "json",
          "--json-only"
        ]
      },
      {
        "id": "apiKey",
        "kind": "secret",
        "title": "API key",
        "redactedValue": "amp_...7890",
        "writeCommand": [
          "codexbar",
          "config",
          "set",
          "--provider",
          "amp",
          "--field",
          "apiKey",
          "--stdin",
          "--format",
          "json",
          "--json-only"
        ]
      }
    ],
    "actions": [
      {
        "id": "refreshCookies",
        "kind": "command",
        "title": "Refresh browser cookies",
        "command": [
          "codexbar",
          "config",
          "action",
          "--provider",
          "amp",
          "--action",
          "refreshCookies",
          "--format",
          "json",
          "--json-only"
        ]
      }
    ]
  }
}
```
