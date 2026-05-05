const std = @import("std");
const Io = std.Io;

const RunOpt = struct { allow_nonzero: bool = false };

/// `git` を起動して終了コードを返す。
/// `allow_nonzero = false` の場合、非 0 終了は `error.GitFailed` として扱う。
fn run(io: Io, argv: []const []const u8, opt: RunOpt) !u8 {
    var child = std.process.spawn(io, .{ .argv = argv }) catch |err| switch (err) {
        error.FileNotFound => return error.GitNotFound,
        else => return err,
    };
    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| blk: {
            if (code != 0 and !opt.allow_nonzero) return error.GitFailed;
            break :blk code;
        },
        else => return error.GitFailed,
    };
}

/// `dir` が git work tree のルートかを判定する。
/// 通常 repo / git worktree / submodule のルートは true、親 repo 配下の
/// 通常ディレクトリは false（誤って親 repo に対して `git add -A` するのを防ぐ）。
pub fn isGitRepo(allocator: std.mem.Allocator, io: Io, dir: []const u8) bool {
    // git の認識する work tree の最上位を取得
    const argv = [_][]const u8{ "git", "-C", dir, "rev-parse", "--show-toplevel" };
    const result = std.process.run(allocator, io, .{ .argv = &argv }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return false,
        else => return false,
    }

    const toplevel = std.mem.trimEnd(u8, result.stdout, "\r\n");

    // dir 側の正規化されたパスを取得
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = Io.Dir.realPathFileAbsolute(io, dir, &buf) catch return false;
    const dir_real = buf[0..len];

    return std.mem.eql(u8, toplevel, dir_real);
}

pub fn pull(io: Io, dir: []const u8) !void {
    const argv = [_][]const u8{ "git", "-C", dir, "pull", "--rebase" };
    _ = try run(io, &argv, .{});
}

pub fn addAll(io: Io, dir: []const u8) !void {
    const argv = [_][]const u8{ "git", "-C", dir, "add", "-A" };
    _ = try run(io, &argv, .{});
}

/// `git diff --cached --quiet` の終了コードでステージング差分の有無を返す。
/// 0 = 変更なし、1 = 変更あり、その他 = git 内部エラー。
pub fn hasStagedChanges(io: Io, dir: []const u8) !bool {
    const argv = [_][]const u8{ "git", "-C", dir, "diff", "--cached", "--quiet" };
    const code = try run(io, &argv, .{ .allow_nonzero = true });
    return switch (code) {
        0 => false,
        1 => true,
        else => error.GitFailed,
    };
}

pub fn commit(io: Io, dir: []const u8, msg: []const u8) !void {
    const argv = [_][]const u8{ "git", "-C", dir, "commit", "-m", msg };
    _ = try run(io, &argv, .{});
}

pub fn push(io: Io, dir: []const u8) !void {
    const argv = [_][]const u8{ "git", "-C", dir, "push" };
    _ = try run(io, &argv, .{});
}

// 否定テスト（`isGitRepo` が non-repo dir で false を返すこと）は、
// std.testing.tmpDir が `.zig-cache/tmp/` 配下を使う関係で zemo 自身の
// work tree 内に入ってしまい、`git rev-parse` が常に true を返すため省略。

test "isGitRepo: returns true after git init at repo root" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &buf);
    const path = buf[0..len];

    const init_argv = [_][]const u8{ "git", "-C", path, "init", "--quiet" };
    var init_child = try std.process.spawn(io, .{
        .argv = &init_argv,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    _ = try init_child.wait(io);

    try std.testing.expect(isGitRepo(a, io, path));
}

test "isGitRepo: returns false for subdir of a repo (not root)" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &buf);
    const path = buf[0..len];

    const init_argv = [_][]const u8{ "git", "-C", path, "init", "--quiet" };
    var init_child = try std.process.spawn(io, .{
        .argv = &init_argv,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    _ = try init_child.wait(io);

    try tmp.dir.createDir(io, "subdir", .default_dir);
    const sub = try std.fs.path.join(a, &.{ path, "subdir" });
    defer a.free(sub);

    try std.testing.expect(!isGitRepo(a, io, sub));
}
