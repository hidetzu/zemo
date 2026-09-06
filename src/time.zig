const std = @import("std");

/// libc の `struct tm` の冒頭 9 フィールド（POSIX/Windows 共通部分）。
/// プラットフォーム固有の追加フィールド（tm_gmtoff 等）は使わないので無視する。
const c_tm = extern struct {
    sec: c_int,
    min: c_int,
    hour: c_int,
    mday: c_int,
    mon: c_int, // 0..11
    year: c_int, // years since 1900
    wday: c_int,
    yday: c_int,
    isdst: c_int,
};

extern "c" fn time(tloc: ?*std.c.time_t) std.c.time_t;
extern "c" fn localtime(timep: *const std.c.time_t) ?*c_tm;

pub const Timestamp = struct {
    year: u16,
    month: u8, // 1..12
    day: u8, // 1..31
    hour: u8, // 0..23
    minute: u8, // 0..59
};

/// 現在のローカル時刻を取得する。
pub fn nowLocal() !Timestamp {
    var t = time(null);
    const local = localtime(&t) orelse return error.LocaltimeFailed;
    return .{
        .year = @intCast(local.year + 1900),
        .month = @intCast(local.mon + 1),
        .day = @intCast(local.mday),
        .hour = @intCast(local.hour),
        .minute = @intCast(local.min),
    };
}

/// "YYYY-MM-DD HH:MM" 形式に整形する。
/// 戻り値はアロケータ確保。呼び出し側が free すること。
pub fn formatTimestamp(allocator: std.mem.Allocator, ts: Timestamp) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}",
        .{ ts.year, ts.month, ts.day, ts.hour, ts.minute },
    );
}

/// "YYYY-MM-DD" 形式に整形する。⚠ ideas の `created` は日付だけを持つ
/// （時刻まで持つと「最終更新」に見えるが、それは git log が答える）。
/// 戻り値はアロケータ確保。呼び出し側が free すること。
pub fn formatDate(allocator: std.mem.Allocator, ts: Timestamp) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}",
        .{ ts.year, ts.month, ts.day },
    );
}

/// 現在ローカル日付を "YYYY-MM-DD" 文字列で返す。
/// 戻り値はアロケータ確保。呼び出し側が free すること。
pub fn nowLocalDateString(allocator: std.mem.Allocator) ![]u8 {
    const ts = try nowLocal();
    return formatDate(allocator, ts);
}

/// 現在ローカル時刻を "YYYY-MM-DD HH:MM" 文字列で返す。
/// 戻り値はアロケータ確保。呼び出し側が free すること。
pub fn nowLocalString(allocator: std.mem.Allocator) ![]u8 {
    const ts = try nowLocal();
    return formatTimestamp(allocator, ts);
}

test "formatTimestamp: zero-pads single digits" {
    const a = std.testing.allocator;
    const got = try formatTimestamp(a, .{
        .year = 2026,
        .month = 5,
        .day = 5,
        .hour = 9,
        .minute = 7,
    });
    defer a.free(got);
    try std.testing.expectEqualStrings("2026-05-05 09:07", got);
}

test "formatTimestamp: handles double-digit fields" {
    const a = std.testing.allocator;
    const got = try formatTimestamp(a, .{
        .year = 2026,
        .month = 12,
        .day = 31,
        .hour = 23,
        .minute = 59,
    });
    defer a.free(got);
    try std.testing.expectEqualStrings("2026-12-31 23:59", got);
}

test "nowLocal: returns plausible values" {
    const ts = try nowLocal();
    try std.testing.expect(ts.year >= 2025 and ts.year <= 2100);
    try std.testing.expect(ts.month >= 1 and ts.month <= 12);
    try std.testing.expect(ts.day >= 1 and ts.day <= 31);
    try std.testing.expect(ts.hour <= 23);
    try std.testing.expect(ts.minute <= 59);
}

test "formatDate: zero-pads and drops the time" {
    const a = std.testing.allocator;
    const got = try formatDate(a, .{ .year = 2026, .month = 9, .day = 6, .hour = 14, .minute = 32 });
    defer a.free(got);
    try std.testing.expectEqualStrings("2026-09-06", got);
}

test "formatDate: is the date prefix of formatTimestamp" {
    const a = std.testing.allocator;
    const ts: Timestamp = .{ .year = 2026, .month = 12, .day = 31, .hour = 23, .minute = 59 };

    const date = try formatDate(a, ts);
    defer a.free(date);
    const full = try formatTimestamp(a, ts);
    defer a.free(full);

    try std.testing.expectEqualStrings(date, full[0..date.len]);
}
