# 0002 — A pointer section in CLAUDE.md carries only the pointer, with no exception

Status: accepted (2026-10-18)
Owner decision. ⚠ **Asked because the new rule and an earlier, deliberate choice disagreed**
([`../../.claude/rules/owner-decisions.md`](../../.claude/rules/owner-decisions.md)).

## What was decided

⚠ **[`../../CLAUDE.md`](../../CLAUDE.md) §2 and §6 now hold the pointer and nothing else.**
The line each carried beside its pointer was removed:

- §2: "no check ever points at the real memo directory; `ZEMO_DIR` names a throwaway, every time"
- §6: "`zig build test --summary all` announces the count; copy that number"

⚠ **Both still bind, and each is still written once, where it is owned**:
the first in [`../../.claude/skills/verify/SKILL.md`](../../.claude/skills/verify/SKILL.md)
§ 2 (Final gate), the second in the same skill's inner tier and in
[`../../.claude/rules/evidence.md`](../../.claude/rules/evidence.md) § Counts.

## What was decided against

⚠ **Keeping §2's line as a named exception.** §2 said of it: "One line does need saying twice,
because forgetting it costs someone their notes." That was a deliberate duplicate, not drift.

## Why

- ⚠ **The rule came from `claude-dev-template` (upstream #7)**, adopted into `CLAUDE.md` in the
  same change: ⚠ **a pointer section carries the pointer and nothing else**, because the body
  moves and the summary does not, ⚠ **and the stale copy then sits under the words "not here".**
- ⚠ **An exception is a second copy with a reason attached.** The reason does not stop the
  two copies diverging; ⚠ **only one copy does.**
- ⚠ **The harm §2's line guarded against is guarded by the owner of the rule**, which is the
  file anyone running a check reads.

## What this costs

⚠ **A reader of `CLAUDE.md` alone no longer meets the memo-directory warning.** ⚠ **They meet
it at the moment they open the verify skill to run something** — which is when it matters.

⚠ **The rule is a note, not yet a wall.** The check that fails when a pointer section grows a
second line is deferred to a separate change (owner decision, same day).
