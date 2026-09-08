# Copilot instructions

Read [AGENTS.md](../AGENTS.md) for repository policy and follow its task-specific
document pointers. This file adds review guidance; keep it consistent with that
policy.

When reviewing pull requests:

- Focus reviews on correctness, security, CLI-contract drift, lifecycle races,
  compatibility, and missing tests. Avoid style-only comments unless they expose
  a concrete maintenance or correctness risk.
- Follow the verification requirements in AGENTS.md. Use actual check results
  and [the CI workflow](workflows/ci.yml) to assess coverage. Report tool failures,
  skips, and missing modules without treating relaxed checks as full coverage.
