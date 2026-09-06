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
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "zemo-x86_64-windows.zip",
            else => error.UnsupportedTarget,
        },
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
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "zemo-x86_64-windows.zip",
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

/// zip アーカイブから basename 一致のエントリを抽出してメモリに返す。
/// std.zip.Iterator が *File.Reader を要求するため、archive bytes を
/// `work_dir_abs` 配下の一時ファイルに書き出してから読み戻す。
pub fn extractZemoBinaryFromZip(
    allocator: std.mem.Allocator,
    io: std.Io,
    archive: []const u8,
    binary_basename: []const u8, // "zemo.exe"
    work_dir_abs: []const u8, // 一時ファイルを置く書き込み可能ディレクトリ
) ![]u8 {
    // 1. archive bytes を一時ファイルへ書き出す
    const temp_zip_path = try std.fs.path.join(
        allocator,
        &.{ work_dir_abs, ".zemo-upgrade.zip.tmp" },
    );
    defer allocator.free(temp_zip_path);
    {
        const f = try std.Io.Dir.createFileAbsolute(io, temp_zip_path, .{});
        defer f.close(io);
        var w_buf: [4096]u8 = undefined;
        var w = f.writer(io, &w_buf);
        try w.interface.writeAll(archive);
        try w.interface.flush();
    }
    defer std.Io.Dir.deleteFileAbsolute(io, temp_zip_path) catch {};

    // 2. 一時ファイルを File.Reader として開く
    var zf = try std.Io.Dir.openFileAbsolute(io, temp_zip_path, .{ .mode = .read_only });
    defer zf.close(io);
    var read_buf: [4096]u8 = undefined;
    var fr = zf.reader(io, &read_buf);

    // 3. central directory を走査して対象エントリを探す
    var iter = try std.zip.Iterator.init(&fr);
    var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
    while (try iter.next()) |entry| {
        if (entry.filename_len == 0 or entry.filename_len > filename_buf.len) continue;
        const filename = filename_buf[0..entry.filename_len];
        try fr.seekTo(entry.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));
        try fr.interface.readSliceAll(filename);

        if (filename[filename.len - 1] == '/') continue; // ディレクトリエントリ
        if (!std.mem.eql(u8, std.fs.path.basename(filename), binary_basename)) continue;

        return try decompressZipEntry(allocator, &fr, entry);
    }

    return error.BinaryNotFoundInArchive;
}

/// zip エントリ 1 件をメモリ上に展開する。
/// std.zip.Iterator.Entry.extract() が File に書き出す挙動を、メモリ向けに置き換えたもの。
fn decompressZipEntry(
    allocator: std.mem.Allocator,
    fr: *std.Io.File.Reader,
    entry: std.zip.Iterator.Entry,
) ![]u8 {
    // local file header からデータ開始位置を計算
    try fr.seekTo(entry.file_offset);
    const local_header = try fr.interface.takeStruct(std.zip.LocalFileHeader, .little);
    if (!std.mem.eql(u8, &local_header.signature, &std.zip.local_file_header_sig))
        return error.ZipBadFileOffset;

    const local_data_offset: u64 = entry.file_offset +
        @sizeOf(std.zip.LocalFileHeader) +
        local_header.filename_len +
        local_header.extra_len;
    try fr.seekTo(local_data_offset);

    var output = std.Io.Writer.Allocating.init(allocator);
    errdefer output.deinit();

    switch (entry.compression_method) {
        .store => try fr.interface.streamExact64(&output.writer, entry.uncompressed_size),
        .deflate => {
            var flate_buf: [std.compress.flate.max_window_len]u8 = undefined;
            var decompress = std.compress.flate.Decompress.init(&fr.interface, .raw, &flate_buf);
            try decompress.reader.streamExact64(&output.writer, entry.uncompressed_size);
        },
        else => return error.UnsupportedCompressionMethod,
    }

    return output.toOwnedSlice();
}

pub fn replaceBinary(
    allocator: std.mem.Allocator,
    io: std.Io,
    install_path: []const u8,
    new_binary: []const u8,
) !void {
    if (builtin.os.tag == .windows) {
        return replaceBinaryWindows(allocator, io, install_path, new_binary);
    }
    return replaceBinaryPosix(allocator, io, install_path, new_binary);
}

fn replaceBinaryPosix(
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

/// Windows では走行中の `.exe` を削除できないため、以下の手順で置換する:
///   1. 新バイナリを `<install>.new` に書き出す
///   2. `<install>` を `<install>.old` に rename (走行中でも可)
///   3. `<install>.new` を `<install>` に rename
/// 残った `<install>.old` は次回起動時に `cleanupStaleBinary` で削除する。
fn replaceBinaryWindows(
    allocator: std.mem.Allocator,
    io: std.Io,
    install_path: []const u8,
    new_binary: []const u8,
) !void {
    const new_path = try std.fmt.allocPrint(allocator, "{s}.new", .{install_path});
    defer allocator.free(new_path);
    const old_path = try std.fmt.allocPrint(allocator, "{s}.old", .{install_path});
    defer allocator.free(old_path);

    // 古い .new / .old が残っていた場合は無視できる範囲で掃除
    std.Io.Dir.deleteFileAbsolute(io, new_path) catch {};

    // 1. 新バイナリを <install>.new に書く
    {
        const f = try std.Io.Dir.createFileAbsolute(io, new_path, .{});
        defer f.close(io);
        var buf: [4096]u8 = undefined;
        var w = f.writer(io, &buf);
        try w.interface.writeAll(new_binary);
        try w.interface.flush();
    }
    errdefer std.Io.Dir.deleteFileAbsolute(io, new_path) catch {};

    // 2. 走行中の <install> を <install>.old へ退避 (REPLACE_EXISTING)
    try moveFileReplaceExistingWindows(allocator, install_path, old_path);

    // 3. <install>.new を <install> へ昇格 (REPLACE_EXISTING; race 対策)
    moveFileReplaceExistingWindows(allocator, new_path, install_path) catch |err| {
        // ロールバック: .old を install_path へ戻す
        moveFileReplaceExistingWindows(allocator, old_path, install_path) catch {};
        return err;
    };
}

const MOVEFILE_REPLACE_EXISTING: u32 = 0x1;

extern "kernel32" fn MoveFileExW(
    lpExistingFileName: ?[*:0]const u16,
    lpNewFileName: ?[*:0]const u16,
    dwFlags: u32,
) callconv(.winapi) std.os.windows.BOOL;

/// Windows で「既存ファイルを置き換える rename」。
/// ⚠ `std.Io.Dir.renameAbsolute` は既存の宛先があると失敗するため、こちらを使う。
/// ⚠ 同じ問いに答える実装を2つ持たないため、`cli.zig` のファイル書き換えもここを呼ぶ。
pub fn moveFileReplaceExistingWindows(
    allocator: std.mem.Allocator,
    src_wtf8: []const u8,
    dst_wtf8: []const u8,
) !void {
    const src_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, src_wtf8) catch
        return error.InvalidPath;
    defer allocator.free(src_w);
    const dst_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, dst_wtf8) catch
        return error.InvalidPath;
    defer allocator.free(dst_w);

    if (!MoveFileExW(src_w.ptr, dst_w.ptr, MOVEFILE_REPLACE_EXISTING).toBool()) {
        return error.MoveFileFailed;
    }
}

/// Windows: 直前の `zemo upgrade` が残した `<exe>.old` をベストエフォートで削除する。
/// 他プラットフォームでは何もしない。失敗しても無視する。
pub fn cleanupStaleBinary(allocator: std.mem.Allocator, io: std.Io) void {
    if (builtin.os.tag != .windows) return;
    const exe_path = std.process.executablePathAlloc(io, allocator) catch return;
    defer allocator.free(exe_path);
    const old_path = std.fmt.allocPrint(allocator, "{s}.old", .{exe_path}) catch return;
    defer allocator.free(old_path);
    std.Io.Dir.deleteFileAbsolute(io, old_path) catch {};
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

/// テスト用: 1 ファイルだけを格納した最小 zip を組み立てる (compression: store)。
fn buildStoredZip(
    allocator: std.mem.Allocator,
    filename: []const u8,
    contents: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    errdefer buf.deinit();
    const w = &buf.writer;

    const crc = std.hash.Crc32.hash(contents);
    const fname_len: u16 = @intCast(filename.len);
    const csize: u32 = @intCast(contents.len);
    const usize_: u32 = @intCast(contents.len);
    const lfh_offset: u32 = 0;

    // Local File Header
    try w.writeAll("PK\x03\x04");
    try w.writeInt(u16, 20, .little); // version needed
    try w.writeInt(u16, 0, .little); // flags
    try w.writeInt(u16, 0, .little); // method = store
    try w.writeInt(u16, 0, .little); // mod time
    try w.writeInt(u16, 0x21, .little); // mod date (1980-01-01)
    try w.writeInt(u32, crc, .little);
    try w.writeInt(u32, csize, .little);
    try w.writeInt(u32, usize_, .little);
    try w.writeInt(u16, fname_len, .little);
    try w.writeInt(u16, 0, .little); // extra len
    try w.writeAll(filename);
    try w.writeAll(contents);

    const cd_offset: u32 = @intCast(buf.written().len);

    // Central Directory File Header
    try w.writeAll("PK\x01\x02");
    try w.writeInt(u16, 20, .little); // version made by
    try w.writeInt(u16, 20, .little); // version needed
    try w.writeInt(u16, 0, .little); // flags
    try w.writeInt(u16, 0, .little); // method
    try w.writeInt(u16, 0, .little); // mod time
    try w.writeInt(u16, 0x21, .little); // mod date
    try w.writeInt(u32, crc, .little);
    try w.writeInt(u32, csize, .little);
    try w.writeInt(u32, usize_, .little);
    try w.writeInt(u16, fname_len, .little);
    try w.writeInt(u16, 0, .little); // extra len
    try w.writeInt(u16, 0, .little); // comment len
    try w.writeInt(u16, 0, .little); // disk number
    try w.writeInt(u16, 0, .little); // internal attrs
    try w.writeInt(u32, 0, .little); // external attrs
    try w.writeInt(u32, lfh_offset, .little);
    try w.writeAll(filename);

    const cd_size: u32 = @intCast(buf.written().len - cd_offset);

    // End of Central Directory
    try w.writeAll("PK\x05\x06");
    try w.writeInt(u16, 0, .little); // disk
    try w.writeInt(u16, 0, .little); // disk with CD start
    try w.writeInt(u16, 1, .little); // entries this disk
    try w.writeInt(u16, 1, .little); // total entries
    try w.writeInt(u32, cd_size, .little);
    try w.writeInt(u32, cd_offset, .little);
    try w.writeInt(u16, 0, .little); // comment len

    return buf.toOwnedSlice();
}

test "extractZemoBinaryFromZip: extracts stored entry by basename" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive = try buildStoredZip(a, "zemo-x86_64-windows/zemo.exe", "MZHELLO");
    defer a.free(archive);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &path_buf);
    const work_dir = path_buf[0..len];

    const out = try extractZemoBinaryFromZip(a, io, archive, "zemo.exe", work_dir);
    defer a.free(out);

    try std.testing.expectEqualStrings("MZHELLO", out);
}

test "extractZemoBinaryFromZip: returns error when basename not in archive" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive = try buildStoredZip(a, "other.txt", "irrelevant");
    defer a.free(archive);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &path_buf);
    const work_dir = path_buf[0..len];

    try std.testing.expectError(
        error.BinaryNotFoundInArchive,
        extractZemoBinaryFromZip(a, io, archive, "zemo.exe", work_dir),
    );
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
