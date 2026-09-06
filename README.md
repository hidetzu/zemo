# zemo

[![CI](https://github.com/hidetzu/zemo/actions/workflows/ci.yml/badge.svg)](https://github.com/hidetzu/zemo/actions/workflows/ci.yml)

Turn any git repository into your terminal notebook.

`zemo` opens markdown notes in your favorite editor and keeps them in sync with a git remote — pulling before you write and committing/pushing after you save. One small static binary on Linux, macOS, and Windows; no runtime dependencies beyond `git` and an editor.

## Features

- `zemo` — open the scratch memo (`<memo>/scratch.txt`).
- `zemo <topic>` — open `<memo>/topics/<topic>.md`. Created with a `# <topic>` header on first use.
- `zemo sync` — pull, stage, commit, and push the memo repository.
- `zemo ls` — list topic names from `<memo>/topics/` (alphabetical).
- `zemo cat [topic]` — print scratch (or `topics/<topic>.md`) to stdout. Read-only, no git operations.
- `zemo dump` — print scratch and all topics to stdout with section headers. Read-only, no git operations.
- `zemo upgrade` — download and install the latest release in-place. `--check` to dry-run.
- `zemo ideas:*` — keep ideas you have to decide about: rank them, move their status, list them. See [Ideas](#ideas).
- Auto pull-on-open / commit-on-close when `<memo>/.git` exists.
- Conventional Commits messages: `docs(<scope>): YYYY-MM-DD HH:MM` for edits, `chore: sync ...` for manual sync.
- Single static binary on Linux / macOS / Windows.

## Installation

### Pre-built binaries

Grab the appropriate archive from the [latest release](https://github.com/hidetzu/zemo/releases/latest), or use one of the one-liners below.

#### Linux (x86_64)

```sh
curl -fsSL https://github.com/hidetzu/zemo/releases/latest/download/zemo-x86_64-linux-gnu.tar.gz | tar -xz
sudo mv zemo-x86_64-linux-gnu/zemo /usr/local/bin/
```

#### macOS (Apple Silicon)

```sh
curl -fsSL https://github.com/hidetzu/zemo/releases/latest/download/zemo-aarch64-macos.tar.gz | tar -xz
sudo mv zemo-aarch64-macos/zemo /usr/local/bin/
```

#### macOS (Intel)

```sh
curl -fsSL https://github.com/hidetzu/zemo/releases/latest/download/zemo-x86_64-macos.tar.gz | tar -xz
sudo mv zemo-x86_64-macos/zemo /usr/local/bin/
```

#### Windows

Download `zemo-x86_64-windows.zip` from the [latest release](https://github.com/hidetzu/zemo/releases/latest), unzip it, and put `zemo.exe` somewhere on your `PATH`.

### From source

Requires [Zig 0.16.0](https://ziglang.org/download/).

```sh
git clone https://github.com/hidetzu/zemo.git
cd zemo
zig build -Doptimize=ReleaseSafe
# Binary is at zig-out/bin/zemo (or zemo.exe on Windows). Move it onto your PATH.
```

### Cross-compile

```sh
zig build -Dtarget=x86_64-windows  -Doptimize=ReleaseSafe
zig build -Dtarget=x86_64-macos    -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-macos   -Doptimize=ReleaseSafe
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
```

On Linux hosts the default target uses `musl` libc to avoid an LLD/glibc incompatibility on bleeding-edge distributions. Pass `-Dtarget=x86_64-linux-gnu` if you specifically want glibc.

## Setting up the memo repository

`zemo` does not manage the git remote itself. Prepare the memo directory once, either by cloning an existing repo or initializing a fresh one.

### Clone an existing repo

```sh
git clone <your-memo-url> ~/memo
```

### Or start fresh

```sh
mkdir -p ~/memo
cd ~/memo
git init
git remote add origin <your-memo-url>
# (optional) make an initial commit and push
```

If `~/memo/.git` is missing, `zemo` and `zemo <topic>` still open the editor but skip the sync step. `zemo sync` requires the directory to be a git repo.

Override the location with `ZEMO_DIR` (see [Configuration](#configuration)).

## Usage

```sh
zemo                # open the scratch memo
zemo journal        # open ~/memo/topics/journal.md
zemo sync           # manual pull / commit / push
zemo ls             # list topic names
zemo cat            # print scratch to stdout
zemo cat journal    # print ~/memo/topics/journal.md to stdout
zemo dump           # print scratch and all topics to stdout
zemo upgrade        # self-update to the latest release
zemo upgrade --check  # check for newer release without installing
zemo --help
zemo --version
```

Topic names must match `[a-zA-Z0-9_-]` (slashes, dots, spaces, and multibyte characters are rejected to avoid path traversal).

## Ideas

A topic is a place to write. An idea is a thing you have to decide about — keep it, rank it, try it, ship it, or drop it — and a topic file cannot record which of those happened. `zemo ideas:*` gives that decision a place, in the same repository, synced by the same `git` calls.

Ideas live in `<memo>/ideas/<name>.md`. The directory is flat: the status is a line in the file's front matter and nowhere else, so nothing can drift out of sync with a directory name.

```sh
zemo ideas:new zig-lsp-server        # create it and open the editor
zemo ideas:priority zig-lsp-server 2 # 1-5, 1 is highest ('-' to unrank)
zemo ideas:status zig-lsp-server prioritized
zemo ideas:list                      # ranked first; --sort=created for newest first
zemo ideas:show zig-lsp-server       # print it, front matter included
```

```console
$ zemo ideas:list
PRI  STATUS         NAME                  EVALUATION
  1  experimenting  zig-lsp-server        solves my own daily friction
  2  prioritized    terminal-canvas       the demo landed well; unclear who pays
  -  backlog        memo-sync-daemon      interesting, no reason to build it yet
```

### Front matter

`zemo ideas:new` writes the keys for you; fill in what you want and leave the rest empty.

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
```

Only these keys are read. Anything else you write in the block is kept exactly as you wrote it — `zemo ideas:status` and `zemo ideas:priority` replace one line and touch nothing else. An empty `priority` means "not ranked yet", which is not the same as ranking it `5`.

`tags` is a comma-separated string rather than a YAML list, so that `zemo` needs no YAML parser and stays dependency-free.

### Status

```text
   backlog <-> prioritized <-> experimenting --> published
       |            |               |
       +------------+---------------+---------> dropped
```

Forward and backward one step at a time. `published` and `dropped` are the end, and nothing leaves them — an idea that comes back is a new file, and the old one stays as the record of what was decided. `dropped` is deliberately not the same as `backlog`: one means you decided against it, the other means nobody has looked yet.

A move that is not on that graph is refused, and the refusal names what *is* reachable:

```console
$ zemo ideas:status zig-lsp-server published
zemo: zig-lsp-server is prioritized; from there it can go to backlog, experimenting or dropped
```

An idea whose front matter cannot be read is still listed, marked `unreadable` with the reason — and `ideas:status` and `ideas:priority` refuse to write to it, rather than rewriting a file they misread.

### Git

`ideas:list` and `ideas:show` are read-only and run no git command. The other three pull first and commit afterwards, with the idea and the change in the subject:

```text
docs(ideas): zig-lsp-server 2026-09-06 14:32
docs(ideas): zig-lsp-server prioritized -> experimenting
docs(ideas): zig-lsp-server priority 2 -> 1
```

So `git log --oneline -- ideas/<name>.md` reads back as the history of the deciding. Setting a value it already has writes nothing and commits nothing.

Full specification: [`docs/ideas-spec.md`](docs/ideas-spec.md). Why the status is not a directory: [`docs/adr/0001-an-ideas-status-lives-only-in-its-front-matter.md`](docs/adr/0001-an-ideas-status-lives-only-in-its-front-matter.md).

## Configuration

| Variable      | Purpose                           | Default                                             |
| ------------- | --------------------------------- | --------------------------------------------------- |
| `ZEMO_DIR`    | Memo directory root               | `$HOME/memo` (Unix), `%USERPROFILE%\memo` (Windows) |
| `ZEMO_EDITOR` | Editor command (highest priority) | —                                                   |
| `VISUAL`      | Editor command                    | —                                                   |
| `EDITOR`      | Editor command                    | —                                                   |

If none of the editor variables are set, `zemo` falls back to the first available editor in `PATH`:

- Unix: `nvim` → `vim` → `vi`
- Windows: `nvim` → `notepad`

Editor strings are split on whitespace, so `ZEMO_EDITOR="code --wait"` works. Shell-style quoting is **not** parsed; use a wrapper script for paths containing spaces.

## Behaviour details

- If `<memo>` is not a git repository, `zemo` and `zemo <topic>` skip sync silently and just open the editor. `zemo sync` errors with exit code 1.
- If `git pull --rebase` fails before opening the editor, no editor is launched and exit code 1 is returned.
- If the editor exits with a non-zero status, the post-edit commit/push is skipped and exit code 1 is returned.
- If the editor binary is not found, a friendly `zemo: editor not found: …` message is printed (no Zig stack trace).
- Timestamps are local time, formatted as `YYYY-MM-DD HH:MM`.

## Exit codes

| Code | Meaning                                                                            |
| ---- | ---------------------------------------------------------------------------------- |
| 0    | Success (including "no local changes" on `sync`)                                   |
| 1    | Runtime error (git failure, editor failure, missing editor, invalid topic name, …) |
| 2    | CLI usage error (too many arguments, etc.)                                         |

## Development

```sh
zig build test                     # run all tests
zig build run -- <args>            # run the CLI from source
```

Module layout (under `src/`):

- `paths.zig` — memo directory resolution, scratch / topic path construction, topic name validation.
- `editor.zig` — editor selection (env vars + `PATH` fallback) and child process invocation.
- `git.zig` — thin wrappers over the `git` CLI.
- `time.zig` — local-time timestamp via libc.
- `cli.zig` — argv parsing, command orchestration.
- `main.zig` — process entry point.
- `root.zig` — module root, re-exports for testing.

## License

MIT.
