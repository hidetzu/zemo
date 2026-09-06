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
            inline for (@typeInfo(ideas.Sort).@"enum".fields) |f| {
                if (std.mem.eql(u8, v, f.name)) return .{ .ideas_list = @field(ideas.Sort, f.name) };
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

const VERSION = "0.3.1";

/// CLI のエントリ。終了コードを返す。
pub fn run(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    args: []const []const u8,
) !u8 {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_w: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_w.interface;
    defer stdout.flush() catch {};

    var stderr_buf: [1024]u8 = undefined;
    var stderr_w: Io.File.Writer = .init(.stderr(), io, &stderr_buf);
    const stderr = &stderr_w.interface;
    defer stderr.flush() catch {};

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
    const is_repo = git.isGitRepo(allocator, io, dir);
    if (is_repo) {
        git.pull(io, dir) catch |err| return reportGit(stderr, "git pull", err);
    }

    const file_path = try paths.scratchPath(allocator, dir);
    defer allocator.free(file_path);

    try ensureFile(io, file_path, null);

    return editAndPostSync(allocator, io, env, stderr, dir, file_path, is_repo, .{ .topic = "scratch" });
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
    const is_repo = git.isGitRepo(allocator, io, dir);
    if (is_repo) {
        git.pull(io, dir) catch |err| return reportGit(stderr, "git pull", err);
    }

    const topics_dir = try std.fs.path.join(allocator, &.{ dir, "topics" });
    defer allocator.free(topics_dir);
    try ensureDir(io, topics_dir);

    const file_path = try paths.topicPath(allocator, dir, topic);
    defer allocator.free(file_path);

    const template = try std.fmt.allocPrint(allocator, "# {s}\n\n", .{topic});
    defer allocator.free(template);
    try ensureFile(io, file_path, template);

    return editAndPostSync(allocator, io, env, stderr, dir, file_path, is_repo, .{ .topic = topic });
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

    if (!git.isGitRepo(allocator, io, dir)) {
        try stderr.writeAll("zemo: memo dir is not a git repo\n");
        return 1;
    }

    git.pull(io, dir) catch |err| return reportGit(stderr, "git pull", err);
    git.addAll(io, dir) catch |err| return reportGit(stderr, "git add", err);

    const has_changes = git.hasStagedChanges(io, dir) catch |err|
        return reportGit(stderr, "git diff", err);

    if (!has_changes) {
        try stdout.writeAll("No local changes\n");
        return 0;
    }

    const ts = try time.nowLocalString(allocator);
    defer allocator.free(ts);
    const msg = try std.fmt.allocPrint(allocator, "chore: sync {s}", .{ts});
    defer allocator.free(msg);

    git.commit(io, dir, msg) catch |err| return reportGit(stderr, "git commit", err);
    git.push(io, dir) catch |err| return reportGit(stderr, "git push", err);
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

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    _ = try file_reader.interface.streamRemaining(stdout);

    return 0;
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

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    _ = try file_reader.interface.streamRemaining(stdout);
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
    is_repo: bool,
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

    if (!is_repo) return 0;

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
    git.addAll(io, dir) catch |err| return reportGit(stderr, "git add", err);
    const has_changes = git.hasStagedChanges(io, dir) catch |err|
        return reportGit(stderr, "git diff", err);
    if (!has_changes) return 0;

    git.commit(io, dir, msg) catch |err| return reportGit(stderr, "git commit", err);
    git.push(io, dir) catch |err| return reportGit(stderr, "git push", err);
    return 0;
}

fn reportGit(stderr: *Io.Writer, label: []const u8, err: anyerror) !u8 {
    try stderr.print("zemo: {s} failed: {s}\n", .{ label, @errorName(err) });
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

fn doUpgrade(allocator: std.mem.Allocator, io: Io, stdout: *Io.Writer, stderr: *Io.Writer, mode: upgrade.UpgradeMode) !u8 {
    const json = upgrade.fetchLatestReleaseJson(allocator, io) catch |err| {
        try stderr.print("zemo: failed to check latest release: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(json);

    const parsed = upgrade.parseReleaseJson(allocator, json) catch |err| {
        try stderr.print("zemo: failed to parse GitHub response: {s}\n", .{@errorName(err)});
        return 1;
    };
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
                    const asset = upgrade.assetName() catch |err| {
                        try stderr.print("zemo: no prebuilt binary for current target: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                    const url = upgrade.findAssetUrl(parsed.value, asset) orelse {
                        try stderr.print("zemo: asset '{s}' not found in release\n", .{asset});
                        return 1;
                    };

                    // 2. アーカイブをダウンロード
                    try stdout.print("Downloading {s}...\n", .{asset});
                    const archive = upgrade.downloadToMemory(allocator, io, url) catch |err| {
                        try stderr.print("zemo: failed to download: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                    defer allocator.free(archive);

                    // 3. 先に install_path を解決 (zip 抽出の作業領域として親ディレクトリを使う)
                    const install_path = upgrade.installPath(allocator, io) catch |err| {
                        try stderr.print("zemo: failed to resolve install path: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                    defer allocator.free(install_path);

                    // 4. アーカイブ形式に応じてバイナリを取り出す
                    const new_binary = if (std.mem.endsWith(u8, asset, ".zip")) blk: {
                        const work_dir = std.fs.path.dirname(install_path) orelse {
                            try stderr.print("zemo: cannot determine working dir from install path: {s}\n", .{install_path});
                            return 1;
                        };
                        break :blk upgrade.extractZemoBinaryFromZip(allocator, io, archive, upgrade.binaryBasename(), work_dir) catch |err| {
                            try stderr.print("zemo: failed to extract binary: {s}\n", .{@errorName(err)});
                            return 1;
                        };
                    } else upgrade.extractZemoBinary(allocator, archive, upgrade.binaryBasename()) catch |err| {
                        try stderr.print("zemo: failed to extract binary: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                    defer allocator.free(new_binary);

                    upgrade.replaceBinary(allocator, io, install_path, new_binary) catch |err| {
                        try stderr.print("zemo: failed to replace binary at {s}: {s}\n", .{ install_path, @errorName(err) });
                        return 1;
                    };

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
    is_repo: bool,

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

    var is_repo = false;
    if (pull_first) {
        try ensureDir(io, memo);
        is_repo = git.isGitRepo(allocator, io, memo);
        if (is_repo) {
            git.pull(io, memo) catch |err| {
                _ = try reportGit(stderr, "git pull", err);
                allocator.free(memo);
                return null;
            };
        }
        const ideas_dir = try std.fs.path.join(allocator, &.{ memo, "ideas" });
        defer allocator.free(ideas_dir);
        try ensureDir(io, ideas_dir);
    }

    const file_path = try paths.ideaPath(allocator, memo, name);
    return .{ .memo = memo, .file_path = file_path, .is_repo = is_repo };
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
        ctx.is_repo,
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

    if (!loaded.ctx.is_repo) return 0;
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

    if (!loaded.ctx.is_repo) return 0;
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
    inline for (@typeInfo(ideas.Status).@"enum".fields, 0..) |f, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(f.name);
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
