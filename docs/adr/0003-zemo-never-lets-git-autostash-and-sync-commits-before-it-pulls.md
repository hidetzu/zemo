# 0003 — zemo never lets git autostash, and `zemo sync` commits before it pulls

Status: accepted (2026-10-27)
Owner decision. ⚠ **Asked because it moves what may be claimed (`docs/SPEC.md`) and what a human
reads** ([`../../.claude/rules/owner-decisions.md`](../../.claude/rules/owner-decisions.md)).

## What was decided

- ⚠ **Every `git pull` zemo runs passes `--rebase --no-autostash`**, whatever the user's
  `rebase.autoStash` says.
- ⚠ **With uncommitted changes in `<memo>`, the pull is refused and zemo stops before the
  editor**, saying the changes are not committed and naming `zemo sync`.
- ⚠ **`zemo sync` stages and commits first, then pulls, then pushes**, so it is the way out of
  that state. ⚠ **While a rebase is in progress it stages nothing.**
- ⚠ **A pull that stopped mid-rebase says so, and names `rebase --continue` and `rebase --abort`.**
  ⚠ **zemo never picks a side** (`docs/SPEC.md`, "Conflict resolution beyond `pull --rebase`").

## What was decided against

⚠ **Passing `--autostash` explicitly and checking `git ls-files -u` afterwards.**

## Why

- ⚠ **With autostash, a stash that conflicts on re-apply leaves conflict markers in the work tree
  and `git pull` still exits `0`.** ⚠ **zemo's next steps are `add -A`, `commit` and `push`.**
  ⚠ **Measured on 2026-10-27 against `v0.4.1`, git 2.56.0, `rebase.autoStash=true`: zemo exited
  `0`, pushed `<<<<<<< Updated upstream` to the remote, and left an `autostash` entry in
  `git stash list`.** ⚠ **The owner's own machine had that setting, which is why the refusal had
  never been seen there.**
- ⚠ **Checking afterwards** would have stopped the push, ⚠ **but it leaves a stash entry the user
  has to know to `git stash drop`** — ⚠ **recovery that depends on git's internal state, in a
  repository the user never asked us to touch** ([`../../.claude/rules/zig.md`](../../.claude/rules/zig.md)).
- ⚠ **Refusing and pointing at `zemo sync` keeps every change a commit the user can see.**
  ⚠ **But only if `zemo sync` can run from that state**: with pull first, it could not, ⚠ **and
  neither could the README's "install git, then run zemo sync" recovery.**
