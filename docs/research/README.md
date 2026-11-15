# Version-pinned evidence

These notes record observations at their stated Plasma commit and official CLI
version. They are historical evidence. [Current guides](../README.md) own shipped
behavior; [TODO](../../TODO.md) owns unresolved work and the last reviewed release.
A scoped probe does not replace the full 0.56.2 baseline.

## Release comparisons

Each note states release coverage, verified Linux output, source-only findings,
blockers, and probe limits. The dates below are review dates.

| Official release | Reviewed | Main evidence |
| --- | --- | --- |
| [0.84.0](2026-11-10-macos-parity-0.84.0.md) | 2026-11-10 | Provider setup, session validation, and history discovery |
| [0.83.0](2026-11-01-macos-parity-0.83.0.md) | 2026-11-01 | Authentication inventory and identified schema 2 |
| [0.82.0](2026-10-27-macos-parity-0.82.0.md) | 2026-10-27 | Cookie and credential-clear writers |
| [0.81.0](2026-10-25-macos-parity-0.81.0.md) | 2026-10-25 | Chatbox setup and Linux Auto gate fix |
| [0.80.0](2026-10-23-macos-parity-0.80.0.md) | 2026-10-23 | Soniox, Copilot login, and musl Codex costs |
| [0.79.0](2026-10-21-macos-parity-0.79.0.md) | 2026-10-21 | 0.78.0–0.79.0; cost confidence and severity |
| [0.77.0](2026-10-17-macos-parity-0.77.0.md) | 2026-10-17 | Gemini Auto regression and provider setup |
| [0.76.0](2026-10-15-macos-parity-0.76.0.md) | 2026-10-15 | Concurrent usage order and notice compatibility |
| [0.75.0](2026-10-15-macos-parity-0.75.0.md) | 2026-10-15 | Provider setup and identified-cost semantics |
| [0.74.1](2026-10-14-macos-parity-0.74.1.md) | 2026-10-14 | OpenCode Go confidence and detail severity |
| [0.74.0](2026-10-11-macos-parity-0.74.0.md) | 2026-10-11 | Subscription dates and provider reachability |
| [0.73.0](2026-10-07-macos-parity-0.73.0.md) | 2026-10-07 | Persistent provider source selection |
| [0.72.0](2026-10-05-macos-parity-0.72.0.md) | 2026-10-05 | 0.70.0–0.72.0; Claude manual session and providers |
| [0.69.0](2026-09-29-macos-parity-0.69.0.md) | 2026-09-29 | 0.68.0–0.69.0; Mistral cookie runtime |
| [0.67.0](2026-09-26-macos-parity-0.67.0.md) | 2026-09-26 | Cost periods and provider reachability |
| [0.66.0](2026-09-24-macos-parity-0.66.0.md) | 2026-09-24 | Provider additions and config preservation |
| [0.65.0](2026-09-23-macos-parity-0.65.0.md) | 2026-09-23 | Detail progress, usage values, and unknown windows |
| [0.64.1](2026-09-22-macos-parity-0.64.1.md) | 2026-09-22 | Provider additions and Linux setup reachability |
| [0.63.0](2026-09-21-macos-parity-0.63.0.md) | 2026-09-21 | Pi local history and cost estimates |
| [0.62.0](2026-09-20-macos-parity-0.62.0.md) | 2026-09-20 | Muse history, remote costs, and usage hook |
| [0.61.0](2026-09-18-macos-parity-0.61.0.md) | 2026-09-18 | Provider registry and Grok reset-credit candidate |
| [0.60.5](2026-09-18-macos-parity-0.60.5.md) | 2026-09-18 | Incomplete-request cost counts |
| [0.60.4](2026-09-16-macos-parity-0.60.4.md) | 2026-09-16 | 0.59.0–0.60.4; detail fields and credit availability |
| [0.58.0](2026-09-11-macos-parity-0.58.0.md) | 2026-09-11 | Unchanged Linux contracts |
| [0.57.0](2026-09-09-macos-parity-0.57.0.md) | 2026-09-09 | Automatic balance text and scoped contracts |
| [0.56.2](2026-09-01-macos-parity-0.56.2.md) | 2026-09-01 | Full Linux CLI baseline |

## Focused contracts and decisions

- [Codex 0.75.0 contracts](2026-10-15-codex-contracts-0.75.0.md): partial-priced
  costs, identified-request merge/failure semantics, reset credits, and pricing.
- [Claude 0.76.0 details](2026-10-15-claude-details-0.76.0.md): emitted
  percentage-only resets, pace, and authenticated verification limits.
- [Settings decisions](2026-09-08-settings-experience.md): Plasma settings,
  disclosure, privacy, and refresh decisions compared with macOS 0.56.8.

## Retention

Keep notes that supply pinned contracts or unresolved findings. A successor must
name what it supersedes before old evidence can be retired. New review summaries
and routine unchanged results belong in the PR; add a maintained note for reusable
contract evidence or unresolved decisions, following
[release maintenance](../development.md#upstream-release-maintenance).

The 0.49.1–0.55.0 reports were superseded by the 0.56.2 baseline and remain in Git
history at `ba0a0d8`. Older captures, completed plans, and review logs are available
in [history before the artifact cleanup](https://github.com/Lucenx9/codexbar-plasma/tree/92679f99ce5d5479f4f87edde051fff91e30b91f/docs).
New temporary captures and probe logs go in ignored `dist/review/` or the OS temp
directory.
