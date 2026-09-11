# Security policy

## Scope

This repository contains the KDE Plasma 6 widget. Report issues here when they
affect the widget itself: its QML and JavaScript, the handling of `codexbar`
output and configuration, the install, update, and packaging scripts, the data
the widget caches, logs, and displays, and the widget's own secret prompt and
stdin handoff, including any exposure through command lines, logs, or the
user interface.

Provider authentication, credential storage, and quota APIs belong to the
upstream [CodexBar CLI](https://github.com/steipete/CodexBar); report a flaw in
how the CLI obtains, stores, or transmits credentials to that project. A leak
caused by the widget's own handling of a secret stays in scope here. If you are
unsure which side is affected, report it here and it will be routed.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest [release](https://github.com/Lucenx9/codexbar-plasma/releases) | Yes |
| Any earlier release | No |

Fixes ship in a new release. Update through the widget's update settings or
`make update`, as described in [the README](README.md#update).

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/Lucenx9/codexbar-plasma/security/advisories/new).
Do not open a public issue, discussion, or pull request for a suspected
vulnerability.

Include:

- The widget version, `codexbar --version`, your Plasma and Qt versions, and
  your distribution.
- Reproduction steps or a proof of concept, and the impact you observed.
- Relevant log excerpts, with account identifiers, paths, and personal data
  redacted.

Never include real API keys, tokens, cookies, or session data in a report.
Describe the credential and where it leaked instead of pasting it.

## What to expect

This is a small volunteer-maintained project, so responses are best effort:
an acknowledgement within 7 days and an assessment within 30 days. Accepted
reports are fixed through a GitHub security advisory and released with a
`Security` entry in [the changelog](CHANGELOG.md). Reporters are credited unless
they ask not to be. Please keep the report private until a fix is released.
