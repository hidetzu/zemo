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
⚠ **Planned is not implemented.**

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

| `ideas` names | An idea is `<memo>/ideas/<name>.md`; ⚠ **the directory is flat and no subdirectory carries meaning**; the name passes the same gate as a topic | [`ideas-spec.md`](ideas-spec.md) §2; [`adr/0001-an-ideas-status-lives-only-in-its-front-matter.md`](adr/0001-an-ideas-status-lives-only-in-its-front-matter.md) | `ideaPath: dir/ideas/<name>.md`, `ideaPath: ideas and topics never collide for the same name`, and the `isValidTopic:` cases above |
| `ideas` front matter | `status`, `priority`, `evaluation`, `tags`, `repo`, `created` are read from the leading `---` block; ⚠ **an empty `priority` is unranked, not an error**; a value keeps everything after its first colon; CRLF is read | [`ideas-spec.md`](ideas-spec.md) §3 | `parse: reads every field`, `parse: an empty priority is unranked, not an error`, `parse: a repo value keeps everything after the first colon`, `parse: CRLF front matter` |
| `ideas` front matter | ⚠ **Each way of being malformed is a different outcome**: no front matter, never closed, `status` absent, `status` unknown, `priority` unparseable — ⚠ **none is coerced, defaulted, or read as absent** | [`ideas-spec.md`](ideas-spec.md) §3-1; [`../.claude/rules/evidence.md`](../.claude/rules/evidence.md) § Outcomes are not one outcome | `parse problem: no front matter`, `parse problem: front matter opened and never closed`, `parse problem: status absent is not the same as unknown`, `parse problem: an unknown status is never coerced to the nearest match`, `parse problem: unparseable priority is not read as absent`, `Problem.write: each failure says which failure it was` |
| `ideas` status | Forward and backward one step at a time; `dropped` from any non-terminal; ⚠ **nothing skips a step and nothing leaves `published` or `dropped`** | [`ideas-spec.md`](ideas-spec.md) §5 | `canTransition: forward one step at a time`, `canTransition: backward one step at a time`, `canTransition: dropped from any non-terminal, never from a terminal`, `canTransition: no skipping`, `canTransition: nothing leaves a terminal state`, `TRANSITIONS covers every Status` |
| `ideas` status | A refusal names what is reachable from where the idea actually is, ⚠ **and a terminal state says `nowhere` rather than nothing** | [`ideas-spec.md`](ideas-spec.md) §4-4 | `writeAllowedFrom: comma list ending in `or``, `writeAllowedFrom: a terminal state says nowhere, never nothing` |
| `ideas` rewrite | One line is replaced; ⚠ **unknown keys, key order, the body and the line endings survive byte for byte**; a missing key is inserted before the closing `---`; an empty value writes `key:` with no trailing space | [`ideas-spec.md`](ideas-spec.md) §3, §4-4 | `rewriteField: replaces one line and preserves everything else byte for byte`, `rewriteField: a CRLF file stays CRLF`, `rewriteField: a missing key is inserted before the closing ---`, `rewriteField: an empty value writes `key:` with no trailing space`, `rewriteField: the body is untouched even when it looks like front matter` |
| `ideas` rewrite | The file is replaced through a sibling temp file and a rename, ⚠ **so a failure part-way cannot leave the idea truncated**, and no temp file is left behind | [`ideas-spec.md`](ideas-spec.md) §4-4 | `writeFileReplacing: replaces the file and leaves no temp behind` |
| `ideas:new` | The created file parses back as `backlog` and unranked, carries the local date in `created`, and heads the body with the name | [`ideas-spec.md`](ideas-spec.md) §4-1 | `template: parses back as backlog and unranked`, `formatDate: zero-pads and drops the time`, `formatDate: is the date prefix of formatTimestamp` |
| `ideas:list` | Ranked first ascending, ⚠ **unranked after them rather than mixed in as `5`**, ties by name; `--sort=created` is newest first with missing dates last | [`ideas-spec.md`](ideas-spec.md) §4-2 | `sortEntries by priority: ranked first ascending, unranked after, ties by name`, `sortEntries by created: newest first, missing last, ties by name` |
| `ideas:list` | ⚠ **An unreadable idea keeps its row and says why**, and sorts as unranked; ⚠ **an empty or absent `ideas/` prints nothing and exits `0`**; non-`.md` entries are left out | [`ideas-spec.md`](ideas-spec.md) §4-2 | `listIdeas: sorted, unreadable rows kept, and nothing printed when empty`, `sortEntries by priority: an unreadable idea sorts as unranked, never dropped`, `writeListRow: an unreadable idea keeps its row and says why` |
| `ideas:list` | Output is ASCII; a long `evaluation` is marked `...` and ⚠ **cut on a UTF-8 boundary**; a row with no evaluation ends at the name | [`ideas-spec.md`](ideas-spec.md) §4-2 | `truncateUtf8: never splits a multibyte sequence`, `writeListRow: a long evaluation is marked as truncated`, `writeListRow: an empty evaluation leaves no trailing space` |
| `ideas` argument parsing | `ideas:` is matched before the bare-word fallback, so ⚠ **an unknown verb is a command error and never "invalid topic name"**; a topic merely starting with `idea` is still a topic | [`ideas-spec.md`](ideas-spec.md) §4-6 | `parseArgs: an unknown ideas verb is a command error, never an invalid topic name`, `parseArgs: a topic named like a prefix is still a topic` |
| `ideas` argument parsing | Each verb takes a fixed number of arguments; `--sort` defaults to `priority` and ⚠ **an unknown `--sort` never falls back to the default** | [`ideas-spec.md`](ideas-spec.md) §4-2 | `parseArgs: ideas:new takes exactly one name`, `parseArgs: ideas:show takes exactly one name`, `parseArgs: ideas:status and ideas:priority take a name and a value`, `parseArgs: ideas:list defaults to priority`, `parseArgs: an unknown --sort never falls back to the default` |
| `ideas` argument parsing | `-` unranks; ⚠ **anything outside `1`-`5` is invalid rather than unranked** | [`ideas-spec.md`](ideas-spec.md) §4-5 | `parsePriorityArg: 1-5, `-` for unranked, and everything else invalid` |
| Help | ⚠ **`--help` names every `ideas` verb** | `HELP_TEXT` in `src/cli.zig` | `HELP_TEXT names every ideas verb` |

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
| ⚠ **Filtering, renaming, or any network link for `ideas`** | ⚠ **no** | ⚠ **Left open on purpose, and named as open** ([`ideas-spec.md`](ideas-spec.md) §8). ⚠ **`grep` and `git mv` answer the first two today; the third needs an ADR** |
| ⚠ **`ideas` front matter as real YAML** | ⚠ **yes** | ⚠ **`tags` is a comma-separated string, not a list.** ⚠ **A real list means a real YAML parser, and that is a dependency** ([`ideas-spec.md`](ideas-spec.md) §3) |
| ⚠ **The `ideas` end-to-end walkthrough as an automated check** | ⚠ **no** | ⚠ **It is run by hand from [`../.claude/skills/verify/SKILL.md`](../.claude/skills/verify/SKILL.md)**, final gate and external. ⚠ **So the rows in §1 are asserted by the inner tier; ⚠ the walkthrough is evidence from a run, not a standing check** |

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
