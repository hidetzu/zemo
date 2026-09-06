# zemo — how we work

This file holds **how to work**.
**What may be claimed** goes in [`docs/SPEC.md`](docs/SPEC.md); **why a decision was made** goes
in [`docs/adr/`](docs/adr/).
⚠ **How to write code** (Zig, the layer split, testing priorities, forbidden git operations)
lives in [`.claude/rules/`](.claude/rules/).

⚠ **Never duplicate.** ⚠ **Written in two places, one of them goes stale.**
When the spec changes, fix the spec. Do not restate it here.

Before starting work, read [`.claude/rules/README.md`](.claude/rules/README.md).

⚠ **`⚠` marks "it hurts if you step on it".** ⚠ It is not decoration.

---

## 0. What this repository is

`zemo` turns any git repository into a terminal notebook. It opens a markdown note in the user's
editor and keeps it in sync with a git remote — pull before writing, commit and push after saving.
One static binary on Linux, macOS and Windows, with no runtime dependency beyond `git` and an
editor.

The experiment is **how little a tool can be and still be trusted with the user's own notes.**
Every feature is measured against that: it must work with no configuration, it must leave the
memo repository looking like a repository the user made themselves, and it must not need a second
process, a daemon, or a file format anyone has to learn.

⚠ **How it gets built is also a subject here.** ⚠ **This repository runs the
[`claude-dev-template`](https://github.com/hidetzu/claude-dev-template) workflow, and it is a
third data point for that template, not a confirmation of it.** ⚠ **When the template has to be
fought to do the right thing in a Zig CLI, that is a finding — say so, and send it upstream
naming this project** (that repository's README §5).

The feature currently being built is `ideas` — see [`docs/ideas-spec.md`](docs/ideas-spec.md).

---

## 1. The first principle

**Pure decision before I/O.**

⚠ **The order is never swapped.** Every module in `src/` is already this shape:
`resolveMemoDir` decides and `memoDir` reads the environment; `resolveEditor` and `splitCommand`
decide and the launch runs the process. ⚠ **A decision written inside an I/O function is a
decision nothing can assert**, and in a tool that runs `git commit` in the user's own repository
that is not a style preference. [`.claude/rules/zig.md`](.claude/rules/zig.md) owns the mechanics.

⚠ **Whatever it says, it never outranks the evidence rules.**
⚠ **Those are [`.claude/rules/evidence.md`](.claude/rules/evidence.md), and they hold everywhere** —
in the code, in the tests, and in every report.

⚠ **Never restate them here.**

---

## 2. Verification

⚠ **The contract is [`.claude/rules/verification.md`](.claude/rules/verification.md).**
⚠ **What to actually run is [`.claude/skills/verify/SKILL.md`](.claude/skills/verify/SKILL.md).**
⚠ Neither belongs here (never two copies).

⚠ **One line does need saying twice, because forgetting it costs someone their notes:**
⚠ **no check ever points at the real memo directory.** ⚠ **`ZEMO_DIR` names a throwaway, every
time.** The rest is in the skill.

---

## 3. Architecture boundaries

- **`src/` is one flat layer of small modules, each owning one subject**: `paths` (where files
  are), `editor` (which program, how invoked), `git` (subprocess calls), `time` (timestamps),
  `upgrade` (the release download), `cli` (argument parsing, wording, exit codes).
  ⚠ **`cli.zig` is the only module that writes a sentence a human reads.**
- **The memo repository is the user's.** ⚠ **`zemo` never creates it, never initialises it, and
  never rewrites its history.** It pulls, stages, commits and pushes — nothing else.
- **Zig standard library only.** ⚠ **`build.zig.zon` has no dependency and gaining one is an ADR.**
- **Single-threaded, no daemon, no configuration file.** Configuration is environment variables
  (`ZEMO_DIR`, `ZEMO_EDITOR`) and nothing more.
- ⚠ **Not introduced without a reason recorded in [`docs/adr/`](docs/adr/):** a third-party
  dependency, a second build system, a config file format, threads, or a network call anywhere
  outside `zemo upgrade`.

Two clauses hold regardless of the domain:

- ⚠ **Never keep two implementations that answer the same question.**
  If one is unavoidable, cross-check them mechanically.
  ⚠ **Writing the same decision in two places is how the two silently diverge.**
  (⚠ **`.gitignore` and `.claude/telemetry-dir.mjs` are one such pair, and
  `node .claude/tools/docs-check.mjs --only=telemetry-ignore-line` is the mechanical check.**)
- ⚠ **A layer split belongs in an ADR before it belongs in code.**

---

## 4. Words

- **Never leak internal state into what a human reads.** Not an error code, but a sentence
  that says what happened and what to do about it.
- **Name things after the concept the domain already named, not after the data structure.**
  ⚠ **Borrow the existing name exactly.** ⚠ If a name here differs, that difference is a claim —
  justify it.
- **Never rename in bulk.** Changing a term does not license a sweep through the ADRs and past
  discussions.

Where the names come from, and what is already spoken for:

| Word | ⚠ What it means here, and nothing else |
|---|---|
| **memo directory**, `<memo>` | What `ZEMO_DIR` resolves to. ⚠ **Never "the repo"** — it may not be one |
| **scratch** | `<memo>/scratch.txt`. ⚠ **Singular, and it has no topic name** |
| **topic** | A file under `<memo>/topics/`, named `[a-zA-Z0-9_-]`. ⚠ **Never a tag, never a folder** |
| **idea** | A file under `<memo>/ideas/`. ⚠ **An idea is not a topic** ([`docs/ideas-spec.md`](docs/ideas-spec.md)) |
| **status**, **priority** | ⚠ **An idea's front-matter fields.** ⚠ Never git status, never process priority |
| `--check` | ⚠ **Dry-run: say what would happen and change nothing.** ⚠ **Already spoken for by `zemo upgrade --check`** — a new flag that means anything else does not get this name |
| `pull`, `commit`, `push`, `work tree` | ⚠ **git's own words, with git's own meaning.** ⚠ Never borrowed for something else |

⚠ **The user-facing surface is English** (`README.md`, `--help`, every message).
⚠ **Source comments are Japanese, and stay Japanese** — ⚠ **do not translate a file in passing.**

### 4-1. Never open with what does not work

⚠ **This is not about hiding anything.** §1 outranks it, and **limitations are always stated**.
What changes is the **order, the subject, and the tense** — not whether it is said.

- **Say what this does first.** What it does not do comes after, with the reason
  and with what to do instead.
- **Do not use the progressive tense for a state.** "not receiving" reads as something
  happening right now on the reader's machine.
- **Never phrase our own gap as the other side's fault.** If we never implemented it,
  do not report it as "no response". ⚠ **The reader's next move depends on which it is** —
  retry, wait, or give up.
  ⚠ **Concretely here: `git` absent, `git` failing, and `<memo>/.git` not existing are three
  different sentences.** ⚠ **Never one of them for another.**
- **Do not sound stalled.** "not implemented yet" beats "unavailable": leave a reason to come back.

---

## 5. Comments

Comments carry **why this, why this value, what is being avoided**. That is an asset.
⚠ **But a stale comment misleads harder than stale code**, because it is believed.

Change code, and update the whole set:

```
implementation → test → comment → README.md → --help text → docs/SPEC.md
```

⚠ **`HELP_TEXT` in `src/cli.zig` is documentation that ships inside the binary.**
⚠ **A new subcommand that is not in it is undiscoverable**, and a removed one that is still in it
is a lie the user reads at the moment they need help.

⚠ **When a check reads documentation or comments, strip the comments first.**
⚠ Otherwise the check picks up the very words written to describe it.

---

## 6. How to write numbers

⚠ **Owned by [`.claude/rules/evidence.md`](.claude/rules/evidence.md).** ⚠ Not here.

⚠ **`zig build test --summary all` announces the count.** ⚠ **Copy that number; never write one
into a document.**

---

## 7. How to proceed

1. **Measure before polishing.** Before fixing anything, state what it does now, in numbers.
2. Report **observation** (measured values, captured output) and **inference** (interpretation)
   separately.
3. Never report as confirmed what was not verified.
   ⚠ **In particular: CI compiles five targets and runs one.** ⚠ **"It builds for Windows" is
   what was observed. ⚠ "It works on Windows" was not.**
4. Do not widen a change past its `Non-goals`. The smallest change that meets the goal is the default.

⚠ **Deciding yourself vs. asking, and `ready-for-ai`, are owned by
[`.claude/rules/owner-decisions.md`](.claude/rules/owner-decisions.md).** ⚠ Not here.

---

## 8. git

⚠ **Owned by [`.claude/rules/git.md`](.claude/rules/git.md)** — Conventional Commits, permission
for `git push` and merge, how to split commits, and what never goes into anything public.
⚠ Not here.

⚠ **That file is about *this* repository.** ⚠ **What `zemo` may do inside the *user's* memo
repository is stricter, and it is owned by [`.claude/rules/zig.md`](.claude/rules/zig.md).**

---

## 9. Pitfalls we have stepped on

⚠ **This table starts empty, and that is correct.**

⚠ **Nothing goes in here that did not happen in this repository.** Not an analogy from another
project, not something plausible, not something an AI expects to be true.
⚠ **A pitfall is a measurement**: it names what happened, and what to do instead.

⚠ **This is not where engineering constraints go.** A rule that holds because of the language,
because of a protocol, or because the input is hostile ⚠ **belongs in
[`.claude/rules/`](.claude/rules/), and binds already.**
⚠ **Never manufacture an incident to move a constraint in here**, and
⚠ **never soften a constraint on the grounds that this table has no row for it yet.**

⚠ **When you fill a row in, also leave the test behind.** A row with no test is a note;
a row with a test is a wall.
⚠ **If the incident also produces a new rule, the rule goes to `.claude/rules/` citing this row.**
⚠ **Both records stay. Neither replaces the other.**

| What happened | What to do instead |
|---|---|
| — | — |
