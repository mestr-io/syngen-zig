//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const models = @import("models.zig");
pub const faker = @import("faker.zig");
pub const generator = @import("generator.zig");
pub const exporter = @import("exporter.zig");
pub const printer = @import("printer.zig");

pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try stdout.flush();
}

test {
    std.testing.refAllDecls(@This());
}
