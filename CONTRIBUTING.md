# Contributing

Thanks for helping improve CodexBar Plasma. This repository contains the
standalone KDE Plasma 6 widget only. Provider logic, authentication, config
parsing, and quota fetching belong to the upstream
[CodexBar CLI](https://github.com/steipete/CodexBar); the widget consumes its
released Linux contracts.

## Report a problem or propose a change

- Widget bugs and ideas: [open an issue](https://github.com/Lucenx9/codexbar-plasma/issues/new/choose)
  and complete the form. Include the widget, Plasma, and `codexbar` versions
  plus your distribution, as described in
  [Report a problem](README.md#report-a-problem).
- Provider setup, login, or quota data that the CLI itself gets wrong:
  report it [upstream](https://github.com/steipete/CodexBar/issues).
- Open questions and usage help:
  [Discussions](https://github.com/Lucenx9/codexbar-plasma/discussions).
- Suspected vulnerabilities: follow the [security policy](SECURITY.md) instead
  of opening a public issue.

Never post credentials, tokens, cookies, or unredacted account data in issues,
logs, or screenshots.

Small fixes can go straight to a pull request. For new settings, new panel
behavior, or anything that needs a CLI contract, open an issue first so the
scope and the upstream dependency can be agreed before you write code.

## Set up a checkout

Install the runtime requirements from [the README](README.md#requirements) plus
`make`, Python 3, GNU gettext, and the Qt 6 QML lint/test tools. Then:

```sh
git clone https://github.com/Lucenx9/codexbar-plasma.git
cd codexbar-plasma
make check
make install
```

[Development](docs/development.md) covers dependencies, code ownership, QML
conventions, regression checks, packaging, and runtime verification.
[AGENTS.md](AGENTS.md) states the project boundaries and required checks that
apply to every change, human or agent. To add or improve a language, follow the
[translation guide](docs/translations.md).

## Pull requests

1. Branch from `main` and keep the change focused on one purpose.
2. Keep user-facing strings in `i18n`/`i18np`, and keep provider or auth logic
   out of QML.
3. Update the affected documentation, [CHANGELOG.md](CHANGELOG.md) under
   `Unreleased` for user-visible changes, and [TODO.md](TODO.md) entries in the
   same change.
4. Run `make check` before pushing, and `make package` for packaging changes.
   Report failures, skips, and unavailable tools instead of omitting them.
5. Use a [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
   title, such as `fix(accounts): release stale requests`. The `pr-title` check
   enforces it.
6. Complete every section of the
   [pull request template](.github/pull_request_template.md), including the
   verification results, and keep it current when the diff changes.

CI runs QML lint and QtTests, ShellCheck, Python and static checks, AppStream
validation, and popup smoke tests. Own your PR's checks through their final
result; see [delivery and CI](docs/development.md#delivery-and-ci).

By contributing, you agree that your work is licensed under the
[MIT License](LICENSE).
