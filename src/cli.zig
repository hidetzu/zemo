const std = @import("std");
const Io = std.Io;

const paths = @import("paths.zig");
const editor = @import("editor.zig");
const git = @import("git.zig");
const time = @import("time.zig");
const upgrade = @import("upgrade.zig");

pub const Command = union(enum) {
    open_scratch,
    open_topic: []const u8,
    sync,
    ls,
    cat: ?[]const u8,
    dump,
    upgrade: upgrade.UpgradeMode,
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
    if (args.len > 2) return .too_many_args;
    return .{ .open_topic = a };
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
    \\Topic name must match [a-zA-Z0-9_-].
    \\
;

const VERSION = "0.3.0";

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

    return editAndPostSync(allocator, io, env, stderr, dir, file_path, is_repo, "scratch");
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

    return editAndPostSync(allocator, io, env, stderr, dir, file_path, is_repo, topic);
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

    var names = try collectTopicNames(allocator, io, topics_dir_path);
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
    var names = try collectTopicNames(allocator, io, topics_dir_path);
    defer {
        for (names.items) |s| allocator.free(s);
        names.deinit(allocator);
    }

    for (names.items) |name| {
        try stdout.print("{s}\n", .{name});
    }
    return 0;
}

fn collectTopicNames(allocator: std.mem.Allocator, io: Io, topics_dir_path: []const u8) !std.ArrayList([]const u8) {
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
    scope: []const u8,
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

    git.addAll(io, dir) catch |err| return reportGit(stderr, "git add", err);
    const has_changes = git.hasStagedChanges(io, dir) catch |err|
        return reportGit(stderr, "git diff", err);
    if (!has_changes) return 0;

    const ts = try time.nowLocalString(allocator);
    defer allocator.free(ts);
    const msg = try std.fmt.allocPrint(allocator, "docs({s}): {s}", .{ scope, ts });
    defer allocator.free(msg);

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

                    // 3. アーカイブから zemo バイナリを抽出
                    const new_binary = upgrade.extractZemoBinary(allocator, archive, upgrade.binaryBasename()) catch |err| {
                        try stderr.print("zemo: failed to extract binary: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                    defer allocator.free(new_binary);

                    // 4. 自分自身のパスを取得して置換
                    const install_path = upgrade.installPath(allocator, io) catch |err| {
                        try stderr.print("zemo: failed to resolve install path: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                    defer allocator.free(install_path);

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
