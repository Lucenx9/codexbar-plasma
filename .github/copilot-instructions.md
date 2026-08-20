# Copilot instructions

`AGENTS.md` is the canonical repository policy. Read and follow it in full; it
takes precedence over this file if the instructions ever differ.

When reviewing pull requests:

- Treat changes outside the standalone Plasma applet as out of scope unless the
  request explicitly authorizes an upstream CLI change.
- Focus reviews on correctness, security, CLI-contract drift, lifecycle races,
  compatibility, and missing tests. Avoid style-only comments unless they expose
  a concrete maintenance or correctness risk.
- Check untrusted CLI/provider data at every boundary and verify that secrets
  never reach command lines, logs, UI text, fixtures, or diagnostics.
- Follow the verification requirements in `AGENTS.md`, including `make check`
  where applicable. Cloud and CI runners lack complete Plasma/Kirigami QML
  modules, so report that limitation rather than presenting relaxed import/type
  diagnostics as full coverage. Full import resolution requires a Plasma desktop.
