# 0001 — An idea's status lives only in its front matter

Status: accepted (2026-09-06)
Owner decision. ⚠ **Asked because measurement could not settle it**
([`../../.claude/rules/owner-decisions.md`](../../.claude/rules/owner-decisions.md)).

## What was decided

⚠ **`<memo>/ideas/` is flat.** ⚠ **An idea's `status` is a line in its YAML front matter and
nowhere else.** `zemo ideas:status` rewrites that line; ⚠ **it never moves the file.**

## What was decided against

⚠ **A directory per status** (`ideas/backlog/`, `ideas/prioritized/`, …), with
`zemo ideas:status` doing a `git mv` — either instead of the front-matter field or alongside it.

## Why

- ⚠ **Alongside it is two implementations of one question**, which
  [`../../CLAUDE.md`](../../CLAUDE.md) §3 forbids keeping unchecked. ⚠ **The two would drift the
  first time anyone moved a file by hand**, ⚠ **and a note repository is edited by hand by
  definition** — ⚠ **it is a directory of the user's own markdown, not a database we own.**
  ⚠ **Every reader would then have to be told which copy wins.**
- ⚠ **Instead of it costs the fields that have no directory**: `priority`, `evaluation`, `tags`
  and `repo` would still live in front matter, so the file would carry metadata *and* the path
  would carry metadata, ⚠ **and the split between them would be arbitrary.**
- ⚠ **The proposal that prompted this already disagreed with itself**: the directories it named
  were `in-progress/` and `archived/`, and the statuses it named were `experimenting` and
  `published`. ⚠ **Two names for one state, before a line of code existed**, is the failure mode
  arriving early.
- `git log -- <memo>/ideas/<name>.md` reads the whole life of an idea without `--follow`, and
  `git log -S` finds the moment a status changed. ⚠ **This is not why the decision was made** —
  git follows renames — ⚠ **it is a consequence, and it is recorded as one.**

## What this costs

⚠ **`ls ~/memo/ideas/` no longer shows the state.** ⚠ **That is a real loss and it is not
argued away**: `zemo ideas:list` is what answers it, and ⚠ **it is the only thing that does.**
⚠ **A user without `zemo` on the machine reads the front matter, or greps for it.**

## What is not claimed

⚠ **That this is the better design in general.** ⚠ **It was chosen for a note repository the
user edits by hand, and that premise is the whole of the reasoning.**
