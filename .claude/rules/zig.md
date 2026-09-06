# Zig — how zemo is written

⚠ **`MUST` = required, `SHOULD` = default, `MAY` = optional.**

⚠ **Every rule here is an engineering constraint** — it comes from the language, from the
platforms, or from the fact that `argv` and the environment are hostile input.
⚠ **It binds from the first line of code** ([`README.md`](README.md)).
⚠ **What went wrong in this repository is `CLAUDE.md` §9, not here.**

Zig 0.16.0 (`build.zig.zon` pins it).

## The pure / I/O split

⚠ **Grounds: `std.Io` is threaded through everything that touches the world, and there is no
cheap fake for it.** ⚠ **A decision written inside an I/O function cannot be tested at all.**
The existing pairs are `resolveMemoDir` / `memoDir` (`src/paths.zig`) and
`resolveEditor` / the launch (`src/editor.zig`).

- MUST: ⚠ **Take the decision in a function whose arguments are plain values.**
  ⚠ **`?[]const u8` for "the environment had it or it did not"** — ⚠ **never an `Environ.Map`.**
- MUST: ⚠ **The I/O side reads, calls the pure side, and writes.** ⚠ **It decides nothing.**
- MUST: ⚠ **Tests reach the pure side.** ⚠ **A branch only the I/O side can take is a branch
  nothing asserts** — move it.

## Memory

- MUST: ⚠ **A function that returns `![]u8` returns memory the caller owns**, and its doc comment
  says so. ⚠ **`zemo` has no arena at the call sites; every returned slice is freed by name.**
- MUST: ⚠ **`defer` for what is always released, `errdefer` for what is released only on the
  error path.** ⚠ **Write it on the line after the allocation, never later.**
- MUST: ⚠ **Free the intermediate.** `std.fs.path.join` and `std.fmt.allocPrint` each allocate;
  ⚠ **a joined path built from an allocated fragment leaks the fragment unless it is deferred.**
- MUST: ⚠ **Tests use `std.testing.allocator`** — ⚠ **it fails the test on a leak, and that is
  the only thing that catches one.**

## ⚠ Anything that becomes a path is hostile input

⚠ **Grounds: `argv` is the user's, and `zemo <topic>` turns it into a file path under the memo
directory.** ⚠ **`..`, `/` and `\` escape that directory.**

- MUST: ⚠ **Validate with `paths.isValidTopic` before joining**, ⚠ **never after**, and
  ⚠ **never "it looks fine".** The permitted set is `[a-zA-Z0-9_-]`, and empty is rejected.
- MUST: ⚠ **A new name-shaped argument gets the same gate, or its own with the same grounds
  written down.** ⚠ **A second, looser validator is two implementations of one question**
  (`CLAUDE.md` §3).
- MUST NOT: ⚠ **Never build a path with `/` or `\` in a format string.** `std.fs.path.join`.

## ⚠ git runs in the user's own repository

⚠ **Grounds: `git.zig` runs `add -A`, `commit` and `push` in whatever `ZEMO_DIR` names.**
⚠ **That directory holds the user's notes and nothing of ours.**

- MUST: ⚠ **Confirm the directory is a work-tree *root* before staging** — `isGitRepo` compares
  `rev-parse --show-toplevel` against the real path. ⚠ **A subdirectory of a repository would
  make `add -A` sweep the parent repository in.**
- MUST NOT: ⚠ **Never run a git operation that rewrites or discards history there** — no `reset`,
  no `checkout --`, no `clean`, no force push. ⚠ **The forbidden list in [`git.md`](git.md) is
  about our own repository; ⚠ in the user's memo repository the bar is higher, because they never
  asked us to touch it at all.**
- MUST: ⚠ **When `<memo>/.git` is absent, open the editor and skip the sync.**
  ⚠ **Never initialise a repository on the user's behalf.**
- MUST: ⚠ **Distinguish `git` missing from `git` failing** (`error.GitNotFound` vs
  `error.GitFailed`). ⚠ **They are different outcomes and the user's next move differs**
  ([`evidence.md`](evidence.md)).

## Errors, and the sentence a human reads

- MUST: ⚠ **Leaf functions return a named error.** ⚠ **They never print.**
- MUST: ⚠ **The wording is written once, at the CLI edge** (`src/cli.zig`), ⚠ **and it says what
  happened and what to do about it** (`CLAUDE.md` §4). ⚠ **Never leak an error name to stdout.**
- MUST: ⚠ **Exit codes are part of the interface**: `0` success, `1` the operation failed,
  `2` the command line was wrong. ⚠ **Changing one is a change to `docs/SPEC.md`.**

## Cross-platform

⚠ **Grounds: the same source is built for Linux, macOS and Windows, and CI compiles all five
targets.** ⚠ **Compiling is not running** — ⚠ **only Linux is executed** (`skills/verify/SKILL.md`).

- MUST: ⚠ **Branch on `@import("builtin").os.tag` at the point of difference**, and
  ⚠ **give the other branch a test** (`HOME` / `USERPROFILE`, the editor fallback list).
- MUST: ⚠ **Trim `\r\n`, not `\n`**, on anything read back from a subprocess.
- MUST NOT: ⚠ **Never assume a path separator, a line ending, or that an executable has no suffix.**

## What may not be introduced without a reason

- MUST: ⚠ **An ADR before any of these**: a dependency in `build.zig.zon`, a second build system,
  a configuration file format, a background thread, a network call outside `zemo upgrade`.
  ⚠ **The claim `zemo` makes is "one static binary, no runtime dependency beyond `git` and an
  editor"** (`docs/SPEC.md`) — ⚠ **each of these spends it.**
