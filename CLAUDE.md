# Working in voidstation-packages

xbps package repository for VoidStation. Read `README.md` for layout and rules.

## Conventions

- **Commit messages in English** (decided by the maintainer, 2026-11-13).
  The first three commits are German; leave them, never rewrite `main`.
- Work on a branch `claude/<topic>`, never push to `main`. The maintainer
  merges. Pushing a `claude/**` branch runs the test build; the pull request
  shows those checks (no second build).
- Every push to `main` that changes templates builds them and then waits for
  approval in the environment `release` before signing and uploading.
  To (re)publish everything: Actions → Build packages → Run workflow → `all`.
- Never commit private keys. `keys/` holds the public plist only
  (fingerprint `df:95:b3:5d:e1:24:a1:4d:1f:63:ff:f4:f3:56:af:5c`).
- Never give a template the name of a void-packages template (CI refuses it);
  variants are called `vs-<name>`.
- Never use GitHub's "Re-run" on a failed run: it reuses the old commit and
  its scripts. Start a new run (Run workflow) instead. A re-run on `main` also
  pushes other pending `main` runs out of the concurrency queue.
- Build jobs: one per group of interdependent templates and architecture
  (`ci/groups.py`); publish collects all `pkgs-<arch>-<group>` artifacts and
  only runs if every build job succeeded.
- Call scripts through their interpreter in the workflow (`bash ci/…`), so a
  missing executable bit cannot break a run (it did once, 2026-11-13).

## Checking work without access to job logs

Job logs need a login. Run status and annotations do not:

    curl -s https://api.github.com/repos/Panther92/voidstation-packages/commits/<sha>/check-runs

A failed build step writes the end of its log as an annotation
(`ci/annotate.sh`); read it through the `annotations_url` of the check run.

## Local checks before pushing

    shellcheck ci/*.sh tools/*.sh
    actionlint .github/workflows/*.yml
    EVENT=push REF=refs/heads/claude/x GITHUB_SHA=HEAD bash ci/plan.sh

`xbps-src` itself only runs in CI (Void container).
