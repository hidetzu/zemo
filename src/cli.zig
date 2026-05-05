const std = @import("std");
const Io = std.Io;

const paths = @import("paths.zig");
const editor = @import("editor.zig");
const git = @import("git.zig");
const time = @import("time.zig");

pub const Command = union(enum) {
    open_scratch,
    open_topic: []const u8,
    sync,
    help,
    version,
    too_many_args,
};

/// argv (program 名含む) を Command に解釈する。
pub fn parseArgs(args: []const []const u8) Command {
    if (args.len <= 1) return .open_scratch;
    const a = args[1];
    if (std.mem.eql(u8, a, "sync")) return .sync;
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
    \\  zemo help           Show this help
    \\  zemo version        Show version
    \\
    \\Topic name must match [a-zA-Z0-9_-].
    \\
;

const VERSION = "0.1.0";

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
    };
}

fn openScratch(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    stderr: *Io.Writer,
) !u8 {
    const dir = try paths.memoDir(allocator, env);
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

    const dir = try paths.memoDir(allocator, env);
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
    const dir = try paths.memoDir(allocator, env);
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
