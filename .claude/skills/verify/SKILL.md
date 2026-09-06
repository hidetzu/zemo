---
name: verify
description: Run zemo's checks in order — inner (zig build test, docs-check), final gate (a real binary against a throwaway memo dir), external (real git, real editor) — and return PASS / FAIL / NOT-VERIFIED in the shape rules/verification.md requires. Use before opening a PR and after every fix.
---

# Verify — zemo

⚠ **The contract is [`.claude/rules/verification.md`](../../rules/verification.md).**
⚠ **This file names only the commands.** ⚠ **When the two disagree, the contract wins.**

⚠ **Return the `PASS` / `FAIL` / `NOT-VERIFIED` block from the contract, verbatim in shape.**
⚠ **`Regression guard` and `Mutation check` are never left empty.**

Requires Zig 0.16.0 (`build.zig.zon` pins it) and `node` for the document checks.
⚠ **On a Linux host the default target is `musl`** — glibc's SFrame format is incompatible with
the bundled LLD (`build.zig`). ⚠ **A bare `zig test src/foo.zig` fails to link for that reason
and it is not a failure of the code.** Pass `-target x86_64-linux-musl`.

---

## The three tiers

| Tier | Entry point | ⚠ What it cannot show |
|---|---|---|
| **Fast / inner** | `zig build test`, `zig fmt --check .`, `node .claude/tools/docs-check.mjs` | ⚠ **Nothing about the binary a user runs.** Every case here is a pure function or a `tmpDir` |
| **Final gate** | `zig build -Doptimize=ReleaseSafe`, then drive `zig-out/bin/zemo` against a throwaway `ZEMO_DIR` | ⚠ **Nothing about the other platforms**, and nothing about a real editor |
| **External** | ⚠ **The other end is `git` and the editor — we wrote neither.** Drive the binary against a real `git` work tree with a local bare remote | ⚠ **It is not evidence about our code when `git` itself failed** |

⚠ **The cross-build matrix (`zig build -Dtarget=…`) proves the code compiles for a target.**
⚠ **It is not evidence that it runs there.** ⚠ **Say "compiled", never "works on Windows".**

---

## 1. Fast / inner

```sh
zig build test --summary all     # ⚠ the runner announces the count. Never write it down
zig fmt --check .                # prints the files it would reformat; silent = clean
node .claude/tools/docs-check.mjs
```

⚠ **Stop and go back at the first failure** (contract, § Order).

### Run one named case only

```sh
zig test src/paths.zig -lc -target x86_64-linux-musl --test-filter "isValidTopic"
```

⚠ **`--test-filter` matches the test name as a substring**, so a filter can silently select
nothing. ⚠ **Read the `N/N … OK` lines and confirm the case you meant is among them** —
⚠ **`All 0 tests passed` is not a pass, it is a filter that matched nothing.**

```sh
node .claude/tools/docs-check.mjs --only=links
```

### Count without running

```sh
grep -c '^test "' src/*.zig      # ⚠ compiles nothing, loads nothing
node .claude/tools/docs-check.mjs --list
```

⚠ **`grep` counts `test` declarations in the source.** ⚠ **That is not what the runner executes** —
a `test` behind a comptime branch, or one the platform skips, is counted here and not there
(`zig build test --summary all` reported a skip on Linux at the time this file was written).
⚠ **Use it to name cases and to notice one that vanished, never as the number of checks that ran.**
⚠ **The number that goes in a report is the runner's.**

---

## 2. Final gate

⚠ **Never point any check at the real memo directory.** ⚠ **`zemo` runs `git add -A` and
`git commit` in whatever `ZEMO_DIR` names, and an exercise must not change the world**
(contract, § An exercise must not change the world). ⚠ **`ZEMO_DIR` is the only thing standing
between a check and the user's notes — set it, confirm it, then run.**

```sh
zig build -Doptimize=ReleaseSafe
BIN="$PWD/zig-out/bin/zemo"

WORK="$(mktemp -d)"; export ZEMO_DIR="$WORK/memo"
mkdir -p "$ZEMO_DIR/topics"
printf 'scratch line\n'      > "$ZEMO_DIR/scratch.txt"
printf '# alpha\nbody\n'     > "$ZEMO_DIR/topics/alpha.md"
printf 'not a topic\n'       > "$ZEMO_DIR/topics/ignore.txt"

"$BIN" version
"$BIN" ls          # expect: alpha
"$BIN" cat alpha   # expect: the file, byte for byte
"$BIN" dump        # expect: scratch and every topic, with headers
"$BIN" cat nope; echo "exit=$?"    # expect: exit 1 and a sentence on stderr
```

⚠ **Confirm the binary under test is the one just built** (contract). ⚠ **`zig-out/bin/zemo`
from a previous optimize mode looks identical and is not.** ⚠ **`zig build` first, in the same
shell, every time.**

⚠ **`zemo` and `zemo <topic>` launch `$ZEMO_EDITOR`.** ⚠ **Drive them with a non-interactive
editor** (`ZEMO_EDITOR=true`, or a script that appends a line) — ⚠ **never with the real one,
which blocks the run and makes the result depend on what a human typed.**

⚠ **`zemo upgrade` reaches the network and replaces the running binary.**
⚠ **Only `zemo upgrade --check` may be run as an exercise**, ⚠ **and `--check` is a claim about
the code paths that read it, not a promise** (contract). ⚠ **A bare `zemo upgrade` is never part
of a check.**

---

## 3. External — the other end is `git`

⚠ **This is the tier that gets skipped.** ⚠ **Run it whenever anything under `src/git.zig`, or
anything that calls it, changed.**

```sh
WORK="$(mktemp -d)"
git init --bare "$WORK/remote.git"
git clone "$WORK/remote.git" "$WORK/memo"
git -C "$WORK/memo" config user.email zemo@example.invalid
git -C "$WORK/memo" config user.name  zemo-verify
export ZEMO_DIR="$WORK/memo"

printf 'first\n' > "$ZEMO_DIR/scratch.txt"
"$PWD/zig-out/bin/zemo" sync

git -C "$WORK/memo" log --oneline          # expect one `chore: sync YYYY-MM-DD HH:MM`
git --git-dir="$WORK/remote.git" log --oneline   # expect the same commit arrived
"$PWD/zig-out/bin/zemo" sync               # expect: nothing to commit, and no error
```

- ⚠ **Depend on nobody's uptime** (contract). ⚠ **The remote is a local bare repo, never a host.**
- ⚠ **`git` failing is still a `FAIL`** — ⚠ **and it is `external`, not evidence that our code broke.**
  ⚠ Say which side failed.
- ⚠ **A missing `git` is `NOT-VERIFIED` for this tier**, ⚠ never a silent skip.

---

## 4. What a fix owes

- ⚠ **Every fixed bug leaves a case behind**, next to the function it covers, in `src/*.zig`.
- ⚠ **Break the code on purpose and watch it fail**, ⚠ **and read the failure text to confirm it
  failed for the reason intended** (contract, § "It failed" is not enough).
  ⚠ **Record that text verbatim in `Mutation check`.**
- ⚠ **`zig build test` caches.** ⚠ **A mutation that changes nothing the test compiles against can
  report the previous run** — ⚠ **confirm the failure text moved, not just that the exit code did.**
