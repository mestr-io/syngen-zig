const std = @import("std");

pub const Printer = struct {
    inner_writer: std.fs.File.Writer,

    pub fn init(buffer: []u8) Printer {
        return .{
            .inner_writer = std.fs.File.stdout().writer(buffer),
        };
    }

    pub fn print(self: *Printer, comptime fmt: []const u8, args: anytype) !void {
        try self.inner_writer.interface.print(fmt, args);
    }

    pub fn flush(self: *Printer) !void {
        try self.inner_writer.interface.flush();
    }
};
