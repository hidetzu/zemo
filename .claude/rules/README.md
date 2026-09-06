# Rules

⚠ **This directory holds "how to write it".**
⚠ **"How to work" is [`CLAUDE.md`](../../CLAUDE.md), "what may be claimed" is
[`docs/SPEC.md`](../../docs/SPEC.md), and "why" is [`docs/adr/`](../../docs/adr/).**

⚠ **Never duplicate.** ⚠ **Written in two places, one of them goes stale.**
⚠ **If a subject already has an owner, this directory only says "look there".**

## Two kinds of rule, and they are not interchangeable

```text
Engineering constraint          Learned pitfall
grounded in the language,       something this repository
the protocol, or the fact       actually paid for
that the input is hostile              |
        |                              |
binds from the first line       lives in CLAUDE.md §9,
of code                         with the test that stops
        |                       it happening again
lives here, with its grounds
```

⚠ **Everything in this directory is an engineering constraint.** ⚠ **It binds now.**
⚠ **It does not wait for an accident here to earn its place.**
⚠ **Each section states its grounds** — cite those, never an anecdote.

⚠ **Never demote a constraint to "we will see" because nothing has gone wrong yet.**
⚠ **Never promote one into `CLAUDE.md` §9 by inventing an incident.**

⚠ **A learned pitfall can add a rule here.** ⚠ **When it does, the grounds it cites is the
incident, and `CLAUDE.md` §9 keeps the row.**
⚠ **The two records point at each other; neither replaces the other.**

## What is here

| File | What it holds |
|---|---|
| [`evidence.md`](evidence.md) | ⚠ **What may be said to have been observed.** Denominators, counts, outcomes |
| [`verification.md`](verification.md) | The three tiers, partial runs, `PASS` / `FAIL` / `NOT-VERIFIED`, ⚠ **and that an exercise must not change the world** |
| [`owner-decisions.md`](owner-decisions.md) | Decide yourself vs. ask, `ready-for-ai` |
| [`git.md`](git.md) | Commits, permission, forbidden operations, what never goes public |
| [`zig.md`](zig.md) | ⚠ **How zemo is written**: the pure / I/O split, memory, ⚠ **path arguments are hostile input**, ⚠ **git runs in the user's own repository**, cross-platform, what needs an ADR |

⚠ **[`zig.md`](zig.md) is this project's own.** ⚠ **Its grounds are the language, the three
target platforms, and the fact that `argv` and `ZEMO_DIR` are the user's, not ours.**
⚠ **Nothing in it waits for an accident here to earn its place.**

⚠ **A rule with no grounds gets argued away.** ⚠ **Name the grounds in anything added beside it.**

⚠ **`MUST` = required, `SHOULD` = default, `MAY` = optional.**
⚠ **`⚠` marks "it hurts if you step on it"** (same convention as `CLAUDE.md`).

## ⚠ Subjects owned elsewhere

⚠ **Do not copy these here.**

| Subject | Owner |
|---|---|
| not observed ≠ did not happen / never dress a guess as a measurement / denominators | [`evidence.md`](evidence.md) |
| Wording a human reads (never open with what does not work) | `CLAUDE.md` §4 |
| Which checks to run, in what order | [`verify`](../skills/verify/SKILL.md) — `zig build test`, the built binary against a throwaway `ZEMO_DIR`, and a real `git` |
| How to review a change (scope, rules, stale results) | `.claude/skills/change-review/SKILL.md` |
| Whether an issue can be handed over | `.claude/skills/issue-ready/SKILL.md` |
| Making an owner decision answerable by looking | [`visual-decision`](../skills/visual-decision/SKILL.md) |
| What `zemo` may be claimed to do | [`../../docs/SPEC.md`](../../docs/SPEC.md) |
| What the `ideas` feature is, command by command | [`../../docs/ideas-spec.md`](../../docs/ideas-spec.md) |
