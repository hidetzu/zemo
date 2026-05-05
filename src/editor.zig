const std = @import("std");
const Io = std.Io;

pub const RunResult = union(enum) {
    ok,
    failed,
    /// エディタの実行ファイルが PATH 上に見つからなかった。中身は名前。
    /// 呼び出し側のアロケータで free すること。
    editor_not_found: []u8,
    /// env / fallback ともに該当エディタが無い。
    no_editor,
};

pub const OsKind = enum { windows, unix };

/// OS 別の fallback 候補（優先順）。
pub fn fallbackCandidates(os: OsKind) []const []const u8 {
    return switch (os) {
        .unix => &.{ "nvim", "vim", "vi" },
        .windows => &.{ "nvim", "notepad" },
    };
}

/// 純粋関数: env 値 + 「PATH で見つかった fallback」からエディタ文字列を決定する。
/// 戻り値はアロケータ確保。呼び出し側が free すること。
/// `chosen_fallback` が null（env も fallback も無い）ときは error.NoEditor。
pub fn resolveEditor(
    allocator: std.mem.Allocator,
    zemo_editor: ?[]const u8,
    visual: ?[]const u8,
    editor: ?[]const u8,
    chosen_fallback: ?[]const u8,
) ![]u8 {
    if (zemo_editor) |v| return try allocator.dupe(u8, v);
    if (visual) |v| return try allocator.dupe(u8, v);
    if (editor) |v| return try allocator.dupe(u8, v);
    const fb = chosen_fallback orelse return error.NoEditor;
    return try allocator.dupe(u8, fb);
}

/// PATH を探索して、候補のうち最初に見つかった実行ファイル名を返す。
/// Windows では PATHEXT を解釈し、`<cand>` だけでなく `<cand><ext>` も試す
/// （PATHEXT 未設定なら `.COM;.EXE;.BAT;.CMD` を既定値として使う）。
/// 戻り値はアロケータ確保（呼び出し側が free）。見つからなければ null。
pub fn pickFromPath(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    candidates: []const []const u8,
) !?[]u8 {
    const path = env.get("PATH") orelse return null;
    const is_windows = comptime @import("builtin").os.tag == .windows;
    const sep_char: u8 = if (is_windows) ';' else ':';

    // Windows のみ PATHEXT を解釈してリスト化
    var ext_list: std.ArrayList([]const u8) = .empty;
    defer ext_list.deinit(allocator);
    if (is_windows) {
        const pathext = env.get("PATHEXT") orelse ".COM;.EXE;.BAT;.CMD";
        var ei = std.mem.tokenizeScalar(u8, pathext, ';');
        while (ei.next()) |ext| try ext_list.append(allocator, ext);
    }

    for (candidates) |cand| {
        var it = std.mem.tokenizeScalar(u8, path, sep_char);
        while (it.next()) |dir| {
            // 拡張子なしで存在チェック（Unix はこれだけ）
            const bare = try std.fs.path.join(allocator, &.{ dir, cand });
            defer allocator.free(bare);
            if (Io.Dir.accessAbsolute(io, bare, .{})) |_| {
                return try allocator.dupe(u8, cand);
            } else |_| {}

            // Windows: PATHEXT の各拡張子で試す
            for (ext_list.items) |ext| {
                const filename = try std.fmt.allocPrint(allocator, "{s}{s}", .{ cand, ext });
                defer allocator.free(filename);
                const full = try std.fs.path.join(allocator, &.{ dir, filename });
                defer allocator.free(full);
                Io.Dir.accessAbsolute(io, full, .{}) catch continue;
                return try allocator.dupe(u8, cand);
            }
        }
    }
    return null;
}

pub fn splitCommand(allocator: std.mem.Allocator, options: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);
    var it = std.mem.tokenizeAny(u8, options, " \t");
    while (it.next()) |tok| try list.append(allocator, tok);
    return try list.toOwnedSlice(allocator);
}

pub fn currentEditor(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
) ![]u8 {
    const ze = env.get("ZEMO_EDITOR");
    const visual = env.get("VISUAL");
    const editor = env.get("EDITOR");
    const os: OsKind = if (@import("builtin").os.tag == .windows) .windows else .unix;

    const chosen = try pickFromPath(allocator, io, env, fallbackCandidates(os));
    defer if (chosen) |c| allocator.free(c);

    return resolveEditor(allocator, ze, visual, editor, chosen);
}

pub fn runEditor(
    allocator: std.mem.Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    file_path: []const u8,
) !RunResult {
    // 1. 環境変数 + PATH 探索からエディタ文字列を決める
    const editor_str = currentEditor(allocator, io, env) catch |err| switch (err) {
        error.NoEditor => return RunResult.no_editor,
        else => return err,
    };
    defer allocator.free(editor_str);

    // 2. 空白 split → argv list（コマンド + フラグ）
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    var it = std.mem.tokenizeAny(u8, editor_str, " \t");
    while (it.next()) |tok| try argv.append(allocator, tok);

    if (argv.items.len == 0) return RunResult.no_editor;

    // 3. 末尾にファイルパスを追加
    try argv.append(allocator, file_path);

    // 4. 子プロセス起動 → 終了待ち
    var child = std.process.spawn(io, .{ .argv = argv.items }) catch |err| switch (err) {
        error.FileNotFound => return RunResult{ .editor_not_found = try allocator.dupe(u8, argv.items[0]) },
        else => return err,
    };
    const term = try child.wait(io);

    // 5. 終了コード判定
    return switch (term) {
        .exited => |code| if (code == 0) RunResult.ok else RunResult.failed,
        else => RunResult.failed, // signal/stopped/unknown
    };
}

test "splitCommand: single token" {
    const a = std.testing.allocator;
    const got = try splitCommand(a, "nvim");
    defer a.free(got);
    try std.testing.expectEqual(@as(usize, 1), got.len);
    try std.testing.expectEqualStrings("nvim", got[0]);
}

test "splitCommand: command with flags" {
    const a = std.testing.allocator;
    const got = try splitCommand(a, "code --wait");
    defer a.free(got);
    try std.testing.expectEqual(@as(usize, 2), got.len);
    try std.testing.expectEqualStrings("code", got[0]);
    try std.testing.expectEqualStrings("--wait", got[1]);
}

test "resolveEditor: ZEMO_EDITOR has highest priority" {
    const a = std.testing.allocator;
    const got = try resolveEditor(a, "vim", "code", "nano", "nvim");
    defer a.free(got);
    try std.testing.expectEqualStrings("vim", got);
}

test "resolveEditor: uses chosen fallback when no env vars set" {
    const a = std.testing.allocator;
    const got = try resolveEditor(a, null, null, null, "vi");
    defer a.free(got);
    try std.testing.expectEqualStrings("vi", got);
}

test "resolveEditor: errors when no env vars and no fallback" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.NoEditor, resolveEditor(a, null, null, null, null));
}

test "fallbackCandidates: unix list" {
    const list = fallbackCandidates(.unix);
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqualStrings("nvim", list[0]);
    try std.testing.expectEqualStrings("vim", list[1]);
    try std.testing.expectEqualStrings("vi", list[2]);
}

test "fallbackCandidates: windows list" {
    const list = fallbackCandidates(.windows);
    try std.testing.expectEqual(@as(usize, 2), list.len);
    try std.testing.expectEqualStrings("nvim", list[0]);
    try std.testing.expectEqualStrings("notepad", list[1]);
}
