# Copilot instructions

Use `AGENTS.md` as the complete repository policy. Apply these review-focused
rules first when working on pull requests.

- This repository implements only the standalone KDE Plasma widget. Treat the
  macOS CodexBar app as a read-only behavior reference, never as code to port.
- Keep provider logic, authentication, configuration parsing, and JSON contract
  ownership in the official `codexbar` CLI. QML may consume only documented CLI
  output and supported commands.
- Treat CLI output, cached data, URLs, labels, and error text as untrusted.
  Validate shapes, types, bounds, command allowlists, and URL schemes before use.
- Never place secrets in command-line arguments, logs, UI text, fixtures, or
  diagnostics. Preserve the repository's descriptor-based secret input flow.
- Preserve nonce, timeout, disconnect, retry, and stale-result protections around
  every external process. Late results must not replace newer state.
- Preserve healthy provider data when one provider or optional enrichment fails.
- Keep presentation QML thin. Put parsing, normalization, decision, and
  transition logic in focused JavaScript modules with direct Qt tests.
- Prefer generic CLI-described fields and graceful handling of unknown providers
  over provider-specific QML branches.
- Add the cheapest regression test that proves each behavior change. Update
  parity documentation when a parity decision changes.
- Focus reviews on correctness, security, CLI-contract drift, lifecycle races,
  compatibility, and missing tests. Avoid style-only comments unless they expose
  a concrete maintenance or correctness risk.
- Before completing a change, run the narrow relevant checks. In the cloud
  agent, run `scripts/test_qml_logic.sh` and applicable static scripts; the KDE
  neon CI is the source of truth for the complete `make check` lint.
