# Claude usage detail contract at CLI 0.76.0

Checked 2026-10-15 against Plasma `e215bd1`, after PR #526 recognized
`percentOnly` but retained the earlier suppression of all non-exact quota
details. The official Linux executable discovered with `command -v codexbar`
reported `CodexBar 0.76.0`. Source references below are pinned to
[`v0.76.0`](https://github.com/steipete/CodexBar/releases/tag/v0.76.0), commit
`2d8b1409a1649dce60f3610ebe4eab52b92545de`.

## Runtime evidence

Read-only `usage --provider claude --format json --json-only` returned
`source: "claude"` and `usage.dataConfidence: "percentOnly"`. Its primary window
had a percentage but no reset; its secondary window had a percentage and a reset
timestamp. No `pace` object was emitted. A separate explicit `--source oauth`
probe succeeded with the same reset availability and no pace; its confidence
field was absent. These observations establish availability, not general
forecast behavior. No identity, credential, or raw error output is retained.
Provider source configuration and authentication were not changed.

To test a non-exhausted window without consuming an account's quota, the same
official executable was run with `--source cli` and `CLAUDE_CLI_PATH` pointing to
a synthetic interactive CLI. A private temporary home, XDG directories, Claude
config directory, and absent CodexBar config path isolated it from host accounts.
The environment contained only those paths, a system PATH, language and UTC.
The fake CLI answered version/auth-status probes and read `/usage` and `/status`
from stdin. Its usage panel contained a 30%-used session without a reset and an
80%-used weekly window resetting four days later. It supplied no pace values.

The official CLI computed and emitted this allowlisted synthetic excerpt:

```json
{
  "source": "claude",
  "usage": {
    "dataConfidence": "percentOnly",
    "secondary": {
      "usedPercent": 80,
      "windowMinutes": 10080,
      "resetsAt": "2026-10-19T20:26:00Z"
    }
  },
  "pace": {
    "secondary": {
      "stage": "farAhead",
      "deltaPercent": 37,
      "expectedUsedPercent": 43,
      "willLastToReset": false,
      "etaSeconds": 64805
    }
  }
}
```

This verifies that `percentOnly` can coexist with both reset dates and structured
pace in released Linux output. The frontend must preserve those supplied fields.
It must not turn missing fields into inferred reset dates or forecasts.

## Source explanation and frontend decision

The pinned [CLI renderer](https://github.com/steipete/CodexBar/blob/v0.76.0/Sources/CodexBarCLI/CLIRenderer.swift)
returns no pace when the window's remaining percentage is zero. That explains the
absent weekly forecast in the separately observed exhausted window; an explicit
OAuth probe alone does not guarantee additional forecasts. The pinned
[provider capability](https://github.com/steipete/CodexBar/blob/v0.76.0/Sources/CodexBarCore/Providers/ProviderDescriptor.swift)
does not reject `percentOnly` as an estimated reading. These source observations
explain the emitted contract; they do not replace its runtime evidence.

Plasma separates presentation from automation: `canPresentQuotaDetails` admits
explicit percentage-only resets and forecasts, while `authoritativeQuota`
continues to protect notifications, quota warning colors, conditional panel
visibility, automatic provider selection and AI Insights quota facts. Estimated,
unknown and malformed confidence retain their existing suppression. Reset dates
survive privacy projection and the quota cache; forecasts follow the existing
live/retained snapshot lifecycle and are not added to the disk quota cache.
Privacy forwards only bounded semantic forecast parts, excluding prose
fallbacks and unknown fields. QML localizes these parts after projection, so the
popup's private forecast remains visible and advances from its observation time.
