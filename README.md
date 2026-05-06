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
zemo --help
zemo --version
```

Topic names must match `[a-zA-Z0-9_-]` (slashes, dots, spaces, and multibyte characters are rejected to avoid path traversal).

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
