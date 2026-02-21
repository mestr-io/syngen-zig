const std = @import("std");
const syngen_zig = @import("syngen_zig");
const models = syngen_zig.models;
const Generator = syngen_zig.generator.Generator;
const Exporter = syngen_zig.exporter.Exporter;

pub const std_options: std.Options = .{
    .log_level = .info,
};

const log = std.log.scoped(.syngen);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var user_count: usize = 10;
    var channel_count: usize = 5;
    var message_count: usize = 1000;
    var thread_prob: f64 = 0.1;
    var days: usize = 30;
    var output_filename: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-u") or std.mem.eql(u8, args[i], "--users")) {
            if (i + 1 < args.len) {
                i += 1;
                user_count = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (std.mem.eql(u8, args[i], "-c") or std.mem.eql(u8, args[i], "--channels")) {
            if (i + 1 < args.len) {
                i += 1;
                channel_count = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (std.mem.eql(u8, args[i], "-m") or std.mem.eql(u8, args[i], "--messages")) {
            if (i + 1 < args.len) {
                i += 1;
                message_count = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (std.mem.eql(u8, args[i], "-t") or std.mem.eql(u8, args[i], "--threads")) {
            if (i + 1 < args.len) {
                i += 1;
                thread_prob = try std.fmt.parseFloat(f64, args[i]);
            }
        } else if (std.mem.eql(u8, args[i], "-d") or std.mem.eql(u8, args[i], "--days")) {
            if (i + 1 < args.len) {
                i += 1;
                days = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (output_filename == null) {
            output_filename = args[i];
        }
    }

    if (output_filename == null) {
        var buf: [4096]u8 = undefined;
        var printer = syngen_zig.printer.Printer.init(&buf);
        try printer.print("Usage: syngen-zig [options] <output_filename.zip>\n", .{});
        try printer.print("Options:\n", .{});
        try printer.print("  -u, --users <count>      Number of users (default: 10)\n", .{});
        try printer.print("  -c, --channels <count>   Number of channels (default: 5)\n", .{});
        try printer.print("  -m, --messages <count>   Total messages (default: 1000)\n", .{});
        try printer.print("  -t, --threads <prob>     Threading probability 0.0-1.0 (default: 0.1)\n", .{});
        try printer.print("  -d, --days <count>       Time window in days (default: 30)\n", .{});
        try printer.flush();
        return;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    var gen = Generator.init(allocator, prng.random());

    var stdout_buf: [4096]u8 = undefined;
    var printer = syngen_zig.printer.Printer.init(&stdout_buf);

    log.info("Starting generation: users={d}, channels={d}, messages={d}, days={d}", .{ user_count, channel_count, message_count, days });

    try printer.print("Generating {d} users...\n", .{user_count});
    try printer.flush();
    const users = try gen.generateUsers(user_count, "T012345678");
    defer {
        for (users) |u| u.deinit(allocator);
        allocator.free(users);
    }
    log.info("Generated {d} users", .{users.len});

    try printer.print("Generating {d} channels...\n", .{channel_count});
    try printer.flush();
    const channels = try gen.generateChannels(channel_count, users);
    defer {
        for (channels) |c| c.deinit(allocator);
        allocator.free(channels);
    }
    log.info("Generated {d} channels", .{channels.len});

    try printer.print("Generating {d} messages over {d} days...\n", .{ message_count, days });
    try printer.flush();

    const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
    const arenas = try allocator.alloc(std.heap.ArenaAllocator, cpu_count);
    defer allocator.free(arenas);
    for (arenas) |*a| a.* = std.heap.ArenaAllocator.init(allocator);
    defer for (arenas) |*a| a.deinit();

    const messages = try gen.generateMessages(message_count, channels, users, days, thread_prob, arenas);
    defer allocator.free(messages);
    log.info("Generated {d} messages", .{messages.len});

    const temp_dir = "temp_export";
    try printer.print("Writing files to {s}...\n", .{temp_dir});
    try printer.flush();
    var exporter = try Exporter.init(allocator, temp_dir);
    defer {
        exporter.deinit();
        std.fs.cwd().deleteTree(temp_dir) catch {};
    }

    try exporter.writeUsers(users);
    try exporter.writeChannels(channels);
    try exporter.writeMessages(messages, channels);
    log.info("Wrote files to disk", .{});

    try printer.print("Creating archive {s}...\n", .{output_filename.?});
    try printer.flush();
    try exporter.finalize(output_filename.?);
    log.info("Created archive: {s}", .{output_filename.?});

    try printer.print("Done!\n", .{});
    try printer.flush();
}
