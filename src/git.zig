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

/// memo ディレクトリが git から見て何か。
/// ⚠ 「git が見つからない」と「work tree のルートではない」は別の答え。前者を後者と言うと、
///   git を入れれば直るのに「repo ではない」と読ませることになる (CLAUDE.md §4-1)。
/// ⚠ 見つかったのに起動できない (権限など) は、まだ `.not_root` に畳まれている
///   (`classifyProbeError`)。main から引き継いだ振る舞いで、ここでは区別していない
///   (hidetzu/zemo#30)。
pub const Repo = enum { root, not_root, git_missing };

/// `git rev-parse` を起動できなかったときの答え。
/// ⚠ `git_missing` は、実行ファイルが無く、かつ `<dir>/.git` がある (同期するはずの memo) ときだけ。
///   `.git` の無い memo は git があっても同期しない設定なので、git が無くても `.not_root` のまま。
///   ここを取り違えると、git を入れていない人の同期しない memo が毎回失敗する。
pub fn classifyProbeError(err: anyerror, dot_git_exists: bool) Repo {
    return if (err == error.FileNotFound and dot_git_exists) .git_missing else .not_root;
}

/// `dir` が git work tree のルートかを判定する。
/// 通常 repo / git worktree / submodule のルートは `.root`、親 repo 配下の
/// 通常ディレクトリは `.not_root`（誤って親 repo に対して `git add -A` するのを防ぐ）。
pub fn repoAt(allocator: std.mem.Allocator, io: Io, dir: []const u8) Repo {
    // git の認識する work tree の最上位を取得
    const argv = [_][]const u8{ "git", "-C", dir, "rev-parse", "--show-toplevel" };
    const result = std.process.run(allocator, io, .{ .argv = &argv }) catch |err| {
        // `.git` は worktree ではファイル、通常はディレクトリ。どちらでも「ある」。
        const dot_git = std.fs.path.join(allocator, &.{ dir, ".git" }) catch return .not_root;
        defer allocator.free(dot_git);
        const exists = if (Io.Dir.accessAbsolute(io, dot_git, .{})) |_| true else |_| false;
        return classifyProbeError(err, exists);
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return .not_root,
        else => return .not_root,
    }

    const toplevel = std.mem.trimEnd(u8, result.stdout, "\r\n");

    // dir 側の正規化されたパスを取得
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = Io.Dir.realPathFileAbsolute(io, dir, &buf) catch return .not_root;
    const dir_real = buf[0..len];

    return if (std.mem.eql(u8, toplevel, dir_real)) .root else .not_root;
}

/// ⚠ `--no-autostash` はユーザーの `rebase.autoStash` を打ち消すため。autostash は、退避した変更を
///   戻すときにコンフリクトしても exit 0 を返し、コンフリクトマーカーを work tree に残す。続く
///   `add -A` と `commit` がそのマーカーを push してしまう (rebase.autoStash=true で実測)。
///   未コミットの変更があれば pull は失敗し、`pullBlock` がその理由を言い当てる。
pub fn pull(io: Io, dir: []const u8) !void {
    const argv = [_][]const u8{ "git", "-C", dir, "pull", "--rebase", "--no-autostash" };
    _ = try run(io, &argv, .{});
}

/// pull が git 側で失敗したとき、memo ディレクトリが何の状態で残ったか。
/// ⚠ 3 つは次の一手が違う: rebase を続けるか戻す / zemo sync でコミットする / リモートを直す。
pub const PullBlock = enum { rebase_in_progress, uncommitted, none };

/// ⚠ rebase 途中が先。途中の work tree は HEAD と違うので、未コミットの変更としても見えてしまう。
pub fn classifyPullBlock(rebase_in_progress: bool, has_uncommitted: bool) PullBlock {
    if (rebase_in_progress) return .rebase_in_progress;
    if (has_uncommitted) return .uncommitted;
    return .none;
}

/// pull 失敗後の状態を調べる。
/// ⚠ 調べられなかったものは「無い」に倒れ、従来どおりの文面 (`.none`) になる。新しい文面は、
///   その状態を実際に見たときだけ出す。
pub fn pullBlock(allocator: std.mem.Allocator, io: Io, dir: []const u8) PullBlock {
    return classifyPullBlock(rebaseInProgress(allocator, io, dir), hasUncommittedChanges(allocator, io, dir));
}

/// rebase が途中で止まっているか。`rebase-merge` (merge backend) と `rebase-apply` (apply backend)
/// のどちらかが git dir にあれば途中。
/// ⚠ git dir は `.git` 決め打ちにしない。worktree では `.git` がファイルで、実体は別の場所にある。
/// ⚠ 調べられなかったときは false (`pullBlock` 参照)。
pub fn rebaseInProgress(allocator: std.mem.Allocator, io: Io, dir: []const u8) bool {
    const argv = [_][]const u8{ "git", "-C", dir, "rev-parse", "--absolute-git-dir" };
    const result = std.process.run(allocator, io, .{ .argv = &argv }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return false,
        else => return false,
    }
    const git_dir = std.mem.trimEnd(u8, result.stdout, "\r\n");

    for ([_][]const u8{ "rebase-merge", "rebase-apply" }) |name| {
        const p = std.fs.path.join(allocator, &.{ git_dir, name }) catch return false;
        defer allocator.free(p);
        if (Io.Dir.accessAbsolute(io, p, .{})) |_| return true else |_| {}
    }
    return false;
}

/// 追跡中のファイルに、コミットされていない変更 (staged / unstaged) があるか。
/// `pull --rebase` が拒むのはこれ。未追跡のファイルは pull を止めないので数えない。
/// ⚠ HEAD が無い (コミットが 1 つも無い) と git は 128 を返す。調べられなかったので false。
///   出力は捕まえて捨てる。git の `fatal:` が zemo の文の上に並ぶと、それが原因に読める。
fn hasUncommittedChanges(allocator: std.mem.Allocator, io: Io, dir: []const u8) bool {
    const argv = [_][]const u8{ "git", "-C", dir, "diff", "--quiet", "HEAD", "--" };
    const result = std.process.run(allocator, io, .{ .argv = &argv }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code == 1,
        else => false,
    };
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

// 否定テスト（`repoAt` が non-repo dir で `.not_root` を返すこと）は、
// std.testing.tmpDir が `.zig-cache/tmp/` 配下を使う関係で zemo 自身の
// work tree 内に入ってしまい、`git rev-parse` が常に true を返すため省略。

test "repoAt: root after git init at repo root" {
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

    try std.testing.expectEqual(Repo.root, repoAt(a, io, path));
}

test "repoAt: not_root for subdir of a repo" {
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

    try std.testing.expectEqual(Repo.not_root, repoAt(a, io, sub));
}

test "classifyPullBlock: a rebase in progress wins over uncommitted changes" {
    try std.testing.expectEqual(PullBlock.rebase_in_progress, classifyPullBlock(true, true));
    try std.testing.expectEqual(PullBlock.rebase_in_progress, classifyPullBlock(true, false));
    try std.testing.expectEqual(PullBlock.uncommitted, classifyPullBlock(false, true));
    try std.testing.expectEqual(PullBlock.none, classifyPullBlock(false, false));
}

test "classifyProbeError: git_missing only when git is absent and .git is there" {
    try std.testing.expectEqual(Repo.git_missing, classifyProbeError(error.FileNotFound, true));
    try std.testing.expectEqual(Repo.not_root, classifyProbeError(error.FileNotFound, false));
    try std.testing.expectEqual(Repo.not_root, classifyProbeError(error.AccessDenied, true));
    try std.testing.expectEqual(Repo.not_root, classifyProbeError(error.OutOfMemory, true));
}
