const std = @import("std");
const zemo = @import("zemo");
const cli = zemo.cli;
const upgrade = zemo.upgrade;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    // Windows で前回の `zemo upgrade` が残した `<exe>.old` を起動時に掃除する。
    // 走行中の自分自身を置換した直後はこのプロセス側がまだ .old を握っているので、
    // クリーンアップできるのは「次回以降の zemo 起動」になる。
    upgrade.cleanupStaleBinary(arena, init.io);

    const args = try init.minimal.args.toSlice(arena);
    const code = try cli.run(arena, init.io, init.environ_map, args);
    std.process.exit(code);
}
