# `zemo ideas` — specification

⚠ **This is the contract, not the record of what is claimed.**
⚠ **What may be claimed is [`SPEC.md`](SPEC.md), and a row reaches its §1 only once the
behaviour exists and a case asserts it** — ⚠ **never because this document says so.**

⚠ **How to work is [`../CLAUDE.md`](../CLAUDE.md); how to write it is
[`../.claude/rules/zig.md`](../.claude/rules/zig.md); why the storage looks like this is
[`adr/0001-an-ideas-status-lives-only-in-its-front-matter.md`](adr/0001-an-ideas-status-lives-only-in-its-front-matter.md).**

⚠ **`MUST` = required, `SHOULD` = default, `MAY` = optional.**
⚠ **`⚠` marks "it hurts if you step on it".**

---

## 1. Why

A topic is a place to write. ⚠ **An idea is a thing that has to be decided about** — kept, ranked,
tried, shipped, or dropped — ⚠ **and a topic file cannot say which of those happened.**

Today that decision lives in the user's head, or in a line of prose somewhere in `scratch.txt`,
which means it cannot be listed, cannot be sorted, and cannot be reviewed later.
`ideas` gives it a place: a markdown file whose YAML front matter carries the judgement,
in the same repository, synced by the same `git` calls.

⚠ **What this is not**: a tracker, a board, a database, or a second thing to keep in sync with
GitHub issues. ⚠ **When an idea becomes work, it gets a `repo:` line and the work happens there.**

⚠ **The design constraint that outranks the feature**: `zemo` claims one static binary and no
runtime dependency beyond `git` and an editor ([`SPEC.md`](SPEC.md)).
⚠ **`ideas` does not spend that.** ⚠ **No YAML library, no index file, no cache** — the front
matter is a handful of `key: value` lines and it is parsed by hand (§4-4).

---

## 2. File structure

```
<memo>/                        # ZEMO_DIR, or $HOME/memo
├── scratch.txt                # unchanged
├── topics/
│   └── <topic>.md             # unchanged
└── ideas/
    ├── zig-lsp-server.md
    ├── memo-sync-daemon.md
    └── terminal-canvas.md
```

- MUST: ⚠ **`<memo>/ideas/` is flat.** ⚠ **No subdirectory carries meaning**
  (ADR 0001). ⚠ **A subdirectory found there is left alone and left out of every listing** —
  the same rule `ls` already applies under `topics/`.
- MUST: ⚠ **An idea name is `[a-zA-Z0-9_-]`, non-empty** — ⚠ **the same gate as a topic, through
  the same `paths.isValidTopic`.** ⚠ **Never a second validator**
  ([`../.claude/rules/zig.md`](../.claude/rules/zig.md)).
- MUST: The file is `<memo>/ideas/<name>.md`. ⚠ **Only `.md` files are listed**; anything else in
  the directory is left alone.
- MUST: ⚠ **`<memo>/ideas/` is created on first use, like `topics/`** — ⚠ **and never anywhere
  but under the memo directory.**

⚠ **There is no `ideas/scratch`.** ⚠ **`scratch` already means one file, `<memo>/scratch.txt`**
([`../CLAUDE.md`](../CLAUDE.md) §4), ⚠ **and a second thing called scratch would take a name that
is spoken for.** An unformed idea is an idea with `status: backlog` and an empty body.

---

## 3. Front matter

```markdown
---
status: prioritized
priority: 2
evaluation: solves my own daily friction; nobody has shipped a good one for Zig
tags: zig, lsp, editor
repo: hidetzu/zig-lsp-server
created: 2026-09-06
---

# zig-lsp-server

<free markdown, the user's own>
```

- MUST: ⚠ **The front matter is the first thing in the file**, opened by `---` on line 1 and
  closed by `---` on a line of its own. ⚠ **A file whose line 1 is not `---` has no front matter**
  — it is reported as such, ⚠ **never silently treated as `backlog`**
  ([`../.claude/rules/evidence.md`](../.claude/rules/evidence.md): absent ≠ default).
- MUST: ⚠ **Unknown keys are preserved byte for byte.** ⚠ **The user's file is theirs**;
  `zemo` rewrites the one line it was asked to change and touches nothing else.
- MUST: ⚠ **Key order is preserved.** ⚠ **A rewrite is a line edit, never a re-serialisation.**

| Key | Required | Value | ⚠ What it must not be confused with |
|---|---|---|---|
| `status` | ⚠ **yes** | One of §5's names | — |
| `priority` | no | An integer `1`–`5`, ⚠ **`1` highest** | ⚠ **Absent means "not ranked yet".** ⚠ **Never the same as `5`** |
| `evaluation` | no | One line: ⚠ **what was judged, and on what basis** | ⚠ **Never a score, a percentage, or a confidence figure** — [`../.claude/rules/evidence.md`](../.claude/rules/evidence.md) forbids a number that was not measured |
| `tags` | no | Comma-separated, each `[a-zA-Z0-9_-]` | ⚠ **Not a status.** ⚠ **A tag never decides anything** |
| `repo` | no | `owner/repo` | ⚠ **Written in full, never a bare name** ([`../.claude/rules/git.md`](../.claude/rules/git.md)). ⚠ **Absent means "no code yet", not "lost"** |
| `created` | ⚠ **yes** | `YYYY-MM-DD`, local time, ⚠ **set once at creation and never rewritten** | ⚠ **Not "last touched"** — `git log` answers that, and it answers it better |

⚠ **`tags` is a comma-separated string, not a YAML list.** ⚠ **Grounds: a real YAML list means a
real YAML parser, and that is a dependency** (§1). ⚠ **This is a deliberate narrowing of YAML,
and it is why the format is called front matter here and not YAML.**

### 3-1. ⚠ What a malformed file must produce

⚠ **These are different outcomes and they never collapse into one**
([`../.claude/rules/evidence.md`](../.claude/rules/evidence.md), § Outcomes are not one outcome).

| What the file is | ⚠ What must happen |
|---|---|
| Well-formed | The value is used |
| ⚠ **No front matter at all** (line 1 is not `---`) | ⚠ **Named as such**, listed with `status: —`. ⚠ **Never repaired without being asked** |
| ⚠ **Front matter opened and never closed** | ⚠ **Named as such.** ⚠ **Never read the whole file as front matter** |
| ⚠ **`status:` present with a name §5 does not list** | ⚠ **Named, with the value quoted back.** ⚠ **Never coerced to the nearest match** |
| ⚠ **`priority:` present and not an integer `1`–`5`** | ⚠ **Named, with the value quoted back.** ⚠ **Never read as absent** — ⚠ **"unparseable" and "not ranked" are different things** |
| ⚠ **`status:` absent** | ⚠ **Named.** ⚠ **Never defaulted to `backlog`** |

- MUST: ⚠ **A malformed idea never stops the others being listed.** ⚠ **`ideas:list` prints
  every idea and marks the ones it could not read.**
- MUST: ⚠ **`ideas:status` and `ideas:priority` refuse to write into a file they could not
  parse.** ⚠ **Fail closed** — ⚠ **a rewrite of a file we misread is how the user's own text
  gets destroyed.**

---

## 4. Commands

⚠ **Exit codes are `0` success, `1` the operation failed, `2` the command line was wrong**
([`../CLAUDE.md`](../CLAUDE.md) is the owner of the wording; `zig.md` of the codes).

⚠ **Every message below is a sentence saying what happened and what to do about it**
([`../CLAUDE.md`](../CLAUDE.md) §4-1). ⚠ **The examples are the specification of the wording,
not decoration.**

### 4-1. `zemo ideas:new <name>`

Creates `<memo>/ideas/<name>.md` and opens it in the editor.

```console
$ zemo ideas:new zig-lsp-server
(editor opens on <memo>/ideas/zig-lsp-server.md)
```

The file it is created with:

```markdown
---
status: backlog
priority:
evaluation:
tags:
repo:
created: 2026-09-06
---

# zig-lsp-server

```

- MUST: ⚠ **An existing file is opened, never overwritten and never re-templated.**
  ⚠ **Same as `zemo <topic>`.**
- MUST: ⚠ **The empty keys are written out.** ⚠ **A key with no value is the prompt to fill it
  in**; ⚠ **an absent key looks like the format changed.**
  ⚠ **An empty value reads as absent** (§3), ⚠ **not as an error.**
- MUST: `created` is the local date at creation, ⚠ **and no command ever rewrites it.**
- MUST: git — ⚠ **pull before the file is created, commit and push after the editor exits**,
  exactly as `zemo <topic>` already does (§6).

### 4-2. `zemo ideas:list [--sort=priority|created]`

⚠ **Read-only.** ⚠ **No git operation, same as `zemo ls` and `zemo cat`.**

```console
$ zemo ideas:list
PRI  STATUS         NAME                  EVALUATION
  1  experimenting  zig-lsp-server        solves my own daily friction; nobody h...
  2  prioritized    terminal-canvas       the demo landed well; unclear who pays
  -  backlog        memo-sync-daemon      interesting, no reason to build it yet
  -  unreadable     half-written          front matter is never closed
```

- MUST: ⚠ **Default sort is `--sort=priority`.**
  ⚠ **Ranked ideas first, ascending (`1` before `5`); ⚠ unranked after them, never mixed in as
  if they were `5`** (§3). ⚠ **Ties break by name, so the order is stable between runs.**
- MUST: `--sort=created` sorts by the `created` value, newest first, ⚠ **ties by name.**
- MUST: ⚠ **Any other `--sort=` value exits `2`** and names the two that exist.
  ⚠ **Never fall back to the default** — ⚠ **a typo would then silently answer a different
  question.**
- MUST: ⚠ **An unreadable idea appears in the listing, marked**, with what could not be read
  (§3-1). ⚠ **It is never dropped**, ⚠ **and it never stops the command.**
- MUST: ⚠ **`<memo>/ideas/` missing or empty prints nothing and exits `0`** —
  ⚠ **the same shape `zemo dump` already has.** ⚠ **Never an error**: having no ideas is not a
  failure.
- SHOULD: `evaluation` is truncated to fit one line, marked with `...`.
  ⚠ **`ideas:show` is what prints it whole.**
  ⚠ **Truncate on a UTF-8 boundary** — ⚠ **an evaluation can be Japanese, and cutting mid-sequence
  emits bytes no terminal can render.**
- MUST: ⚠ **The output is ASCII.** ⚠ **The unreadable marker is the word `unreadable` and the
  truncation mark is `...`** — ⚠ **not `⚠` and not `…`.** ⚠ **Grounds: this ships to a Windows
  console, and a marker that renders as garbage is worse than a plain word.**
  ⚠ **The `⚠` in this document is the document's own convention; it is not output.**
- SHOULD: ⚠ **Do not pad past the last column.** A row whose evaluation is empty ends at the name,
  with no trailing spaces.

### 4-3. `zemo ideas:show <name>`

⚠ **Read-only.** ⚠ **No git operation, same as `zemo cat`.**

```console
$ zemo ideas:show zig-lsp-server
(the file, byte for byte, front matter included)
```

- MUST: ⚠ **Byte for byte, front matter included.** ⚠ **Never reformatted, never re-ordered** —
  ⚠ **this is the command a user reaches for when they suspect the file is wrong**, so hiding
  the front matter would hide the answer.
- MUST: ⚠ **A missing idea exits `1` with a sentence on stderr and nothing on stdout** —
  the shape `zemo cat` already has.

### 4-4. `zemo ideas:status <name> <status>`

Rewrites the `status:` line. ⚠ **Nothing else in the file changes.**

```console
$ zemo ideas:status zig-lsp-server experimenting
zig-lsp-server: prioritized -> experimenting
```

- MUST: ⚠ **Print the transition, both ends.** ⚠ **"ok" does not tell the user what it was
  before**, and the value it was before is the thing they are about to be unable to check.
- MUST: ⚠ **Refuse a transition §5 does not permit, exit `1`**, and ⚠ **name the ones that are
  permitted from where it actually is.**
- MUST: ⚠ **Refuse a file whose front matter could not be parsed, exit `1`** (§3-1).
- MUST: ⚠ **Setting the status it already has is not an error.** ⚠ **It writes nothing, commits
  nothing, and says so** (`<name>: already <status>`) — ⚠ **an empty commit is noise in a history
  the user reads.**
- MUST: ⚠ **A status name §5 does not list exits `2`**, not `1`, and ⚠ **names every status that
  exists.** ⚠ **The command line was wrong; the idea was not.**
- MUST: ⚠ **The rewrite replaces one line.** ⚠ **Read the file, write a temporary file in the
  same directory, then rename over it** — ⚠ **a truncate-then-write loses the user's idea if
  anything fails in between.**
- MUST: git — pull, rewrite, commit, push (§6).

### 4-5. `zemo ideas:priority <name> <priority>`

Rewrites the `priority:` line. ⚠ **Nothing else in the file changes.**

```console
$ zemo ideas:priority zig-lsp-server 1
zig-lsp-server: priority 2 -> 1
```

- MUST: ⚠ **`1`–`5` only.** ⚠ **Anything else exits `2`** and names the range.
- MUST: ⚠ **`-` clears it back to unranked**, and the message says `2 -> unranked`.
  ⚠ **Unranked is a value a user can choose**, ⚠ **not only a state a file starts in.**
- MUST: ⚠ **Print both ends**, and ⚠ **say `unranked`, never `-` or nothing**, when either end
  is absent.
- MUST: ⚠ **Setting the priority it already has writes nothing and says so**
  (`<name>: already priority <n>`, or `already priority unranked`), as §4-4.
- MUST: ⚠ **Priority and status are independent.** ⚠ **Ranking an idea does not move it to
  `prioritized`** — ⚠ **that is §5's business, and doing it here would be one command making two
  decisions.**
- MUST: git — pull, rewrite, commit, push (§6).

### 4-6. ⚠ Parsing `ideas:<verb>`

⚠ **`:` is not in the topic character set**, so today `zemo ideas:new` reaches `open_topic` and
is rejected as an invalid topic name.

- MUST: ⚠ **The `ideas:` prefix is matched before the bare-word fallback** in `parseArgs`.
- MUST: ⚠ **`ideas:<something we do not have>` exits `2`** and names the verbs that exist.
  ⚠ **Never fall through to "invalid topic name"** — ⚠ **the user typed a command, and telling
  them it is a bad filename sends them to fix the wrong thing** ([`../CLAUDE.md`](../CLAUDE.md) §4-1).
- MUST: ⚠ **A bare `zemo ideas` exits `2`** and prints the ideas verbs.
- MUST: ⚠ **`HELP_TEXT` carries every verb** ([`../CLAUDE.md`](../CLAUDE.md) §5).

---

## 5. Status, and how it moves

```text
                    ┌──────────────┐   ┌───────────────┐
                    v              │   v               │
   ┌──────────┐   ┌─────────────┐  │ ┌───────────────┐ │  ┌───────────┐
   │ backlog  │──>│ prioritized │──┴>│ experimenting │─┴─>│ published │
   └────┬─────┘   └──────┬──────┘    └───────┬───────┘    └───────────┘
        │                │                   │             ⚠ terminal
        └────────────────┴───────────────────┘
                         │
                         v
                   ┌───────────┐
                   │  dropped  │   ⚠ terminal, ⚠ and NOT the same as published
                   └───────────┘
```

| Status | What it means | ⚠ What it must not be confused with |
|---|---|---|
| `backlog` | Written down. ⚠ **Nothing has been decided about it** | ⚠ **Not "rejected".** Nobody has looked |
| `prioritized` | Looked at, ranked, ⚠ **and worth doing** | ⚠ **Not "started"** |
| `experimenting` | Something is being built or tried | ⚠ **Not "it works"** |
| `published` | ⚠ **It shipped, and the thing exists** | ⚠ **Not "finished thinking about it"** |
| `dropped` | ⚠ **Decided against, on purpose** | ⚠ **Not `backlog`.** ⚠ **`backlog` is undecided; `dropped` is decided.** ⚠ **Collapsing them loses the one thing worth keeping — that it was already considered** |

- MUST: **Forward, one step at a time.** `backlog → prioritized → experimenting → published`.
- MUST: **Backward, one step at a time.** `prioritized → backlog` (deprioritised),
  `experimenting → prioritized` (shelved). ⚠ **These happen and they are not failures.**
- MUST: **`→ dropped` from `backlog`, `prioritized` or `experimenting`.**
- MUST NOT: ⚠ **Nothing leaves `published` or `dropped`.**
  ⚠ **An idea that comes back is a new idea with a new file** — ⚠ **and the old file, which says
  what was decided and when, stays exactly as it is.**
- MUST NOT: ⚠ **No skipping.** ⚠ **`backlog → published` is refused**, and the refusal names
  what is permitted from `backlog`.
  ⚠ **Grounds: a skipped step is a step nobody decided**, and this feature exists to record
  the deciding (§1).
- MUST: ⚠ **The graph lives in one place in the code**, and ⚠ **`ideas:list`, the refusal message
  and this table all read from it.** ⚠ **A second copy of the transitions is exactly what
  [`../CLAUDE.md`](../CLAUDE.md) §3 forbids.**

⚠ **There is no `archived`.** ⚠ **`published` and `dropped` are the two ways an idea ends, and
they are different** — ⚠ **one name over both would say only "it is over", which is the half
that does not matter.**

---

## 6. Git

⚠ **`ideas` adds no git behaviour.** ⚠ **It uses the calls that are already there**
(`src/git.zig`: `pull --rebase`, `add -A`, `commit`, `push`), ⚠ **under the conditions
[`../.claude/rules/zig.md`](../.claude/rules/zig.md) already sets** — ⚠ **including that the memo
directory must be a work-tree *root* before anything is staged.**

| Command | git |
|---|---|
| `ideas:list`, `ideas:show` | ⚠ **None.** Read-only, same as `zemo ls` / `cat` / `dump` |
| `ideas:new` | pull → create → editor → add → commit → push |
| `ideas:status`, `ideas:priority` | pull → rewrite → add → commit → push |

Commit messages, ⚠ **Conventional Commits, scope `ideas`**:

```text
docs(ideas): zig-lsp-server 2026-09-06 14:32          # ideas:new, after the editor
docs(ideas): zig-lsp-server prioritized -> experimenting
docs(ideas): zig-lsp-server priority 2 -> 1
```

- MUST: ⚠ **The subject says which idea and what changed.** ⚠ **`git log --oneline` is the
  history of the deciding**, ⚠ **and a timestamp-only subject would throw that away.**
- MUST: ⚠ **Nothing is committed when nothing changed** — `hasStagedChanges` already gates this,
  ⚠ **and `ideas:status` / `ideas:priority` also refuse before writing** (§4-4).
- MUST: ⚠ **`<memo>/.git` absent means the editor still opens and the sync is skipped**, the
  behaviour `zemo <topic>` already has. ⚠ **`ideas` never initialises a repository**
  ([`SPEC.md`](SPEC.md) §2).
- MUST: ⚠ **A git failure is reported as a git failure, naming the step**, and ⚠ **`git` missing
  is a different sentence from `git` failing** ([`../CLAUDE.md`](../CLAUDE.md) §4-1).

---

## 7. Worked example

```console
$ zemo ideas:new zig-lsp-server
(editor; the user writes the body and fills in evaluation and tags)

$ zemo ideas:list
PRI  STATUS         NAME                 EVALUATION
  -  backlog        zig-lsp-server       solves my own daily friction; nobody has …

$ zemo ideas:priority zig-lsp-server 2
zig-lsp-server: priority unranked -> 2

$ zemo ideas:status zig-lsp-server prioritized
zig-lsp-server: backlog -> prioritized

$ zemo ideas:status zig-lsp-server published
zemo: zig-lsp-server is prioritized; from there it can go to backlog, experimenting or dropped

$ zemo ideas:status zig-lsp-server experimenting
zig-lsp-server: prioritized -> experimenting

$ zemo ideas:show zig-lsp-server | head -3
---
status: experimenting
priority: 2

$ git -C ~/memo log --oneline -- ideas/zig-lsp-server.md
a1b2c3d docs(ideas): zig-lsp-server prioritized -> experimenting
e4f5g6h docs(ideas): zig-lsp-server backlog -> prioritized
i7j8k9l docs(ideas): zig-lsp-server priority unranked -> 2
m0n1o2p docs(ideas): zig-lsp-server 2026-09-06 14:32
```

---

## 8. What this specification does not settle

⚠ **A gap named here is a decision to name it later.** ⚠ **An unnamed gap is just something
forgotten** ([`SPEC.md`](SPEC.md) §2 draws the same line).

| Not settled | Why it is left open |
|---|---|
| Filtering `ideas:list` by status or tag | ⚠ **`grep` answers it today.** ⚠ **A flag earns its place when the listing is too long to read, and it is not yet** |
| Renaming an idea | ⚠ **`git mv` and an editor answer it.** ⚠ **A command would have to decide what happens to the history, and nobody has needed it yet** |
| Any link to GitHub issues beyond the `repo:` line | ⚠ **A network call outside `zemo upgrade` needs an ADR** ([`../CLAUDE.md`](../CLAUDE.md) §3) |
| Whether `topics/` and `ideas/` should share anything | ⚠ **Deliberately not decided before both exist.** ⚠ **A shared abstraction chosen from one example is a guess** |

---

## 9. Verification this owes

⚠ **The contract is [`../.claude/rules/verification.md`](../.claude/rules/verification.md);
what to run is [`../.claude/skills/verify/SKILL.md`](../.claude/skills/verify/SKILL.md).**
⚠ **This section names only what `ideas` in particular has to show before any row reaches
[`SPEC.md`](SPEC.md) §1.**

⚠ **Priority order is the contract's** (parsing of outside input first, then state transitions,
then hostile input, then the path a user walks).

- **Front-matter parsing, as a pure function**, against fixtures for ⚠ **every row of §3-1** —
  ⚠ **including the ones that must not collapse into each other** (absent vs. unparseable,
  no front matter vs. unterminated).
- **The transition graph, as a pure function**: ⚠ **every permitted edge, and the refusals** —
  ⚠ **skipping, leaving a terminal state, and setting the status it already has.**
- **The rewrite, as a pure function**: input text and one field in, ⚠ **output text out.**
  ⚠ **Assert that unknown keys, key order and the body survive byte for byte** — that is the
  clause most likely to be broken by an innocent change.
- **Name validation**: ⚠ **that `ideas:new ../etc` is refused before anything is joined**
  ([`../.claude/rules/zig.md`](../.claude/rules/zig.md)).
- **Sorting**: unranked ideas after ranked ones, ⚠ **and the tie-break, so the order is stable.**
- **Final gate**: the built binary against a throwaway `ZEMO_DIR`, walking §7 end to end.
  ⚠ **Never the real memo directory** ([`../CLAUDE.md`](../CLAUDE.md) §2).
- **External**: §7 again against a real `git` with a local bare remote, ⚠ **asserting the commit
  subjects in §6 are what actually landed** — ⚠ **reading them out of `git log`, not out of our
  own format string.**

---

## 10. ⚠ What the first implementation had to be told

⚠ **These are not predictions.** ⚠ **Each one is something that actually went wrong or was
actually observed while building this, and each left a case behind.**

- ⚠ **Rewriting a `status:` line dropped the `\r` of a CRLF file**, silently converting the whole
  line ending. ⚠ **The line's terminator has to be taken from the end of its *content*, not from
  the index of the `\n`** — the trimmed line no longer carries the `\r`.
  Case: `rewriteField: a CRLF file stays CRLF`.
- ⚠ **`git pull --rebase` against an empty remote fails**, so a check whose fixture is a fresh
  bare repository reports `git pull failed` and asserts nothing.
  ⚠ **Seed the remote with a commit** ([`../.claude/skills/verify/SKILL.md`](../.claude/skills/verify/SKILL.md)).
  ⚠ **This is a property of `git`, not of `ideas`** — it is here because it is where a check gets
  lost, not because `ideas` caused it.
