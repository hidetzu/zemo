# SPEC — what zemo may claim

⚠ **This file holds what this project may claim about itself.** ⚠ Nothing else.
**How to work** is [`CLAUDE.md`](../CLAUDE.md); **how to write it** is
[`.claude/rules/`](../.claude/rules/); **why** is [`adr/`](adr/).

⚠ **Never write a count in here** ([`evidence.md`](../.claude/rules/evidence.md)).
⚠ **Counts are announced by whatever produced them**, at the moment it runs
(`zig build test --summary all`).
⚠ **A count written down here is stale from the moment it is written, and it makes every
parallel change conflict.**

---

## 1. What this implements

⚠ **A row goes in here only once the behaviour exists and a check asserts it.**
⚠ **Planned is not implemented.** ⚠ **The `ideas` feature has no row, and that is why**
([`ideas-spec.md`](ideas-spec.md) is a specification, not a claim).

⚠ **"What asserts it" names a case, not a file.**

⚠ **The authority for the user-facing surface is [`../README.md`](../README.md) and the
`HELP_TEXT` block in `src/cli.zig`** — ⚠ **they are what a user reads, so they are what we are
held to.** ⚠ **Where they disagree with each other, that is a bug in this project, not an
ambiguity to interpret.**

| Layer | What is supported | Which authority, which section | What asserts it |
|---|---|---|---|
| Argument parsing | Bare `zemo` opens scratch; a single bare word opens that topic; a second bare word is rejected | `README.md` § Usage; `HELP_TEXT` | `parseArgs: no args opens scratch`, `parseArgs: single topic`, `parseArgs: too many args` |
| Argument parsing | `sync`, `ls`, `dump`, `help` / `--help` / `-h`, `version` / `--version` / `-V` | `HELP_TEXT` | `parseArgs: sync subcommand`, `parseArgs: ls subcommand`, `parseArgs: dump subcommand`, `parseArgs: help variants`, `parseArgs: version variants` |
| Argument parsing | `cat` with no topic means scratch; `cat <topic>` means that topic; a third argument is rejected | `HELP_TEXT` | `parseArgs: cat without topic`, `parseArgs: cat with topic`, `parseArgs: cat too many args` |
| Argument parsing | `upgrade` runs, `upgrade --check` dry-runs, anything else on that line is rejected | `README.md` § Usage; `HELP_TEXT` | `parseArgs: upgrade run`, `parseArgs: upgrade check`, `parseArgs: upgrade with invalid arg`, `parseArgs: upgrade with too many args` |
| Names → paths | A topic name is `[a-zA-Z0-9_-]`, non-empty; ⚠ **path separators, `..`, dots, spaces and multibyte are rejected** | `README.md` § Usage ("Topic name must match `[a-zA-Z0-9_-]`") | `isValidTopic: accepts alphanumerics, underscore, hyphen`, `isValidTopic: rejects empty string`, `isValidTopic: rejects path traversal and separators`, `isValidTopic: rejects dots, spaces, multibyte` |
| Names → paths | Scratch is `<memo>/scratch.txt`; a topic is `<memo>/topics/<topic>.md` | `README.md` § Usage | `scratchPath: ends with scratch.txt`, `topicPath: dir/topics/<topic>.md` |
| Configuration | `ZEMO_DIR` wins; otherwise `$HOME/memo` (`%USERPROFILE%\memo` on Windows); with neither, an error | `README.md` § Configuration | `resolveMemoDir: ZEMO_DIR has highest priority`, `resolveMemoDir: falls back to HOME/memo on unix`, `resolveMemoDir: errors when no env available` |
| Configuration | A relative memo directory is resolved against the working directory; an absolute one is left alone | `README.md` § Configuration | `absolutePath: keeps absolute paths`, `absolutePath: resolves relative paths from cwd` |
| Configuration | `ZEMO_EDITOR` wins over the fallback list; the fallback list differs by platform; with neither, an error | `README.md` § Configuration | `resolveEditor: ZEMO_EDITOR has highest priority`, `resolveEditor: uses chosen fallback when no env vars set`, `resolveEditor: errors when no env vars and no fallback`, `fallbackCandidates: unix list`, `fallbackCandidates: windows list` |
| Configuration | An editor setting may carry flags, and they are passed through as separate arguments | `README.md` § Configuration | `splitCommand: single token`, `splitCommand: command with flags` |
| `ls` | Topic names only, alphabetical; ⚠ **non-`.md` entries and subdirectories are left out** | `README.md` § Usage | `listTopics: alphabetical order, only .md files` |
| `cat` | Prints the file to stdout byte for byte and exits `0`; ⚠ **a missing file exits `1` with a sentence on stderr and nothing on stdout** | `README.md` § Usage | `printFile: prints file contents to stdout`, `printFile: missing file → exit 1, stderr message` |
| `dump` | Scratch then every topic, sorted, with section headers; non-`.md` entries left out; ⚠ **an empty memo directory prints nothing** | `README.md` § Usage | `dumpMemos: scratch only`, `dumpMemos: topics only sorted and filtered`, `dumpMemos: scratch and topics`, `dumpMemos: neither scratch nor topics prints nothing`, `doDump: uses ZEMO_DIR override` |
| git | ⚠ **A directory is treated as a memo repository only when it is the work-tree root** — a subdirectory of a repository is not | `git` § `rev-parse --show-toplevel` | `isGitRepo: returns true after git init at repo root`, `isGitRepo: returns false for subdir of a repo (not root)` |
| Commit messages | `docs(<scope>): YYYY-MM-DD HH:MM` for an edit, `chore: sync YYYY-MM-DD HH:MM` for `zemo sync`; local time, zero-padded | [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) § Summary; `README.md` § Features | `formatTimestamp: zero-pads single digits`, `formatTimestamp: handles double-digit fields`, `nowLocal: returns plausible values` |
| `upgrade` | Compares the running version against the latest release tag, `v` prefix or not, and rejects unparseable input | `README.md` § Usage | `compareVersions: equal`, `compareVersions: older when local behind`, `compareVersions: newer when local ahead`, `compareVersions: handles ``v`` prefix`, `compareVersions: invalid input` |
| `upgrade` | Picks the asset for the running target; ⚠ **refuses on musl Linux rather than replacing a musl binary with a glibc one** | `README.md` § Usage | `assetName: returns asset for current target`, `assetName: rejects musl Linux to avoid replacing musl with glibc binary` |
| `upgrade` | Reads the release JSON, finds the asset URL when the name matches and returns nothing when it does not, and fails on malformed JSON | GitHub REST API § Releases (`tag_name`, `assets[].browser_download_url`) | `parseReleaseJson: extracts tag_name and assets`, `parseReleaseJson: invalid JSON returns error`, `findAssetUrl: returns URL when asset name matches`, `findAssetUrl: returns null when not found` |
| `upgrade` | Extracts `zemo` from the downloaded archive by basename and replaces the installed file; ⚠ **a basename that is not in the archive is an error, not a silent no-op** | `README.md` § Usage | `extractZemoBinaryFromZip: extracts stored entry by basename`, `extractZemoBinaryFromZip: returns error when basename not in archive`, `replaceBinary: replaces existing file with new contents`, `installPath: returns absolute non-empty path` |

## 2. What this deliberately does not implement

⚠ **A gap named here is a decision.** ⚠ **An unnamed gap is just something not done yet** —
they are different things and the difference is stated, not implied.

| Not implemented | Deliberate? | Why |
|---|---|---|
| Creating or initialising the memo repository | ⚠ **yes** | ⚠ **It is the user's repository and their remote.** `README.md` § Setting up the memo repository tells them how; ⚠ **guessing a remote on their behalf is not recoverable** |
| A configuration file | yes | Configuration is `ZEMO_DIR` and `ZEMO_EDITOR`. ⚠ **A file format is one more thing to learn and one more thing to keep in sync** (`CLAUDE.md` §3) |
| Conflict resolution beyond `pull --rebase` | yes | ⚠ **A conflict in the user's notes is theirs to settle.** `zemo` stops and says so rather than choosing a side |
| Any runtime dependency beyond `git` and an editor | yes | ⚠ **The claim is one static binary.** `build.zig.zon` has no dependency and gaining one is an ADR |
| `upgrade` on musl Linux | yes | ⚠ **The published Linux asset is glibc.** ⚠ **Replacing a musl binary with it would leave a binary that does not start**, so it refuses instead (asserted above) |
| ⚠ **Running the binary on macOS or Windows in CI** | ⚠ **no** | ⚠ **Not a decision, just not done.** ⚠ **CI compiles those targets and executes only Linux** (`.github/workflows/ci.yml`) — ⚠ **so "it builds for Windows" is what may be said, and nothing more** |
| ⚠ **`zemo ideas:*`** | ⚠ **no** | ⚠ **Specified and not yet built** ([`ideas-spec.md`](ideas-spec.md)). ⚠ **A row moves into §1 when the behaviour exists and a case asserts it, ⚠ never when the spec is written** |

## 3. Measured numbers

⚠ **Every number here carries the denominator of its claim, the date, and the conditions**
([`evidence.md`](../.claude/rules/evidence.md)): the versions that matter, how the environment was
built, how many runs, which percentile.

⚠ **A number without those is deleted, not corrected.**

⚠ **Conditions shared by every row below**: Zig 0.16.0 as pinned by `build.zig.zon`; built from a
clean checkout by `zig build`; ⚠ **the host target, which on Linux means the bundled musl libc**
(`build.zig`); `git` and the editor are whatever the machine already had.
⚠ **Each row states its own optimize mode, machine and run count** — ⚠ **a row that does not is
not a measurement.**

⚠ **This table is empty because nothing has been measured under stated conditions yet.**
⚠ **That is not the same as "zemo is fast".** ⚠ **Nothing may be said about its speed or its size
until a row is here.**

| What was measured | Value | When | Under what conditions |
|---|---|---|---|
| — | — | — | — |
