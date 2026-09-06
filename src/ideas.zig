//! ideas 機能の純粋ロジック。
//!
//! ⚠ ここには I/O が無い。ファイルを読むのも書くのも git を呼ぶのも `cli.zig` の仕事で、
//!   この module は「テキストが入って、判断とテキストが出る」だけに保つ。
//!   （CLAUDE.md §1 "Pure decision before I/O"。I/O 関数の中に書いた判断は
//!   何にも assert できない。）
//!
//! 仕様は docs/ideas-spec.md。ステータスをディレクトリで持たない理由は
//! docs/adr/0001-an-ideas-status-lives-only-in-its-front-matter.md。

const std = @import("std");

/// アイディアの状態。⚠ この enum と `TRANSITIONS` が遷移の唯一の定義で、
/// 一覧・拒否メッセージ・help はすべてここを読む（2つ目のコピーを作らない）。
pub const Status = enum {
    backlog,
    prioritized,
    experimenting,
    published,
    dropped,

    pub fn fromString(s: []const u8) ?Status {
        inline for (@typeInfo(Status).@"enum".fields) |f| {
            if (std.mem.eql(u8, s, f.name)) return @field(Status, f.name);
        }
        return null;
    }

    pub fn name(self: Status) []const u8 {
        return @tagName(self);
    }
};

const Edge = struct { from: Status, to: []const Status };

/// ⚠ 遷移の唯一の定義。
/// 前進も後退も 1 段ずつ。`published` と `dropped` は終端で、そこからは出ない
/// （戻ってきたアイディアは新しいファイル。古いファイルは決定の記録として残る）。
const TRANSITIONS = [_]Edge{
    .{ .from = .backlog, .to = &.{ .prioritized, .dropped } },
    .{ .from = .prioritized, .to = &.{ .backlog, .experimenting, .dropped } },
    .{ .from = .experimenting, .to = &.{ .prioritized, .published, .dropped } },
    .{ .from = .published, .to = &.{} },
    .{ .from = .dropped, .to = &.{} },
};

/// `from` から行ける先。⚠ 拒否メッセージはこれを読んで「行ける先」を挙げる。
pub fn allowedFrom(from: Status) []const Status {
    for (TRANSITIONS) |e| {
        if (e.from == from) return e.to;
    }
    unreachable; // TRANSITIONS は Status 全要素を網羅する（下のテストが assert する）
}

pub fn canTransition(from: Status, to: Status) bool {
    for (allowedFrom(from)) |s| {
        if (s == to) return true;
    }
    return false;
}

/// 「行ける先」を人が読む形で並べる: "backlog, experimenting or dropped"。
/// 終端なら "nowhere" と書く。⚠ 空欄にしない（何も言っていないのと同じになる）。
pub fn writeAllowedFrom(w: *std.Io.Writer, from: Status) !void {
    const list = allowedFrom(from);
    if (list.len == 0) {
        try w.writeAll("nowhere");
        return;
    }
    for (list, 0..) |s, i| {
        if (i > 0) try w.writeAll(if (i == list.len - 1) " or " else ", ");
        try w.writeAll(s.name());
    }
}

/// フロントマターが読めなかったときの「読めなかった理由」。
/// ⚠ 壊れ方ごとに別の値であることが要件（docs/ideas-spec.md §3-1）。
/// 「フロントマターが無い」と「閉じていない」と「status が未知」は別の出来事で、
/// 1つに潰すとユーザの次の手が変わってしまう。
pub const Problem = union(enum) {
    no_front_matter,
    unterminated_front_matter,
    status_absent,
    status_unknown: []const u8,
    priority_unparseable: []const u8,

    pub fn write(self: Problem, w: *std.Io.Writer) !void {
        switch (self) {
            .no_front_matter => try w.writeAll("no front matter (line 1 is not `---`)"),
            .unterminated_front_matter => try w.writeAll("front matter is never closed"),
            .status_absent => try w.writeAll("no status: line"),
            .status_unknown => |v| try w.print("unknown status '{s}'", .{v}),
            .priority_unparseable => |v| try w.print("priority '{s}' is not an integer 1-5", .{v}),
        }
    }
};

/// 読めたフロントマター。文字列フィールドは元テキストへの参照で、コピーしていない。
/// ⚠ 元テキストより長生きさせないこと。
pub const Idea = struct {
    status: Status,
    /// ⚠ null は「未ランク」。5 と同じではないし、「壊れている」でもない。
    priority: ?u8,
    evaluation: []const u8,
    tags: []const u8,
    repo: []const u8,
    created: []const u8,
};

pub const Parse = union(enum) {
    ok: Idea,
    problem: Problem,
};

fn trimLineEnd(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

/// フロントマターを読む。⚠ 何も割り当てない。
pub fn parse(src: []const u8) Parse {
    const first_end = std.mem.indexOfScalar(u8, src, '\n') orelse src.len;
    if (!std.mem.eql(u8, trimLineEnd(src[0..first_end]), "---")) {
        return .{ .problem = .no_front_matter };
    }

    var status_raw: ?[]const u8 = null;
    var priority_raw: []const u8 = "";
    var evaluation: []const u8 = "";
    var tags: []const u8 = "";
    var repo: []const u8 = "";
    var created: []const u8 = "";
    var closed = false;

    var i: usize = if (first_end < src.len) first_end + 1 else src.len;
    while (i < src.len) {
        const e = std.mem.indexOfScalarPos(u8, src, i, '\n') orelse src.len;
        const line = trimLineEnd(src[i..e]);
        i = if (e < src.len) e + 1 else src.len;

        if (std.mem.eql(u8, line, "---")) {
            closed = true;
            break;
        }

        // ⚠ ':' を持たない行は読み飛ばす。壊れている印ではない（コメント等）。
        //   書き換えは行単位なので、読み飛ばした行もそのまま保存される。
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        if (std.mem.eql(u8, key, "status")) {
            status_raw = value;
        } else if (std.mem.eql(u8, key, "priority")) {
            priority_raw = value;
        } else if (std.mem.eql(u8, key, "evaluation")) {
            evaluation = value;
        } else if (std.mem.eql(u8, key, "tags")) {
            tags = value;
        } else if (std.mem.eql(u8, key, "repo")) {
            repo = value;
        } else if (std.mem.eql(u8, key, "created")) {
            created = value;
        }
    }

    if (!closed) return .{ .problem = .unterminated_front_matter };

    const st_raw = status_raw orelse return .{ .problem = .status_absent };
    if (st_raw.len == 0) return .{ .problem = .status_absent };
    const status = Status.fromString(st_raw) orelse
        return .{ .problem = .{ .status_unknown = st_raw } };

    // ⚠ 空 = 未ランク、読めない = エラー。この2つを混ぜない。
    var priority: ?u8 = null;
    if (priority_raw.len > 0) {
        const n = std.fmt.parseInt(u8, priority_raw, 10) catch
            return .{ .problem = .{ .priority_unparseable = priority_raw } };
        if (!isValidPriority(n)) return .{ .problem = .{ .priority_unparseable = priority_raw } };
        priority = n;
    }

    return .{ .ok = .{
        .status = status,
        .priority = priority,
        .evaluation = evaluation,
        .tags = tags,
        .repo = repo,
        .created = created,
    } };
}

/// 優先度は 1..5、1 が最高。
pub fn isValidPriority(n: u8) bool {
    return n >= 1 and n <= 5;
}

/// `zemo ideas:priority <name> <value>` の引数の解釈結果。
/// ⚠ 「未ランクにする」と「引数が誤り」は別の結果。混ぜると打ち間違いが
///   黙って未ランク化として通ってしまう。
pub const PriorityArg = union(enum) {
    set: u8,
    unranked,
    invalid,
};

/// "-" は「未ランクに戻す」。
/// ⚠ 未ランクはユーザが選べる値で、ファイルの初期状態専用ではない。
pub fn parsePriorityArg(s: []const u8) PriorityArg {
    if (std.mem.eql(u8, s, "-")) return .unranked;
    const n = std.fmt.parseInt(u8, s, 10) catch return .invalid;
    if (!isValidPriority(n)) return .invalid;
    return .{ .set = n };
}

/// フロントマター内の `<key>:` 行を書き換えた新しいテキストを返す。
///
/// ⚠ 未知のキー・キーの順序・本文はバイト単位で保存する。
///   これは1行の置換であって再シリアライズではない（ユーザのファイルはユーザのもの）。
/// ⚠ key が無い場合は閉じ `---` の直前に挿入する。
/// 戻り値はアロケータ確保。呼び出し側が free すること。
pub fn rewriteField(
    allocator: std.mem.Allocator,
    src: []const u8,
    key: []const u8,
    value: []const u8,
) ![]u8 {
    const crlf = std.mem.startsWith(u8, src, "---\r\n");
    const term: []const u8 = if (crlf) "\r\n" else "\n";

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const first_end = std.mem.indexOfScalar(u8, src, '\n') orelse src.len;
    var i: usize = if (first_end < src.len) first_end + 1 else src.len;
    try out.appendSlice(allocator, src[0..i]);

    while (i < src.len) {
        const e = std.mem.indexOfScalarPos(u8, src, i, '\n') orelse src.len;
        const next = if (e < src.len) e + 1 else src.len;
        const raw = src[i..e]; // 改行を含まない生の行
        const line = trimLineEnd(raw);

        if (std.mem.eql(u8, line, "---")) {
            // 閉じ `---` に到達 = 当該キーが無かった。⚠ ここに挿入する。
            try writeField(allocator, &out, key, value);
            try out.appendSlice(allocator, term);
            try out.appendSlice(allocator, src[i..]);
            return out.toOwnedSlice(allocator);
        }

        const colon = std.mem.indexOfScalar(u8, line, ':');
        if (colon != null and std.mem.eql(u8, std.mem.trim(u8, line[0..colon.?], " \t"), key)) {
            try writeField(allocator, &out, key, value);
            // ⚠ 元の行の行末をそのまま使う（CRLF のファイルを LF に変えない）。
            //   `line` は `\r` を落としてあるので、`e` からではなく本文の終わりから取る。
            try out.appendSlice(allocator, src[i + line.len .. next]);
            try out.appendSlice(allocator, src[next..]);
            return out.toOwnedSlice(allocator);
        }

        try out.appendSlice(allocator, src[i..next]);
        i = next;
    }

    // 閉じ `---` が無いテキストはここに来る。⚠ 呼び出し側が parse で弾いている前提。
    return error.NoFrontMatter;
}

fn writeField(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    key: []const u8,
    value: []const u8,
) !void {
    try out.appendSlice(allocator, key);
    try out.append(allocator, ':');
    // ⚠ 空の値は "key:" と書く。"key: " と末尾に空白を残さない。
    if (value.len > 0) {
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, value);
    }
}

/// `zemo ideas:new` が作るファイルの中身。
/// ⚠ 空のキーも書き出す。値の無いキーは「埋めてくれ」という促しで、
///   キーごと無いのは「形式が変わった」ように見える。
pub fn template(allocator: std.mem.Allocator, name: []const u8, created: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\---
        \\status: backlog
        \\priority:
        \\evaluation:
        \\tags:
        \\repo:
        \\created: {s}
        \\---
        \\
        \\# {s}
        \\
        \\
    , .{ created, name });
}

// ---- 一覧 ----

/// 一覧の1行分。`parse` の結果をそのまま持つので、読めなかったものも行として残る
/// （⚠ 読めないアイディアを一覧から落とさない）。
pub const Entry = struct {
    name: []const u8,
    parsed: Parse,

    pub fn priority(self: Entry) ?u8 {
        return switch (self.parsed) {
            .ok => |i| i.priority,
            .problem => null,
        };
    }

    pub fn created(self: Entry) []const u8 {
        return switch (self.parsed) {
            .ok => |i| i.created,
            .problem => "",
        };
    }
};

/// 既定の並び。⚠ ランク済みが先、昇順（1 が先）。未ランクはその後ろで、
/// 5 扱いで混ぜない。同順位は名前で解決するので並びは実行ごとに安定する。
pub fn lessByPriority(_: void, a: Entry, b: Entry) bool {
    const pa = a.priority();
    const pb = b.priority();
    if (pa) |x| {
        if (pb) |y| {
            if (x != y) return x < y;
        } else return true;
    } else if (pb != null) return false;
    return std.mem.lessThan(u8, a.name, b.name);
}

/// `--sort=created`。⚠ 新しい順。`created` が読めないものは最後、同着は名前順。
pub fn lessByCreated(_: void, a: Entry, b: Entry) bool {
    const ca = a.created();
    const cb = b.created();
    if (ca.len > 0) {
        if (cb.len > 0) {
            if (!std.mem.eql(u8, ca, cb)) return std.mem.lessThan(u8, cb, ca);
        } else return true;
    } else if (cb.len > 0) return false;
    return std.mem.lessThan(u8, a.name, b.name);
}

pub const Sort = enum { priority, created };

pub fn sortEntries(entries: []Entry, how: Sort) void {
    switch (how) {
        .priority => std.mem.sort(Entry, entries, {}, lessByPriority),
        .created => std.mem.sort(Entry, entries, {}, lessByCreated),
    }
}

/// UTF-8 の途中で切らずに `max` バイト以内に収める。
/// ⚠ evaluation は日本語が入りうるので、単純な `s[0..max]` は壊れたバイト列を出す。
pub fn truncateUtf8(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var end = max;
    while (end > 0 and (s[end] & 0xC0) == 0x80) end -= 1;
    return s[0..end];
}

// 一覧の桁。⚠ "experimenting" がちょうど収まる幅にしてある。
const PRI_W = 3;
const STATUS_W = 13;
const NAME_W = 20;
const EVAL_W = 40;

/// ⚠ 読めなかったアイディアの STATUS 欄。
/// 記号を使わないのは、Windows のコンソールで化けたものを見せないため。
const UNREADABLE = "unreadable";

fn padLeft(w: *std.Io.Writer, s: []const u8, width: usize) !void {
    if (s.len < width) try w.splatByteAll(' ', width - s.len);
    try w.writeAll(s);
}

fn padRight(w: *std.Io.Writer, s: []const u8, width: usize) !void {
    try w.writeAll(s);
    if (s.len < width) try w.splatByteAll(' ', width - s.len);
}

pub fn writeListHeader(w: *std.Io.Writer) !void {
    try padLeft(w, "PRI", PRI_W);
    try w.writeAll("  ");
    try padRight(w, "STATUS", STATUS_W);
    try w.writeAll("  ");
    try padRight(w, "NAME", NAME_W);
    try w.writeAll("  ");
    try w.writeAll("EVALUATION\n");
}

/// 一覧の1行。⚠ 名前は切り詰めない（切り詰めた名前はコマンドに打ち返せない）。
pub fn writeListRow(w: *std.Io.Writer, e: Entry) !void {
    var pri_buf: [4]u8 = undefined;
    const pri: []const u8 = if (e.priority()) |p|
        std.fmt.bufPrint(&pri_buf, "{d}", .{p}) catch unreachable
    else
        "-";
    try padLeft(w, pri, PRI_W);
    try w.writeAll("  ");

    switch (e.parsed) {
        .ok => |idea| {
            try padRight(w, idea.status.name(), STATUS_W);
            try w.writeAll("  ");
            // ⚠ 続く欄が空なら名前を詰めない。行末に空白を残さないため。
            const ev = truncateUtf8(idea.evaluation, EVAL_W);
            if (ev.len == 0) {
                try w.writeAll(e.name);
            } else {
                try padRight(w, e.name, NAME_W);
                try w.writeAll("  ");
                try w.writeAll(ev);
                if (ev.len < idea.evaluation.len) try w.writeAll("...");
            }
        },
        .problem => |p| {
            try padRight(w, UNREADABLE, STATUS_W);
            try w.writeAll("  ");
            try padRight(w, e.name, NAME_W);
            try w.writeAll("  ");
            try p.write(w);
        },
    }
    try w.writeAll("\n");
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn problemOf(src: []const u8) Problem {
    return switch (parse(src)) {
        .ok => @panic("expected a problem"),
        .problem => |p| p,
    };
}

/// ⚠ `Problem` はスライスを持つので `==` で比べられない。どの壊れ方かはタグで見る。
fn expectProblem(want: std.meta.Tag(Problem), src: []const u8) !void {
    try testing.expectEqual(want, std.meta.activeTag(problemOf(src)));
}

test "TRANSITIONS covers every Status" {
    // ⚠ allowedFrom は網羅を前提に unreachable を持つ。網羅が崩れたらここで落ちる。
    inline for (@typeInfo(Status).@"enum".fields) |f| {
        _ = allowedFrom(@field(Status, f.name));
    }
}

test "canTransition: forward one step at a time" {
    try testing.expect(canTransition(.backlog, .prioritized));
    try testing.expect(canTransition(.prioritized, .experimenting));
    try testing.expect(canTransition(.experimenting, .published));
}

test "canTransition: backward one step at a time" {
    try testing.expect(canTransition(.prioritized, .backlog));
    try testing.expect(canTransition(.experimenting, .prioritized));
}

test "canTransition: dropped from any non-terminal, never from a terminal" {
    try testing.expect(canTransition(.backlog, .dropped));
    try testing.expect(canTransition(.prioritized, .dropped));
    try testing.expect(canTransition(.experimenting, .dropped));
    try testing.expect(!canTransition(.published, .dropped));
    try testing.expect(!canTransition(.dropped, .published));
}

test "canTransition: no skipping" {
    try testing.expect(!canTransition(.backlog, .experimenting));
    try testing.expect(!canTransition(.backlog, .published));
    try testing.expect(!canTransition(.prioritized, .published));
}

test "canTransition: nothing leaves a terminal state" {
    try testing.expectEqual(@as(usize, 0), allowedFrom(.published).len);
    try testing.expectEqual(@as(usize, 0), allowedFrom(.dropped).len);
}

test "writeAllowedFrom: comma list ending in `or`" {
    var out = std.Io.Writer.Allocating.init(testing.allocator);
    defer out.deinit();
    try writeAllowedFrom(&out.writer, .prioritized);
    try out.writer.flush();
    try testing.expectEqualStrings("backlog, experimenting or dropped", out.written());
}

test "writeAllowedFrom: a terminal state says nowhere, never nothing" {
    var out = std.Io.Writer.Allocating.init(testing.allocator);
    defer out.deinit();
    try writeAllowedFrom(&out.writer, .published);
    try out.writer.flush();
    try testing.expectEqualStrings("nowhere", out.written());
}

test "parse: reads every field" {
    const src =
        \\---
        \\status: prioritized
        \\priority: 2
        \\evaluation: solves my own daily friction
        \\tags: zig, lsp
        \\repo: hidetzu/zig-lsp-server
        \\created: 2026-09-06
        \\---
        \\
        \\# zig-lsp-server
        \\
    ;
    const idea = parse(src).ok;
    try testing.expectEqual(Status.prioritized, idea.status);
    try testing.expectEqual(@as(?u8, 2), idea.priority);
    try testing.expectEqualStrings("solves my own daily friction", idea.evaluation);
    try testing.expectEqualStrings("zig, lsp", idea.tags);
    try testing.expectEqualStrings("hidetzu/zig-lsp-server", idea.repo);
    try testing.expectEqualStrings("2026-09-06", idea.created);
}

test "parse: an empty priority is unranked, not an error" {
    const src = "---\nstatus: backlog\npriority:\n---\n";
    const idea = parse(src).ok;
    try testing.expectEqual(@as(?u8, null), idea.priority);
}

test "parse: CRLF front matter" {
    const src = "---\r\nstatus: backlog\r\npriority: 3\r\n---\r\n\r\n# x\r\n";
    const idea = parse(src).ok;
    try testing.expectEqual(Status.backlog, idea.status);
    try testing.expectEqual(@as(?u8, 3), idea.priority);
}

test "parse: a repo value keeps everything after the first colon" {
    const src = "---\nstatus: backlog\nevaluation: it is good: really\n---\n";
    const idea = parse(src).ok;
    try testing.expectEqualStrings("it is good: really", idea.evaluation);
}

// ⚠ 以下は docs/ideas-spec.md §3-1 の各行。壊れ方が別々の値になることが要件。

test "parse problem: no front matter" {
    try expectProblem(.no_front_matter, "# just a heading\n");
    try expectProblem(.no_front_matter, "");
    try expectProblem(.no_front_matter, "\n---\nstatus: backlog\n---\n");
}

test "parse problem: front matter opened and never closed" {
    try expectProblem(.unterminated_front_matter, "---\nstatus: backlog\npriority: 1\n");
}

test "parse problem: status absent is not the same as unknown" {
    try expectProblem(.status_absent, "---\npriority: 1\n---\n");
    try expectProblem(.status_absent, "---\nstatus:\n---\n");

    const p = problemOf("---\nstatus: archived\n---\n");
    try testing.expectEqualStrings("archived", p.status_unknown);
}

test "parse problem: an unknown status is never coerced to the nearest match" {
    const p = problemOf("---\nstatus: backlogged\n---\n");
    try testing.expectEqualStrings("backlogged", p.status_unknown);
}

test "parse problem: unparseable priority is not read as absent" {
    const a = problemOf("---\nstatus: backlog\npriority: high\n---\n");
    try testing.expectEqualStrings("high", a.priority_unparseable);

    const b = problemOf("---\nstatus: backlog\npriority: 9\n---\n");
    try testing.expectEqualStrings("9", b.priority_unparseable);

    const c = problemOf("---\nstatus: backlog\npriority: 0\n---\n");
    try testing.expectEqualStrings("0", c.priority_unparseable);
}

test "Problem.write: each failure says which failure it was" {
    const cases = [_]struct { p: Problem, want: []const u8 }{
        .{ .p = .no_front_matter, .want = "no front matter (line 1 is not `---`)" },
        .{ .p = .unterminated_front_matter, .want = "front matter is never closed" },
        .{ .p = .status_absent, .want = "no status: line" },
        .{ .p = .{ .status_unknown = "archived" }, .want = "unknown status 'archived'" },
        .{ .p = .{ .priority_unparseable = "x" }, .want = "priority 'x' is not an integer 1-5" },
    };
    for (cases) |c| {
        var out = std.Io.Writer.Allocating.init(testing.allocator);
        defer out.deinit();
        try c.p.write(&out.writer);
        try out.writer.flush();
        try testing.expectEqualStrings(c.want, out.written());
    }
}

test "parsePriorityArg: 1-5, `-` for unranked, and everything else invalid" {
    try testing.expectEqual(@as(u8, 1), parsePriorityArg("1").set);
    try testing.expectEqual(@as(u8, 5), parsePriorityArg("5").set);
    try testing.expectEqual(PriorityArg.unranked, std.meta.activeTag(parsePriorityArg("-")));
    // ⚠ 範囲外・非数値は invalid。unranked に落とさない。
    for ([_][]const u8{ "0", "6", "300", "high", "", " 1", "1.5" }) |bad| {
        try testing.expectEqual(PriorityArg.invalid, std.meta.activeTag(parsePriorityArg(bad)));
    }
}

test "rewriteField: replaces one line and preserves everything else byte for byte" {
    const src =
        \\---
        \\status: backlog
        \\priority: 2
        \\note: a key we do not know
        \\created: 2026-09-06
        \\---
        \\
        \\# x
        \\
        \\body: with a colon, and a --- inside
        \\
    ;
    const out = try rewriteField(testing.allocator, src, "status", "prioritized");
    defer testing.allocator.free(out);

    const want =
        \\---
        \\status: prioritized
        \\priority: 2
        \\note: a key we do not know
        \\created: 2026-09-06
        \\---
        \\
        \\# x
        \\
        \\body: with a colon, and a --- inside
        \\
    ;
    try testing.expectEqualStrings(want, out);
}

test "rewriteField: an empty value writes `key:` with no trailing space" {
    const src = "---\nstatus: backlog\npriority: 4\n---\n\n# x\n";
    const out = try rewriteField(testing.allocator, src, "priority", "");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("---\nstatus: backlog\npriority:\n---\n\n# x\n", out);
}

test "rewriteField: a missing key is inserted before the closing ---" {
    const src = "---\nstatus: backlog\n---\n\n# x\n";
    const out = try rewriteField(testing.allocator, src, "priority", "3");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("---\nstatus: backlog\npriority: 3\n---\n\n# x\n", out);
}

test "rewriteField: a CRLF file stays CRLF" {
    const src = "---\r\nstatus: backlog\r\npriority: 1\r\n---\r\n\r\n# x\r\n";
    const out = try rewriteField(testing.allocator, src, "status", "prioritized");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        "---\r\nstatus: prioritized\r\npriority: 1\r\n---\r\n\r\n# x\r\n",
        out,
    );
}

test "rewriteField: the body is untouched even when it looks like front matter" {
    const src = "---\nstatus: backlog\n---\n\nstatus: not this one\n";
    const out = try rewriteField(testing.allocator, src, "status", "dropped");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("---\nstatus: dropped\n---\n\nstatus: not this one\n", out);
}

test "template: parses back as backlog and unranked" {
    const t = try template(testing.allocator, "zig-lsp-server", "2026-09-06");
    defer testing.allocator.free(t);

    const idea = parse(t).ok;
    try testing.expectEqual(Status.backlog, idea.status);
    try testing.expectEqual(@as(?u8, null), idea.priority);
    try testing.expectEqualStrings("2026-09-06", idea.created);
    try testing.expect(std.mem.indexOf(u8, t, "# zig-lsp-server\n") != null);
}

fn entry(name: []const u8, src: []const u8) Entry {
    return .{ .name = name, .parsed = parse(src) };
}

test "sortEntries by priority: ranked first ascending, unranked after, ties by name" {
    var entries = [_]Entry{
        entry("d", "---\nstatus: backlog\n---\n"),
        entry("b", "---\nstatus: backlog\npriority: 1\n---\n"),
        entry("c", "---\nstatus: backlog\n---\n"),
        entry("a", "---\nstatus: backlog\npriority: 3\n---\n"),
    };
    sortEntries(&entries, .priority);
    try testing.expectEqualStrings("b", entries[0].name); // 1
    try testing.expectEqualStrings("a", entries[1].name); // 3
    try testing.expectEqualStrings("c", entries[2].name); // 未ランク、名前順
    try testing.expectEqualStrings("d", entries[3].name);
}

test "sortEntries by priority: an unreadable idea sorts as unranked, never dropped" {
    var entries = [_]Entry{
        entry("broken", "not front matter\n"),
        entry("ok", "---\nstatus: backlog\npriority: 2\n---\n"),
    };
    sortEntries(&entries, .priority);
    try testing.expectEqualStrings("ok", entries[0].name);
    try testing.expectEqualStrings("broken", entries[1].name);
}

test "sortEntries by created: newest first, missing last, ties by name" {
    var entries = [_]Entry{
        entry("old", "---\nstatus: backlog\ncreated: 2026-01-01\n---\n"),
        entry("none", "---\nstatus: backlog\n---\n"),
        entry("new", "---\nstatus: backlog\ncreated: 2026-09-06\n---\n"),
    };
    sortEntries(&entries, .created);
    try testing.expectEqualStrings("new", entries[0].name);
    try testing.expectEqualStrings("old", entries[1].name);
    try testing.expectEqualStrings("none", entries[2].name);
}

test "truncateUtf8: never splits a multibyte sequence" {
    const s = "あいうえお"; // 3 bytes each
    try testing.expectEqualStrings("あい", truncateUtf8(s, 7));
    try testing.expectEqualStrings("あい", truncateUtf8(s, 8));
    try testing.expectEqualStrings("あいう", truncateUtf8(s, 9));
    try testing.expectEqualStrings(s, truncateUtf8(s, 100));
}

test "writeListRow: an unreadable idea keeps its row and says why" {
    var out = std.Io.Writer.Allocating.init(testing.allocator);
    defer out.deinit();
    try writeListRow(&out.writer, entry("half-written", "---\nstatus: backlog\n"));
    try out.writer.flush();

    const line = out.written();
    try testing.expect(std.mem.indexOf(u8, line, "half-written") != null);
    try testing.expect(std.mem.indexOf(u8, line, UNREADABLE) != null);
    try testing.expect(std.mem.indexOf(u8, line, "never closed") != null);
    try testing.expect(std.mem.startsWith(u8, line, "  -  "));
}

test "writeListRow: a long evaluation is marked as truncated" {
    var out = std.Io.Writer.Allocating.init(testing.allocator);
    defer out.deinit();
    const long = "---\nstatus: backlog\nevaluation: " ++ ("x" ** 60) ++ "\n---\n";
    try writeListRow(&out.writer, entry("e", long));
    try out.writer.flush();
    try testing.expect(std.mem.endsWith(u8, std.mem.trimEnd(u8, out.written(), "\n"), "..."));
}

test "writeListRow: an empty evaluation leaves no trailing space" {
    var out = std.Io.Writer.Allocating.init(testing.allocator);
    defer out.deinit();
    try writeListRow(&out.writer, entry("x", "---\nstatus: backlog\n---\n"));
    try out.writer.flush();

    const line = std.mem.trimEnd(u8, out.written(), "\n");
    try testing.expect(!std.mem.endsWith(u8, line, " "));
    try testing.expect(std.mem.endsWith(u8, line, "x"));
}
