const std = @import("std");

/// topic 名が許容文字 `[a-zA-Z0-9_-]` のみで構成されているか判定する。
/// 空文字列は false。
pub fn isValidTopic(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_' or c == '-';
        if (!ok) return false;
    }
    return true;
}

/// 指定したディレクトリ配下のscratch.txtを返す
//  scratchファイルを返却する
pub fn scratchPath(allocator: std.mem.Allocator, dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ dir, "scratch.txt" });
}

/// トピック記載用のメモファイルのパスを返す
pub fn topicPath(allocator: std.mem.Allocator, dir: []const u8, topic: []const u8) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.md", .{topic});
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ dir, "topics", filename });
}

/// 純粋関数: 環境変数の値（取れたか取れなかったか）と OS を入力にして
/// memo dir を決定する。テストはこっちを叩く。
pub fn resolveMemoDir(
    allocator: std.mem.Allocator,
    zemo_dir: ?[]const u8,
    home: ?[]const u8,
) ![]u8 {
    if (zemo_dir) |d| return allocator.dupe(u8, d);
    const h = home orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ h, "memo" });
}

/// I/O 側: 環境マップから値を読んで resolveMemoDir に渡すだけ
pub fn memoDir(allocator: std.mem.Allocator, env: *const std.process.Environ.Map) ![]u8 {
    const zemo_dir = env.get("ZEMO_DIR");
    const home_var = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    const home = env.get(home_var);
    return resolveMemoDir(allocator, zemo_dir, home);
}

test "isValidTopic: accepts alphanumerics, underscore, hyphen" {
    try std.testing.expect(isValidTopic("hello"));
    try std.testing.expect(isValidTopic("Hello-World_123"));
    try std.testing.expect(isValidTopic("a"));
}

test "isValidTopic: rejects empty string" {
    try std.testing.expect(!isValidTopic(""));
}

test "isValidTopic: rejects path traversal and separators" {
    try std.testing.expect(!isValidTopic("../etc"));
    try std.testing.expect(!isValidTopic("foo/bar"));
    try std.testing.expect(!isValidTopic("foo\\bar"));
}

test "isValidTopic: rejects dots, spaces, multibyte" {
    try std.testing.expect(!isValidTopic("hello.md"));
    try std.testing.expect(!isValidTopic("hello world"));
    try std.testing.expect(!isValidTopic("日本語"));
}

test "scratchPath: ends with scratch.txt" {
    const a = std.testing.allocator;
    const got = try scratchPath(a, "/tmp/memo");
    defer a.free(got);
    try std.testing.expectEqualStrings(
        "/tmp/memo" ++ std.fs.path.sep_str ++ "scratch.txt",
        got,
    );
}

test "topicPath: dir/topics/<topic>.md" {
    const a = std.testing.allocator;
    const got = try topicPath(a, "/tmp/memo", "hello");
    defer a.free(got);
    const sep = std.fs.path.sep_str;
    try std.testing.expectEqualStrings(
        "/tmp/memo" ++ sep ++ "topics" ++ sep ++ "hello.md",
        got,
    );
}

test "resolveMemoDir: ZEMO_DIR has highest priority" {
    const a = std.testing.allocator;
    const got = try resolveMemoDir(a, "/custom/dir", "/home/foo");
    defer a.free(got);
    try std.testing.expectEqualStrings("/custom/dir", got);
}

test "resolveMemoDir: falls back to HOME/memo on unix" {
    const a = std.testing.allocator;
    const got = try resolveMemoDir(a, null, "/home/foo");
    defer a.free(got);
    try std.testing.expectEqualStrings("/home/foo/memo", got);
}

test "resolveMemoDir: errors when no env available" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.HomeNotSet, resolveMemoDir(a, null, null));
}
