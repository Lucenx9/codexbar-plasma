# Documentation

Start with the guide for your task. Current behavior lives in the guides;
[TODO](../TODO.md) owns remaining Linux/Plasma parity work. Historical findings
are evidence for a specific version, not a description of today's widget.

## Maintained references

| Need | Read |
| --- | --- |
| Install, update, or report a problem | [Project README](../README.md) |
| Find installation and usage docs as an AI agent | [Agent documentation index](../llms.txt) |
| Use the panel, popup, providers, history, or settings | [Usage](usage.md) |
| Contribute or report a vulnerability | [Contributing](../CONTRIBUTING.md), [security policy](../SECURITY.md) |
| Change the UI | [Design](../DESIGN.md) |
| Build, deliver a PR, or maintain the repository | [Development](development.md) |
| Find ownership and implementation invariants | [Implementation](implementation.md) |
| Choose checks or maintain CI | [Testing](testing.md) |
| Capture isolated UI scenarios | [Smoke tests](smoke-tests.md) |
| Inspect an installed widget or probe the CLI | [Runtime verification](runtime-verification.md) |
| Translate strings | [Translations](translations.md) |
| Check delivered changes or remaining work | [Changelog](../CHANGELOG.md), [TODO](../TODO.md) |
| Follow agent policy | [AGENTS.md](../AGENTS.md) |
| Publish a release or review upstream | [Release skill](../.claude/skills/release/SKILL.md), [parity-review skill](../.claude/skills/parity-review/SKILL.md) |

## Contracts and decisions

| Topic | Reference |
| --- | --- |
| CLI credential commands, version gates, and verified cookie support | [Provider credentials](provider-credentials.md) |
| Daily cost/model data, confidence, currency, and identified Codex tokens | [Cost history](cost-history.md) |
| AI snapshot, private helper, credentials, and scheduling | [AI Insights](ai-insights.md) |
| Panel spend budgets, automatic quota priority, and monthly allowance | [Panel decisions and CLI 0.84.0 evidence](panel-budget-and-monthly-allowance.md) |
| Proposed generic provider settings, **not a shipped contract** | [Descriptor proposal](cli-provider-settings-descriptor.md) |
| Version-pinned CLI probes and release comparisons | [Research index](research/README.md) |

## Product screenshots

All captures are synthetic. Replace the relevant image when behavior changes;
temporary before/after captures belong in ignored `dist/review/`. Rebuild the
README tour from the `readme-` smoke scenarios using
[runtime verification](runtime-verification.md#runtime-verification).

| Purpose | Assets |
| --- | --- |
| Popup tour and main views | [Tour](codexbar-plasma-tour.gif), [Overview](codexbar-plasma-overview.png), [provider details](codexbar-plasma-codex.png), [Sessions](codexbar-plasma-sessions.png) |
| Usage and history | [Usage & Spend](codexbar-plasma-usage-spend.png), [models](codexbar-plasma-models.png), [daily activity](codexbar-plasma-daily-activity.png), [chart hover](codexbar-plasma-chart-hover.gif), [identified tokens](codexbar-plasma-identified-tokens.png) |
| Provider detail states | [Hidden rows](codexbar-plasma-hidden-usage-rows.png), [detail severity](codexbar-plasma-detail-severity.png) |
| Provider setup | [Chatbox key](codexbar-plasma-chatbox-key-setup.png), [authentication](codexbar-plasma-provider-authentication.png) |
| Usage sharing | [Exported card](codexbar-plasma-share.png), [sharing window](codexbar-plasma-share-window.png) |
| Panel appearances | [Provider colors](codexbar-plasma-panel-standard.png), [Monochrome](codexbar-plasma-panel-minimal.png), [rings](codexbar-plasma-panel-rings.png), [usage text](codexbar-plasma-panel-information.png) |
| Store artwork | [512px icon](codexbar-plasma-store-icon.png), [editable SVG](codexbar-plasma-store-icon.svg) |

## Maintaining this index

Every document and image under `docs/` must appear here or in a linked `README.md`
index. The documentation check follows linked indexes and rejects unindexed files.
Keep entry descriptions short; the destination owns its content and status.
Follow [documentation maintenance](development.md#documentation-and-work-tracking)
when adding, replacing, or retiring material.
