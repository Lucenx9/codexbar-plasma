---
name: release
description: Prepare and publish a CodexBar Plasma widget release vX.Y.Z by reconciling CHANGELOG.md, setting the metadata version, delivering the release PR, and tagging the merged commit. Use when the user asks to release, cut, tag, or prepare a widget version. Do not use for an upstream CodexBar release; that is the parity-review skill.
---

# Release the widget

Policy lives in [changelog and releases](../../../docs/development.md#changelog-and-releases)
and [delivery and CI](../../../docs/development.md#delivery-and-ci). This skill
is the command sequence. Two steps need explicit authorization in the current
task: merging the release PR and pushing the tag. Stop and report before each
one when authorization is missing.

## 1. Scope the release

```sh
git fetch --tags origin
last=$(git describe --tags --abbrev=0 origin/main)
git log --oneline "$last"..origin/main
```

Use the version the user named. Otherwise propose the next patch version, as
the 0.2.x history does, and confirm it before editing.

## 2. Prepare the branch

```sh
git switch -c codex/release-X.Y.Z origin/main
```

- Compare the log with `## Unreleased`. Add missing user-visible entries and
  remove claims that did not ship.
- Move the entries into `## X.Y.Z - YYYY-MM-DD` with today's date, leave an
  empty `## Unreleased` first, and end the section with
  `[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/vPREV...vX.Y.Z)`.
- Set `KPlugin.Version` in `metadata.json` to `X.Y.Z`.
- Check setup, requirements, defaults, and changed features in README and the
  usage guide against the shipped diff.

## 3. Verify

```sh
make check
make package
python3 scripts/changelog.py --tag vX.Y.Z
```

Read the extracted notes: they become the GitHub release body verbatim.

## 4. Deliver the PR

Title `chore(release): prepare X.Y.Z`. Complete the PR template; the
changelog line states that the entries moved into the versioned section.
Follow CI to its final result. With merge authorization, check the head and
base again, then `gh pr merge <pr> --squash`.

## 5. Tag the merged commit

The `v*` ruleset blocks moving or deleting a pushed tag, so confirm the commit
first.

```sh
git fetch origin
sha=$(git rev-parse origin/main)
git show --stat "$sha"   # must be the squash commit of the release PR
git tag -a vX.Y.Z -m "vX.Y.Z" "$sha"
git push origin vX.Y.Z
```

## 6. Follow the release run

```sh
gh run list --commit "$sha" --json databaseId,event,headBranch,status,conclusion
gh run watch <tag-run-id> --exit-status
tmp=$(mktemp -d)
gh release download vX.Y.Z -D "$tmp"
(cd "$tmp" && sha256sum -c codexbar-plasma.plasmoid.sha256)
```

The tag run is the one whose `headBranch` is the tag. It must publish
`codexbar-plasma.plasmoid` and its `.sha256`. Follow the `main` push run for
the same commit too.

Report the version, merged commit, tag, run links, and verified assets.
