const std = @import("std");
const cli = @import("zemo").cli;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const code = try cli.run(arena, init.io, init.environ_map, args);
    std.process.exit(code);
}
