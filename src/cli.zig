const std = @import("std");
const Io = std.Io;

const paths = @import("paths.zig");
const editor = @import("editor.zig");
const git = @import("git.zig");
const time = @import("time.zig");
const upgrade = @import("upgrade.zig");
const ideas = @import("ideas.zig");
const builtin = @import("builtin");

/// `ideas:<verb>` の引数が受け付けられなかった理由。
/// ⚠ どれも exit 2（コマンドラインが誤り）で、「invalid topic name」には落とさない。
///   ユーザはコマンドを打ったのであって、ファイル名を打ったのではない。
pub const IdeasFault = union(enum) {
    missing_verb,
    unknown_verb: []const u8,
    wrong_args: []const u8,
    bad_sort: []const u8,
};

pub const NameAndValue = struct { name: []const u8, value: []const u8 };

pub const Command = union(enum) {
    open_scratch,
    open_topic: []const u8,
    sync,
    ls,
    cat: ?[]const u8,
    dump,
    upgrade: upgrade.UpgradeMode,
    ideas_new: []const u8,
    ideas_list: ideas.Sort,
    ideas_show: []const u8,
    ideas_status: NameAndValue,
    ideas_priority: NameAndValue,
    ideas_fault: IdeasFault,
    help,
    version,
    too_many_args,
};

/// argv (program 名含む) を Command に解釈する。
pub fn parseArgs(args: []const []const u8) Command {
    if (args.len <= 1) return .open_scratch;
    const a = args[1];
    if (std.mem.eql(u8, a, "sync")) return .sync;
    if (std.mem.eql(u8, a, "ls")) return .ls;
    if (std.mem.eql(u8, a, "cat")) {
        return switch (args.len) {
            2 => .{ .cat = null },
            3 => .{ .cat = args[2] },
            else => .too_many_args,
        };
    }
    if (std.mem.eql(u8, a, "dump")) return if (args.len == 2) .dump else .too_many_args;
    if (std.mem.eql(u8, a, "upgrade")) {
        if (args.len == 2) return .{ .upgrade = .run };
        if ((args.len == 3) and std.mem.eql(u8, args[2], "--check")) return .{ .upgrade = .check };
        return .too_many_args;
    }
    if (std.mem.eql(u8, a, "help") or std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h"))
        return .help;
    if (std.mem.eql(u8, a, "version") or std.mem.eql(u8, a, "--version") or std.mem.eql(u8, a, "-V"))
        return .version;
    // ⚠ `:` は topic の文字集合に無いので、bare word へのフォールバックより前で分岐する。
    //   ここを後ろに置くと `zemo ideas:new x` が「invalid topic name」になる。
    if (std.mem.eql(u8, a, "ideas")) return .{ .ideas_fault = .missing_verb };
    if (std.mem.startsWith(u8, a, IDEAS_PREFIX)) return parseIdeas(a[IDEAS_PREFIX.len..], args);

    if (args.len > 2) return .too_many_args;
    return .{ .open_topic = a };
}

const IDEAS_PREFIX = "ideas:";
const SORT_PREFIX = "--sort=";

fn parseIdeas(verb: []const u8, args: []const []const u8) Command {
    if (std.mem.eql(u8, verb, "new")) {
        if (args.len == 3) return .{ .ideas_new = args[2] };
        return .{ .ideas_fault = .{ .wrong_args = "new" } };
    }
    if (std.mem.eql(u8, verb, "show")) {
        if (args.len == 3) return .{ .ideas_show = args[2] };
        return .{ .ideas_fault = .{ .wrong_args = "show" } };
    }
    if (std.mem.eql(u8, verb, "list")) {
        if (args.len == 2) return .{ .ideas_list = .priority };
        if (args.len == 3 and std.mem.startsWith(u8, args[2], SORT_PREFIX)) {
            const v = args[2][SORT_PREFIX.len..];
            // ⚠ 未知の値は既定にフォールバックしない。打ち間違いが黙って
            //   別の問いに答えることになる。
            inline for (@typeInfo(ideas.Sort).@"enum".field_names) |field_name| {
                if (std.mem.eql(u8, v, field_name)) return .{ .ideas_list = @field(ideas.Sort, field_name) };
            }
            return .{ .ideas_fault = .{ .bad_sort = v } };
        }
        return .{ .ideas_fault = .{ .wrong_args = "list" } };
    }
    if (std.mem.eql(u8, verb, "status")) {
        if (args.len == 4) return .{ .ideas_status = .{ .name = args[2], .value = args[3] } };
        return .{ .ideas_fault = .{ .wrong_args = "status" } };
    }
    if (std.mem.eql(u8, verb, "priority")) {
        if (args.len == 4) return .{ .ideas_priority = .{ .name = args[2], .value = args[3] } };
        return .{ .ideas_fault = .{ .wrong_args = "priority" } };
    }
    return .{ .ideas_fault = .{ .unknown_verb = verb } };
}

const HELP_TEXT =
    \\zemo - cross-platform memo tool
    \\
    \\USAGE:
    \\  zemo                Open scratch memo
    \\  zemo <topic>        Open topics/<topic>.md
    \\  zemo sync           Manually pull/commit/push the memo repo
    \\  zemo ls             List topic names (alphabetical)
    \\  zemo cat            Print scratch memo to stdout
    \\  zemo cat <topic>    Print topics/<topic>.md to stdout
    \\  zemo dump           Print scratch and all topics to stdout
    \\  zemo upgrade        Download and install the latest release (--check to dry-run)
    \\  zemo help           Show this help
    \\  zemo version        Show version
    \\
    \\IDEAS:
    \\  zemo ideas:new <name>              Create an idea and open it
    \\  zemo ideas:list [--sort=SORT]      List ideas (SORT: priority, created)
    \\  zemo ideas:show <name>             Print an idea to stdout
    \\  zemo ideas:status <name> <status>  Move an idea's status
    \\  zemo ideas:priority <name> <1-5>   Rank an idea ('-' to unrank)
    \\
    \\Topic and idea names must match [a-zA-Z0-9_-].
    \\
;

/// ⚠ `ideas:` を打ち間違えたときに出す。help 全体は長すぎて、
///   直したい行が埋もれる。
const IDEAS_USAGE =
    \\
    \\  zemo ideas:new <name>
    \\  zemo ideas:list [--sort=priority|created]
    \\  zemo ideas:show <name>
    \\  zemo ideas:status <name> <status>
    \\  zemo ideas:priority <name> <1-5|->
    \\
;

const VERSION = "0.4.1";

/// stdout / stderr 用の writer。
/// ⚠ streaming で開く。`.init` は positional で、writer ごとに自分の位置 0 から書く。
///   `zemo … > f 2>&1` で stdout と stderr が同じファイルを指すと、互いに上書きして行が消える
///   (hidetzu/zemo#23)。streaming は OS の共有の書き込み位置を使う。
/// ⚠ バッファを持たない。書いたらその場で出る。バッファすると zemo の行が終了時まで残り、
///   git の出力や自分の stderr より後ろに出る (hidetzu/zemo#26)。
///   flush を呼び出し側に覚えさせない — git やエディタを呼ぶ箇所は増える。
///   代償 (書き込み回数が増える) は条件付きで hidetzu/zemo#26 に測ってある。
fn stdioWriter(file: Io.File, io: Io) Io.File.Writer {
    return .initStreaming(file, io, &.{});
}

/// CLI のエントリ。終了コードを返す。
pub fn run(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    args: []const []const u8,
) !u8 {
    // ⚠ どちらもバッファを持たない (stdioWriter)。flush する相手が無いので defer flush も無い。
    var stdout_w = stdioWriter(.stdout(), io);
    const stdout = &stdout_w.interface;

    var stderr_w = stdioWriter(.stderr(), io);
    const stderr = &stderr_w.interface;

    return switch (parseArgs(args)) {
        .help => blk: {
            try stdout.writeAll(HELP_TEXT);
            break :blk 0;
        },
        .version => blk: {
            try stdout.print("zemo {s}\n", .{VERSION});
            break :blk 0;
        },
        .too_many_args => blk: {
            try stderr.writeAll("zemo: too many arguments\n");
            try stderr.writeAll(HELP_TEXT);
            break :blk 2;
        },
        .open_scratch => try openScratch(allocator, io, env, stderr),
        .open_topic => |t| try openTopic(allocator, io, env, stderr, t),
        .sync => try doSync(allocator, io, env, stderr, stdout),
        .ls => try doLs(allocator, io, env, stdout),
        .cat => |t| try doCat(allocator, io, env, stdout, stderr, t),
        .dump => try doDump(allocator, io, env, stdout),
        .upgrade => |mode| try doUpgrade(allocator, io, stdout, stderr, mode),
        .ideas_new => |name| try doIdeasNew(allocator, io, env, stderr, name),
        .ideas_list => |how| try doIdeasList(allocator, io, env, stdout, how),
        .ideas_show => |name| try doIdeasShow(allocator, io, env, stdout, stderr, name),
        .ideas_status => |nv| try doIdeasStatus(allocator, io, env, stdout, stderr, nv),
        .ideas_priority => |nv| try doIdeasPriority(allocator, io, env, stdout, stderr, nv),
        .ideas_fault => |fault| try reportIdeasFault(stderr, fault),
    };
}

fn openScratch(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
) !u8 {
    const dir = try paths.memoDir(allocator, io, env);
    defer allocator.free(dir);

    try ensureDir(io, dir);

    // pull はファイル作成より先（リモートに同名ファイルが追加されたケースで
    // 未追跡ファイルが pull を妨げないようにする）
    const repo = git.repoAt(allocator, io, dir);
    if (repo == .root) {
        git.pull(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.pull, err, dir));
    }

    const file_path = try paths.scratchPath(allocator, dir);
    defer allocator.free(file_path);

    try ensureFile(io, file_path, null);

    return editAndPostSync(allocator, io, env, stderr, dir, file_path, repo, .{ .topic = "scratch" });
}

fn openTopic(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    topic: []const u8,
) !u8 {
    if (!paths.isValidTopic(topic)) {
        try stderr.print("zemo: invalid topic name '{s}': allowed [a-zA-Z0-9_-]\n", .{topic});
        return 1;
    }

    const dir = try paths.memoDir(allocator, io, env);
    defer allocator.free(dir);

    try ensureDir(io, dir);

    // pull はファイル作成より先（理由は openScratch 参照）
    const repo = git.repoAt(allocator, io, dir);
    if (repo == .root) {
        git.pull(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.pull, err, dir));
    }

    const topics_dir = try std.fs.path.join(allocator, &.{ dir, "topics" });
    defer allocator.free(topics_dir);
    try ensureDir(io, topics_dir);

    const file_path = try paths.topicPath(allocator, dir, topic);
    defer allocator.free(file_path);

    const template = try std.fmt.allocPrint(allocator, "# {s}\n\n", .{topic});
    defer allocator.free(template);
    try ensureFile(io, file_path, template);

    return editAndPostSync(allocator, io, env, stderr, dir, file_path, repo, .{ .topic = topic });
}

fn doSync(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
) !u8 {
    const dir = try paths.memoDir(allocator, io, env);
    defer allocator.free(dir);

    switch (git.repoAt(allocator, io, dir)) {
        .root => {},
        .git_missing => return reportGitFailure(stderr, .{ .no_git = .{ .dir = dir, .when = .sync } }),
        .not_root => {
            try stderr.writeAll("zemo: memo dir is not a git repo\n");
            return 1;
        },
    }

    git.pull(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.pull, err, dir));
    git.addAll(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.add, err, dir));

    const has_changes = git.hasStagedChanges(io, dir) catch |err|
        return reportGitFailure(stderr, gitFailure(.diff, err, dir));

    if (!has_changes) {
        try stdout.writeAll("No local changes\n");
        return 0;
    }

    const ts = try time.nowLocalString(allocator);
    defer allocator.free(ts);
    const msg = try std.fmt.allocPrint(allocator, "chore: sync {s}", .{ts});
    defer allocator.free(msg);

    git.commit(io, dir, msg) catch |err| return reportGitFailure(stderr, gitFailure(.commit, err, dir));
    git.push(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.push, err, dir));
    return 0;
}

// cat実行関数
fn doCat(allocator: std.mem.Allocator, io: Io, env: *const std.process.Environ.Map, stdout: *Io.Writer, stderr: *Io.Writer, topic: ?[]const u8) !u8 {
    const memo = try paths.memoDir(allocator, io, env);
    defer allocator.free(memo);

    const file_path = if (topic) |t| blk: {
        if (!paths.isValidTopic(t)) {
            try stderr.print("zemo: invalid topic name '{s}': allowed [a-zA-Z0-9_-]\n", .{t});
            return 1;
        }
        break :blk try paths.topicPath(allocator, memo, t);
    } else try paths.scratchPath(allocator, memo);
    defer allocator.free(file_path);

    return printFile(io, file_path, stdout, stderr);
}

fn doDump(allocator: std.mem.Allocator, io: Io, env: *const std.process.Environ.Map, stdout: *Io.Writer) !u8 {
    const memo = try paths.memoDir(allocator, io, env);
    defer allocator.free(memo);

    return dumpMemos(allocator, io, memo, stdout);
}

/// lsコマンド実行関数
fn doLs(allocator: std.mem.Allocator, io: Io, env: *const std.process.Environ.Map, stdout: *Io.Writer) !u8 {
    const memo = try paths.memoDir(allocator, io, env);
    defer allocator.free(memo);

    const topics_dir_path = try std.fs.path.join(allocator, &.{ memo, "topics" });
    defer allocator.free(topics_dir_path);

    return listTopics(allocator, io, topics_dir_path, stdout);
}

fn printFile(io: Io, file_path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) !u8 {
    var file = Io.Dir.openFileAbsolute(io, file_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("zemo: no such file: {s}\n", .{file_path});
            return 1;
        },
        else => return err,
    };
    defer file.close(io);

    try copyFileTo(io, file, stdout);
    return 0;
}

/// ファイルの中身を `w` にそのまま書く。
/// ⚠ `Reader.streamRemaining` に stdio の writer を渡さない。sendfile が使えない出力先
///   (Linux の `>>`、そして std の実装上 macOS / Windows) では書き込み側のバッファを要求し、
///   バッファを持たない stdioWriter だとパニックする。Linux の Debug ではその手前で、
///   copy_file_range の EBADF をバグとしてパニックする (copy_file_range を使うのは std では
///   Linux と FreeBSD だけ) (hidetzu/zemo#27 のレビュー)。
fn copyFileTo(io: Io, file: Io.File, w: *Io.Writer) !void {
    var buf: [4096]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const n = try file.readPositional(io, &.{&buf}, offset);
        if (n == 0) return;
        try w.writeAll(buf[0..n]);
        offset += n;
    }
}

fn writeSectionHeader(stdout: *Io.Writer, name: []const u8, wrote_any: bool, previous_ended_with_newline: bool) !void {
    if (wrote_any) {
        try stdout.writeAll(if (previous_ended_with_newline) "\n" else "\n\n");
    }
    try stdout.print("=== {s} ===\n\n", .{name});
}

fn dumpSectionFileIfExists(
    io: Io,
    file_path: []const u8,
    name: []const u8,
    stdout: *Io.Writer,
    wrote_any: *bool,
    previous_ended_with_newline: *bool,
) !void {
    var file = Io.Dir.openFileAbsolute(io, file_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close(io);

    try writeSectionHeader(stdout, name, wrote_any.*, previous_ended_with_newline.*);
    wrote_any.* = true;

    const len = try file.length(io);
    if (len == 0) {
        previous_ended_with_newline.* = false;
    } else {
        var last: [1]u8 = undefined;
        _ = try file.readPositionalAll(io, &last, len - 1);
        previous_ended_with_newline.* = last[0] == '\n';
    }

    try copyFileTo(io, file, stdout);
}

fn dumpMemos(allocator: std.mem.Allocator, io: Io, memo: []const u8, stdout: *Io.Writer) !u8 {
    var wrote_any = false;
    var previous_ended_with_newline = false;

    const scratch_path = try paths.scratchPath(allocator, memo);
    defer allocator.free(scratch_path);
    try dumpSectionFileIfExists(io, scratch_path, "scratch", stdout, &wrote_any, &previous_ended_with_newline);

    const topics_dir_path = try std.fs.path.join(allocator, &.{ memo, "topics" });
    defer allocator.free(topics_dir_path);

    var names = try collectMarkdownNames(allocator, io, topics_dir_path);
    defer {
        for (names.items) |s| allocator.free(s);
        names.deinit(allocator);
    }

    for (names.items) |name| {
        const file_path = try paths.topicPath(allocator, memo, name);
        defer allocator.free(file_path);
        try dumpSectionFileIfExists(io, file_path, name, stdout, &wrote_any, &previous_ended_with_newline);
    }

    return 0;
}

fn listTopics(allocator: std.mem.Allocator, io: Io, topics_dir_path: []const u8, stdout: *Io.Writer) !u8 {
    var names = try collectMarkdownNames(allocator, io, topics_dir_path);
    defer {
        for (names.items) |s| allocator.free(s);
        names.deinit(allocator);
    }

    for (names.items) |name| {
        try stdout.print("{s}\n", .{name});
    }
    return 0;
}

/// `<dir>` 直下の `.md` ファイルの stem を名前順で集める。
/// ⚠ topics/ と ideas/ の両方が使う（同じ問いに答える実装を2つ持たない）。
/// ⚠ サブディレクトリと `.md` 以外は落とす。
fn collectMarkdownNames(allocator: std.mem.Allocator, io: Io, topics_dir_path: []const u8) !std.ArrayList([]const u8) {
    var topics_dir = Io.Dir.openDirAbsolute(io, topics_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .empty,
        else => return err,
    };
    defer topics_dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |s| allocator.free(s);
        names.deinit(allocator);
    }

    var it = topics_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        const stem = entry.name[0 .. entry.name.len - ".md".len];
        if (stem.len == 0) continue; // ".md" だけのファイルは弾く

        const owned = try allocator.dupe(u8, stem);
        try names.append(allocator, owned);
    }

    std.mem.sort([]const u8, names.items, {}, lessThanString);
    return names;
}

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// コミット subject の作り方。⚠ topic と idea で形が違う。
const CommitSubject = union(enum) {
    topic: []const u8,
    idea: []const u8,
};

/// エディタ起動 → post-sync の共通フロー。
/// pre-sync (pull) は呼び出し側でファイル作成より前に実行済みであること。
fn editAndPostSync(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    dir: []const u8,
    file_path: []const u8,
    repo: git.Repo,
    subject: CommitSubject,
) !u8 {
    const result = try editor.runEditor(allocator, io, env, file_path);
    switch (result) {
        .ok => {},
        .failed => {
            try stderr.writeAll("zemo: editor exited with non-zero status, skipping sync\n");
            return 1;
        },
        .editor_not_found => |name| {
            defer allocator.free(name);
            try stderr.print("zemo: editor not found: {s}\n", .{name});
            return 1;
        },
        .no_editor => {
            try stderr.writeAll("zemo: no editor configured (set ZEMO_EDITOR/VISUAL/EDITOR or install nvim/vim/vi)\n");
            return 1;
        },
    }

    if (try syncGate(stderr, repo, dir)) |code| return code;

    const ts = try time.nowLocalString(allocator);
    defer allocator.free(ts);
    const msg = switch (subject) {
        // topic / scratch: 既存の形をそのまま保つ。
        .topic => |scope| try std.fmt.allocPrint(allocator, "docs({s}): {s}", .{ scope, ts }),
        // ⚠ ideas は scope を `ideas` に固定し、どのアイディアかを subject に書く。
        //   `git log --oneline` が判断の履歴になる（docs/ideas-spec.md 6）。
        .idea => |name| try std.fmt.allocPrint(allocator, "docs(ideas): {s} {s}", .{ name, ts }),
    };
    defer allocator.free(msg);

    return stageCommitPush(io, stderr, dir, msg);
}

/// stage → 差分が無ければ何もしない → commit → push。
/// ⚠ 変わっていないのにコミットしない。ユーザが読む履歴にノイズを足すことになる。
fn stageCommitPush(io: Io, stderr: *Io.Writer, dir: []const u8, msg: []const u8) !u8 {
    git.addAll(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.add, err, dir));
    const has_changes = git.hasStagedChanges(io, dir) catch |err|
        return reportGitFailure(stderr, gitFailure(.diff, err, dir));
    if (!has_changes) return 0;

    git.commit(io, dir, msg) catch |err| return reportGitFailure(stderr, gitFailure(.commit, err, dir));
    git.push(io, dir) catch |err| return reportGitFailure(stderr, gitFailure(.push, err, dir));
    return 0;
}

/// 同期に進むか。`null` なら進む。値なら、その終了コードで止まる。
/// ⚠ `.git` の無い memo は同期しない設定であって失敗ではない (0)。git が無いのは、同期するはずの
///   memo を同期できなかった失敗 (1) (hidetzu/zemo#25 の owner 判断)。
fn syncGate(stderr: *Io.Writer, repo: git.Repo, dir: []const u8) !?u8 {
    return switch (repo) {
        .root => null,
        .not_root => 0,
        .git_missing => try reportGitFailure(stderr, .{ .no_git = .{ .dir = dir, .when = .after_edit } }),
    };
}

pub const GitStep = enum { pull, add, diff, commit, push };

/// git の段階が止まった理由。⚠ 文面は `reportGitFailure` だけが書く。
pub const GitFailure = union(enum) {
    /// git は動いて、失敗を返した。git 自身のメッセージは上に出ている。
    failed: struct { step: GitStep, dir: []const u8 },
    /// git が無い (PATH に無い)、commit より前。⚠ push 時に無いのは `could_not_run` (`gitFailure`)。
    no_git: struct { dir: []const u8, when: enum { sync, after_edit } },
    /// git を起動できなかった (見つからない以外の理由、または push 時に見つからない)。
    /// ⚠ git のメッセージは出ていない。
    could_not_run: struct { step: GitStep, dir: []const u8 },
};

/// git 呼び出しのエラーを振り分ける。⚠ pull は編集の前、ほかは編集の後。
/// ⚠ push の時点では commit 済みなので、git が無くても「not committed」とは言えない。
///   承認済みの「could not start git push」に寄せる (hidetzu/zemo#25 の owner 判断、2026-10-19)。
fn gitFailure(step: GitStep, err: anyerror, dir: []const u8) GitFailure {
    return switch (err) {
        error.GitFailed => .{ .failed = .{ .step = step, .dir = dir } },
        error.GitNotFound => switch (step) {
            .pull => .{ .no_git = .{ .dir = dir, .when = .sync } },
            .push => .{ .could_not_run = .{ .step = step, .dir = dir } },
            .add, .diff, .commit => .{ .no_git = .{ .dir = dir, .when = .after_edit } },
        },
        else => .{ .could_not_run = .{ .step = step, .dir = dir } },
    };
}

fn reportGitFailure(stderr: *Io.Writer, failure: GitFailure) !u8 {
    switch (failure) {
        .failed => |f| switch (f.step) {
            .push => try stderr.print(
                "zemo: could not push to the remote; git's message is above.\n" ++
                    "      The change is committed in {s} but not pushed. Push it with: git -C {s} push\n",
                .{ f.dir, f.dir },
            ),
            .pull => try stderr.writeAll(
                "zemo: could not pull from the remote; git's message is above.\n" ++
                    "      Nothing was changed. Fix the remote, then run the command again.\n",
            ),
            .add, .diff, .commit => try stderr.print(
                "zemo: git {s} failed in {s}; git's message is above.\n" ++
                    "      Your file is saved; it was not committed.\n",
                .{ @tagName(f.step), f.dir },
            ),
        },
        .no_git => |n| switch (n.when) {
            .sync => try stderr.print(
                "zemo: git is not installed or not on PATH, so {s} cannot be synced.\n" ++
                    "      Install git, then run zemo sync.\n",
                .{n.dir},
            ),
            .after_edit => try stderr.print(
                "zemo: git is not installed or not on PATH; your note is saved in {s} but not committed.\n" ++
                    "      Install git, then run zemo sync.\n",
                .{n.dir},
            ),
        },
        .could_not_run => |c| switch (c.step) {
            .pull => try stderr.print(
                "zemo: could not start git pull in {s}.\n" ++
                    "      Nothing was changed. Check that git runs, then run the command again.\n",
                .{c.dir},
            ),
            .add, .diff, .commit, .push => try stderr.print(
                "zemo: could not start git {s} in {s}.\n" ++
                    "      Your file is saved; it was not {s}.\n",
                .{ @tagName(c.step), c.dir, if (c.step == .push) "pushed" else "committed" },
            ),
        },
    }
    return 1;
}

fn ensureDir(io: Io, abs_path: []const u8) !void {
    Io.Dir.cwd().createDirPath(io, abs_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn ensureFile(io: Io, abs_path: []const u8, template: ?[]const u8) !void {
    Io.Dir.accessAbsolute(io, abs_path, .{}) catch {
        const file = try Io.Dir.createFileAbsolute(io, abs_path, .{});
        defer file.close(io);
        if (template) |t| {
            var buf: [1024]u8 = undefined;
            var w = file.writer(io, &buf);
            try w.interface.writeAll(t);
            try w.interface.flush();
        }
    };
}

/// `zemo upgrade` が止まった理由。⚠ 文面は `reportUpgradeFailure` だけが書く。
/// ⚠ 段階ごとに分けるのは、次の一手 (待つ・回線を見る・報告する・手で入れる) が違うから。
pub const UpgradeFailure = union(enum) {
    /// 最新リリースの問い合わせ。
    check: upgrade.FetchFailure,
    /// 最新リリースの情報が JSON として読めなかった。
    release_unreadable,
    /// このプラットフォーム向けのビルドが配布されていない (musl Linux ほか)。
    unsupported_target,
    /// 最新リリースに、このプラットフォーム向けのアセットが載っていない。
    /// ⚠ 「読めなかった」ではない。読めたうえで、無かった。
    asset_missing: []const u8,
    /// アセットのダウンロード。
    download: struct { asset: []const u8, failure: upgrade.FetchFailure },
    /// アーカイブを展開できなかった。
    archive_unreadable,
    /// アーカイブは開けたが zemo のバイナリが入っていなかった。
    archive_without_binary,
    /// 自分がどこにインストールされているか分からなかった。
    install_path_unknown,
    /// 置き換えに失敗した。
    replace: struct { path: []const u8, permission_denied: bool },
    out_of_memory,
};

const ISSUES_URL = "https://github.com/hidetzu/zemo/issues";
const RELEASES_URL = "https://github.com/hidetzu/zemo/releases/latest";

const LOCAL_CERTIFICATES_HINT =
    "      Check the system certificate store (for example the ca-certificates package)\n";
const LOCAL_CERTIFICATES_CHECK =
    "zemo: could not load this machine's CA certificates, so api.github.com could not be verified.\n" ++
    LOCAL_CERTIFICATES_HINT ++ "      and try again.\n";
const LOCAL_CERTIFICATES_DOWNLOAD =
    "zemo: could not load this machine's CA certificates, so github.com could not be verified.\n" ++
    LOCAL_CERTIFICATES_HINT ++ "      and try again. The installed zemo is unchanged.\n";

/// `zemo: GitHub answered HTTP 400 (bad_request)` まで書く。
/// ⚠ `std.http.Status` は非網羅 enum。名前の無い値 (599 など) に `@tagName` を当てるとパニックする。
///   名前が無ければ数字だけを書く。
fn writeHttpStatus(w: *Io.Writer, status: std.http.Status) !void {
    try w.print("zemo: GitHub answered HTTP {d}", .{@backingInt(status)});
    if (std.enums.tagName(std.http.Status, status)) |name| try w.print(" ({s})", .{name});
}

/// ⚠ 置き換える前に止まったときは「今の zemo はそのまま」と言う。言えるのはその場合だけ。
fn reportUpgradeFailure(stderr: *Io.Writer, failure: UpgradeFailure) !u8 {
    switch (failure) {
        .check => |f| switch (f) {
            .no_connection => try stderr.writeAll(
                "zemo: could not reach api.github.com to check the latest release.\n" ++
                    "      Check the network connection and try again.\n",
            ),
            .local_certificates => try stderr.writeAll(LOCAL_CERTIFICATES_CHECK),
            .http_status => |status| {
                try writeHttpStatus(stderr, status);
                try stderr.writeAll(" when asked for the latest release.\n      Try again later.\n");
            },
            .unreadable => return reportUpgradeFailure(stderr, .release_unreadable),
            .out_of_memory => return reportUpgradeFailure(stderr, .out_of_memory),
        },
        .release_unreadable => try stderr.writeAll(
            "zemo: the latest-release information from GitHub could not be read.\n" ++
                "      Try again later; if it keeps failing, report it at\n" ++
                "      " ++ ISSUES_URL ++ "\n",
        ),
        .unsupported_target => try stderr.writeAll(
            "zemo: there is no prebuilt zemo for this platform (musl Linux and others).\n" ++
                "      Build it from source instead: see README \"From source\".\n",
        ),
        .asset_missing => |asset| try stderr.print(
            "zemo: the latest release has no {s}.\n" ++
                "      Try again later; if it keeps failing, report it at " ++ ISSUES_URL ++ "\n",
            .{asset},
        ),
        .download => |d| switch (d.failure) {
            .no_connection => try stderr.print(
                "zemo: could not reach github.com to download {s}.\n" ++
                    "      Check the network connection and try again. The installed zemo is unchanged.\n",
                .{d.asset},
            ),
            .local_certificates => try stderr.writeAll(LOCAL_CERTIFICATES_DOWNLOAD),
            .http_status => |status| {
                try writeHttpStatus(stderr, status);
                try stderr.print(" for {s}.\n      Try again later. The installed zemo is unchanged.\n", .{d.asset});
            },
            .unreadable => try stderr.print(
                "zemo: the answer from GitHub for {s} could not be read.\n" ++
                    "      Try again later. The installed zemo is unchanged.\n",
                .{d.asset},
            ),
            .out_of_memory => return reportUpgradeFailure(stderr, .out_of_memory),
        },
        .archive_unreadable => try stderr.writeAll(
            "zemo: the downloaded archive could not be unpacked.\n" ++
                "      The installed zemo is unchanged. Report it at " ++ ISSUES_URL ++ "\n",
        ),
        .archive_without_binary => try stderr.writeAll(
            "zemo: the downloaded archive has no zemo binary in it.\n" ++
                "      The installed zemo is unchanged. Report it at " ++ ISSUES_URL ++ "\n",
        ),
        .install_path_unknown => try stderr.writeAll(
            "zemo: could not find where this zemo is installed.\n" ++
                "      Download the release by hand: " ++ RELEASES_URL ++ "\n",
        ),
        .replace => |r| try stderr.print(
            "zemo: could not replace {s}{s}.\n" ++
                "      Re-run with permission to write there, or download the release by hand:\n" ++
                "      " ++ RELEASES_URL ++ "\n",
            .{ r.path, if (r.permission_denied) " (permission denied)" else "" },
        ),
        .out_of_memory => try stderr.writeAll("zemo: ran out of memory during upgrade. The installed zemo is unchanged.\n"),
    }
    return 1;
}

/// 配布物の中から、このプラットフォーム向けのアセットを選ぶ。
/// ⚠ 「このプラットフォーム向けは作っていない」と「作っているがこのリリースに無い」は別の答え。
const AssetChoice = union(enum) {
    found: struct { asset: []const u8, url: []const u8 },
    failure: UpgradeFailure,
};

fn resolveAsset(info: upgrade.ReleaseInfo, asset_name: upgrade.AssetError![]const u8) AssetChoice {
    const asset = asset_name catch return .{ .failure = .unsupported_target };
    const url = upgrade.findAssetUrl(info, asset) orelse return .{ .failure = .{ .asset_missing = asset } };
    return .{ .found = .{ .asset = asset, .url = url } };
}

/// 置き換えのエラーを振り分ける。⚠ 「権限がない」と言えるのはその errno のときだけ。
fn replaceFailure(path: []const u8, err: anyerror) UpgradeFailure {
    return .{ .replace = .{
        .path = path,
        .permission_denied = err == error.AccessDenied or err == error.PermissionDenied,
    } };
}

/// ⚠ メモリ不足は「読めなかった」「見つからなかった」ではない。そう言うと別の原因を探させる。
fn unlessOutOfMemory(err: anyerror, otherwise: UpgradeFailure) UpgradeFailure {
    return if (err == error.OutOfMemory) .out_of_memory else otherwise;
}

/// 展開のエラーを振り分ける。⚠ 「入っていない」と「開けない」は別の答え。
fn extractFailure(err: anyerror) UpgradeFailure {
    return switch (err) {
        error.BinaryNotFoundInArchive => .archive_without_binary,
        error.OutOfMemory => .out_of_memory,
        else => .archive_unreadable,
    };
}

fn doUpgrade(allocator: std.mem.Allocator, io: Io, stdout: *Io.Writer, stderr: *Io.Writer, mode: upgrade.UpgradeMode) !u8 {
    var fetch_failure: upgrade.FetchFailure = undefined;
    const json = upgrade.fetchLatestReleaseJson(allocator, io, &fetch_failure) catch
        return reportUpgradeFailure(stderr, .{ .check = fetch_failure });
    defer allocator.free(json);

    const parsed = upgrade.parseReleaseJson(allocator, json) catch |err|
        return reportUpgradeFailure(stderr, unlessOutOfMemory(err, .release_unreadable));
    defer parsed.deinit();

    const cmp = upgrade.compareVersions(VERSION, parsed.value.tag_name);
    switch (cmp) {
        .equal, .newer => {
            try stdout.print("Already up to date (v{s})\n", .{VERSION});
            return 0;
        },
        .older => {
            switch (mode) {
                .check => {
                    try stdout.print("Newer version available: v{s} -> {s}\n", .{ VERSION, parsed.value.tag_name });
                    return 0;
                },
                .run => {
                    // 1. 自分のプラットフォーム用アセットの URL を取得
                    const chosen = switch (resolveAsset(parsed.value, upgrade.assetName())) {
                        .found => |found| found,
                        .failure => |failure| return reportUpgradeFailure(stderr, failure),
                    };
                    const asset = chosen.asset;
                    const url = chosen.url;

                    // 2. アーカイブをダウンロード
                    try stdout.print("Downloading {s}...\n", .{asset});
                    const archive = upgrade.downloadToMemory(allocator, io, url, &fetch_failure) catch
                        return reportUpgradeFailure(stderr, .{ .download = .{ .asset = asset, .failure = fetch_failure } });
                    defer allocator.free(archive);

                    // 3. 先に install_path を解決 (zip 抽出の作業領域として親ディレクトリを使う)
                    const install_path = upgrade.installPath(allocator, io) catch |err|
                        return reportUpgradeFailure(stderr, unlessOutOfMemory(err, .install_path_unknown));
                    defer allocator.free(install_path);

                    // 4. アーカイブ形式に応じてバイナリを取り出す
                    const new_binary = if (std.mem.endsWith(u8, asset, ".zip")) blk: {
                        const work_dir = std.fs.path.dirname(install_path) orelse
                            return reportUpgradeFailure(stderr, .install_path_unknown);
                        break :blk upgrade.extractZemoBinaryFromZip(allocator, io, archive, upgrade.binaryBasename(), work_dir) catch |err|
                            return reportUpgradeFailure(stderr, extractFailure(err));
                    } else upgrade.extractZemoBinary(allocator, archive, upgrade.binaryBasename()) catch |err|
                        return reportUpgradeFailure(stderr, extractFailure(err));
                    defer allocator.free(new_binary);

                    upgrade.replaceBinary(allocator, io, install_path, new_binary) catch |err|
                        return reportUpgradeFailure(stderr, replaceFailure(install_path, err));

                    try stdout.print("Upgraded v{s} -> {s}\n", .{ VERSION, parsed.value.tag_name });
                    return 0;
                },
            }
        },
        .invalid => {
            try stderr.print("zemo: cannot parse version: current={s}, latest={s}\n", .{ VERSION, parsed.value.tag_name });
            return 1;
        },
    }

    return 0;
}

// ---- ideas ----

fn reportIdeasFault(stderr: *Io.Writer, fault: IdeasFault) !u8 {
    switch (fault) {
        .missing_verb => try stderr.writeAll("zemo: ideas needs a verb\n"),
        .unknown_verb => |v| try stderr.print("zemo: no such command: ideas:{s}\n", .{v}),
        .wrong_args => |v| try stderr.print("zemo: wrong number of arguments for ideas:{s}\n", .{v}),
        // ⚠ 既定へフォールバックせず、存在する2つを挙げて止まる。
        .bad_sort => |v| try stderr.print(
            "zemo: unknown sort '{s}'; use --sort=priority or --sort=created\n",
            .{v},
        ),
    }
    try stderr.writeAll(IDEAS_USAGE);
    return 2;
}

fn reportInvalidIdeaName(stderr: *Io.Writer, name: []const u8) !u8 {
    try stderr.print("zemo: invalid idea name '{s}': allowed [a-zA-Z0-9_-]\n", .{name});
    return 1;
}

/// ファイル全体をメモリに読む。戻り値はアロケータ確保。
fn readFileAlloc(allocator: std.mem.Allocator, io: Io, file_path: []const u8) ![]u8 {
    var file = try Io.Dir.openFileAbsolute(io, file_path, .{ .mode = .read_only });
    defer file.close(io);

    const len = try file.length(io);
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);
    if (len > 0) _ = try file.readPositionalAll(io, buf, 0);
    return buf;
}

/// 同ディレクトリの一時ファイルに書いてから rename で置き換える。
/// ⚠ truncate してから書くと、途中で失敗したときにユーザの本文が消える。
fn writeFileReplacing(
    allocator: std.mem.Allocator,
    io: Io,
    file_path: []const u8,
    contents: []const u8,
) !void {
    const temp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{file_path});
    defer allocator.free(temp_path);

    {
        const temp_file = try Io.Dir.createFileAbsolute(io, temp_path, .{});
        defer temp_file.close(io);
        var buf: [4096]u8 = undefined;
        var w = temp_file.writer(io, &buf);
        try w.interface.writeAll(contents);
        try w.interface.flush();
    }
    errdefer Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    if (builtin.os.tag == .windows) {
        // ⚠ renameAbsolute は宛先が存在すると失敗する。置換 move は upgrade.zig が持つ
        //   実装を再利用する（同じ問いに答える実装を2つ持たない）。
        try upgrade.moveFileReplaceExistingWindows(allocator, temp_path, file_path);
    } else {
        try Io.Dir.renameAbsolute(temp_path, file_path, io);
    }
}

/// ideas ディレクトリを用意し、必要なら pull まで済ませる。
const IdeasCtx = struct {
    memo: []u8,
    file_path: []u8,
    repo: git.Repo,

    fn deinit(self: IdeasCtx, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        allocator.free(self.memo);
    }
};

fn openIdeasCtx(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    name: []const u8,
    pull_first: bool,
) !?IdeasCtx {
    const memo = try paths.memoDir(allocator, io, env);
    errdefer allocator.free(memo);

    var repo: git.Repo = .not_root;
    if (pull_first) {
        try ensureDir(io, memo);
        repo = git.repoAt(allocator, io, memo);
        if (repo == .root) {
            git.pull(io, memo) catch |err| {
                _ = try reportGitFailure(stderr, gitFailure(.pull, err, memo));
                allocator.free(memo);
                return null;
            };
        }
        const ideas_dir = try std.fs.path.join(allocator, &.{ memo, "ideas" });
        defer allocator.free(ideas_dir);
        try ensureDir(io, ideas_dir);
    }

    const file_path = try paths.ideaPath(allocator, memo, name);
    return .{ .memo = memo, .file_path = file_path, .repo = repo };
}

fn doIdeasNew(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    name: []const u8,
) !u8 {
    if (!paths.isValidTopic(name)) return reportInvalidIdeaName(stderr, name);

    const ctx = (try openIdeasCtx(allocator, io, env, stderr, name, true)) orelse return 1;
    defer ctx.deinit(allocator);

    const created = try time.nowLocalDateString(allocator);
    defer allocator.free(created);
    const tmpl = try ideas.template(allocator, name, created);
    defer allocator.free(tmpl);

    // ⚠ 既存ファイルは開くだけ。上書きも再テンプレート化もしない。
    try ensureFile(io, ctx.file_path, tmpl);

    return editAndPostSync(
        allocator,
        io,
        env,
        stderr,
        ctx.memo,
        ctx.file_path,
        ctx.repo,
        .{ .idea = name },
    );
}

fn doIdeasShow(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    name: []const u8,
) !u8 {
    if (!paths.isValidTopic(name)) return reportInvalidIdeaName(stderr, name);

    const memo = try paths.memoDir(allocator, io, env);
    defer allocator.free(memo);
    const file_path = try paths.ideaPath(allocator, memo, name);
    defer allocator.free(file_path);

    // ⚠ フロントマター込みでそのまま出す。ファイルが怪しいときに開くコマンドなので、
    //   整形して隠すと答えを隠すことになる。
    return printFile(io, file_path, stdout, stderr);
}

fn doIdeasList(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stdout: *Io.Writer,
    how: ideas.Sort,
) !u8 {
    const memo = try paths.memoDir(allocator, io, env);
    defer allocator.free(memo);

    const ideas_dir = try std.fs.path.join(allocator, &.{ memo, "ideas" });
    defer allocator.free(ideas_dir);

    return listIdeas(allocator, io, memo, ideas_dir, stdout, how);
}

/// ⚠ 読めないアイディアも行として残す（落とさないし、コマンドを止めない）。
/// ⚠ アイディアが1つも無いのは失敗ではない。何も出さずに 0 で終わる。
fn listIdeas(
    allocator: std.mem.Allocator,
    io: Io,
    memo: []const u8,
    ideas_dir: []const u8,
    stdout: *Io.Writer,
    how: ideas.Sort,
) !u8 {
    var names = try collectMarkdownNames(allocator, io, ideas_dir);
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }
    if (names.items.len == 0) return 0;

    var sources: std.ArrayList([]u8) = .empty;
    defer {
        for (sources.items) |src| allocator.free(src);
        sources.deinit(allocator);
    }
    var entries: std.ArrayList(ideas.Entry) = .empty;
    defer entries.deinit(allocator);

    for (names.items) |n| {
        const file_path = try paths.ideaPath(allocator, memo, n);
        defer allocator.free(file_path);

        const src = readFileAlloc(allocator, io, file_path) catch |err| switch (err) {
            // 一覧を取ってから読むまでの間に消えたファイル。⚠ 他の行を止めない。
            error.FileNotFound => continue,
            else => return err,
        };
        try sources.append(allocator, src);
        try entries.append(allocator, .{ .name = n, .parsed = ideas.parse(src) });
    }
    if (entries.items.len == 0) return 0;

    ideas.sortEntries(entries.items, how);

    try ideas.writeListHeader(stdout);
    for (entries.items) |e| try ideas.writeListRow(stdout, e);
    return 0;
}

/// status / priority が共通で踏む手順: 名前検証 → pull → 読む → parse。
/// 返り値が `.stop` ならその終了コードで抜ける。
const Loaded = union(enum) {
    stop: u8,
    ready: struct { ctx: IdeasCtx, src: []u8, idea: ideas.Idea },
};

fn loadIdeaForWrite(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    name: []const u8,
) !Loaded {
    if (!paths.isValidTopic(name)) return .{ .stop = try reportInvalidIdeaName(stderr, name) };

    const ctx = (try openIdeasCtx(allocator, io, env, stderr, name, true)) orelse
        return .{ .stop = 1 };
    errdefer ctx.deinit(allocator);

    const src = readFileAlloc(allocator, io, ctx.file_path) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("zemo: no such idea: {s}\n", .{name});
            ctx.deinit(allocator);
            return .{ .stop = 1 };
        },
        else => return err,
    };
    errdefer allocator.free(src);

    switch (ideas.parse(src)) {
        // ⚠ 読めなかったファイルには書き込まない (fail closed)。
        //   誤読したファイルを書き換えるのが、ユーザの文章を壊す経路。
        .problem => |problem| {
            try stderr.print("zemo: cannot read {s}: ", .{name});
            try problem.write(stderr);
            try stderr.writeAll("; not writing to it\n");
            allocator.free(src);
            ctx.deinit(allocator);
            return .{ .stop = 1 };
        },
        .ok => |idea| return .{ .ready = .{ .ctx = ctx, .src = src, .idea = idea } },
    }
}

fn doIdeasStatus(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    nv: NameAndValue,
) !u8 {
    const to = ideas.Status.fromString(nv.value) orelse {
        try stderr.print("zemo: unknown status '{s}'; it is one of ", .{nv.value});
        try writeAllStatuses(stderr);
        try stderr.writeAll("\n");
        return 2;
    };

    const loaded = switch (try loadIdeaForWrite(allocator, io, env, stderr, nv.name)) {
        .stop => |code| return code,
        .ready => |r| r,
    };
    defer allocator.free(loaded.src);
    defer loaded.ctx.deinit(allocator);

    const from = loaded.idea.status;

    // ⚠ 同じ値の再設定はエラーではない。書かないしコミットもしない。
    if (from == to) {
        try stdout.print("{s}: already {s}\n", .{ nv.name, to.name() });
        return 0;
    }

    if (!ideas.canTransition(from, to)) {
        try stderr.print("zemo: {s} is {s}; from there it can go to ", .{ nv.name, from.name() });
        try ideas.writeAllowedFrom(stderr, from);
        try stderr.writeAll("\n");
        return 1;
    }

    const updated = try ideas.rewriteField(allocator, loaded.src, "status", to.name());
    defer allocator.free(updated);
    try writeFileReplacing(allocator, io, loaded.ctx.file_path, updated);

    // ⚠ 両端を出す。"ok" では、直前の値という「これから確かめられなくなるもの」が残らない。
    try stdout.print("{s}: {s} -> {s}\n", .{ nv.name, from.name(), to.name() });

    if (try syncGate(stderr, loaded.ctx.repo, loaded.ctx.memo)) |code| return code;
    const msg = try std.fmt.allocPrint(
        allocator,
        "docs(ideas): {s} {s} -> {s}",
        .{ nv.name, from.name(), to.name() },
    );
    defer allocator.free(msg);
    return stageCommitPush(io, stderr, loaded.ctx.memo, msg);
}

fn doIdeasPriority(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    nv: NameAndValue,
) !u8 {
    const want: ?u8 = switch (ideas.parsePriorityArg(nv.value)) {
        .set => |n| n,
        .unranked => null,
        .invalid => {
            try stderr.print(
                "zemo: invalid priority '{s}'; use 1-5 (1 is highest) or '-' to unrank\n",
                .{nv.value},
            );
            return 2;
        },
    };

    const loaded = switch (try loadIdeaForWrite(allocator, io, env, stderr, nv.name)) {
        .stop => |code| return code,
        .ready => |r| r,
    };
    defer allocator.free(loaded.src);
    defer loaded.ctx.deinit(allocator);

    const from = loaded.idea.priority;
    if (samePriority(from, want)) {
        var buf: [16]u8 = undefined;
        try stdout.print("{s}: already priority {s}\n", .{ nv.name, priorityText(&buf, want) });
        return 0;
    }

    var value_buf: [4]u8 = undefined;
    const value: []const u8 = if (want) |n|
        std.fmt.bufPrint(&value_buf, "{d}", .{n}) catch unreachable
    else
        "";

    const updated = try ideas.rewriteField(allocator, loaded.src, "priority", value);
    defer allocator.free(updated);
    try writeFileReplacing(allocator, io, loaded.ctx.file_path, updated);

    // ⚠ どちらかが未設定でも "unranked" と書く。'-' や空欄で済ませない。
    var from_buf: [16]u8 = undefined;
    var to_buf: [16]u8 = undefined;
    const from_text = priorityText(&from_buf, from);
    const to_text = priorityText(&to_buf, want);
    try stdout.print("{s}: priority {s} -> {s}\n", .{ nv.name, from_text, to_text });

    if (try syncGate(stderr, loaded.ctx.repo, loaded.ctx.memo)) |code| return code;
    const msg = try std.fmt.allocPrint(
        allocator,
        "docs(ideas): {s} priority {s} -> {s}",
        .{ nv.name, from_text, to_text },
    );
    defer allocator.free(msg);
    return stageCommitPush(io, stderr, loaded.ctx.memo, msg);
}

fn samePriority(a: ?u8, b: ?u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.? == b.?;
}

/// 優先度を人が読む文字列にする。⚠ 未設定は "unranked"。空文字にしない。
fn priorityText(buf: []u8, p: ?u8) []const u8 {
    const n = p orelse return "unranked";
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch unreachable;
}

fn writeAllStatuses(w: *Io.Writer) !void {
    inline for (@typeInfo(ideas.Status).@"enum".field_names, 0..) |field_name, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(field_name);
    }
}

test "parseArgs: no args opens scratch" {
    try std.testing.expectEqual(Command.open_scratch, parseArgs(&.{"zemo"}));
}

test "parseArgs: single topic" {
    const cmd = parseArgs(&.{ "zemo", "hello" });
    switch (cmd) {
        .open_topic => |t| try std.testing.expectEqualStrings("hello", t),
        else => try std.testing.expect(false),
    }
}

test "parseArgs: sync subcommand" {
    try std.testing.expectEqual(Command.sync, parseArgs(&.{ "zemo", "sync" }));
}

test "parseArgs: ls subcommand" {
    try std.testing.expectEqual(Command.ls, parseArgs(&.{ "zemo", "ls" }));
}

test "parseArgs: dump subcommand" {
    try std.testing.expectEqual(Command.dump, parseArgs(&.{ "zemo", "dump" }));
}

test "parseArgs: help variants" {
    try std.testing.expectEqual(Command.help, parseArgs(&.{ "zemo", "help" }));
    try std.testing.expectEqual(Command.help, parseArgs(&.{ "zemo", "--help" }));
    try std.testing.expectEqual(Command.help, parseArgs(&.{ "zemo", "-h" }));
}

test "parseArgs: version variants" {
    try std.testing.expectEqual(Command.version, parseArgs(&.{ "zemo", "version" }));
    try std.testing.expectEqual(Command.version, parseArgs(&.{ "zemo", "--version" }));
    try std.testing.expectEqual(Command.version, parseArgs(&.{ "zemo", "-V" }));
}

test "parseArgs: too many args" {
    try std.testing.expectEqual(Command.too_many_args, parseArgs(&.{ "zemo", "a", "b" }));
}

// ---- listTopics ----
test "listTopics: alphabetical order, only .md files" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // topics/ + .md ファイル + ノイズを仕込む
    try tmp.dir.createDir(io, "topics", .default_dir);
    var topics = try tmp.dir.openDir(io, "topics", .{});
    defer topics.close(io);

    // ヘルパで .md / .txt / サブディレクトリを作る
    inline for (.{ "foo.md", "bar.md", "ignore.txt" }) |name| {
        const f = try topics.createFile(io, name, .{});
        f.close(io);
    }
    try topics.createDir(io, "should-skip-dir", .default_dir);

    // realPath で topics/ のフルパスを取る
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try topics.realPath(io, &path_buf);
    const topics_path = path_buf[0..len];

    // in-memory writer
    var alloc_w = std.Io.Writer.Allocating.init(a);
    defer alloc_w.deinit();

    _ = try listTopics(a, io, topics_path, &alloc_w.writer);
    try alloc_w.writer.flush();

    try std.testing.expectEqualStrings("bar\nfoo\n", alloc_w.written());
}

test "parseArgs: cat without topic" {
    const cmd = parseArgs(&.{ "zemo", "cat" });
    switch (cmd) {
        .cat => |t| try std.testing.expectEqual(@as(?[]const u8, null), t),
        else => try std.testing.expect(false),
    }
}

test "parseArgs: cat with topic" {
    const cmd = parseArgs(&.{ "zemo", "cat", "hello" });
    switch (cmd) {
        .cat => |t| {
            try std.testing.expect(t != null);
            try std.testing.expectEqual("hello", t.?);
        },
        else => try std.testing.expect(false),
    }
}

test "parseArgs: cat too many args" {
    try std.testing.expectEqual(Command.too_many_args, parseArgs(&.{ "zemo", "cat", "a", "b" }));
}

test "printFile: prints file contents to stdout" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 内容を書いたファイルを作る
    {
        var f = try tmp.dir.createFile(io, "hello.md", .{});
        defer f.close(io);
        var buf: [256]u8 = undefined;
        var w = f.writer(io, &buf);
        try w.interface.writeAll("# hello\nworld\n");
        try w.interface.flush();
    }

    // realPath で絶対パス取得
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &path_buf);
    const file_path = try std.fs.path.join(a, &.{ path_buf[0..len], "hello.md" });
    defer a.free(file_path);

    // capture buffers
    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();
    var stderr = std.Io.Writer.Allocating.init(a);
    defer stderr.deinit();

    const code = try printFile(io, file_path, &stdout.writer, &stderr.writer);
    try stdout.writer.flush();
    try stderr.writer.flush();

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("# hello\nworld\n", stdout.written());
    try std.testing.expectEqualStrings("", stderr.written());
}

test "printFile: missing file → exit 1, stderr message" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &path_buf);
    const missing = try std.fs.path.join(a, &.{ path_buf[0..len], "nope.md" });
    defer a.free(missing);

    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();
    var stderr = std.Io.Writer.Allocating.init(a);
    defer stderr.deinit();

    const code = try printFile(io, missing, &stdout.writer, &stderr.writer);
    try stdout.writer.flush();
    try stderr.writer.flush();

    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqualStrings("", stdout.written());
    // stderr に "no such file" が含まれるかをチェック
    try std.testing.expect(std.mem.indexOf(u8, stderr.written(), "no such file") != null);
}

fn writeTestFile(io: Io, dir: Io.Dir, path: []const u8, contents: []const u8) !void {
    var f = try dir.createFile(io, path, .{});
    defer f.close(io);
    var buf: [256]u8 = undefined;
    var w = f.writer(io, &buf);
    try w.interface.writeAll(contents);
    try w.interface.flush();
}

fn tmpDirPath(allocator: std.mem.Allocator, io: Io, dir: Io.Dir) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try dir.realPath(io, &path_buf);
    return allocator.dupe(u8, path_buf[0..len]);
}

test "dumpMemos: scratch only" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeTestFile(io, tmp.dir, "scratch.txt", "scratch");
    const memo = try tmpDirPath(a, io, tmp.dir);
    defer a.free(memo);

    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();

    const code = try dumpMemos(a, io, memo, &stdout.writer);
    try stdout.writer.flush();

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("=== scratch ===\n\nscratch", stdout.written());
}

test "dumpMemos: topics only sorted and filtered" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "topics", .default_dir);
    try writeTestFile(io, tmp.dir, "topics/zemo.md", "zemo\n");
    try writeTestFile(io, tmp.dir, "topics/git.md", "git\n");
    try writeTestFile(io, tmp.dir, "topics/ignore.txt", "ignored\n");
    try tmp.dir.createDir(io, "topics/subdir", .default_dir);

    const memo = try tmpDirPath(a, io, tmp.dir);
    defer a.free(memo);

    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();

    const code = try dumpMemos(a, io, memo, &stdout.writer);
    try stdout.writer.flush();

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("=== git ===\n\ngit\n\n=== zemo ===\n\nzemo\n", stdout.written());
}

test "dumpMemos: scratch and topics" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeTestFile(io, tmp.dir, "scratch.txt", "scratch\n");
    try tmp.dir.createDir(io, "topics", .default_dir);
    try writeTestFile(io, tmp.dir, "topics/beta.md", "beta");
    try writeTestFile(io, tmp.dir, "topics/alpha.md", "alpha\n");

    const memo = try tmpDirPath(a, io, tmp.dir);
    defer a.free(memo);

    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();

    const code = try dumpMemos(a, io, memo, &stdout.writer);
    try stdout.writer.flush();

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("=== scratch ===\n\nscratch\n\n=== alpha ===\n\nalpha\n\n=== beta ===\n\nbeta", stdout.written());
}

test "dumpMemos: neither scratch nor topics prints nothing" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const memo = try tmpDirPath(a, io, tmp.dir);
    defer a.free(memo);

    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();

    const code = try dumpMemos(a, io, memo, &stdout.writer);
    try stdout.writer.flush();

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("", stdout.written());
}

test "doDump: uses ZEMO_DIR override" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeTestFile(io, tmp.dir, "scratch.txt", "from-zemo-dir\n");
    const memo = try tmpDirPath(a, io, tmp.dir);
    defer a.free(memo);

    var env = std.process.Environ.Map.init(a);
    defer env.deinit();
    try env.put("ZEMO_DIR", memo);

    var stdout = std.Io.Writer.Allocating.init(a);
    defer stdout.deinit();

    const code = try doDump(a, io, &env, &stdout.writer);
    try stdout.writer.flush();

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("=== scratch ===\n\nfrom-zemo-dir\n", stdout.written());
}

test "parseArgs: upgrade run" {
    const cmd = parseArgs(&.{ "zemo", "upgrade" });
    switch (cmd) {
        .upgrade => |mode| try std.testing.expectEqual(upgrade.UpgradeMode.run, mode),
        else => try std.testing.expect(false),
    }
}

test "parseArgs: upgrade check" {
    const cmd = parseArgs(&.{ "zemo", "upgrade", "--check" });
    switch (cmd) {
        .upgrade => |mode| try std.testing.expectEqual(upgrade.UpgradeMode.check, mode),
        else => try std.testing.expect(false),
    }
}

test "parseArgs: upgrade with invalid arg" {
    try std.testing.expectEqual(Command.too_many_args, parseArgs(&.{ "zemo", "upgrade", "foo" }));
}

test "parseArgs: upgrade with too many args" {
    try std.testing.expectEqual(Command.too_many_args, parseArgs(&.{ "zemo", "upgrade", "--check", "extra" }));
}

// ---- ideas: parseArgs ----

fn ideasFaultOf(args: []const []const u8) IdeasFault {
    return switch (parseArgs(args)) {
        .ideas_fault => |f| f,
        else => @panic("expected an ideas fault"),
    };
}

test "parseArgs: ideas:new takes exactly one name" {
    try std.testing.expectEqualStrings("x", parseArgs(&.{ "zemo", "ideas:new", "x" }).ideas_new);
    try std.testing.expectEqualStrings(
        "new",
        ideasFaultOf(&.{ "zemo", "ideas:new" }).wrong_args,
    );
    try std.testing.expectEqualStrings(
        "new",
        ideasFaultOf(&.{ "zemo", "ideas:new", "x", "y" }).wrong_args,
    );
}

test "parseArgs: ideas:show takes exactly one name" {
    try std.testing.expectEqualStrings("x", parseArgs(&.{ "zemo", "ideas:show", "x" }).ideas_show);
    try std.testing.expectEqualStrings("show", ideasFaultOf(&.{ "zemo", "ideas:show" }).wrong_args);
}

test "parseArgs: ideas:list defaults to priority" {
    try std.testing.expectEqual(ideas.Sort.priority, parseArgs(&.{ "zemo", "ideas:list" }).ideas_list);
    try std.testing.expectEqual(
        ideas.Sort.priority,
        parseArgs(&.{ "zemo", "ideas:list", "--sort=priority" }).ideas_list,
    );
    try std.testing.expectEqual(
        ideas.Sort.created,
        parseArgs(&.{ "zemo", "ideas:list", "--sort=created" }).ideas_list,
    );
}

test "parseArgs: an unknown --sort never falls back to the default" {
    // ⚠ ここが .ideas_list になったら、打ち間違いが黙って別の問いに答えている。
    try std.testing.expectEqualStrings(
        "name",
        ideasFaultOf(&.{ "zemo", "ideas:list", "--sort=name" }).bad_sort,
    );
    try std.testing.expectEqualStrings(
        "",
        ideasFaultOf(&.{ "zemo", "ideas:list", "--sort=" }).bad_sort,
    );
    try std.testing.expectEqualStrings(
        "list",
        ideasFaultOf(&.{ "zemo", "ideas:list", "priority" }).wrong_args,
    );
}

test "parseArgs: ideas:status and ideas:priority take a name and a value" {
    const st = parseArgs(&.{ "zemo", "ideas:status", "x", "dropped" }).ideas_status;
    try std.testing.expectEqualStrings("x", st.name);
    try std.testing.expectEqualStrings("dropped", st.value);

    const pr = parseArgs(&.{ "zemo", "ideas:priority", "x", "2" }).ideas_priority;
    try std.testing.expectEqualStrings("x", pr.name);
    try std.testing.expectEqualStrings("2", pr.value);

    try std.testing.expectEqualStrings(
        "status",
        ideasFaultOf(&.{ "zemo", "ideas:status", "x" }).wrong_args,
    );
    try std.testing.expectEqualStrings(
        "priority",
        ideasFaultOf(&.{ "zemo", "ideas:priority", "x", "2", "3" }).wrong_args,
    );
}

test "parseArgs: an unknown ideas verb is a command error, never an invalid topic name" {
    // ⚠ open_topic に落ちると「invalid topic name」と言うことになり、
    //   ユーザは直す場所を間違える。
    try std.testing.expectEqualStrings("nope", ideasFaultOf(&.{ "zemo", "ideas:nope" }).unknown_verb);
    try std.testing.expectEqualStrings("", ideasFaultOf(&.{ "zemo", "ideas:" }).unknown_verb);
    try std.testing.expectEqual(
        std.meta.Tag(IdeasFault).missing_verb,
        std.meta.activeTag(ideasFaultOf(&.{ "zemo", "ideas" })),
    );
}

test "parseArgs: a topic named like a prefix is still a topic" {
    // ⚠ `ideas` の接頭辞判定が bare word を食い過ぎていないこと。
    try std.testing.expectEqualStrings("ideas-backlog", parseArgs(&.{ "zemo", "ideas-backlog" }).open_topic);
    try std.testing.expectEqualStrings("idea", parseArgs(&.{ "zemo", "idea" }).open_topic);
}

test "HELP_TEXT names every ideas verb" {
    // ⚠ help はバイナリに同梱されるドキュメント。載っていない verb は見つけられない。
    for ([_][]const u8{ "ideas:new", "ideas:list", "ideas:show", "ideas:status", "ideas:priority" }) |verb| {
        try std.testing.expect(std.mem.indexOf(u8, HELP_TEXT, verb) != null);
    }
}

test "listIdeas: sorted, unreadable rows kept, and nothing printed when empty" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const memo = try tmpDirPath(a, io, tmp.dir);
    defer a.free(memo);
    const ideas_dir = try std.fs.path.join(a, &.{ memo, "ideas" });
    defer a.free(ideas_dir);

    // ideas/ がまだ無い状態: 何も出さず 0。
    {
        var out = std.Io.Writer.Allocating.init(a);
        defer out.deinit();
        try std.testing.expectEqual(@as(u8, 0), try listIdeas(a, io, memo, ideas_dir, &out.writer, .priority));
        try out.writer.flush();
        try std.testing.expectEqualStrings("", out.written());
    }

    try tmp.dir.createDir(io, "ideas", .default_dir);
    var dir = try tmp.dir.openDir(io, "ideas", .{});
    defer dir.close(io);

    try writeTestFile(io, dir, "ranked.md", "---\nstatus: experimenting\npriority: 1\nevaluation: yes\n---\n");
    try writeTestFile(io, dir, "unranked.md", "---\nstatus: backlog\n---\n");
    try writeTestFile(io, dir, "broken.md", "no front matter here\n");
    try writeTestFile(io, dir, "notes.txt", "ignored\n");

    var out = std.Io.Writer.Allocating.init(a);
    defer out.deinit();
    try std.testing.expectEqual(@as(u8, 0), try listIdeas(a, io, memo, ideas_dir, &out.writer, .priority));
    try out.writer.flush();

    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, out.written(), "\n"), '\n');
    try std.testing.expect(std.mem.startsWith(u8, lines.next().?, "PRI"));
    // ランク済みが先、未ランクは名前順で後ろ。読めない行も残る。
    try std.testing.expect(std.mem.indexOf(u8, lines.next().?, "ranked") != null);
    try std.testing.expect(std.mem.indexOf(u8, lines.next().?, "broken") != null);
    try std.testing.expect(std.mem.indexOf(u8, lines.next().?, "unranked") != null);
    try std.testing.expect(lines.next() == null);
    // .txt は一覧に出ない。
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "notes") == null);
}

test "writeFileReplacing: replaces the file and leaves no temp behind" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeTestFile(io, tmp.dir, "x.md", "old\n");
    const dir_path = try tmpDirPath(a, io, tmp.dir);
    defer a.free(dir_path);
    const file_path = try std.fs.path.join(a, &.{ dir_path, "x.md" });
    defer a.free(file_path);

    try writeFileReplacing(a, io, file_path, "new contents\n");

    const got = try readFileAlloc(a, io, file_path);
    defer a.free(got);
    try std.testing.expectEqualStrings("new contents\n", got);

    const temp_path = try std.fmt.allocPrint(a, "{s}.tmp", .{file_path});
    defer a.free(temp_path);
    try std.testing.expectError(error.FileNotFound, Io.Dir.accessAbsolute(io, temp_path, .{}));
}

// ---- upgrade failure wording ----

fn upgradeFailureText(buf: []u8, failure: UpgradeFailure) ![]const u8 {
    var w = Io.Writer.fixed(buf);
    const code = try reportUpgradeFailure(&w, failure);
    try std.testing.expectEqual(@as(u8, 1), code);
    return w.buffered();
}

test "reportUpgradeFailure: download unreachable says check the network and nothing changed" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not reach github.com to download zemo-x86_64-linux-gnu.tar.gz.\n" ++
            "      Check the network connection and try again. The installed zemo is unchanged.\n",
        try upgradeFailureText(&buf, .{ .download = .{ .asset = "zemo-x86_64-linux-gnu.tar.gz", .failure = .no_connection } }),
    );
}

test "reportUpgradeFailure: download HTTP error names the status, never an error name" {
    var buf: [512]u8 = undefined;
    const text = try upgradeFailureText(&buf, .{ .download = .{ .asset = "zemo-x86_64-linux-gnu.tar.gz", .failure = .{ .http_status = .bad_request } } });
    try std.testing.expectEqualStrings(
        "zemo: GitHub answered HTTP 400 (bad_request) for zemo-x86_64-linux-gnu.tar.gz.\n" ++
            "      Try again later. The installed zemo is unchanged.\n",
        text,
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "HttpRequestFailed") == null);
}

test "reportUpgradeFailure: download answer unreadable is not reported as unreachable" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: the answer from GitHub for zemo.zip could not be read.\n" ++
            "      Try again later. The installed zemo is unchanged.\n",
        try upgradeFailureText(&buf, .{ .download = .{ .asset = "zemo.zip", .failure = .unreadable } }),
    );
}

test "reportUpgradeFailure: latest-release check, by outcome" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not reach api.github.com to check the latest release.\n" ++
            "      Check the network connection and try again.\n",
        try upgradeFailureText(&buf, .{ .check = .no_connection }),
    );
    try std.testing.expectEqualStrings(
        "zemo: GitHub answered HTTP 503 (service_unavailable) when asked for the latest release.\n" ++
            "      Try again later.\n",
        try upgradeFailureText(&buf, .{ .check = .{ .http_status = .service_unavailable } }),
    );
    // ⚠ HTTP として読めない答えは、JSON として読めない答えと同じ次の一手になる
    try std.testing.expectEqualStrings(
        try upgradeFailureText(&buf, .release_unreadable),
        try upgradeFailureText(buf[256..], .{ .check = .unreadable }),
    );
}

test "reportUpgradeFailure: release info unreadable points at the issue tracker" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: the latest-release information from GitHub could not be read.\n" ++
            "      Try again later; if it keeps failing, report it at\n" ++
            "      https://github.com/hidetzu/zemo/issues\n",
        try upgradeFailureText(&buf, .release_unreadable),
    );
}

test "reportUpgradeFailure: unsupported target points at building from source" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: there is no prebuilt zemo for this platform (musl Linux and others).\n" ++
            "      Build it from source instead: see README \"From source\".\n",
        try upgradeFailureText(&buf, .unsupported_target),
    );
}

test "reportUpgradeFailure: an asset missing from the release is not 'unreadable'" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: the latest release has no zemo-aarch64-macos.tar.gz.\n" ++
            "      Try again later; if it keeps failing, report it at https://github.com/hidetzu/zemo/issues\n",
        try upgradeFailureText(&buf, .{ .asset_missing = "zemo-aarch64-macos.tar.gz" }),
    );
}

test "reportUpgradeFailure: archive without a binary and an unreadable archive are two sentences" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: the downloaded archive has no zemo binary in it.\n" ++
            "      The installed zemo is unchanged. Report it at https://github.com/hidetzu/zemo/issues\n",
        try upgradeFailureText(&buf, .archive_without_binary),
    );
    try std.testing.expectEqualStrings(
        "zemo: the downloaded archive could not be unpacked.\n" ++
            "      The installed zemo is unchanged. Report it at https://github.com/hidetzu/zemo/issues\n",
        try upgradeFailureText(&buf, .archive_unreadable),
    );
}

test "reportUpgradeFailure: replace says permission denied only when it was" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not replace /home/me/.local/bin/zemo (permission denied).\n" ++
            "      Re-run with permission to write there, or download the release by hand:\n" ++
            "      https://github.com/hidetzu/zemo/releases/latest\n",
        try upgradeFailureText(&buf, .{ .replace = .{ .path = "/home/me/.local/bin/zemo", .permission_denied = true } }),
    );
    try std.testing.expectEqualStrings(
        "zemo: could not replace /home/me/.local/bin/zemo.\n" ++
            "      Re-run with permission to write there, or download the release by hand:\n" ++
            "      https://github.com/hidetzu/zemo/releases/latest\n",
        try upgradeFailureText(&buf, .{ .replace = .{ .path = "/home/me/.local/bin/zemo", .permission_denied = false } }),
    );
}

test "reportUpgradeFailure: install path unknown and out of memory" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not find where this zemo is installed.\n" ++
            "      Download the release by hand: https://github.com/hidetzu/zemo/releases/latest\n",
        try upgradeFailureText(&buf, .install_path_unknown),
    );
    try std.testing.expectEqualStrings(
        "zemo: ran out of memory during upgrade. The installed zemo is unchanged.\n",
        try upgradeFailureText(&buf, .{ .download = .{ .asset = "x", .failure = .out_of_memory } }),
    );
}

test "extractFailure: a missing binary and a broken archive are told apart" {
    try std.testing.expectEqual(UpgradeFailure.archive_without_binary, extractFailure(error.BinaryNotFoundInArchive));
    try std.testing.expectEqual(UpgradeFailure.archive_unreadable, extractFailure(error.ZipBadFileOffset));
    try std.testing.expectEqual(UpgradeFailure.out_of_memory, extractFailure(error.OutOfMemory));
}

test "resolveAsset: unsupported target, missing asset and found are three answers" {
    var assets = [_]upgrade.Asset{.{ .name = "zemo-x86_64-linux-gnu.tar.gz", .browser_download_url = "https://example.invalid/a" }};
    const info: upgrade.ReleaseInfo = .{ .tag_name = "v9.9.9", .assets = &assets };

    try std.testing.expectEqual(UpgradeFailure.unsupported_target, resolveAsset(info, error.UnsupportedTarget).failure);
    try std.testing.expectEqualStrings("zemo-x86_64-macos.tar.gz", resolveAsset(info, "zemo-x86_64-macos.tar.gz").failure.asset_missing);
    const found = resolveAsset(info, "zemo-x86_64-linux-gnu.tar.gz").found;
    try std.testing.expectEqualStrings("https://example.invalid/a", found.url);
}

test "replaceFailure: permission denied only for the permission errors" {
    try std.testing.expect(replaceFailure("/p", error.AccessDenied).replace.permission_denied);
    try std.testing.expect(replaceFailure("/p", error.PermissionDenied).replace.permission_denied);
    try std.testing.expect(!replaceFailure("/p", error.NoSpaceLeft).replace.permission_denied);
    try std.testing.expectEqualStrings("/p", replaceFailure("/p", error.NoSpaceLeft).replace.path);
}

test "unlessOutOfMemory: out of memory is never reported as unreadable or unknown" {
    try std.testing.expectEqual(UpgradeFailure.out_of_memory, unlessOutOfMemory(error.OutOfMemory, .release_unreadable));
    try std.testing.expectEqual(UpgradeFailure.release_unreadable, unlessOutOfMemory(error.SyntaxError, .release_unreadable));
    try std.testing.expectEqual(UpgradeFailure.install_path_unknown, unlessOutOfMemory(error.FileNotFound, .install_path_unknown));
}

test "reportUpgradeFailure: an HTTP status with no name prints the number, never panics" {
    var buf: [512]u8 = undefined;
    const unnamed: std.http.Status = @fromBackingInt(599);
    try std.testing.expectEqualStrings(
        "zemo: GitHub answered HTTP 599 for zemo-x86_64-linux-gnu.tar.gz.\n" ++
            "      Try again later. The installed zemo is unchanged.\n",
        try upgradeFailureText(&buf, .{ .download = .{ .asset = "zemo-x86_64-linux-gnu.tar.gz", .failure = .{ .http_status = unnamed } } }),
    );
    try std.testing.expectEqualStrings(
        "zemo: GitHub answered HTTP 599 when asked for the latest release.\n" ++
            "      Try again later.\n",
        try upgradeFailureText(&buf, .{ .check = .{ .http_status = unnamed } }),
    );
}

test "reportUpgradeFailure: unreadable CA certificates point at this machine, not the network" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not load this machine's CA certificates, so github.com could not be verified.\n" ++
            "      Check the system certificate store (for example the ca-certificates package)\n" ++
            "      and try again. The installed zemo is unchanged.\n",
        try upgradeFailureText(&buf, .{ .download = .{ .asset = "zemo-x86_64-linux-gnu.tar.gz", .failure = .local_certificates } }),
    );
    try std.testing.expectEqualStrings(
        "zemo: could not load this machine's CA certificates, so api.github.com could not be verified.\n" ++
            "      Check the system certificate store (for example the ca-certificates package)\n" ++
            "      and try again.\n",
        try upgradeFailureText(&buf, .{ .check = .local_certificates }),
    );
}

test "stdioWriter: two writers on one file keep every line, in the order they were written" {
    // `zemo … > f 2>&1` の再現: stdout と stderr が同じファイルを指す。
    // ⚠ flush しない。書いた順にそのままファイルに出ることを確かめる (hidetzu/zemo#23, #26)。
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, "out.txt", .{ .read = true });
    defer file.close(io);

    var out_w = stdioWriter(file, io);
    var err_w = stdioWriter(file, io);

    try out_w.interface.print("demo: {s} -> {s}\n", .{ "backlog", "prioritized" });
    try err_w.interface.writeAll("zemo: failed\n");
    try out_w.interface.writeAll("more\n");

    var read_buf: [128]u8 = undefined;
    const n = try file.readPositionalAll(io, &read_buf, 0);
    try std.testing.expectEqualStrings("demo: backlog -> prioritized\nzemo: failed\nmore\n", read_buf[0..n]);
}

/// テスト用: O_APPEND で開いたファイル (`zemo … >> f` の出力先と同じ) を返す。
fn openAppendForTest(dir: Io.Dir, name: []const u8) !Io.File {
    const fd = try std.posix.openat(dir.handle, name, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, 0o644);
    return .{ .handle = fd, .flags = .{ .nonblocking = false } };
}

test "printFile: an append-mode file gets the whole file through the stdio writer" {
    // ⚠ `zemo cat t >> f` の再現。streamRemaining だとここでパニックした
    //   (Debug では copy_file_range の EBADF。バッファの有無は区別しない — それは verify § 2 が見る)。
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const body = "# t1\nbody\nline three\n";
    {
        const f = try tmp.dir.createFile(io, "t1.md", .{});
        defer f.close(io);
        var w = f.writer(io, &.{});
        try w.interface.writeAll(body);
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_len = try tmp.dir.realPath(io, &path_buf);
    const src_path = try std.fs.path.join(std.testing.allocator, &.{ path_buf[0..dir_len], "t1.md" });
    defer std.testing.allocator.free(src_path);

    const out = try openAppendForTest(tmp.dir, "out.txt");
    defer out.close(io);
    var out_w = stdioWriter(out, io);
    var err_w = stdioWriter(out, io);

    try std.testing.expectEqual(@as(u8, 0), try printFile(io, src_path, &out_w.interface, &err_w.interface));

    const back = try tmp.dir.openFile(io, "out.txt", .{});
    defer back.close(io);
    var read_buf: [128]u8 = undefined;
    const n = try back.readPositionalAll(io, &read_buf, 0);
    try std.testing.expectEqualStrings(body, read_buf[0..n]);
}

test "dumpMemos: an append-mode file gets every section through the stdio writer" {
    // ⚠ `zemo dump >> f` の再現。streamRemaining だと最初の見出しのあとでパニックした。
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "topics", .default_dir);
    inline for (.{ .{ "scratch.txt", "scratch\n" }, .{ "topics/t1.md", "# t1\nbody\n" } }) |entry| {
        const f = try tmp.dir.createFile(io, entry[0], .{});
        defer f.close(io);
        var w = f.writer(io, &.{});
        try w.interface.writeAll(entry[1]);
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_len = try tmp.dir.realPath(io, &path_buf);

    const out = try openAppendForTest(tmp.dir, "out.txt");
    defer out.close(io);
    var out_w = stdioWriter(out, io);
    try std.testing.expectEqual(@as(u8, 0), try dumpMemos(a, io, path_buf[0..dir_len], &out_w.interface));

    const back = try tmp.dir.openFile(io, "out.txt", .{});
    defer back.close(io);
    var read_buf: [256]u8 = undefined;
    const n = try back.readPositionalAll(io, &read_buf, 0);
    try std.testing.expectEqualStrings("=== scratch ===\n\nscratch\n\n=== t1 ===\n\n# t1\nbody\n", read_buf[0..n]);
}

// ---- git failure wording (hidetzu/zemo#25) ----

fn gitFailureText(buf: []u8, failure: GitFailure) ![]const u8 {
    var w = Io.Writer.fixed(buf);
    try std.testing.expectEqual(@as(u8, 1), try reportGitFailure(&w, failure));
    return w.buffered();
}

test "reportGitFailure: a refused push says the commit is local and how to push it" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not push to the remote; git's message is above.\n" ++
            "      The change is committed in /m but not pushed. Push it with: git -C /m push\n",
        try gitFailureText(&buf, gitFailure(.push, error.GitFailed, "/m")),
    );
}

test "reportGitFailure: a failed pull says nothing was changed" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not pull from the remote; git's message is above.\n" ++
            "      Nothing was changed. Fix the remote, then run the command again.\n",
        try gitFailureText(&buf, gitFailure(.pull, error.GitFailed, "/m")),
    );
}

test "reportGitFailure: add, diff and commit say the file is saved and not committed" {
    var buf: [512]u8 = undefined;
    inline for (.{ GitStep.add, GitStep.diff, GitStep.commit }) |step| {
        try std.testing.expectEqualStrings(
            "zemo: git " ++ @tagName(step) ++ " failed in /m; git's message is above.\n" ++
                "      Your file is saved; it was not committed.\n",
            try gitFailureText(&buf, gitFailure(step, error.GitFailed, "/m")),
        );
    }
}

test "reportGitFailure: git missing is not 'not a repo', before and after editing" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: git is not installed or not on PATH, so /m cannot be synced.\n" ++
            "      Install git, then run zemo sync.\n",
        try gitFailureText(&buf, gitFailure(.pull, error.GitNotFound, "/m")),
    );
    try std.testing.expectEqualStrings(
        "zemo: git is not installed or not on PATH; your note is saved in /m but not committed.\n" ++
            "      Install git, then run zemo sync.\n",
        try gitFailureText(&buf, gitFailure(.commit, error.GitNotFound, "/m")),
    );
}

test "reportGitFailure: git that could not start never claims git's message is above" {
    var buf: [512]u8 = undefined;
    const pull = try gitFailureText(&buf, gitFailure(.pull, error.AccessDenied, "/m"));
    try std.testing.expect(std.mem.indexOf(u8, pull, "message is above") == null);
    try std.testing.expectEqualStrings(
        "zemo: could not start git pull in /m.\n" ++
            "      Nothing was changed. Check that git runs, then run the command again.\n",
        pull,
    );
    try std.testing.expectEqualStrings(
        "zemo: could not start git push in /m.\n" ++
            "      Your file is saved; it was not pushed.\n",
        try gitFailureText(&buf, gitFailure(.push, error.AccessDenied, "/m")),
    );
}

test "reportGitFailure: git missing after editing says the note is saved, at add and diff too" {
    var buf: [512]u8 = undefined;
    inline for (.{ GitStep.add, GitStep.diff }) |step| {
        try std.testing.expectEqualStrings(
            "zemo: git is not installed or not on PATH; your note is saved in /m but not committed.\n" ++
                "      Install git, then run zemo sync.\n",
            try gitFailureText(&buf, gitFailure(step, error.GitNotFound, "/m")),
        );
    }
}

test "reportGitFailure: git that could not start at add, diff or commit says the file is not committed" {
    var buf: [512]u8 = undefined;
    inline for (.{ GitStep.add, GitStep.diff, GitStep.commit }) |step| {
        try std.testing.expectEqualStrings(
            "zemo: could not start git " ++ @tagName(step) ++ " in /m.\n" ++
                "      Your file is saved; it was not committed.\n",
            try gitFailureText(&buf, gitFailure(step, error.AccessDenied, "/m")),
        );
    }
}

test "reportGitFailure: git missing at push never says the note is not committed" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "zemo: could not start git push in /m.\n" ++
            "      Your file is saved; it was not pushed.\n",
        try gitFailureText(&buf, gitFailure(.push, error.GitNotFound, "/m")),
    );
}

test "reportGitFailure: no error name reaches the sentence" {
    var buf: [512]u8 = undefined;
    inline for (.{ GitStep.pull, GitStep.add, GitStep.diff, GitStep.commit, GitStep.push }) |step| {
        inline for (.{ error.GitFailed, error.GitNotFound, error.AccessDenied }) |err| {
            const text = try gitFailureText(&buf, gitFailure(step, err, "/m"));
            try std.testing.expect(std.mem.indexOf(u8, text, @errorName(err)) == null);
        }
    }
}

test "syncGate: no .git skips with 0, git missing stops with 1, a repo root proceeds" {
    var buf: [512]u8 = undefined;
    var w = Io.Writer.fixed(&buf);
    try std.testing.expectEqual(@as(?u8, null), try syncGate(&w, .root, "/m"));
    try std.testing.expectEqual(@as(?u8, 0), try syncGate(&w, .not_root, "/m"));
    try std.testing.expectEqualStrings("", w.buffered());
    try std.testing.expectEqual(@as(?u8, 1), try syncGate(&w, .git_missing, "/m"));
    try std.testing.expect(std.mem.startsWith(u8, w.buffered(), "zemo: git is not installed or not on PATH; your note is saved in /m"));
}
