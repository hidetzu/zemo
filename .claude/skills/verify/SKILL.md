---
name: verify
description: Run zemo's checks in order — inner (zig build test, docs-check), final gate (a real binary against a throwaway memo dir), external (real git, real editor) — and return PASS / FAIL / NOT-VERIFIED in the shape rules/verification.md requires. Use before opening a PR and after every fix.
---

# Verify — zemo

⚠ **The contract is [`.claude/rules/verification.md`](../../rules/verification.md).**
⚠ **This file names only the commands.** ⚠ **When the two disagree, the contract wins.**

⚠ **Return the `PASS` / `FAIL` / `NOT-VERIFIED` block from the contract, verbatim in shape.**
⚠ **`Regression guard` and `Mutation check` are never left empty.**

Requires Zig 0.17.0 (`mise.toml` pins it; `build.zig.zon` requires at least it) and `node` for the document checks.
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
# ⚠ an append-mode file: the copy must not need an output buffer (hidetzu/zemo#27)
: > "$WORK/cat.txt";  "$BIN" cat alpha >> "$WORK/cat.txt"; echo "exit=$?"   # expect: exit=0
cmp "$WORK/cat.txt" "$ZEMO_DIR/topics/alpha.md" && echo same                # expect: same
"$BIN" dump > "$WORK/dump-new.txt"
: > "$WORK/dump.txt"; "$BIN" dump >> "$WORK/dump.txt"; echo "exit=$?"       # expect: exit=0
cmp "$WORK/dump.txt" "$WORK/dump-new.txt" && echo same                      # expect: same
"$BIN" cat nope; echo "exit=$?"    # expect: exit 1 and a sentence on stderr

export ZEMO_EDITOR=true            # non-interactive, see below
"$BIN" ideas:new zig-lsp-server            # expect: the template, status backlog
"$BIN" ideas:priority zig-lsp-server 2     # expect: priority unranked -> 2
"$BIN" ideas:status   zig-lsp-server prioritized
"$BIN" ideas:status   zig-lsp-server published; echo "exit=$?"
                                   # expect: exit 1, naming what IS reachable
"$BIN" ideas:status   zig-lsp-server experimenting
"$BIN" ideas:status   zig-lsp-server experimenting
                                   # expect: "already experimenting", exit 0, nothing written
printf 'no front matter\n' > "$ZEMO_DIR/ideas/broken.md"
"$BIN" ideas:status broken prioritized; echo "exit=$?"
                                   # expect: exit 1, and ⚠ broken.md unchanged (fail closed)
"$BIN" ideas:list                  # expect: ranked first, and broken still listed as unreadable
"$BIN" ideas:list --sort=name; echo "exit=$?"    # expect: exit 2, never the default order
```

⚠ **After the `fail closed` case, read `broken.md` back.** ⚠ **An exit code of `1` is not
evidence that nothing was written** — ⚠ **the claim is about the file, so look at the file.**

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

⚠ **Seed the remote with a commit first.** ⚠ **`zemo` pulls before it writes, and
`git pull --rebase` against an *empty* remote fails with "no such ref was fetched"** —
⚠ **which is a broken fixture, not a finding about zemo.** ⚠ **Observed on 2026-09-06 while
writing this file: the whole external run reported `git pull failed` and asserted nothing.**

```sh
WORK="$(mktemp -d)"
git init --bare "$WORK/remote.git"
git clone "$WORK/remote.git" "$WORK/memo"
cd "$WORK/memo"
git config user.email zemo@example.invalid
git config user.name  zemo-verify
git commit --allow-empty -m "chore: init" && git push -u origin HEAD   # ⚠ the seed
cd -
export ZEMO_DIR="$WORK/memo" ZEMO_EDITOR=true
BIN="$PWD/zig-out/bin/zemo"

printf 'first\n' > "$ZEMO_DIR/scratch.txt"
"$BIN" sync

git -C "$WORK/memo" log --oneline          # expect one `chore: sync YYYY-MM-DD HH:MM`
git --git-dir="$WORK/remote.git" log --oneline   # expect the same commit arrived
"$BIN" sync                                # expect: nothing to commit, and no error

# ideas — ⚠ read the subjects out of git log, never out of our own format string
"$BIN" ideas:new zig-lsp-server
"$BIN" ideas:priority zig-lsp-server 2
"$BIN" ideas:status   zig-lsp-server prioritized
git -C "$WORK/memo" log --oneline -- ideas/zig-lsp-server.md
#   expect, newest first:
#     docs(ideas): zig-lsp-server backlog -> prioritized
#     docs(ideas): zig-lsp-server priority unranked -> 2
#     docs(ideas): zig-lsp-server YYYY-MM-DD HH:MM

before=$(git -C "$WORK/memo" rev-parse HEAD)
"$BIN" ideas:status zig-lsp-server prioritized      # the status it already has
test "$before" = "$(git -C "$WORK/memo" rev-parse HEAD)"   # ⚠ expect: no new commit

# ⚠ stdout and stderr sharing one file, and a pipe — git pull's line, zemo's line and git
#   commit's line must each appear once, in the order they happened (hidetzu/zemo#23, #26)
"$BIN" ideas:priority zig-lsp-server 3 > "$WORK/both.txt" 2>&1
"$BIN" ideas:priority zig-lsp-server 4 > "$WORK/stdout.txt"
: > "$WORK/append-both.txt"; "$BIN" ideas:priority zig-lsp-server 5 >> "$WORK/append-both.txt" 2>&1
: > "$WORK/append.txt";      "$BIN" ideas:priority zig-lsp-server - >> "$WORK/append.txt"
"$BIN" ideas:priority zig-lsp-server 1 2>&1 | cat > "$WORK/pipe.txt"
for pair in "both.txt:2 -> 3" "stdout.txt:3 -> 4" "append-both.txt:4 -> 5" "append.txt:5 -> unranked" "pipe.txt:unranked -> 1"; do
  f="$WORK/${pair%%:*}"; t="${pair#*:}"
  grep -c '^Already up to date\.$' "$f"                    # expect: 1 (git pull)
  grep -c "^zig-lsp-server: priority $t\$" "$f"            # expect: 1 (zemo)
  grep -c "docs(ideas): zig-lsp-server priority $t" "$f"   # expect: 1 (git commit)
  awk -v z="zig-lsp-server: priority $t" -v c="docs(ideas): zig-lsp-server priority $t" \
    '$0 == "Already up to date." { p = NR } $0 == z { m = NR } index($0, c) { k = NR }
     END { print (p && m && k && p < m && m < k) ? "in order" : "OUT OF ORDER" }' "$f"
                                                            # expect: in order
done

# ⚠ push refused — zemo's own line before git's commit, zemo's own error last (hidetzu/zemo#26)
chmod -R a-w "$WORK/remote.git"
"$BIN" ideas:priority zig-lsp-server 2 > "$WORK/refused.txt" 2>&1; echo "exit=$?"   # expect: exit=1
awk -v z="zig-lsp-server: priority 1 -> 2" -v c="docs(ideas): zig-lsp-server priority 1 -> 2" \
  '$0 == z { m = NR } index($0, c) { k = NR } /^zemo: .*push/ { e = NR }
   END { print (m && k && e && m < k && k < e && e >= NR - 1) ? "in order" : "OUT OF ORDER" }' "$WORK/refused.txt"
                                                            # expect: in order
chmod -R u+w "$WORK/remote.git"
```

⚠ **The redirect case is hidetzu/zemo#23; the order is hidetzu/zemo#26.**
⚠ **With positional stdout/stderr writers, zemo's line landed at offset 0 over git's output and
lines were lost** — ⚠ **observed on `f7161dd`, 2026-10-18.** ⚠ **A pipe does not show that; only
a regular file does.**
⚠ **With buffered writers, zemo's line came after git's commit and push, on a file and on a pipe
alike** — ⚠ **observed on `bcfc767`, 2026-10-18.** ⚠ **Every case here, including the two `>>`
runs and the pipe, can fail for that.**
⚠ **`Already up to date.` is git's wording, not ours** — ⚠ **observed with git 2.56.0.** ⚠ **If it
reads 0 under another git, look at what git printed before blaming zemo.**
⚠ **Each file must hold all three lines once, in that order** — ⚠ **git's first line is the one an overwrite at offset 0 destroys, and zemo's line is the one buffering moves.**

- ⚠ **Depend on nobody's uptime** (contract). ⚠ **The remote is a local bare repo, never a host.**
- ⚠ **`git` failing is still a `FAIL`** — ⚠ **and it is `external`, not evidence that our code broke.**
  ⚠ Say which side failed.
- ⚠ **A missing `git` is `NOT-VERIFIED` for this tier**, ⚠ never a silent skip.
- ⚠ **`git` not on `PATH` is checked on purpose** (hidetzu/zemo#25) — ⚠ **with a `PATH` that
  holds only the editor, so it is the absence that is measured:**

```sh
NOGIT="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$NOGIT/ed"; chmod +x "$NOGIT/ed"   # ⚠ not `ln -s "$(command -v true)"`: `true` is a shell builtin
PATH="$NOGIT" "$BIN" sync; echo "exit=$?"                       # expect: "git is not installed or not on PATH, so <memo> cannot be synced", exit=1
PATH="$NOGIT" ZEMO_EDITOR="$NOGIT/ed" "$BIN"; echo "exit=$?"    # expect: "…your note is saved in <memo> but not committed", exit=1
PLAIN="$(mktemp -d)"
ZEMO_DIR="$PLAIN" PATH="$NOGIT" ZEMO_EDITOR="$NOGIT/ed" "$BIN"; echo "exit=$?"   # expect: nothing printed, exit=0 (no .git: no sync, as before)
```

- ⚠ **A pull that `git` refuses, or that stops mid-rebase, is checked on purpose** — ⚠ **once with a
  clean git config and once with `rebase.autoStash=true`**, because the user's own config decides
  what `git pull` does and ⚠ **a developer machine with autoStash on hides the refusal entirely:**

```sh
P="$(mktemp -d)"
printf '[user]\n\tname = zemo-verify\n\temail = zemo@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$P/plain.cfg"
cp "$P/plain.cfg" "$P/autostash.cfg"; printf '[rebase]\n\tautoStash = true\n' >> "$P/autostash.cfg"
for cfg in plain autostash; do
  export GIT_CONFIG_GLOBAL="$P/$cfg.cfg" GIT_CONFIG_NOSYSTEM=1 ZEMO_DIR="$P/$cfg/memo" ZEMO_EDITOR=true
  R="$P/$cfg"; mkdir -p "$R"
  git init -q --bare "$R/remote.git"; git clone -q "$R/remote.git" "$R/memo" 2>/dev/null
  printf 'base\n' > "$R/memo/scratch.txt"
  git -C "$R/memo" add -A; git -C "$R/memo" commit -qm init; git -C "$R/memo" push -q origin main   # ⚠ the seed
  git clone -q "$R/remote.git" "$R/other"
  other() { printf '%s\n' "$2" > "$R/other/$1"; git -C "$R/other" add -A; git -C "$R/other" commit -qm "$1"; git -C "$R/other" push -q; }

  # an uncommitted change, and the remote moved another file
  other r.txt remote; printf 'mine\n' >> "$R/memo/scratch.txt"
  "$BIN"; echo "exit=$?"            # expect: "<memo> has changes that are not committed", never "Fix the remote", exit=1
  "$BIN" sync; echo "exit=$?"       # expect: exit=0 — ⚠ this is the recovery the README names
  git --git-dir="$R/remote.git" show main:scratch.txt   # expect: base, mine

  # an uncommitted change to the file the remote also changed
  git -C "$R/other" pull -q; other scratch.txt theirs; printf 'conflicting\n' > "$R/memo/scratch.txt"
  "$BIN"; echo "exit=$?"            # expect: exit=1; scratch.txt still reads "conflicting"
  "$BIN" sync; echo "exit=$?"       # expect: "git pull stopped partway through a rebase", --continue, --abort, exit=1
  "$BIN"; echo "exit=$?"            # expect: the same, on the next run
  "$BIN" sync; echo "exit=$?"       # expect: "<memo> is partway through a rebase, so nothing was synced", exit=1
  git -C "$R/memo" ls-files -u | wc -l                     # expect: non-zero — ⚠ nothing was staged mid-rebase
  git --git-dir="$R/remote.git" grep -c '<<<<<<<' main --; echo "exit=$?"   # expect: exit=1 — ⚠ no marker reached the remote
  git -C "$R/memo" stash list | wc -l                      # expect: 0
done
```

⚠ **Observed on 2026-10-27 against `5b4c215` (`v0.4.1`), git 2.56.0**: ⚠ **with a plain config both
uncommitted cases said "Fix the remote" and `zemo sync` exited `1`;** ⚠ **with `rebase.autoStash=true`,
`zemo` exited `0`, pushed `<<<<<<< Updated upstream` to the remote, and left an `autostash` entry in
`git stash list`.** ⚠ **The second `sync` and the `ls-files -u` line catch `add -A` run mid-rebase** —
⚠ **removing the check made the count `0`.**

- ⚠ **An editor that is found but cannot be started is checked on purpose** (hidetzu/zemo#28) —
  ⚠ **the unit tests cover the classification, not that `runEditor` goes through it:**

```sh
ED="$(mktemp -d)"; mkdir -p "$ED/loop" "$ED/noexec" "$ED/dir/ed" "$ED/memo"
ln -s true "$ED/loop/true"                                           # ⚠ a loop, on purpose this time
printf '#!/bin/sh\nexit 0\n' > "$ED/noexec/ed"                       # no execute bit
ZEMO_DIR="$ED/memo" PATH="$ED/loop" ZEMO_EDITOR=true "$BIN"; echo "exit=$?"
                    # expect: "could not start the editor true." + "executable file (a shell alias or builtin will not do)", exit=1
ZEMO_DIR="$ED/memo" PATH="$ED/noexec" ZEMO_EDITOR=ed "$BIN"; echo "exit=$?"   # expect: "could not start the editor ed: permission denied.", exit=1
ZEMO_DIR="$ED/memo" ZEMO_EDITOR="$ED/dir/ed" "$BIN"; echo "exit=$?"            # expect: "…: permission denied.", exit=1
```

⚠ **On `ebec599` all three printed an error name (`error: FileSystem`, `error: AccessDenied`) —
observed 2026-10-27, Zig 0.17.0, Linux x86_64.** ⚠ **Bypassing the classification in `runEditor`
passes every unit test and fails only here.**

⚠ **Observed on 2026-10-18 while writing this step**: ⚠ **`ln -s "$(command -v true)"` made `true -> true`
(the builtin's name, not a path), the editor could not start, and zemo printed `error: FileSystem`** —
⚠ **a broken fixture, and separately an error name reaching the user from the editor launch (not this
step's subject; it is hidetzu/zemo#28).**

---

## 4. What a fix owes

- ⚠ **Every fixed bug leaves a case behind**, next to the function it covers, in `src/*.zig`.
- ⚠ **Break the code on purpose and watch it fail**, ⚠ **and read the failure text to confirm it
  failed for the reason intended** (contract, § "It failed" is not enough).
  ⚠ **Record that text verbatim in `Mutation check`.**
- ⚠ **`zig build test` caches.** ⚠ **A mutation that changes nothing the test compiles against can
  report the previous run** — ⚠ **confirm the failure text moved, not just that the exit code did.**
