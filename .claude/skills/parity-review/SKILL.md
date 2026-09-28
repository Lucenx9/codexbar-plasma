---
name: parity-review
description: Review new stable upstream CodexBar releases for Linux/Plasma parity, probe changed CLI contracts in isolation, and update TODO.md with a dated research note in one docs PR. Use when a new official CodexBar release appears, when the scheduled release monitor runs, or when the user asks for a parity review. Do not use to implement the gaps it finds or to release the widget.
---

# Review upstream releases for parity

The procedure and its rules live in
[upstream release maintenance](../../../docs/development.md#upstream-release-maintenance);
gap classification follows the sources of truth in
[AGENTS.md](../../../AGENTS.md#sources-of-truth). This skill supplies the
commands, the isolation recipe, and the note shape.

## 1. Find the delta

```sh
git fetch origin
git show origin/main:TODO.md | grep -m1 -A1 'Last release reviewed'
gh release list -R steipete/CodexBar --exclude-pre-releases --limit 10
gh pr list --state open --search 'parity in:title'
```

Stop without a commit or notification when no stable release is newer than
the baseline and no verification is pending. Reuse an open parity PR branch
instead of opening a second one. For each release since the baseline:

```sh
gh release view vA.B.C -R steipete/CodexBar --json tagName,publishedAt,body
gh api repos/steipete/CodexBar/commits/vA.B.C --jq .sha
```

## 2. Compare

Check each Linux-relevant change, fix, and changed contract against the
current Plasma code, config schema, tests, and guides. Recheck the carried
blockers in TODO and the unresolved findings of the newest note under
`docs/research/`.

## 3. Probe changed contracts in isolation

```sh
v=A.B.C
tmp=$(mktemp -d)
cd "$tmp"
gh release download "v$v" -R steipete/CodexBar \
  -p "CodexBarCLI-v$v-linux-x86_64.tar.gz" \
  -p "CodexBarCLI-v$v-linux-x86_64.tar.gz.sha256"
sha256sum -c "CodexBarCLI-v$v-linux-x86_64.tar.gz.sha256"
mkdir bin home config cache
tar -xzf "CodexBarCLI-v$v-linux-x86_64.tar.gz" -C bin
probe() {
  env -i PATH=/usr/bin:/bin HOME="$tmp/home" \
    XDG_CONFIG_HOME="$tmp/config" XDG_CACHE_HOME="$tmp/cache" \
    "$tmp/bin/codexbar" "$@"
}
probe --version
```

- Never replace the installed `codexbar`, and pass no credential environment.
- Use synthetic keys only. Serve fixtures from a loopback
  `python3 -m http.server` bound to `127.0.0.1`.
- `cost` discovery for Codex, Claude, Antigravity, and Muse can still read
  host history despite the temporary `HOME`. Use those runs for field shapes
  only and record no account data.
- Record every probe you could not run, with the reason.

## 4. Write the results

- Add `docs/research/YYYY-MM-DD-macos-parity-A.B.C.md` with the sections of the
  newest note: header with Plasma commit and upstream tag, commit, and publish
  time; release coverage table; Linux CLI contract changes; carried-forward
  blockers rechecked; excluded from the Linux backlog; unverified; probe method.
- Index the note in `docs/README.md`.
- In TODO.md, update the review baseline, add gaps with evidence and a done
  condition, remove implemented ones, and revise resolved blockers.

## 5. Deliver

Use branch `codex/parity-A.B.C` and title
`docs(parity): review upstream release A.B.C`. Run `make check`, complete the
PR template with exact versions and evidence, and follow CI to its final
result. A scheduled run stops at a green PR: no merge and no feature work.
