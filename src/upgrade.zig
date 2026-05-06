const std = @import("std");
const builtin = @import("builtin");

pub const UpgradeMode = enum {
    run,
    check,
};

pub const Comparison = enum { older, equal, newer, invalid };

pub const AssetError = error{UnsupportedTarget};

pub const Asset = struct {
    name: []const u8,
    browser_download_url: []const u8,
};

pub const ReleaseInfo = struct {
    tag_name: []const u8,
    assets: []Asset,
};

pub fn assetName() AssetError![]const u8 {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            // Released asset is built with glibc (-Dtarget=x86_64-linux-gnu).
            // Refuse to upgrade musl-built binaries — replacing them with a
            // glibc binary would break on Alpine and similar musl-only systems.
            .x86_64 => switch (builtin.abi) {
                .gnu => "zemo-x86_64-linux-gnu.tar.gz",
                else => error.UnsupportedTarget,
            },
            else => error.UnsupportedTarget,
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "zemo-x86_64-macos.tar.gz",
            .aarch64 => "zemo-aarch64-macos.tar.gz",
            else => error.UnsupportedTarget,
        },
        // Windows support deferred to #11 — needs zip extraction and the
        // running-.exe self-replacement workaround. Returning UnsupportedTarget
        // here makes `zemo upgrade` fail fast instead of hitting confusing
        // gzip errors when fed the .zip asset.
        else => error.UnsupportedTarget,
    };
}

pub fn binaryBasename() []const u8 {
    return if (builtin.os.tag == .windows) "zemo.exe" else "zemo";
}

pub fn compareVersions(current: []const u8, latest: []const u8) Comparison {
    const cur = std.SemanticVersion.parse(stripV(current)) catch return .invalid;
    const lat = std.SemanticVersion.parse(stripV(latest)) catch return .invalid;
    return switch (cur.order(lat)) {
        .lt => .older,
        .eq => .equal,
        .gt => .newer,
    };
}

fn stripV(s: []const u8) []const u8 {
    if (s.len > 0 and s[0] == 'v') return s[1..];
    return s;
}

pub fn parseReleaseJson(
    allocator: std.mem.Allocator,
    json: []const u8,
) !std.json.Parsed(ReleaseInfo) {
    return std.json.parseFromSlice(ReleaseInfo, allocator, json, .{
        .ignore_unknown_fields = true,
    });
}

pub fn fetchLatestReleaseJson(allocator: std.mem.Allocator, io: anytype) ![]u8 {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = "https://api.github.com/repos/hidetzu/zemo/releases/latest" },
        .method = .GET,
        .response_writer = &body.writer,
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "zemo-upgrade" },
            .{ .name = "Accept", .value = "application/vnd.github+json" },
        },
    });

    if (result.status != .ok) return error.HttpRequestFailed;

    return body.toOwnedSlice();
}

pub fn findAssetUrl(info: ReleaseInfo, target_name: []const u8) ?[]const u8 {
    for (info.assets) |asset| {
        if (std.mem.eql(u8, asset.name, target_name)) {
            return asset.browser_download_url;
        }
    }
    return null;
}

test "assetName: returns asset for current target" {
    const expected = switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => switch (builtin.abi) {
                .gnu => "zemo-x86_64-linux-gnu.tar.gz",
                else => return error.SkipZigTest,
            },
            else => return error.SkipZigTest,
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "zemo-x86_64-macos.tar.gz",
            .aarch64 => "zemo-aarch64-macos.tar.gz",
            else => return error.SkipZigTest,
        },
        else => return error.SkipZigTest,
    };
    try std.testing.expectEqualStrings(expected, try assetName());
}

test "assetName: rejects musl Linux to avoid replacing musl with glibc binary" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    if (builtin.abi == .gnu) return error.SkipZigTest;
    try std.testing.expectError(error.UnsupportedTarget, assetName());
}

test "assetName: rejects Windows until #11 lands zip extraction" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expectError(error.UnsupportedTarget, assetName());
}

test "compareVersions: equal" {
    try std.testing.expectEqual(Comparison.equal, compareVersions("0.2.0", "0.2.0"));
}

test "compareVersions: older when local behind" {
    try std.testing.expectEqual(Comparison.older, compareVersions("0.2.0", "0.3.0"));
}

test "compareVersions: newer when local ahead" {
    try std.testing.expectEqual(Comparison.newer, compareVersions("0.3.0", "0.2.0"));
}

test "compareVersions: handles `v` prefix" {
    try std.testing.expectEqual(Comparison.equal, compareVersions("0.2.0", "v0.2.0"));
}

test "compareVersions: invalid input" {
    try std.testing.expectEqual(Comparison.invalid, compareVersions("not-semver", "0.2.0"));
}

test "parseReleaseJson: extracts tag_name and assets" {
    const json =
        \\{
        \\  "tag_name": "v0.3.0",
        \\  "id": 123456,
        \\  "name": "v0.3.0",
        \\  "draft": false,
        \\  "prerelease": false,
        \\  "assets": [
        \\    { "name": "zemo-x86_64-linux-gnu.tar.gz", "browser_download_url": "https://example.com/linux.tar.gz", "size": 1234 },
        \\    { "name": "zemo-x86_64-windows.zip", "browser_download_url": "https://example.com/win.zip", "size": 5678 }
        \\  ]
        \\}
    ;
    const parsed = try parseReleaseJson(std.testing.allocator, json);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("v0.3.0", parsed.value.tag_name);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.assets.len);
    try std.testing.expectEqualStrings("zemo-x86_64-linux-gnu.tar.gz", parsed.value.assets[0].name);
    try std.testing.expectEqualStrings("https://example.com/linux.tar.gz", parsed.value.assets[0].browser_download_url);
}

pub fn installPath(allocator: std.mem.Allocator, io: std.Io) ![:0]u8 {
    return std.process.executablePathAlloc(io, allocator);
}

pub fn downloadToMemory(
    allocator: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
) ![]u8 {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &body.writer,
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "zemo/0.2.0 (+https://github.com/hidetzu/zemo)" },
            .{ .name = "Accept", .value = "*/*" },
        },
    });

    if (result.status != .ok) {
        std.log.err("download failed: HTTP {d} {s} url={s}", .{
            @intFromEnum(result.status),
            @tagName(result.status),
            url,
        });
        return error.HttpRequestFailed;
    }

    return body.toOwnedSlice();
}

pub fn extractZemoBinary(
    allocator: std.mem.Allocator,
    archive: []const u8,
    binary_basename: []const u8, // "zemo" or "zemo.exe"
) ![]u8 {
    // 1. archive bytes を Reader として包む
    var input = std.Io.Reader.fixed(archive);

    // 2. gzip decompressor
    var window_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress = std.compress.flate.Decompress.init(&input, .gzip, &window_buf);

    // 3. tar iterator
    var file_name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var iter = std.tar.Iterator.init(&decompress.reader, .{
        .file_name_buffer = &file_name_buf,
        .link_name_buffer = &link_name_buf,
    });

    // 4. 対象ファイルを探して抽出
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        // エントリ名は "zemo-x86_64-linux-gnu/zemo" のような形なので basename 比較
        const basename = std.fs.path.basename(entry.name);
        if (std.mem.eql(u8, basename, binary_basename)) {
            var output = std.Io.Writer.Allocating.init(allocator);
            errdefer output.deinit();
            try iter.streamRemaining(entry, &output.writer);
            return output.toOwnedSlice();
        }
    }

    return error.BinaryNotFoundInArchive;
}

pub fn replaceBinary(
    allocator: std.mem.Allocator,
    io: std.Io,
    install_path: []const u8,
    new_binary: []const u8,
) !void {
    // 1. sibling temp path "<install_path>.new"
    const temp_path = try std.fmt.allocPrint(allocator, "{s}.new", .{install_path});
    defer allocator.free(temp_path);

    // 2. temp ファイルに書き出し + 実行権限付与
    {
        const temp_file = try std.Io.Dir.createFileAbsolute(io, temp_path, .{});
        defer temp_file.close(io);

        var buf: [4096]u8 = undefined;
        var w = temp_file.writer(io, &buf);
        try w.interface.writeAll(new_binary);
        try w.interface.flush();

        // chmod 0o755 相当 (Unix の場合; Windows では no-op 相当の挙動)
        const perms: std.Io.File.Permissions = @enumFromInt(0o755);
        try temp_file.setPermissions(io, perms);
    }

    // 3. atomic rename: temp → install_path
    try std.Io.Dir.renameAbsolute(temp_path, install_path, io);
}

test "parseReleaseJson: invalid JSON returns error" {
    try std.testing.expectError(error.SyntaxError, parseReleaseJson(std.testing.allocator, "not a json"));
}

test "findAssetUrl: returns URL when asset name matches" {
    var assets = [_]Asset{
        .{ .name = "zemo-x86_64-linux-gnu.tar.gz", .browser_download_url = "https://example.com/linux" },
        .{ .name = "zemo-x86_64-windows.zip", .browser_download_url = "https://example.com/win" },
    };
    const info = ReleaseInfo{ .tag_name = "v1.0.0", .assets = &assets };
    const url = findAssetUrl(info, "zemo-x86_64-linux-gnu.tar.gz");
    try std.testing.expectEqualStrings("https://example.com/linux", url.?);
}

test "findAssetUrl: returns null when not found" {
    var assets = [_]Asset{
        .{ .name = "zemo-x86_64-windows.zip", .browser_download_url = "https://example.com/win" },
    };
    const info = ReleaseInfo{ .tag_name = "v1.0.0", .assets = &assets };
    try std.testing.expect(findAssetUrl(info, "zemo-aarch64-macos.tar.gz") == null);
}

test "installPath: returns absolute non-empty path" {
    const a = std.testing.allocator;
    const path = try installPath(a, std.testing.io);
    defer a.free(path);
    try std.testing.expect(path.len > 0);
    try std.testing.expect(std.fs.path.isAbsolute(path));
}

test "replaceBinary: replaces existing file with new contents" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 既存ファイルを作る (= 置換対象)
    {
        const f = try tmp.dir.createFile(io, "fakezemo", .{});
        defer f.close(io);
        var buf: [16]u8 = undefined;
        var w = f.writer(io, &buf);
        try w.interface.writeAll("OLD");
        try w.interface.flush();
    }

    // 絶対パス取得
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &path_buf);
    const install_path = try std.fs.path.join(a, &.{ path_buf[0..len], "fakezemo" });
    defer a.free(install_path);

    // 置換実行
    try replaceBinary(a, io, install_path, "NEW BINARY");

    // 検証
    const f = try std.Io.Dir.openFileAbsolute(io, install_path, .{ .mode = .read_only });
    defer f.close(io);
    var read_buf: [64]u8 = undefined;
    var r = f.reader(io, &read_buf);
    var content = std.Io.Writer.Allocating.init(a);
    defer content.deinit();
    _ = try r.interface.streamRemaining(&content.writer);
    try content.writer.flush();
    try std.testing.expectEqualStrings("NEW BINARY", content.written());
}
