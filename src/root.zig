//! Library root for the `zemo` package. Re-exports submodules so consumers
//! and the test runner can reach them via the `zemo` module.

const std = @import("std");

pub const paths = @import("paths.zig");
pub const editor = @import("editor.zig");
pub const git = @import("git.zig");
pub const time = @import("time.zig");
pub const cli = @import("cli.zig");
pub const upgrade = @import("upgrade.zig");

test {
    std.testing.refAllDecls(@This());
}
